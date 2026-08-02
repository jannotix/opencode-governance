#!/usr/bin/env python3
"""DETERMINISTIC_ROLE_REPORT_INGESTION_V1 — controlled channel for reviewer/final reports."""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import time
from typing import Any

SCHEMA = "opencode-governance.role-report/v1"
CHAIN_SCHEMA = "REVIEW_CHAIN_ATTESTATION_V1"
ALLOWED_ROLES = {
    "implementation-reviewer": "REVIEW_IMPLEMENTATION.md",
    "architecture-reviewer": "REVIEW_ARCHITECTURE.md",
    "final-reviewer": "FINAL_ADJUDICATION.md",
}


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def ingest(project: pathlib.Path, envelope_path: pathlib.Path, body_path: pathlib.Path) -> dict[str, Any]:
    envelope = json.loads(envelope_path.read_text(encoding="utf-8-sig"))
    if envelope.get("schema") != SCHEMA:
        raise SystemExit(json.dumps({"status": "ERROR", "code": "ROLE_REPORT_SCHEMA_INVALID"}))
    role = envelope.get("role")
    if role not in ALLOWED_ROLES:
        raise SystemExit(json.dumps({"status": "ERROR", "code": "ROLE_REPORT_ROLE_INVALID", "detail": str(role)}))
    body = body_path.read_text(encoding="utf-8")
    body_hash = sha256_text(body)
    if envelope.get("report_body_sha256") != body_hash:
        raise SystemExit(json.dumps({"status": "ERROR", "code": "ROLE_REPORT_BODY_HASH_MISMATCH"}))
    for field in ("task_id", "packet_sha256", "candidate_identity", "verdict"):
        if not envelope.get(field):
            raise SystemExit(json.dumps({"status": "ERROR", "code": "ROLE_REPORT_FIELD_MISSING", "detail": field}))
    if envelope.get("secret_scan") not in {"PASS", "N/A"}:
        raise SystemExit(json.dumps({"status": "ERROR", "code": "ROLE_REPORT_SECRET_SCAN_REQUIRED"}))
    out_name = ALLOWED_ROLES[role]
    task_id = str(envelope["task_id"])
    dest_dir = project / ".ai" / "tasks" / task_id / "reports"
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / out_name
    # Only the ingestion channel may write these files.
    dest.write_text(body, encoding="utf-8", newline="\n")
    meta = {
        "schema": SCHEMA,
        "role": role,
        "task_id": task_id,
        "packet_sha256": envelope["packet_sha256"],
        "candidate_identity": envelope["candidate_identity"],
        "evidence_manifest_sha256": envelope.get("evidence_manifest_sha256") or "",
        "route_id": envelope.get("route_id") or "",
        "model_family": envelope.get("model_family") or "",
        "report_body_sha256": body_hash,
        "report_path": str(dest.relative_to(project)).replace("\\", "/"),
        "permission_policy_sha256": envelope.get("permission_policy_sha256") or "",
        "ingested_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "verdict": envelope["verdict"],
    }
    meta_path = dest.with_suffix(dest.suffix + ".ingest.json")
    meta_path.write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    return {"status": "ROLE_REPORT_INGESTED", "meta": meta}


def attest_chain(project: pathlib.Path, task_id: str) -> dict[str, Any]:
    base = project / ".ai" / "tasks" / task_id / "reports"
    required = ["REVIEW_IMPLEMENTATION.md", "REVIEW_ARCHITECTURE.md", "FINAL_ADJUDICATION.md"]
    chain = []
    for name in required:
        path = base / name
        meta_path = path.with_suffix(path.suffix + ".ingest.json")
        if not path.is_file() or not meta_path.is_file():
            raise SystemExit(json.dumps({"status": "ERROR", "code": "REVIEW_CHAIN_INCOMPLETE", "detail": name}))
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        chain.append(
            {
                "role": meta.get("role"),
                "route_id": meta.get("route_id"),
                "model_family": meta.get("model_family"),
                "packet_sha256": meta.get("packet_sha256"),
                "candidate_identity": meta.get("candidate_identity"),
                "report_body_sha256": meta.get("report_body_sha256"),
                "permission_policy_sha256": meta.get("permission_policy_sha256"),
                "evidence_manifest_sha256": meta.get("evidence_manifest_sha256"),
            }
        )
    # Independence: implementation vs architecture model families must differ when both set
    families = [c.get("model_family") for c in chain[:2] if c.get("model_family")]
    if len(families) == 2 and families[0] == families[1]:
        raise SystemExit(json.dumps({"status": "ERROR", "code": "REVIEW_INDEPENDENCE_FAMILY_COLLISION"}))
    out = {
        "schema": CHAIN_SCHEMA,
        "task_id": task_id,
        "chain": chain,
        "reviewer_independence": "PASS",
        "attested_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    out_path = base / "REVIEW_CHAIN_ATTESTATION.json"
    body = json.dumps(out, indent=2, sort_keys=True) + "\n"
    out_path.write_text(body, encoding="utf-8", newline="\n")
    return {"status": "REVIEW_CHAIN_ATTESTED", "path": str(out_path), "sha256": sha256_text(body), "attestation": out}


def main() -> int:
    p = argparse.ArgumentParser(prog="role-report-ingest")
    sub = p.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("ingest")
    i.add_argument("--project-dir", required=True)
    i.add_argument("--envelope", required=True)
    i.add_argument("--body", required=True)
    a = sub.add_parser("attest-chain")
    a.add_argument("--project-dir", required=True)
    a.add_argument("--task-id", required=True)
    args = p.parse_args()
    if args.cmd == "ingest":
        result = ingest(pathlib.Path(args.project_dir), pathlib.Path(args.envelope), pathlib.Path(args.body))
        print(json.dumps(result, sort_keys=True))
        return 0
    result = attest_chain(pathlib.Path(args.project_dir), args.task_id)
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
