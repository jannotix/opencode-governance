#!/usr/bin/env python3
"""GOVERNED_ROLE_LAUNCH_CONTRACT_V3 + plugin preflight (non-mutating).

4.0.3: launch receipts are V3 (session-single-use, capability-manifest- and
route-receipt-bound). V2 receipts remain accepted on read for an in-flight
upgrade window; new launches are V3."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import secrets
import sys
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

CONTRACT = "GOVERNED_ROLE_LAUNCH_CONTRACT_V3"
CONTRACT_V2 = "GOVERNED_ROLE_LAUNCH_CONTRACT_V2"
VERSION = "4.0.4"
PLUGIN_ID = "opencode-governance-effect-enforcement"
OWNED = ".opencode-governance-ownership.json"
PLUGIN_DIR = "opencode-governance-effect-enforcement"
ENTRY_NAME = "opencode-governance-effect-enforcement.mjs"


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


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def preflight_plugin(config_dir: pathlib.Path) -> dict[str, Any]:
    plugins = config_dir / "plugins"
    entry = plugins / ENTRY_NAME
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
    # Require file:// registration in opencode.json
    cfg = config_dir / "opencode.json"
    if not cfg.is_file():
        fail("EFFECT_PLUGIN_NOT_ACTIVE", "opencode.json missing plugin registration")
    try:
        data = json.loads(cfg.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        fail("EFFECT_PLUGIN_NOT_ACTIVE", f"opencode.json unreadable: {exc}")
    plugins_list = data.get("plugin") or []
    if not any(ENTRY_NAME in str(x) or PLUGIN_DIR in str(x) for x in plugins_list):
        fail("EFFECT_PLUGIN_NOT_ACTIVE", "plugin not registered in opencode.json plugin array")
    return {
        "status": "EFFECT_PLUGIN_PREFLIGHT_OK",
        "plugin_sha256": plugin_sha,
        "policy_sha256": policy_sha,
        "entry": str(entry),
        "policy": str(policy),
        "plugin_uri": entry.resolve().as_uri(),
    }


def write_launch_v2(
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
    effect_policy_sha256: str = "",
    plugin_sha256: str = "",
    route_receipt_sha256: str = "",
    expected_agent: str = "",
    expected_opencode_version: str = "",
    ttl_seconds: int = 3600,
    single_use: bool = True,
    parent_pid: int | None = None,
    tool_capability_manifest: str = "",
    tool_capability_manifest_sha256: str = "",
    work_class: str = "",
    frozen_target: str = "",
    route: str = "",
    model: str = "",
    variant: str = "",
    model_family: str = "",
) -> dict[str, Any]:
    now = datetime.now(timezone.utc)
    expires = now + timedelta(seconds=max(60, ttl_seconds))
    body = {
        "schema": CONTRACT,
        "version": VERSION,
        "launch_id": str(uuid.uuid4()),
        "nonce": secrets.token_hex(16),
        "issued_at_utc": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "expires_at_utc": expires.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "single_use": bool(single_use),
        "consumed_at_utc": "",
        "role": role,
        "expected_agent": expected_agent or role,
        "task_id": task_id,
        "phase": phase,
        "workspace_root": str(pathlib.Path(workspace).resolve()),
        "repository_root": str(pathlib.Path(repository).resolve()),
        "execution_root_or_evidence_root": str(pathlib.Path(execution_root).resolve()) if execution_root else "",
        "packet_sha256": packet_sha256,
        "candidate_identity": candidate_identity,
        "route_receipt_sha256": route_receipt_sha256,
        "permission_policy_sha256": permission_policy_sha256,
        "effect_policy_sha256": effect_policy_sha256,
        "plugin_sha256": plugin_sha256,
        "expected_opencode_version": expected_opencode_version,
        "parent_pid": int(parent_pid if parent_pid is not None else os.getpid()),
        "expected_child_identity": "",
        # S-018: tool capability manifest binding (hash-bound at launch).
        "tool_capability_manifest": tool_capability_manifest,
        "tool_capability_manifest_sha256": tool_capability_manifest_sha256,
        # Executor attempt binding (frozen target / route / model).
        "work_class": work_class,
        "frozen_target": frozen_target,
        "route": route,
        "model": model,
        "variant": variant,
        "model_family": model_family,
    }
    out = pathlib.Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    # Reject if parent is symlink
    if out.parent.exists() and out.parent.is_symlink():
        fail("LAUNCH_PATH_SYMLINK", str(out.parent))
    data = (json.dumps(body, indent=2, sort_keys=True) + "\n").encode("utf-8")
    tmp = out.with_suffix(out.suffix + ".tmp")
    tmp.write_bytes(data)
    os.replace(tmp, out)
    try:
        os.chmod(out, 0o600)
    except OSError:
        pass
    digest = sha256_bytes(data)
    return {
        "status": "GOVERNED_ROLE_LAUNCH_WRITTEN",
        "contract": CONTRACT,
        "path": str(out),
        "sha256": digest,
        "launch": body,
        "env": {
            "OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE": "1",
            "OPENCODE_GOVERNANCE_LAUNCH_FILE": str(out),
            "OPENCODE_GOVERNANCE_LAUNCH_SHA256": digest,
            "OPENCODE_GOVERNANCE_ROLE": role,
            "OPENCODE_GOVERNANCE_EXPECTED_AGENT": expected_agent or role,
        },
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
    w.add_argument("--effect-policy", default="")  # ignored for V2 hash-only path
    w.add_argument("--effect-policy-sha256", default="")
    w.add_argument("--plugin-sha256", default="")
    w.add_argument("--route-receipt-sha256", default="")
    w.add_argument("--expected-agent", default="")
    w.add_argument("--expected-opencode-version", default="")
    w.add_argument("--ttl-seconds", type=int, default=3600)
    w.add_argument("--no-single-use", action="store_true")
    w.add_argument("--config-dir", default="")
    w.add_argument("--require-plugin", action="store_true")
    # S-018 / S-014 binding fields (forwarded into the V3 launch body so the
    # plugin can hash-bind the capability manifest and the chain can revalidate).
    w.add_argument("--tool-capability-manifest", default="")
    w.add_argument("--tool-capability-manifest-sha256", default="")
    w.add_argument("--work-class", default="")
    w.add_argument("--frozen-target", default="")
    w.add_argument("--route", default="")
    w.add_argument("--model", default="")
    w.add_argument("--variant", default="")
    w.add_argument("--model-family", default="")
    args = p.parse_args()
    if args.cmd == "preflight-plugin":
        print(json.dumps(preflight_plugin(pathlib.Path(args.config_dir)), sort_keys=True))
        return 0
    plugin_sha = args.plugin_sha256
    effect_sha = args.effect_policy_sha256
    if args.require_plugin:
        if not args.config_dir:
            fail("CONFIG_DIR_REQUIRED_FOR_PLUGIN_PREFLIGHT")
        pre = preflight_plugin(pathlib.Path(args.config_dir))
        plugin_sha = plugin_sha or pre["plugin_sha256"]
        effect_sha = effect_sha or pre["policy_sha256"]
    result = write_launch_v2(
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
        effect_policy_sha256=effect_sha,
        plugin_sha256=plugin_sha,
        route_receipt_sha256=args.route_receipt_sha256,
        expected_agent=args.expected_agent,
        expected_opencode_version=args.expected_opencode_version,
        ttl_seconds=args.ttl_seconds,
        single_use=not args.no_single_use,
        tool_capability_manifest=args.tool_capability_manifest,
        tool_capability_manifest_sha256=args.tool_capability_manifest_sha256,
        work_class=args.work_class,
        frozen_target=args.frozen_target,
        route=args.route,
        model=args.model,
        variant=args.variant,
        model_family=args.model_family,
    )
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
