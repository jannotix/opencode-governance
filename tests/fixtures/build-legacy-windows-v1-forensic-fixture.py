#!/usr/bin/env python3
"""Build a sanitised Windows LEGACY_PROJECT_STATE_FORENSICS_V1 orphan fixture for 3.7.7.

Faithful layout of the pre-3.7.6 PowerShell collector (path\\tsize\\tsha256 MANIFEST,
orphaned-transaction/, attempt-logs/, TSV inventories). No private incident data.
"""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
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
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def write_bytes(path: pathlib.Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def tsv_header() -> str:
    return "TYPE\tRELATIVE_PATH\tSIZE\tATTRIBUTES\tLAST_WRITE_UTC\tSHA256_OR_TARGET"


def tsv_file_row(rel: str, path: pathlib.Path) -> str:
    size = path.stat().st_size
    digest = sha256_file(path)
    return f"FILE\t{rel}\t{size}\tA\t2026-08-01T12:00:00Z\t{digest}"


def tsv_dir_row(rel: str) -> str:
    return f"DIR\t{rel}\t0\tD\t2026-08-01T12:00:00Z\t"


def main() -> int:
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "legacy-windows-v1-fixture").resolve()
    if out.exists():
        shutil.rmtree(out)
    ws = out / "workspace"
    repo = ws / "Source_Code"
    task = "TASK-LEGACY-V1-001"

    # --- baseline (before architect) ---
    write(ws / ".ai" / "STATUS.md", "workspace-status-before\n")
    write(ws / ".ai" / "PROJECT_HISTORY.md", "# history before\n")
    write(repo / "app" / "file.php", "<?php // app unchanged\n")
    # Root dependency manifest so V1 adapter derives dependency-hashes (not empty {}).
    write(repo / "composer.json", '{"name":"fixture/app","require":{}}\n')
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
    # Capture "before" managed inventory paths while they still exist with baseline content
    before_paths = [
        (".ai/STATUS.md", ws / ".ai" / "STATUS.md"),
        (".ai/PROJECT_HISTORY.md", ws / ".ai" / "PROJECT_HISTORY.md"),
        ("Source_Code/.ai/STATUS.md", repo / ".ai" / "STATUS.md"),
        ("Source_Code/.ai/RUN_STATE.json", repo / ".ai" / "RUN_STATE.json"),
        (f"Source_Code/.ai/tasks/{task}/RUN_STATE.json", task_dir / "RUN_STATE.json"),
    ]
    before_rows = [tsv_header()]
    for rel, p in before_paths:
        before_rows.append(tsv_file_row(rel, p))
    ai_before_text = "\n".join(before_rows) + "\n"

    subprocess.run(["git", "init"], cwd=repo, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=repo, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.name", "Test"], cwd=repo, check=True, capture_output=True)
    subprocess.run(["git", "add", "."], cwd=repo, check=True, capture_output=True)
    subprocess.run(["git", "commit", "--no-verify", "-qm", "base"], cwd=repo, check=True, capture_output=True)
    head = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()

    # Snapshot outer .ai only (3.7.4 single-root)
    tx = out / "transaction"
    snap = tx / "ai-snapshot"
    shutil.copytree(ws / ".ai", snap)
    ai_hash = tree_hash(snap)
    arguments = f"{task}\nlegacy windows v1 handoff\n"
    arguments_hash = sha256_text(arguments)
    legacy_fp = sha256_text(
        "PROJECT_STATE_FINGERPRINT_V1\nMODE=NON_GIT\nTREE=legacy-placeholder\nHEAD=N/A\nINDEX=N/A\nSUBMODULES=N/A"
    )
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
        "pid": 999999,
        "started_at_utc": "2026-08-01T12:00:00Z",
        "ai_existed": True,
        "ai_hash": ai_hash,
        "project_state_fingerprint": legacy_fp,
        "permission_contract": "ARCHITECT_HEADLESS_PERMISSION_CONTRACT_V1",
        "runtime_policy_sha256": "0" * 64,
        "governance_version": "3.7.4",
    }
    meta_text = json.dumps(meta, separators=(",", ":"))
    write(tx / "meta.json", meta_text)
    tx_hash = sha256_text(meta_text)

    # --- architect completes planning ---
    write(ws / ".ai" / "STATUS.md", "workspace-status-after\n")
    write(ws / ".ai" / "PROJECT_HISTORY.md", "# history after planning\n")
    write(repo / ".ai" / "STATUS.md", "repo-status-after\n")
    write(repo / ".ai" / "RUN_STATE.json", '{"state":"READY_FOR_EXECUTION"}\n')
    plan_body = f"PLAN: LEGACY-V1-PLAN\nTask {task}\n"
    packet_body = f"PACKET: LEGACY-V1-PACKET\nTask {task}\n"
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

    after_paths = [
        (".ai/STATUS.md", ws / ".ai" / "STATUS.md"),
        (".ai/PROJECT_HISTORY.md", ws / ".ai" / "PROJECT_HISTORY.md"),
        ("Source_Code/.ai/STATUS.md", repo / ".ai" / "STATUS.md"),
        ("Source_Code/.ai/RUN_STATE.json", repo / ".ai" / "RUN_STATE.json"),
        (f"Source_Code/.ai/tasks/{task}/PLAN.md", task_dir / "PLAN.md"),
        (f"Source_Code/.ai/tasks/{task}/EXECUTION_PACKET.md", task_dir / "EXECUTION_PACKET.md"),
        (f"Source_Code/.ai/tasks/{task}/RUN_STATE.json", task_dir / "RUN_STATE.json"),
    ]
    after_rows = [tsv_header()]
    for rel, p in after_paths:
        after_rows.append(tsv_file_row(rel, p))
    ai_after_text = "\n".join(after_rows) + "\n"

    stdout = (
        "ARCHITECT_PROMPT_TRANSPORT contract=ARCHITECT_STDIN_PROMPT_TRANSPORT_V1 mode=stdin argv_prompt_bytes=0\n"
        f"GOVERNANCE_RESULT\nTASK_ID: {task}\nSTATE: READY_FOR_EXECUTION\nNEXT_COMMAND: /ai-execute\n"
    )
    stderr = ""  # empty stderr matches real incident empty-hash class
    write(out / "_tmp_stdout.log", stdout)
    write(out / "_tmp_stderr.log", stderr)
    stdout_hash = sha256_file(out / "_tmp_stdout.log")
    stderr_hash = sha256_file(out / "_tmp_stderr.log")
    (out / "_tmp_stdout.log").unlink()
    (out / "_tmp_stderr.log").unlink()

    # Non-managed inventory (closed set)
    app_rel = "Source_Code/app/file.php"
    composer_rel = "Source_Code/composer.json"
    non_ai_rows = [
        tsv_header(),
        tsv_dir_row("Source_Code"),
        tsv_dir_row("Source_Code/app"),
        tsv_file_row(app_rel, repo / "app" / "file.php"),
        tsv_file_row(composer_rel, repo / "composer.json"),
    ]
    non_ai_text = "\n".join(non_ai_rows) + "\n"
    recent_text = non_ai_text  # supplementary; same closed set for fixture

    # --- V1 bundle layout ---
    bundle = out / "bundle-src"
    write(bundle / "orphaned-transaction" / "meta.json", meta_text)
    shutil.copytree(snap, bundle / "orphaned-transaction" / "ai-snapshot")
    write(bundle / "attempt-logs" / "attempt-1.stdout.log", stdout)
    write(bundle / "attempt-logs" / "attempt-1.stderr.log", stderr)
    # current-task/** = post-attempt task artifacts
    write(bundle / "current-task" / "PLAN.md", plan_body)
    write(bundle / "current-task" / "EXECUTION_PACKET.md", packet_body)
    write(bundle / "current-task" / "RUN_STATE.json", json.dumps(run_state, indent=2) + "\n")
    write(bundle / "project-non-ai-current.tsv", non_ai_text)
    write(bundle / "project-non-ai-recent.tsv", recent_text)
    write(bundle / "ai-before.tsv", ai_before_text)
    write(bundle / "ai-after.tsv", ai_after_text)
    write(bundle / "git-probe.txt", f"HEAD={head}\n{head}\n")
    write(bundle / "git-mode.txt", "MODE=GIT\n")
    write(bundle / "git-status.txt", "clean\n")
    write(bundle / "git-diff.txt", "\n")
    write(bundle / "SUMMARY.txt", "TOR-TEST LEGACY WINDOWS FORENSICS FIXTURE\n")

    # MANIFEST: path\\tsize\\tsha256 with recognised headers
    man_lines = [
        "TOR-004 PROJECT STATE CHANGED FORENSICS",
        "CREATED_AT: 2026-08-01T12:00:00Z",
        "",
        "FILES:",
    ]
    for path in sorted(bundle.rglob("*")):
        if path.is_file():
            rel = path.relative_to(bundle).as_posix()
            size = path.stat().st_size
            dig = sha256_file(path)
            man_lines.append(f"{rel}\t{size}\t{dig}")
    write(bundle / "MANIFEST.txt", "\n".join(man_lines) + "\n")
    manifest_hash = sha256_file(bundle / "MANIFEST.txt")

    zip_path = out / "evidence-bundle.zip"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(bundle.rglob("*")):
            if path.is_file():
                zf.write(path, path.relative_to(bundle).as_posix())
    bundle_hash = sha256_file(zip_path)

    summary = {
        "task_id": task,
        "workspace": str(ws),
        "repository": str(repo),
        "transaction_dir": str(tx),
        "transaction_meta_sha256": tx_hash,
        "evidence_bundle": str(zip_path),
        "evidence_bundle_sha256": bundle_hash,
        "evidence_manifest_sha256": manifest_hash,
        "arguments_sha256": arguments_hash,
        "plan_sha256": plan_hash,
        "execution_packet_sha256": packet_hash,
        "checkpoint_sha256": checkpoint_hash,
        "stdout_sha256": stdout_hash,
        "stderr_sha256": stderr_hash,
        "repository_head": head,
        "source_evidence_format": "LEGACY_PROJECT_STATE_FORENSICS_V1",
        "adapter_contract": "LEGACY_FORENSIC_BUNDLE_V1_ADAPTER",
    }
    write(out / "SUMMARY.json", json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
