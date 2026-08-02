#!/usr/bin/env python3
"""GOVERNED_ROLE_PROCESS_CONTRACT_V1 — dedicated OpenCode child per security role."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time
from typing import Any

CONTRACT = "GOVERNED_ROLE_PROCESS_CONTRACT_V1"
ROLES = {
    "architect": {"agent": "architect"},
    "executor": {"agent": "executor"},
    "implementation-reviewer": {"agent": "reviewer"},
    "architecture-reviewer": {"agent": "reviewer-architecture"},
    "final-reviewer": {"agent": "final-reviewer"},
}


def fail(code: str, detail: str = "") -> None:
    print(json.dumps({"status": "ERROR", "code": code, "contract": CONTRACT, "detail": detail}, sort_keys=True), file=sys.stderr)
    raise SystemExit(2)


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def find_opencode() -> str:
    which = shutil.which("opencode")
    appdata = os.environ.get("APPDATA", "")
    candidates = []
    if which:
        candidates.append(pathlib.Path(which))
        candidates.append(pathlib.Path(which).parent / "node_modules" / "opencode-ai" / "bin" / "opencode.exe")
    if appdata:
        candidates.append(pathlib.Path(appdata) / "npm" / "node_modules" / "opencode-ai" / "bin" / "opencode.exe")
    candidates.append(pathlib.Path.home() / ".opencode" / "bin" / "opencode.exe")
    candidates.append(pathlib.Path.home() / ".opencode" / "bin" / "opencode")
    for c in candidates:
        if c.is_file():
            return str(c)
    if which:
        return which
    fail("OPENCODE_BINARY_MISSING")


def tools_dir(config: pathlib.Path) -> pathlib.Path:
    return config / "opencode-governance-tools"


def launch_role(args: argparse.Namespace) -> dict[str, Any]:
    role = args.role
    if role not in ROLES:
        fail("ROLE_INVALID", role)
    config = pathlib.Path(args.config_dir).resolve()
    workspace = pathlib.Path(args.workspace).resolve()
    repository = pathlib.Path(args.repository or args.workspace).resolve()
    tdir = tools_dir(config)
    launch_helper = tdir / "governed-role-launch.py"
    if not launch_helper.is_file():
        launch_helper = pathlib.Path(__file__).resolve().parent / "governed-role-launch.py"
    if not launch_helper.is_file():
        fail("LAUNCH_HELPER_MISSING")

    # Non-mutating preflight only — never install --skip-self-test here (R-008).
    pre = subprocess.run(
        [sys.executable, str(launch_helper), "preflight-plugin", "--config-dir", str(config)],
        capture_output=True,
        text=True,
    )
    if pre.returncode != 0:
        fail("EFFECT_PLUGIN_NOT_ACTIVE", (pre.stderr or pre.stdout or "")[:2000])
    pre_j = json.loads(pre.stdout.strip().splitlines()[-1])

    logs = pathlib.Path(args.logs_dir or (workspace / ".ai" / "tasks" / (args.task_id or "_ungoverned") / "logs" / "role-processes"))
    logs.mkdir(parents=True, exist_ok=True)
    launch_path = logs / f"launch-{role}-{int(time.time())}.json"
    hs_path = logs / f"handshake-{role}-{int(time.time())}.json"
    wcmd = [
        sys.executable,
        str(launch_helper),
        "write",
        "--out",
        str(launch_path),
        "--role",
        role if role not in {"implementation-reviewer", "architecture-reviewer"} else (
            "reviewer" if role == "implementation-reviewer" else "reviewer-architecture"
        ),
        "--expected-agent",
        ROLES[role]["agent"],
        "--workspace",
        str(workspace),
        "--repository",
        str(repository),
        "--phase",
        args.phase or role,
        "--config-dir",
        str(config),
        "--require-plugin",
        "--plugin-sha256",
        pre_j["plugin_sha256"],
        "--effect-policy-sha256",
        pre_j["policy_sha256"],
    ]
    if args.execution_root:
        wcmd += ["--execution-root", str(pathlib.Path(args.execution_root).resolve())]
    if args.task_id:
        wcmd += ["--task-id", args.task_id]
    if args.packet_sha256:
        wcmd += ["--packet-sha256", args.packet_sha256]
    if args.candidate_identity:
        wcmd += ["--candidate-identity", args.candidate_identity]
    if args.route_receipt_sha256:
        wcmd += ["--route-receipt-sha256", args.route_receipt_sha256]
    wr = subprocess.run(wcmd, capture_output=True, text=True)
    if wr.returncode != 0:
        fail("GOVERNED_ROLE_LAUNCH_REQUIRED", (wr.stderr or wr.stdout or "")[:2000])
    launch_j = json.loads(wr.stdout.strip().splitlines()[-1])

    opencode = args.opencode_command or find_opencode()
    message = args.message or args.prompt or f"Governed {role} session."
    if args.prompt_file:
        message = pathlib.Path(args.prompt_file).read_text(encoding="utf-8")

    env = os.environ.copy()
    env["OPENCODE_CONFIG_DIR"] = str(config)
    env.update(launch_j.get("env") or {})
    env["OPENCODE_GOVERNANCE_HANDSHAKE_PATH"] = str(hs_path)
    env["OPENCODE_GOVERNANCE_PLUGIN_SHA256"] = pre_j["plugin_sha256"]
    env["OPENCODE_GOVERNANCE_EFFECT_POLICY_SHA256"] = pre_j["policy_sha256"]
    env["OPENCODE_GOVERNANCE_EFFECT_POLICY"] = pre_j["policy"]
    if args.execution_root:
        env["OPENCODE_GOVERNANCE_EXECUTION_ROOT"] = str(pathlib.Path(args.execution_root).resolve())

    agent = ROLES[role]["agent"]
    cmd = [
        opencode,
        "run",
        "--dir",
        str(workspace),
        "--agent",
        agent,
        "--format",
        "json",
    ]
    if args.model:
        cmd += ["--model", args.model]
    cmd.append(message)

    stdout_path = logs / f"{role}.stdout.jsonl"
    stderr_path = logs / f"{role}.stderr.log"
    started = time.time()
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=max(30, int(args.timeout_seconds)),
            env=env,
            cwd=str(workspace),
        )
    except subprocess.TimeoutExpired as exc:
        fail("ROLE_PROCESS_TIMEOUT", str(exc))
    except Exception as exc:
        fail("ROLE_PROCESS_SPAWN_FAILED", str(exc))
    stdout_path.write_text(proc.stdout or "", encoding="utf-8")
    stderr_path.write_text(proc.stderr or "", encoding="utf-8")

    if not hs_path.is_file():
        fail("EFFECT_PLUGIN_HANDSHAKE_MISSING", f"role={role} logs={logs}")
    handshake = json.loads(hs_path.read_text(encoding="utf-8"))
    if handshake.get("schema") != "EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1":
        fail("EFFECT_PLUGIN_HANDSHAKE_INVALID", str(handshake.get("schema")))
    if handshake.get("role") not in {role, ROLES[role]["agent"], "reviewer", "reviewer-architecture"}:
        # mapped reviewer roles may handshake as agent role name
        if handshake.get("role") != launch_j["launch"]["role"]:
            fail("EFFECT_PLUGIN_HANDSHAKE_ROLE_MISMATCH", str(handshake.get("role")))
    if str(handshake.get("plugin_sha256")) != pre_j["plugin_sha256"]:
        fail("EFFECT_PLUGIN_HANDSHAKE_PLUGIN_MISMATCH")

    receipt = {
        "status": "GOVERNED_ROLE_PROCESS_COMPLETE",
        "contract": CONTRACT,
        "role": role,
        "agent": agent,
        "exit_code": proc.exit_code if hasattr(proc, "exit_code") else proc.returncode,
        "pid": handshake.get("process_id"),
        "handshake_path": str(hs_path),
        "handshake_sha256": sha256_file(hs_path),
        "launch_path": str(launch_path),
        "launch_sha256": launch_j["sha256"],
        "stdout_path": str(stdout_path),
        "stderr_path": str(stderr_path),
        "duration_seconds": round(time.time() - started, 3),
        "plugin_sha256": pre_j["plugin_sha256"],
        "policy_sha256": pre_j["policy_sha256"],
        "task_id": args.task_id,
        "packet_sha256": args.packet_sha256,
        "candidate_identity": args.candidate_identity,
    }
    receipt_path = logs / f"role-process-receipt-{role}.json"
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    receipt["receipt_path"] = str(receipt_path)
    receipt["receipt_sha256"] = sha256_file(receipt_path)
    return receipt


def main() -> int:
    p = argparse.ArgumentParser(prog="governed-role-attempt")
    p.add_argument("--role", required=True, choices=sorted(ROLES.keys()))
    p.add_argument("--config-dir", required=True)
    p.add_argument("--workspace", required=True)
    p.add_argument("--repository", default="")
    p.add_argument("--execution-root", default="")
    p.add_argument("--task-id", default="")
    p.add_argument("--phase", default="")
    p.add_argument("--packet-sha256", default="")
    p.add_argument("--candidate-identity", default="")
    p.add_argument("--route-receipt-sha256", default="")
    p.add_argument("--message", default="")
    p.add_argument("--prompt", default="")
    p.add_argument("--prompt-file", default="")
    p.add_argument("--model", default="")
    p.add_argument("--opencode-command", default="")
    p.add_argument("--timeout-seconds", type=int, default=600)
    p.add_argument("--logs-dir", default="")
    args = p.parse_args()
    print(json.dumps(launch_role(args), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
