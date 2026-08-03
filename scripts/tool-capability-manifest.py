#!/usr/bin/env python3
"""TOOL_CAPABILITY_MANIFEST_V1 — hash-bound custom/MCP tool manifest (S-018).

4.0.2 loaded custom/MCP tool effects from a path in an environment variable
without binding the manifest hash, provider, version or exact tool inventory to
the launch. 4.0.3 requires a hash-bound manifest included in Launch V3 and
validated by the plugin at setup. Unknown/missing/hash-mismatched manifests fail
closed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import sys
from typing import Any

SCHEMA = "TOOL_CAPABILITY_MANIFEST_V1"
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
REQUIRED_TOOL_FIELDS = ("name", "connector", "version", "effect_classes")
ALLOWED_EFFECTS = {
    "READ", "WRITE", "CREATE", "DELETE", "RENAME", "EXECUTE", "NETWORK",
    "DEPENDENCY_MUTATION", "GIT_METADATA_MUTATION", "GIT_REMOTE_MUTATION",
    "PROCESS_CONTROL", "SECRET_ACCESS", "EXTERNAL_SIDE_EFFECT",
}


def emit_error(code: str, detail: str = "") -> None:
    payload = {"status": "ERROR", "code": code, "contract": SCHEMA}
    if detail:
        payload["detail"] = detail
    print(json.dumps(payload, sort_keys=True), file=sys.stderr)
    raise SystemExit(2)


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def validate_manifest(body: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(body, dict):
        emit_error("TOOL_MANIFEST_INVALID", "not a json object")
    if body.get("schema") != SCHEMA:
        emit_error("TOOL_MANIFEST_SCHEMA_INVALID", str(body.get("schema")))
    tools = body.get("tools")
    if not isinstance(tools, list) or not tools:
        emit_error("TOOL_MANIFEST_NO_TOOLS")
    names = set()
    for t in tools:
        if not isinstance(t, dict):
            emit_error("TOOL_MANIFEST_TOOL_INVALID", "not an object")
        for f in REQUIRED_TOOL_FIELDS:
            if not str(t.get(f) or "").strip():
                emit_error("TOOL_MANIFEST_TOOL_FIELD_MISSING", f)
        name = str(t.get("name"))
        if name in names:
            emit_error("TOOL_MANIFEST_DUPLICATE_TOOL", name)
        names.add(name)
        effects = t.get("effect_classes")
        if not isinstance(effects, list) or not effects:
            emit_error("TOOL_MANIFEST_EFFECTS_MISSING", name)
        for e in effects:
            if e not in ALLOWED_EFFECTS:
                emit_error("TOOL_MANIFEST_EFFECT_UNKNOWN", f"{name}:{e}")
        # network_behaviour / external_side_effects declared explicitly.
        if "network_behaviour" not in t:
            emit_error("TOOL_MANIFEST_NETWORK_BEHAVIOUR_MISSING", name)
        if "external_side_effects" not in t:
            emit_error("TOOL_MANIFEST_EXTERNAL_SIDE_EFFECTS_MISSING", name)
    return body


def write_manifest(out: pathlib.Path, body: dict[str, Any]) -> dict[str, Any]:
    out = pathlib.Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.parent.exists() and out.parent.is_symlink():
        emit_error("TOOL_MANIFEST_PATH_SYMLINK", str(out.parent))
    validate_manifest(body)
    data = (json.dumps(body, indent=2, sort_keys=True) + "\n").encode("utf-8")
    tmp = out.with_suffix(out.suffix + ".tmp")
    tmp.write_bytes(data)
    os.replace(tmp, out)
    digest = hashlib.sha256(data).hexdigest()
    return {"status": "TOOL_MANIFEST_WRITTEN", "contract": SCHEMA, "path": str(out), "sha256": digest}


def main() -> int:
    p = argparse.ArgumentParser(prog="tool-capability-manifest")
    sub = p.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("emit")
    e.add_argument("--out", required=True)
    e.add_argument("--tools-json", required=True, help="JSON array of tool entries")
    v = sub.add_parser("validate")
    v.add_argument("--manifest", required=True)
    args = p.parse_args()
    if args.cmd == "emit":
        try:
            tools = json.loads(args.tools_json)
        except Exception as exc:
            emit_error("TOOL_MANIFEST_TOOLS_JSON_INVALID", str(exc))
        body = {"schema": SCHEMA, "tools": tools}
        result = write_manifest(pathlib.Path(args.out), body)
        print(json.dumps(result, sort_keys=True))
        return 0
    man_path = pathlib.Path(args.manifest)
    if not man_path.is_file() or man_path.is_symlink():
        emit_error("TOOL_MANIFEST_MISSING", str(man_path))
    body = json.loads(man_path.read_text(encoding="utf-8"))
    validate_manifest(body)
    print(json.dumps({"status": "TOOL_MANIFEST_VALID", "sha256": sha256_file(man_path)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
