#!/usr/bin/env python3
"""GOVERNED_ROLE_LAUNCH_CONTRACT_V1 — write runner-owned launch files / preflight plugin."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import sys
import time
from typing import Any

CONTRACT = "GOVERNED_ROLE_LAUNCH_CONTRACT_V1"
PLUGIN_ENTRY = "opencode-governance-effect-enforcement.mjs"
PLUGIN_DIR = "opencode-governance-effect-enforcement"
OWNED = ".opencode-governance-ownership.json"


def fail(code: str, detail: str = "") -> None:
    payload: dict[str, Any] = {"status": "ERROR", "code": code, "contract": CONTRACT}
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


def preflight_plugin(config_dir: pathlib.Path) -> dict[str, Any]:
    plugins = config_dir / "plugins"
    entry = plugins / PLUGIN_ENTRY
    pkg = plugins / PLUGIN_DIR
    index = pkg / "index.mjs"
    policy = pkg / "role-effect-policy.json"
    marker = pkg / OWNED
    if not entry.is_file() or not index.is_file() or not policy.is_file() or not marker.is_file():
        fail("EFFECT_PLUGIN_NOT_ACTIVE", f"missing owned plugin under {plugins}")
    ownership = json.loads(marker.read_text(encoding="utf-8-sig"))
    plugin_sha = sha256_file(index)
    policy_sha = sha256_file(policy)
    if plugin_sha != ownership.get("plugin_sha256"):
        fail("EFFECT_PLUGIN_HASH_MISMATCH", plugin_sha)
    if policy_sha != ownership.get("policy_sha256"):
        fail("EFFECT_POLICY_HASH_MISMATCH", policy_sha)
    return {
        "status": "EFFECT_PLUGIN_PREFLIGHT_OK",
        "plugin_sha256": plugin_sha,
        "policy_sha256": policy_sha,
        "entry": str(entry),
        "policy": str(policy),
    }


def write_launch(
    out: pathlib.Path,
    *,
    role: str,
    workspace: str,
    repository: str,
    execution_root: str = "",
    phase: str = "",
    task_id: str = "",
    packet_sha256: str = "",
    candidate_identity: str = "",
    permission_policy_sha256: str = "",
    effect_policy: str = "",
    effect_policy_sha256: str = "",
    expected_agent: str = "",
) -> dict[str, Any]:
    body = {
        "schema": CONTRACT,
        "contract": CONTRACT,
        "active": "1",
        "role": role,
        "expected_agent": expected_agent or role,
        "phase": phase,
        "task_id": task_id,
        "workspace": workspace,
        "repository": repository,
        "execution_root": execution_root,
        "packet_sha256": packet_sha256,
        "candidate_identity": candidate_identity,
        "permission_policy_sha256": permission_policy_sha256,
        "effect_policy": effect_policy,
        "effect_policy_sha256": effect_policy_sha256,
        "written_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(out.suffix + ".tmp")
    data = (json.dumps(body, indent=2, sort_keys=True) + "\n").encode("utf-8")
    tmp.write_bytes(data)
    os.replace(tmp, out)
    return {
        "status": "GOVERNED_ROLE_LAUNCH_WRITTEN",
        "path": str(out),
        "sha256": hashlib.sha256(data).hexdigest(),
        "launch": body,
    }


def main() -> int:
    p = argparse.ArgumentParser(prog="governed-role-launch")
    sub = p.add_subparsers(dest="cmd", required=True)
    pf = sub.add_parser("preflight-plugin")
    pf.add_argument("--config-dir", required=True)
    w = sub.add_parser("write")
    w.add_argument("--out", required=True)
    w.add_argument("--role", required=True)
    w.add_argument("--workspace", required=True)
    w.add_argument("--repository", required=True)
    w.add_argument("--execution-root", default="")
    w.add_argument("--phase", default="")
    w.add_argument("--task-id", default="")
    w.add_argument("--packet-sha256", default="")
    w.add_argument("--candidate-identity", default="")
    w.add_argument("--permission-policy-sha256", default="")
    w.add_argument("--effect-policy", default="")
    w.add_argument("--effect-policy-sha256", default="")
    w.add_argument("--expected-agent", default="")
    w.add_argument("--config-dir", default="")
    w.add_argument("--require-plugin", action="store_true")
    args = p.parse_args()
    if args.cmd == "preflight-plugin":
        print(json.dumps(preflight_plugin(pathlib.Path(args.config_dir)), sort_keys=True))
        return 0
    if args.require_plugin:
        if not args.config_dir:
            fail("CONFIG_DIR_REQUIRED_FOR_PLUGIN_PREFLIGHT")
        preflight_plugin(pathlib.Path(args.config_dir))
    result = write_launch(
        pathlib.Path(args.out),
        role=args.role,
        workspace=args.workspace,
        repository=args.repository,
        execution_root=args.execution_root,
        phase=args.phase,
        task_id=args.task_id,
        packet_sha256=args.packet_sha256,
        candidate_identity=args.candidate_identity,
        permission_policy_sha256=args.permission_policy_sha256,
        effect_policy=args.effect_policy,
        effect_policy_sha256=args.effect_policy_sha256,
        expected_agent=args.expected_agent,
    )
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
