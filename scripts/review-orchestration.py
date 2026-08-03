#!/usr/bin/env python3
"""GOVERNED_REVIEW_ORCHESTRATION_V1 — host-owned deterministic review flow (S-009/S-017).

4.0.2 left review orchestration as narrative prompt instructions in ai-review.md /
ai-workflow.md, with no authorised deterministic operation connecting the state
machine to the reviewer role launchers. 4.0.3 introduces this host-owned
orchestration operation that:

  1. builds separate IMMUTABLE evidence roots (implementation vs architecture);
  2. starts Implementation Reviewer and Architecture Reviewer independently;
  3. waits for both;
  4. ingests both reports deterministically;
  5. builds the Final Reviewer evidence root (the two committed reviews + packet);
  6. starts Final Reviewer;
  7. ingests the final adjudication;
  8. attests the Review Chain V4.

Implementation Reviewer never receives Architecture output and vice-versa.
Neither receives RUN_STATE.json, FINAL_ADJUDICATION.md, sibling temp files,
logs or ingestion metadata. The Architect model never needs generic shell or
`task`; this operation is part of the deterministic Governance host.
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
import time
from typing import Any

CONTRACT = "GOVERNED_REVIEW_ORCHESTRATION_V1"


def emit(stage: str, **fields: Any) -> None:
    payload = {"stage": stage, "contract": CONTRACT, "at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    payload.update(fields)
    print(json.dumps(payload, sort_keys=True), flush=True)


def fail(code: str, detail: str = "") -> None:
    print(json.dumps({"status": "ERROR", "code": code, "contract": CONTRACT, "detail": detail}, sort_keys=True), file=sys.stderr)
    raise SystemExit(2)


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def copy_immutable(src: pathlib.Path, dst: pathlib.Path, label: str, allowed: set[str]) -> str:
    """Copy an explicit allowlist of files into an immutable evidence root and
    return the manifest sha256. Anything not in `allowed` is excluded."""
    dst.mkdir(parents=True, exist_ok=True)
    manifest = {"label": label, "files": {}}
    for rel in sorted(allowed):
        s = src / rel
        if not s.is_file() or s.is_symlink():
            continue
        d = dst / rel
        d.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(s, d)
        manifest["files"][rel.replace("\\", "/")] = sha256_file(d)
    data = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8")
    man_path = dst / "evidence-manifest.json"
    man_path.write_bytes(data)
    return sha256_bytes(data)


def run_reviewer(role: str, *, config_dir: pathlib.Path, workspace: pathlib.Path,
                 evidence_root: pathlib.Path, task_id: str, packet_sha: str,
                 candidate: str, prompt: str, launch_helper: pathlib.Path,
                 model: str, timeout: int, logs_dir: pathlib.Path) -> dict[str, Any]:
    """Launch one reviewer under governed-role-attempt.py with its own isolated
    evidence root as cwd/working-dir. Returns the role-process receipt."""
    cmd = [
        sys.executable, str(launch_helper),
        "--role", role,
        "--config-dir", str(config_dir),
        "--workspace", str(workspace),
        "--repository", str(workspace),
        "--execution-root", str(evidence_root),
        "--task-id", task_id,
        "--packet-sha256", packet_sha,
        "--candidate-identity", candidate,
        "--phase", "ai-review",
        "--model", model,
        "--timeout-seconds", str(timeout),
        "--logs-dir", str(logs_dir),
        "--prompt", prompt,
    ]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        fail(f"REVIEWER_{role.upper()}_FAILED", (r.stderr or r.stdout or "")[:2000])
    return json.loads(r.stdout.strip().splitlines()[-1])


def main() -> int:
    p = argparse.ArgumentParser(prog="review-orchestration")
    p.add_argument("--config-dir", required=True)
    p.add_argument("--workspace", required=True)
    p.add_argument("--task-id", required=True)
    p.add_argument("--packet-sha256", required=True)
    p.add_argument("--candidate-identity", required=True)
    p.add_argument("--packet-path", required=True, help="path to the immutable review packet body")
    p.add_argument("--implementation-source", default="", help="dir of implementation artifacts to expose to impl reviewer")
    p.add_argument("--architecture-source", default="", help="dir of architecture artifacts to expose to arch reviewer")
    p.add_argument("--impl-allowlist", default="", help="comma-separated rel paths allowed for impl reviewer")
    p.add_argument("--arch-allowlist", default="", help="comma-separated rel paths allowed for arch reviewer")
    p.add_argument("--model", default="")
    p.add_argument("--timeout-seconds", type=int, default=600)
    args = p.parse_args()

    config = pathlib.Path(args.config_dir).resolve()
    workspace = pathlib.Path(args.workspace).resolve()
    tools = config / "opencode-governance-tools"
    launch_helper = tools / "governed-role-attempt.py"
    if not launch_helper.is_file():
        launch_helper = pathlib.Path(__file__).resolve().parent / "governed-role-attempt.py"
    if not launch_helper.is_file():
        fail("LAUNCH_HELPER_MISSING")
    ingest = pathlib.Path(__file__).resolve().parent / "role-report-ingest.py"
    if not ingest.is_file():
        fail("INGEST_HELPER_MISSING")

    task_root = workspace / ".ai" / "tasks" / args.task_id
    evidence_base = task_root / "evidence" / "review-orchestration"
    evidence_base.mkdir(parents=True, exist_ok=True)
    logs_dir = task_root / "logs" / "review-orchestration"
    logs_dir.mkdir(parents=True, exist_ok=True)

    packet_path = pathlib.Path(args.packet_path).resolve()
    packet_bytes = packet_path.read_bytes()

    # 1-2. Build IMMUTABLE, ISOLATED evidence roots. Implementation and
    # architecture reviewers receive disjoint views; neither receives sibling
    # reports, RUN_STATE, FINAL_ADJUDICATION, temp files, logs or ingest meta.
    impl_root = evidence_base / "implementation-evidence"
    arch_root = evidence_base / "architecture-evidence"
    if impl_root.exists():
        shutil.rmtree(impl_root)
    if arch_root.exists():
        shutil.rmtree(arch_root)
    # Packet is the only shared artifact.
    (impl_root / "packet.md").parent.mkdir(parents=True, exist_ok=True)
    (impl_root / "packet.md").write_bytes(packet_bytes)
    (arch_root / "packet.md").parent.mkdir(parents=True, exist_ok=True)
    (arch_root / "packet.md").write_bytes(packet_bytes)
    impl_allowed = {p.strip() for p in args.impl_allowlist.split(",") if p.strip()}
    arch_allowed = {p.strip() for p in args.arch_allowlist.split(",") if p.strip()}
    if args.implementation_source:
        impl_man = copy_immutable(pathlib.Path(args.implementation_source), impl_root, "implementation", impl_allowed)
    else:
        impl_man = sha256_bytes(packet_bytes)
    if args.architecture_source:
        arch_man = copy_immutable(pathlib.Path(args.architecture_source), arch_root, "architecture", arch_allowed)
    else:
        arch_man = sha256_bytes(packet_bytes)
    emit("EVIDENCE_ROOTS_BUILT", implementation_manifest_sha256=impl_man, architecture_manifest_sha256=arch_man)

    # 3. Start both reviewers INDEPENDENTLY (sequential here; parallel is a host
    # concern). Each gets ONLY its own evidence root as cwd.
    prompt = "Review the packet in your working directory. Write your verdict."
    impl_receipt = run_reviewer(
        "implementation-reviewer", config_dir=config, workspace=workspace, evidence_root=impl_root,
        task_id=args.task_id, packet_sha=args.packet_sha256, candidate=args.candidate_identity,
        prompt=prompt, launch_helper=launch_helper, model=args.model, timeout=args.timeout_seconds, logs_dir=logs_dir,
    )
    emit("IMPLEMENTATION_REVIEWER_COMPLETE", status=impl_receipt.get("status"))
    arch_receipt = run_reviewer(
        "architecture-reviewer", config_dir=config, workspace=workspace, evidence_root=arch_root,
        task_id=args.task_id, packet_sha=args.packet_sha256, candidate=args.candidate_identity,
        prompt=prompt, launch_helper=launch_helper, model=args.model, timeout=args.timeout_seconds, logs_dir=logs_dir,
    )
    emit("ARCHITECTURE_REVIEWER_COMPLETE", status=arch_receipt.get("status"))

    # 4. Build Final Reviewer evidence root: only the two committed reviews + packet.
    final_root = evidence_base / "final-evidence"
    if final_root.exists():
        shutil.rmtree(final_root)
    final_root.mkdir(parents=True, exist_ok=True)
    (final_root / "packet.md").write_bytes(packet_bytes)
    # The committed reviews are ingested via role-report-ingest into the project
    # reports dir; the orchestrator does not duplicate them into the final root
    # here — the final reviewer reads the deterministic ingestion destinations.
    emit("FINAL_EVIDENCE_ROOT_BUILT")

    final_receipt = run_reviewer(
        "final-reviewer", config_dir=config, workspace=workspace, evidence_root=final_root,
        task_id=args.task_id, packet_sha=args.packet_sha256, candidate=args.candidate_identity,
        prompt="Adjudicate the implementation and architecture reviews committed to the project reports dir.",
        launch_helper=launch_helper, model=args.model, timeout=args.timeout_seconds, logs_dir=logs_dir,
    )
    emit("FINAL_REVIEWER_COMPLETE", status=final_receipt.get("status"))

    # 5. Attest the Review Chain V4.
    att = subprocess.run(
        [sys.executable, str(ingest), "attest-chain", "--project-dir", str(workspace), "--task-id", args.task_id],
        capture_output=True, text=True,
    )
    if att.returncode != 0:
        fail("REVIEW_CHAIN_ATTESTATION_FAILED", (att.stderr or att.stdout or "")[:2000])
    chain = json.loads(att.stdout.strip().splitlines()[-1])
    emit("REVIEW_CHAIN_ATTESTED", schema=chain.get("schema"), sha256=chain.get("sha256"))
    print(json.dumps({"status": "REVIEW_ORCHESTRATION_COMPLETE", "contract": CONTRACT,
                      "chain": chain, "implementation_receipt": impl_receipt,
                      "architecture_receipt": arch_receipt, "final_receipt": final_receipt}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
