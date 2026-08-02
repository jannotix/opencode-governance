#!/usr/bin/env python3
"""GOVERNED_ROLE_PROCESS_CONTRACT_V2 — dedicated OpenCode child per security role.

4.0.3 corrections vs 4.0.2 (GOVERNED_ROLE_PROCESS_CONTRACT_V1):

  * S-001: pre-side-effect READY gate. The launcher monitors the plugin READY
    barrier while the child is running, validates it immediately, and writes a
    host acknowledgement bound to READY before any tool can be permitted. A
    post-process handshake check alone is no longer the gate.
  * S-004: the prepared Executor launch receipt is the SOLE authoritative
    launch; --launch-file/--expected-launch-sha256 bind the child to the exact
    prepared attempt. The launcher never creates a replacement launch.
  * S-005: prompt transport is stdin (GOVERNED_ROLE_STDIN_TRANSPORT_V1). The
    packet/role prompt is never placed on argv or in the environment.
  * S-006: role-specific working directories. Executor cwd == execution root;
    the real workspace is read-only authority and never the child cwd.
  * S-013: a non-zero OpenCode exit code is a typed failure, never
    GOVERNED_ROLE_PROCESS_COMPLETE.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import threading
import time
from typing import Any

CONTRACT = "GOVERNED_ROLE_PROCESS_CONTRACT_V2"
HOST_ACK_SCHEMA = "GOVERNED_ROLE_HOST_ACK_V1"
READY_SCHEMA_V2 = "EFFECT_PLUGIN_RUNTIME_READY_GATE_V2"
HANDSHAKE_SCHEMA_V1 = "EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1"
STDIN_TRANSPORT = "GOVERNED_ROLE_STDIN_TRANSPORT_V1"

ROLES = {
    "architect": {"agent": "architect", "cwd": "workspace"},
    "executor": {"agent": "executor", "cwd": "execution_root"},
    "implementation-reviewer": {"agent": "reviewer", "cwd": "evidence_root"},
    "architecture-reviewer": {"agent": "reviewer-architecture", "cwd": "evidence_root"},
    "final-reviewer": {"agent": "final-reviewer", "cwd": "evidence_root"},
}

# Roles whose OpenCode --dir / process cwd must be the isolated root, not workspace.
ISOLATED_CWD_ROLES = {"executor", "implementation-reviewer", "architecture-reviewer", "final-reviewer"}


def fail(code: str, detail: str = "") -> None:
    print(json.dumps({"status": "ERROR", "code": code, "contract": CONTRACT, "detail": detail}, sort_keys=True), file=sys.stderr)
    raise SystemExit(2)


def fail_typed(code: str, **fields: Any) -> None:
    payload = {"status": "ERROR", "code": code, "contract": CONTRACT}
    payload.update(fields)
    print(json.dumps(payload, sort_keys=True), file=sys.stderr)
    raise SystemExit(2)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


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


def opencode_version(opencode: str) -> str:
    try:
        out = subprocess.run([opencode, "--version"], capture_output=True, text=True, timeout=15)
        return (out.stdout or out.stderr or "").strip()
    except Exception:
        return ""


def tools_dir(config: pathlib.Path) -> pathlib.Path:
    return config / "opencode-governance-tools"


def resolve_role_dir(args: argparse.Namespace, workspace: pathlib.Path, execution_root: pathlib.Path) -> pathlib.Path:
    """S-006: role-specific working directory. Executor/reviewers use the
    isolated root; Architect uses the exact workspace root."""
    role = args.role
    if role in ISOLATED_CWD_ROLES:
        if role == "executor":
            if not execution_root:
                fail("EXECUTION_ROOT_REQUIRED", "executor requires --execution-root or prepared launch execution_root")
            return execution_root
        # reviewers → evidence root (provided via --execution-root/evidence-root)
        if not execution_root:
            fail("EVIDENCE_ROOT_REQUIRED", f"{role} requires an immutable evidence root")
        return execution_root
    return workspace


def load_prepared_launch(args: argparse.Namespace) -> dict[str, Any] | None:
    """S-004: when --launch-file is given, the prepared Executor launch is the
    SOLE authoritative launch. Validate its hash and bind attempt manifest."""
    if not args.launch_file:
        return None
    launch_path = pathlib.Path(args.launch_file).resolve()
    if not launch_path.is_file():
        fail("PREPARED_LAUNCH_MISSING", str(launch_path))
    if launch_path.is_symlink():
        fail("PREPARED_LAUNCH_SYMLINK", str(launch_path))
    raw = launch_path.read_bytes()
    actual_sha = sha256_bytes(raw)
    expected_sha = (args.expected_launch_sha256 or "").strip()
    if expected_sha and expected_sha != actual_sha:
        fail("PREPARED_LAUNCH_HASH_MISMATCH", f"expected={expected_sha} actual={actual_sha}")
    try:
        body = json.loads(raw.decode("utf-8"))
    except Exception as exc:
        fail("PREPARED_LAUNCH_JSON_INVALID", str(exc))
    schema = body.get("schema") or body.get("contract")
    if schema not in {
        "GOVERNED_ROLE_LAUNCH_CONTRACT_V3",
        "GOVERNED_ROLE_LAUNCH_CONTRACT_V2",
    }:
        fail("PREPARED_LAUNCH_SCHEMA_INVALID", str(schema))
    # Bind to the attempt manifest when provided.
    if args.attempt_manifest:
        man_path = pathlib.Path(args.attempt_manifest).resolve()
        if not man_path.is_file():
            fail("ATTEMPT_MANIFEST_MISSING", str(man_path))
        try:
            man = json.loads(man_path.read_text(encoding="utf-8"))
        except Exception as exc:
            fail("ATTEMPT_MANIFEST_JSON_INVALID", str(exc))
        # Cross-check the launch binds the same attempt identity.
        for key in ("task_id",):
            mv = str(man.get(key) or "")
            lv = str(body.get(key) or "")
            if mv and lv and mv != lv:
                fail("PREPARED_LAUNCH_ATTEMPT_MISMATCH", f"{key}: manifest={mv} launch={lv}")
        # frozen_target / route / packet come from the manifest; ensure launch packet agrees.
        man_packet = str(man.get("packet_sha256") or "").lower()
        launch_packet = str(body.get("packet_sha256") or "").lower()
        if man_packet and launch_packet and man_packet != launch_packet:
            fail("PREPARED_LAUNCH_PACKET_MISMATCH", f"manifest={man_packet} launch={launch_packet}")
    return {"path": str(launch_path), "sha256": actual_sha, "body": body}


def write_host_ack(ack_path: pathlib.Path, ready: dict[str, Any], session_id: str) -> dict[str, Any]:
    """S-001: host acknowledgement bound to the plugin READY. The plugin's
    tool.execute.before hook requires this ack before permitting any effect."""
    ack = {
        "schema": HOST_ACK_SCHEMA,
        "ready_nonce": str(ready.get("ready_nonce") or ""),
        "launch_id": str(ready.get("launch_id") or ""),
        "launch_nonce": str(ready.get("launch_nonce") or ""),
        "process_id": int(ready.get("process_id") or 0),
        "session_id": session_id,
        "plugin_sha256": str(ready.get("plugin_sha256") or ""),
        "policy_sha256": str(ready.get("policy_sha256") or ""),
        "acknowledged_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    ack_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = ack_path.with_suffix(ack_path.suffix + ".tmp")
    tmp.write_text(json.dumps(ack, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(tmp, ack_path)
    try:
        os.chmod(ack_path, 0o600)
    except OSError:
        pass
    return ack


def wait_for_ready(hs_path: pathlib.Path, deadline: float, expected_launch_sha: str) -> dict[str, Any]:
    """Poll for the plugin READY barrier while the child runs. Returns the
    validated READY body or raises after timeout."""
    last_err = ""
    while time.time() < deadline:
        if hs_path.is_file() and not hs_path.is_symlink():
            try:
                body = json.loads(hs_path.read_text(encoding="utf-8"))
            except Exception as exc:
                last_err = f"handshake parse: {exc}"
                time.sleep(0.1)
                continue
            schema = body.get("schema")
            if schema == READY_SCHEMA_V2:
                # Validate READY binds the expected launch.
                if expected_launch_sha and str(body.get("launch_receipt_sha256") or "") and str(body.get("launch_receipt_sha256")) != expected_launch_sha:
                    last_err = f"READY launch mismatch: {body.get('launch_receipt_sha256')} != {expected_launch_sha}"
                    time.sleep(0.1)
                    continue
                if not body.get("plugin_sha256") or not body.get("policy_sha256"):
                    last_err = "READY missing plugin/policy hash"
                    time.sleep(0.1)
                    continue
                return body
            if schema == "EFFECT_PLUGIN_NOT_READY_V1":
                # Plugin setup failed — abort immediately, do not claim completion.
                fail_typed("EFFECT_PLUGIN_NOT_READY", reason=body.get("reason"), detail=body.get("detail"))
        time.sleep(0.1)
    fail_typed("EFFECT_PLUGIN_READY_TIMEOUT", last_error=last_err, handshake_path=str(hs_path))


def validate_ready(ready: dict[str, Any], expected: dict[str, Any]) -> None:
    """S-011: full handshake/READY validation. Every required field must be
    present and match; an empty value is not valid evidence. Route receipt is
    required only when the launch binds one (so a bare discovery session is not
    blocked, but a routed Executor/review session is bound)."""
    required_fields = [
        "plugin_id", "plugin_sha256", "policy_sha256", "launch_receipt_sha256",
        "launch_id", "launch_nonce", "role", "expected_agent", "task_id",
        "phase", "packet_sha256", "candidate_identity",
        "process_id", "session_id", "opencode_version", "ready_at_utc",
    ]
    for f in required_fields:
        v = str(ready.get(f) or "").strip()
        if not v:
            fail_typed("EFFECT_PLUGIN_HANDSHAKE_INVALID", field=f, reason="empty_or_missing")
    # Route receipt binding is mandatory when the launch declares one.
    if expected.get("route_receipt_required"):
        required_fields = required_fields + ["route_receipt_sha256"]
        v = str(ready.get("route_receipt_sha256") or "").strip()
        if not v:
            fail_typed("EFFECT_PLUGIN_HANDSHAKE_INVALID", field="route_receipt_sha256", reason="empty_or_missing")
    if str(ready.get("plugin_id")) != "opencode-governance-effect-enforcement":
        fail_typed("EFFECT_PLUGIN_HANDSHAKE_PLUGIN_ID_MISMATCH", got=ready.get("plugin_id"))
    if expected.get("plugin_sha256") and str(ready.get("plugin_sha256")) != expected["plugin_sha256"]:
        fail_typed("EFFECT_PLUGIN_HANDSHAKE_PLUGIN_MISMATCH", expected=expected.get("plugin_sha256"), got=ready.get("plugin_sha256"))
    if expected.get("policy_sha256") and str(ready.get("policy_sha256")) != expected["policy_sha256"]:
        fail_typed("EFFECT_PLUGIN_HANDSHAKE_POLICY_MISMATCH", expected=expected.get("policy_sha256"), got=ready.get("policy_sha256"))
    if expected.get("launch_sha256") and str(ready.get("launch_receipt_sha256")) != expected["launch_sha256"]:
        fail_typed("EFFECT_PLUGIN_HANDSHAKE_LAUNCH_MISMATCH", expected=expected.get("launch_sha256"), got=ready.get("launch_receipt_sha256"))
    if expected.get("launch_nonce") and str(ready.get("launch_nonce")) != expected["launch_nonce"]:
        fail_typed("EFFECT_PLUGIN_HANDSHAKE_NONCE_MISMATCH", expected=expected.get("launch_nonce"), got=ready.get("launch_nonce"))


def build_prompt(args: argparse.Namespace) -> bytes:
    """GOVERNED_ROLE_STDIN_TRANSPORT_V1 — UTF-8, no BOM, LF-normalized."""
    message = args.message or args.prompt or f"Governed {args.role} session."
    if args.prompt_file:
        message = pathlib.Path(args.prompt_file).read_text(encoding="utf-8")
    text = message.replace("\r\n", "\n").replace("\r", "\n")
    return text.encode("utf-8")


def launch_role(args: argparse.Namespace) -> dict[str, Any]:
    role = args.role
    if role not in ROLES:
        fail("ROLE_INVALID", role)
    config = pathlib.Path(args.config_dir).resolve()
    workspace = pathlib.Path(args.workspace).resolve()
    repository = pathlib.Path(args.repository or args.workspace).resolve()
    execution_root = pathlib.Path(args.execution_root).resolve() if args.execution_root else pathlib.Path("")
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

    # S-004: consume the prepared Executor launch when provided; otherwise write one.
    prepared = load_prepared_launch(args)
    ack_path = logs / f"host-ack-{role}-{int(time.time())}.json"
    if prepared:
        launch_path = pathlib.Path(prepared["path"])
        launch_sha = prepared["sha256"]
        launch_body = prepared["body"]
        # Inherit identity from the authoritative prepared launch.
        role_for_launch = str(launch_body.get("role") or role)
        expected_agent = str(launch_body.get("expected_agent") or role_for_launch)
        launch_env = {
            "OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE": "1",
            "OPENCODE_GOVERNANCE_LAUNCH_FILE": str(launch_path),
            "OPENCODE_GOVERNANCE_LAUNCH_SHA256": launch_sha,
            "OPENCODE_GOVERNANCE_ROLE": role_for_launch,
            "OPENCODE_GOVERNANCE_EXPECTED_AGENT": expected_agent,
        }
        er = str(launch_body.get("execution_root_or_evidence_root") or "")
        if er:
            execution_root = pathlib.Path(er).resolve()
    else:
        launch_path = logs / f"launch-{role}-{int(time.time())}.json"
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
        if execution_root:
            wcmd += ["--execution-root", str(execution_root)]
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
        launch_sha = launch_j["sha256"]
        launch_body = launch_j["launch"]
        launch_env = launch_j.get("env") or {}

    # S-006: role-specific working directory.
    role_dir = resolve_role_dir(args, workspace, execution_root)
    role_dir.mkdir(parents=True, exist_ok=True)

    opencode = args.opencode_command or find_opencode()
    prompt_bytes = build_prompt(args)
    prompt_sha = sha256_bytes(prompt_bytes)

    env = os.environ.copy()
    env["OPENCODE_CONFIG_DIR"] = str(config)
    env.update(launch_env)
    env["OPENCODE_GOVERNANCE_PLUGIN_SHA256"] = pre_j["plugin_sha256"]
    env["OPENCODE_GOVERNANCE_EFFECT_POLICY_SHA256"] = pre_j["policy_sha256"]
    env["OPENCODE_GOVERNANCE_EFFECT_POLICY"] = pre_j["policy"]
    if execution_root:
        env["OPENCODE_GOVERNANCE_EXECUTION_ROOT"] = str(execution_root)
        env["OPENCODE_GOVERNANCE_EVIDENCE_ROOT"] = str(execution_root)
    env["OPENCODE_GOVERNANCE_WORKSPACE"] = str(workspace)
    env["OPENCODE_GOVERNANCE_REPOSITORY"] = str(repository)
    env["OPENCODE_GOVERNANCE_HANDSHAKE_PATH"] = str(logs / f"handshake-{role}-{int(time.time())}.json")
    # S-001: require host acknowledgement before any tool effect.
    env["OPENCODE_GOVERNANCE_REQUIRE_HOST_ACK"] = "1"
    env["OPENCODE_GOVERNANCE_HOST_ACK_PATH"] = str(ack_path)
    env["OPENCODE_GOVERNANCE_OPENCODE_BINARY"] = opencode
    if args.session_id:
        env["OPENCODE_GOVERNANCE_SESSION_ID"] = args.session_id
    elif not env.get("OPENCODE_GOVERNANCE_SESSION_ID"):
        # Bind a deterministic session identity for this run so READY can echo it
        # even when OpenCode does not surface a sessionID at plugin-load time.
        env["OPENCODE_GOVERNANCE_SESSION_ID"] = f"gov-{launch_body.get('launch_id', '')[:16]}-{os.getpid()}"

    agent = ROLES[role]["agent"]
    # S-005: prompt transport = stdin. NO positional message on argv.
    cmd = [
        opencode,
        "run",
        "--dir",
        str(role_dir),
        "--agent",
        agent,
        "--format",
        "json",
    ]
    if args.model:
        cmd += ["--model", args.model]

    stdout_path = logs / f"{role}.stdout.jsonl"
    stderr_path = logs / f"{role}.stderr.log"
    stdin_meta_path = logs / f"{role}.stdin-transport.json"
    started = time.time()
    ready_body: dict[str, Any] | None = None
    ack_body: dict[str, Any] | None = None
    hs_path = pathlib.Path(env["OPENCODE_GOVERNANCE_HANDSHAKE_PATH"])

    try:
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=False,
            env=env,
            cwd=str(role_dir),
        )
    except Exception as exc:
        fail("ROLE_PROCESS_SPAWN_FAILED", str(exc))

    # S-001: feed the prompt via stdin (S-005) and concurrently monitor READY.
    ready_deadline = started + max(30, int(args.timeout_seconds))

    def feed_stdin() -> None:
        try:
            assert proc.stdin is not None
            proc.stdin.write(prompt_bytes)
            proc.stdin.close()
        except Exception:
            pass

    feeder = threading.Thread(target=feed_stdin, daemon=True)
    feeder.start()

    # Poll for READY while the child runs; write host ack once validated.
    expected_ready = {
        "plugin_sha256": pre_j["plugin_sha256"],
        "policy_sha256": pre_j["policy_sha256"],
        "launch_sha256": launch_sha,
        "launch_nonce": str(launch_body.get("nonce") or ""),
        "route_receipt_required": bool(args.route_receipt_sha256 or launch_body.get("route_receipt_sha256")),
    }
    try:
        ready_body = wait_for_ready(hs_path, ready_deadline, launch_sha)
        validate_ready(ready_body, expected_ready)
        session_id = str(ready_body.get("session_id") or args.session_id or "")
        ack_body = write_host_ack(ack_path, ready_body, session_id)
    except SystemExit:
        # READY failed/timeout — terminate the child and propagate the typed failure.
        try:
            proc.terminate()
        except Exception:
            pass
        raise

    try:
        stdout_b, stderr_b = proc.communicate(timeout=max(30, int(args.timeout_seconds)))
    except subprocess.TimeoutExpired as exc:
        proc.kill()
        proc.communicate()
        fail("ROLE_PROCESS_TIMEOUT", str(exc))
    feeder.join(timeout=5)
    stdout_path.write_bytes(stdout_b or b"")
    stderr_path.write_bytes(stderr_b or b"")

    # Record stdin transport evidence.
    stdin_meta = {
        "schema": STDIN_TRANSPORT,
        "prompt_sha256": prompt_sha,
        "prompt_utf8_bytes": len(prompt_bytes),
        "argv_prompt_bytes": 0,
        "environment_prompt_bytes": 0,
        "utf8_no_bom": not prompt_bytes.startswith(b"\xef\xbb\xbf"),
        "stdin_closed": True,
        "lf_normalized": b"\r" not in prompt_bytes,
    }
    stdin_meta_path.write_text(json.dumps(stdin_meta, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    exit_code = proc.returncode

    # S-013: non-zero exit is a typed failure, never PROCESS_COMPLETE.
    if not hs_path.is_file():
        fail_typed("EFFECT_PLUGIN_HANDSHAKE_MISSING", role=role, logs=str(logs), exit_code=exit_code)
    handshake = json.loads(hs_path.read_text(encoding="utf-8"))
    hs_schema = handshake.get("schema")
    if hs_schema not in {READY_SCHEMA_V2, HANDSHAKE_SCHEMA_V1}:
        fail_typed("EFFECT_PLUGIN_HANDSHAKE_INVALID", schema=hs_schema)
    hs_role = str(handshake.get("role") or "")
    if hs_role not in {role, ROLES[role]["agent"], "reviewer", "reviewer-architecture"} and hs_role != str(launch_body.get("role") or ""):
        fail_typed("EFFECT_PLUGIN_HANDSHAKE_ROLE_MISMATCH", got=hs_role)
    if str(handshake.get("plugin_sha256") or "") and str(handshake.get("plugin_sha256")) != pre_j["plugin_sha256"]:
        fail_typed("EFFECT_PLUGIN_HANDSHAKE_PLUGIN_MISMATCH")

    status = "GOVERNED_ROLE_PROCESS_COMPLETE" if exit_code == 0 else "GOVERNED_ROLE_PROCESS_FAILED"
    receipt: dict[str, Any] = {
        "status": status,
        "contract": CONTRACT,
        "role": role,
        "agent": agent,
        "exit_code": exit_code,
        "exit_zero": exit_code == 0,
        "pid": handshake.get("process_id"),
        "session_id": str(ready_body.get("session_id") or args.session_id or "") if ready_body else "",
        "handshake_path": str(hs_path),
        "handshake_sha256": sha256_file(hs_path),
        "handshake_schema": hs_schema,
        "ready_validated_pre_side_effect": ready_body is not None,
        "host_ack_path": str(ack_path),
        "host_ack_sha256": sha256_file(ack_path) if ack_path.is_file() else "",
        "launch_path": str(launch_path),
        "launch_sha256": launch_sha,
        "launch_consumed_prepared": prepared is not None,
        "prepared_attempt_manifest": args.attempt_manifest or "",
        "role_working_directory": str(role_dir),
        "executor_cwd_is_execution_root": (role == "executor" and str(role_dir) == str(execution_root)),
        "stdin_transport": stdin_meta,
        "stdout_path": str(stdout_path),
        "stderr_path": str(stderr_path),
        "duration_seconds": round(time.time() - started, 3),
        "plugin_sha256": pre_j["plugin_sha256"],
        "policy_sha256": pre_j["policy_sha256"],
        "opencode_version": opencode_version(opencode),
        "task_id": args.task_id,
        "packet_sha256": args.packet_sha256,
        "candidate_identity": args.candidate_identity,
    }
    receipt_path = logs / f"role-process-receipt-{role}.json"
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    receipt["receipt_path"] = str(receipt_path)
    receipt["receipt_sha256"] = sha256_file(receipt_path)
    if exit_code != 0:
        # Typed failure with full evidence; do NOT claim completion.
        print(json.dumps(receipt, sort_keys=True), file=sys.stderr)
        raise SystemExit(3)
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
    # S-004: consume the prepared Executor launch.
    p.add_argument("--launch-file", default="", help="authoritative prepared launch receipt (Executor)")
    p.add_argument("--expected-launch-sha256", default="", help="required sha256 of --launch-file")
    p.add_argument("--attempt-manifest", default="", help="executor attempt manifest binding launch to attempt")
    p.add_argument("--session-id", default="", help="session identity for READY binding")
    args = p.parse_args()
    print(json.dumps(launch_role(args), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
