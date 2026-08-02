#!/usr/bin/env python3
"""Build a sanitised 3.7.4-format orphan transaction + forensic evidence bundle for 3.7.6 tests.

Does not contain private project data. Writes under the provided output directory.
"""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time
import zipfile


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def tree_hash(path: pathlib.Path) -> str:
    if not path.exists():
        return "ABSENT"
    rows = []
    for item in sorted(path.rglob("*")):
        rel = item.relative_to(path).as_posix()
        if item.is_symlink():
            rows.append(f"{rel}\tSYMLINK:{os.readlink(item)}")
        elif item.is_file():
            rows.append(f"{rel}\t{sha256_file(item)}")
    return sha256_text("\n".join(rows))


def write(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Force LF so hashes are stable across Windows/Unix.
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def main() -> int:
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "legacy-374-fixture").resolve()
    if out.exists():
        shutil.rmtree(out)
    ws = out / "workspace"
    repo = ws / "Source_Code"
    task = "TASK-LEGACY-001"
    # Baseline workspace (non-git outer) + nested git repo
    write(ws / ".ai" / "STATUS.md", "workspace-status-before\n")
    write(ws / ".ai" / "PROJECT_HISTORY.md", "# history before\n")
    write(repo / "app" / "file.php", "<?php // app unchanged\n")
    write(repo / ".ai" / "STATUS.md", "repo-status-before\n")
    write(repo / ".ai" / "RUN_STATE.json", '{"state":"DISCOVERY"}\n')
    task_dir = repo / ".ai" / "tasks" / task
    write(
        task_dir / "RUN_STATE.json",
        json.dumps(
            {
                "task_id": task,
                "state": "DISCOVERY",
                "current_phase": "DISCOVERY",
                "next_required_phase": "PLANNING",
                "next_action": {"kind": "resume", "command": "/ai-resume"},
            },
            indent=2,
        )
        + "\n",
    )
    subprocess.run(["git", "init"], cwd=repo, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=repo, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.name", "Test"], cwd=repo, check=True, capture_output=True)
    subprocess.run(["git", "add", "."], cwd=repo, check=True, capture_output=True)
    subprocess.run(["git", "commit", "--no-verify", "-qm", "base"], cwd=repo, check=True, capture_output=True)
    head = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    idx_path = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "--git-path", "index"], text=True).strip()
    idx = pathlib.Path(idx_path) if pathlib.Path(idx_path).is_absolute() else (repo / idx_path)
    index_hash = sha256_file(idx) if idx.is_file() else "ABSENT"

    # Snapshot outer .ai only (3.7.4 single-root)
    tx = out / "transaction"
    snap = tx / "ai-snapshot"
    shutil.copytree(ws / ".ai", snap)
    ai_hash = tree_hash(snap)
    arguments = f"{task}\nlegacy handoff body\n"
    arguments_hash = sha256_text(arguments)
    # Legacy NON_GIT fingerprint placeholder (not used for equality in 3.7.6)
    legacy_fp = sha256_text(f"PROJECT_STATE_FINGERPRINT_V1\nMODE=NON_GIT\nTREE=legacy-placeholder\nHEAD=N/A\nINDEX=N/A\nSUBMODULES=N/A")
    meta = {
        "schema": "ARCHITECT_TRANSACTION_V2",
        "compatibility": "ARCHITECT_TRANSACTION_V1",
        "command": "ai-resume",
        "task_id": task,
        "arguments_sha256": arguments_hash,
        "prompt_transport": "stdin",
        "prompt_transport_contract": "ARCHITECT_STDIN_PROMPT_TRANSPORT_V1",
        "arguments_utf8_bytes": len(arguments.encode("utf-8")),
        "argv_prompt_bytes": 0,
        "checkpoint_sha256": sha256_file(task_dir / "RUN_STATE.json"),
        "project_dir": str(ws),
        "pid": 1,  # dead PID on almost all systems after reassignment; tests use a free PID
        "started_at_utc": "2026-08-01T12:00:00Z",
        "ai_existed": True,
        "ai_hash": ai_hash,
        "project_state_fingerprint": legacy_fp,
        "permission_contract": "ARCHITECT_HEADLESS_PERMISSION_CONTRACT_V1",
        "runtime_policy_sha256": "0" * 64,
        "governance_version": "3.7.4",
    }
    # Use an almost-certainly-dead PID
    meta["pid"] = 999999
    meta_text = json.dumps(meta, separators=(",", ":"))
    write(tx / "meta.json", meta_text)
    tx_hash = sha256_text(meta_text)

    # Architect "completes" planning — advance both governance roots
    write(ws / ".ai" / "STATUS.md", "workspace-status-after\n")
    write(ws / ".ai" / "PROJECT_HISTORY.md", "# history after planning\n")
    write(repo / ".ai" / "STATUS.md", "repo-status-after\n")
    write(repo / ".ai" / "RUN_STATE.json", '{"state":"READY_FOR_EXECUTION"}\n')
    plan_body = f"PLAN: LEGACY-PLAN-V1\nTask {task}\n"
    packet_body = f"PACKET: LEGACY-PACKET-V1\nTask {task}\n"
    write(task_dir / "PLAN.md", plan_body)
    write(task_dir / "EXECUTION_PACKET.md", packet_body)
    run_state = {
        "task_id": task,
        "state": "READY_FOR_EXECUTION",
        "current_phase": "READY_FOR_EXECUTION",
        "next_required_phase": "IMPLEMENTING",
        "next_action": {"kind": "execute", "command": "/ai-execute"},
        "a5_attempt_status": "PENDING_DELEGATION",
        "source_modified": False,
        "application_commit_created": False,
    }
    write(task_dir / "RUN_STATE.json", json.dumps(run_state, indent=2) + "\n")
    plan_hash = sha256_file(task_dir / "PLAN.md")
    packet_hash = sha256_file(task_dir / "EXECUTION_PACKET.md")
    checkpoint_hash = sha256_file(task_dir / "RUN_STATE.json")

    stdout = (
        "ARCHITECT_PROMPT_TRANSPORT contract=ARCHITECT_STDIN_PROMPT_TRANSPORT_V1 mode=stdin argv_prompt_bytes=0\n"
        f"GOVERNANCE_RESULT\nTASK_ID: {task}\nSTATE: READY_FOR_EXECUTION\nNEXT_COMMAND: /ai-execute\n"
    )
    stderr = "architect started\n"
    # hashes of files as written (LF)
    write(out / "_tmp_stdout.log", stdout)
    write(out / "_tmp_stderr.log", stderr)
    stdout_hash = sha256_file(out / "_tmp_stdout.log")
    stderr_hash = sha256_file(out / "_tmp_stderr.log")
    (out / "_tmp_stdout.log").unlink()
    (out / "_tmp_stderr.log").unlink()

    # Build forensic bundle
    bundle_root = out / "bundle-src"
    write(bundle_root / "transaction" / "meta.json", meta_text)
    write(bundle_root / "attempt" / "stdout.log", stdout)
    write(bundle_root / "attempt" / "stderr.log", stderr)
    write(bundle_root / "attempt" / "transport.txt", "ARCHITECT_STDIN_PROMPT_TRANSPORT_V1\nmode=stdin\n")
    write(bundle_root / "git" / "HEAD", head + "\n")
    write(bundle_root / "git" / "index.sha256", index_hash + "\n")
    write(bundle_root / "git" / "dependency-hashes.json", "{}\n")

    # Non-managed inventory AFTER governance advance (app still original)
    # Inventory excludes managed roots; only app/file.php
    inv = {"Source_Code/app/file.php": sha256_file(repo / "app" / "file.php")}
    write(bundle_root / "inventory" / "workspace-files.json", json.dumps(inv, indent=2) + "\n")
    allow = {
        "paths": [
            ".ai/STATUS.md",
            ".ai/PROJECT_HISTORY.md",
            "Source_Code/.ai/STATUS.md",
            "Source_Code/.ai/RUN_STATE.json",
            f"Source_Code/.ai/tasks/{task}/PLAN.md",
            f"Source_Code/.ai/tasks/{task}/EXECUTION_PACKET.md",
            f"Source_Code/.ai/tasks/{task}/RUN_STATE.json",
        ]
    }
    write(bundle_root / "inventory" / "changed-paths.json", json.dumps(allow, indent=2) + "\n")

    # MANIFEST
    entries = []
    for path in sorted(bundle_root.rglob("*")):
        if path.is_file():
            rel = path.relative_to(bundle_root).as_posix()
            entries.append((rel, sha256_file(path)))
    man_lines = [f"{digest}  {rel}" for rel, digest in entries]
    write(bundle_root / "MANIFEST.txt", "\n".join(man_lines) + "\n")

    zip_path = out / "evidence-bundle.zip"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(bundle_root.rglob("*")):
            if path.is_file():
                zf.write(path, path.relative_to(bundle_root).as_posix())
    bundle_hash = sha256_file(zip_path)

    summary = {
        "task_id": task,
        "workspace": str(ws),
        "repository": str(repo),
        "transaction_dir": str(tx),
        "transaction_meta_sha256": tx_hash,
        "evidence_bundle": str(zip_path),
        "evidence_bundle_sha256": bundle_hash,
        "arguments_sha256": arguments_hash,
        "plan_sha256": plan_hash,
        "execution_packet_sha256": packet_hash,
        "checkpoint_sha256": checkpoint_hash,
        "stdout_sha256": stdout_hash,
        "stderr_sha256": stderr_hash,
        "repository_head": head,
        "index_sha256": index_hash,
    }
    write(out / "SUMMARY.json", json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
