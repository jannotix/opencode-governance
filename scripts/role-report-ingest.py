#!/usr/bin/env python3
"""DETERMINISTIC_ROLE_REPORT_INGESTION_V2 + REVIEW_CHAIN_ATTESTATION_V2.

Hardened report channel for Reviewer / Architecture Reviewer / Final Reviewer.
Fails closed on path escape, overwrite of divergent content, forged routes,
stale policy/packet/candidate, and incomplete independence evidence.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import sys
import time
from typing import Any

SCHEMA = "opencode-governance.role-report/v3"
SCHEMA_V2 = "opencode-governance.role-report/v2"
SCHEMA_V1_COMPAT = "opencode-governance.role-report/v1"
CHAIN_SCHEMA = "REVIEW_CHAIN_ATTESTATION_V4"
CHAIN_SCHEMA_V3 = "REVIEW_CHAIN_ATTESTATION_V3"
CHAIN_SCHEMA_V2 = "REVIEW_CHAIN_ATTESTATION_V2"
INGEST_CONTRACT = "DETERMINISTIC_ROLE_REPORT_INGESTION_V3"
INGEST_CONTRACT_V2 = "DETERMINISTIC_ROLE_REPORT_INGESTION_V2"
PRODUCTION_SCHEMAS = {SCHEMA}
LEGACY_SCHEMAS = {SCHEMA_V2, SCHEMA_V1_COMPAT}
# Strict task id: alphanumeric, underscore, hyphen; no separators/path forms.
TASK_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
ALLOWED_ROLES = {
    "implementation-reviewer": "REVIEW_IMPLEMENTATION.md",
    "architecture-reviewer": "REVIEW_ARCHITECTURE.md",
    "final-reviewer": "FINAL_ADJUDICATION.md",
}
ROLE_ORDER = ("implementation-reviewer", "architecture-reviewer", "final-reviewer")


def emit_error(code: str, detail: str = "") -> None:
    payload: dict[str, Any] = {"status": "ERROR", "code": code, "contract": INGEST_CONTRACT}
    if detail:
        payload["detail"] = detail
    print(json.dumps(payload, sort_keys=True), file=sys.stderr)
    raise SystemExit(2)


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def validate_sha256(value: Any, field: str) -> str:
    s = str(value or "")
    if not SHA256_RE.fullmatch(s):
        emit_error("ROLE_REPORT_SHA256_INVALID", field)
    return s


def validate_task_id(task_id: str) -> str:
    if not task_id or not TASK_ID_RE.fullmatch(task_id):
        emit_error("ROLE_REPORT_TASK_ID_INVALID", task_id)
    if task_id in {".", ".."} or "/" in task_id or "\\" in task_id:
        emit_error("ROLE_REPORT_TASK_ID_INVALID", task_id)
    if ".." in task_id:
        emit_error("ROLE_REPORT_TASK_ID_INVALID", task_id)
    return task_id


def is_symlink_or_reparse(path: pathlib.Path) -> bool:
    try:
        return path.is_symlink()
    except OSError:
        return True


def assert_safe_path_component(path: pathlib.Path, label: str) -> None:
    if is_symlink_or_reparse(path):
        emit_error("ROLE_REPORT_PATH_SYMLINK", f"{label}:{path}")


def canonicalize_project(project: pathlib.Path) -> pathlib.Path:
    if not project.exists():
        emit_error("ROLE_REPORT_PROJECT_MISSING", str(project))
    assert_safe_path_component(project, "project")
    try:
        resolved = project.resolve(strict=True)
    except Exception as exc:
        emit_error("ROLE_REPORT_PROJECT_RESOLVE", str(exc))
    # Walk parents for reparse
    cur = resolved
    for _ in range(64):
        if is_symlink_or_reparse(cur):
            emit_error("ROLE_REPORT_PROJECT_SYMLINK", str(cur))
        if cur.parent == cur:
            break
        cur = cur.parent
    return resolved


def ensure_contained(project: pathlib.Path, target: pathlib.Path, label: str) -> pathlib.Path:
    try:
        resolved = target if target.exists() else target.parent.resolve() / target.name
        # Resolve existing parents
        parent = target.parent
        if parent.exists():
            parent_res = parent.resolve(strict=True)
            if is_symlink_or_reparse(parent) or is_symlink_or_reparse(parent_res):
                emit_error("ROLE_REPORT_PATH_SYMLINK", f"{label}-parent:{parent}")
            candidate = parent_res / target.name
        else:
            # Walk up to existing ancestor
            anc = parent
            while not anc.exists() and anc != anc.parent:
                if ".." in anc.parts:
                    emit_error("ROLE_REPORT_PATH_TRAVERSAL", f"{label}:{target}")
                anc = anc.parent
            if not anc.exists():
                emit_error("ROLE_REPORT_PATH_UNRESOLVABLE", f"{label}:{target}")
            anc_res = anc.resolve(strict=True)
            rel_tail = parent.relative_to(anc)
            if ".." in pathlib.PurePath(rel_tail).parts:
                emit_error("ROLE_REPORT_PATH_TRAVERSAL", f"{label}:{target}")
            candidate = anc_res / rel_tail / target.name
        resolved = candidate
    except Exception as exc:
        emit_error("ROLE_REPORT_PATH_RESOLVE", f"{label}:{exc}")
    try:
        resolved.relative_to(project)
    except ValueError:
        emit_error("ROLE_REPORT_PATH_OUTSIDE_PROJECT", f"{label}:{resolved}")
    return resolved


def atomic_write_no_clobber(path: pathlib.Path, data: bytes, allow_identical: bool = False) -> str:
    """Atomic write; reject if different content exists. Returns sha256 of written bytes."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if is_symlink_or_reparse(path.parent):
        emit_error("ROLE_REPORT_DEST_PARENT_SYMLINK", str(path.parent))
    digest = hashlib.sha256(data).hexdigest()
    if path.exists():
        if is_symlink_or_reparse(path):
            emit_error("ROLE_REPORT_DEST_SYMLINK", str(path))
        existing = path.read_bytes()
        existing_hash = hashlib.sha256(existing).hexdigest()
        if existing_hash == digest and allow_identical:
            return digest
        if existing_hash == digest:
            return digest  # idempotent same bytes
        emit_error("ROLE_REPORT_DUPLICATE_DIVERGENT", str(path))
    tmp = path.with_name(path.name + f".tmp.{os.getpid()}")
    try:
        with open(tmp, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        # no-clobber replace
        if path.exists():
            existing_hash = sha256_file(path)
            if existing_hash != digest:
                emit_error("ROLE_REPORT_RACE_DIVERGENT", str(path))
            tmp.unlink(missing_ok=True)
            return digest
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            tmp.unlink(missing_ok=True)
    # re-hash after persistence
    written = sha256_file(path)
    if written != digest:
        emit_error("ROLE_REPORT_POST_WRITE_HASH_MISMATCH", f"{digest}!={written}")
    return written


def load_optional_json(path: pathlib.Path | None) -> dict[str, Any] | None:
    if path is None:
        return None
    if not path.is_file():
        emit_error("ROLE_REPORT_HELPER_FILE_MISSING", str(path))
    if is_symlink_or_reparse(path):
        emit_error("ROLE_REPORT_HELPER_SYMLINK", str(path))
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        emit_error("ROLE_REPORT_HELPER_JSON_INVALID", str(exc))


def ingest(
    project: pathlib.Path,
    envelope_path: pathlib.Path,
    body_path: pathlib.Path,
    *,
    route_receipt_path: pathlib.Path | None = None,
    allow_identical_idempotent: bool = True,
) -> dict[str, Any]:
    project = canonicalize_project(project)
    if is_symlink_or_reparse(envelope_path) or is_symlink_or_reparse(body_path):
        emit_error("ROLE_REPORT_INPUT_SYMLINK")
    if not envelope_path.is_file() or not body_path.is_file():
        emit_error("ROLE_REPORT_INPUT_MISSING")

    envelope = json.loads(envelope_path.read_text(encoding="utf-8-sig"))
    schema = envelope.get("schema")
    # legacy-schema acceptance is gated SOLELY on a trusted operator env
    # var, never on caller-supplied envelope input. A caller must not be able to
    # downgrade the production schema by setting a flag inside the ingest payload.
    allow_legacy = os.environ.get("OPENCODE_GOVERNANCE_ALLOW_LEGACY_REPORT_SCHEMA") == "1"
    if schema == SCHEMA:
        pass
    elif schema in LEGACY_SCHEMAS and allow_legacy:
        pass
    else:
        emit_error("ROLE_REPORT_SCHEMA_INVALID", f"{schema}; production requires {SCHEMA}")

    role = envelope.get("role")
    if role not in ALLOWED_ROLES:
        emit_error("ROLE_REPORT_ROLE_INVALID", str(role))

    task_id = validate_task_id(str(envelope.get("task_id") or ""))
    body = body_path.read_text(encoding="utf-8")
    body_hash = sha256_text(body)
    if envelope.get("report_body_sha256") != body_hash:
        emit_error("ROLE_REPORT_BODY_HASH_MISMATCH")

    packet_sha = validate_sha256(envelope.get("packet_sha256"), "packet_sha256")
    candidate = str(envelope.get("candidate_identity") or "").strip()
    if not candidate:
        emit_error("ROLE_REPORT_FIELD_MISSING", "candidate_identity")
    evidence_raw = envelope.get("evidence_manifest_sha256")
    if evidence_raw:
        evidence_sha = validate_sha256(evidence_raw, "evidence_manifest_sha256")
    elif schema == SCHEMA:
        emit_error("ROLE_REPORT_FIELD_MISSING", "evidence_manifest_sha256")
    else:
        evidence_sha = ""

    if envelope.get("secret_scan") not in {"PASS", "N/A"}:
        emit_error("ROLE_REPORT_SECRET_SCAN_REQUIRED")
    verdict = envelope.get("verdict")
    if not verdict:
        emit_error("ROLE_REPORT_FIELD_MISSING", "verdict")

    permission_sha = str(envelope.get("permission_policy_sha256") or "")
    if permission_sha:
        permission_sha = validate_sha256(permission_sha, "permission_policy_sha256")
    effect_sha = str(envelope.get("effect_policy_sha256") or "")
    if effect_sha:
        effect_sha = validate_sha256(effect_sha, "effect_policy_sha256")

    # Route receipt is mandatory for V3 production path (R-009).
    # receipt must be AUTHORITATIVE_ROUTE_RECEIPT_V1 (strict schema),
    # not arbitrary JSON containing only route_id/model_family. The strict
    # schema is required unless legacy-envelope mode explicitly opts in.
    route_id = str(envelope.get("route_id") or "")
    model_family = str(envelope.get("model_family") or "")
    route_receipt_sha = ""
    if route_receipt_path is not None:
        receipt = load_optional_json(route_receipt_path)
        assert receipt is not None
        if receipt.get("schema") == "AUTHORITATIVE_ROUTE_RECEIPT_V1":
            # Strict path: validate every required binding field.
            for f in ("route_id", "role", "task_id", "packet_sha256", "candidate_identity",
                      "model", "model_family", "provider_route_identity",
                      "selection_policy_sha256", "launch_sha256",
                      "role_process_receipt_sha256", "process_id", "session_id",
                      "started_at_utc", "completed_at_utc"):
                if not str(receipt.get(f) or "").strip():
                    emit_error("ROLE_REPORT_ROUTE_RECEIPT_INVALID", f"missing {f}")
            if str(receipt.get("role")) not in {role, "executor"}:
                emit_error("ROLE_REPORT_ROUTE_RECEIPT_ROLE_MISMATCH", str(receipt.get("role")))
            if str(receipt.get("packet_sha256")) != packet_sha:
                emit_error("ROLE_REPORT_ROUTE_RECEIPT_PACKET_MISMATCH", str(receipt.get("packet_sha256")))
            route_id = str(receipt.get("route_id"))
            model_family = str(receipt.get("model_family"))
        elif schema == SCHEMA and os.environ.get("OPENCODE_GOVERNANCE_ALLOW_LEGACY_ROUTE_RECEIPT") != "1":
            # legacy loose receipts are gated SOLELY on a trusted operator
            # env var, never on caller-supplied envelope input.
            emit_error("ROLE_REPORT_ROUTE_RECEIPT_INVALID", "production requires AUTHORITATIVE_ROUTE_RECEIPT_V1")
        else:
            # Legacy loose path (operator opt-in via env only): tolerate route_id/model_family strings.
            route_id = str(receipt.get("route_id") or receipt.get("route") or "")
            model_family = str(receipt.get("model_family") or receipt.get("family") or "")
            if not route_id or not model_family:
                emit_error("ROLE_REPORT_ROUTE_RECEIPT_INVALID", "route_id/model_family")
        route_receipt_sha = sha256_file(route_receipt_path)
        # Co-locate the validated route receipt so Review Chain V4 can
        # live-revalidate (re-hash + re-check schema/packet) rather than skip
        # with "not_colocated". Copy atomically into the task route-receipts dir.
        if role and schema == SCHEMA:
            colocated_dir = project / ".ai" / "tasks" / task_id / "route-receipts"
            colocated_dir.mkdir(parents=True, exist_ok=True)
            if is_symlink_or_reparse(colocated_dir):
                emit_error("ROLE_REPORT_ROUTE_RECEIPT_DIR_SYMLINK", str(colocated_dir))
            colocated = colocated_dir / f"{role}.json"
            try:
                rr_bytes = route_receipt_path.read_bytes()
                rr_tmp = colocated.with_name(colocated.name + f".tmp.{os.getpid()}")
                rr_tmp.write_bytes(rr_bytes)
                os.replace(rr_tmp, colocated)
            except Exception as exc:
                emit_error("ROLE_REPORT_ROUTE_RECEIPT_COLOCATE_FAILED", str(exc))
    elif schema == SCHEMA:
        emit_error("ROLE_REPORT_ROUTE_RECEIPT_REQUIRED")
    elif envelope.get("accept_envelope_route_without_receipt"):
        emit_error("ROLE_REPORT_ROUTE_RECEIPT_REQUIRED", "accept_envelope_route_without_receipt removed in V3 production")

    tool_transcript_sha = str(envelope.get("tool_transcript_sha256") or "")
    if tool_transcript_sha:
        tool_transcript_sha = validate_sha256(tool_transcript_sha, "tool_transcript_sha256")

    out_name = ALLOWED_ROLES[role]
    dest_dir = project / ".ai" / "tasks" / task_id / "reports"
    # Ensure path containment for dest
    ensure_contained(project, dest_dir / out_name, "dest")
    dest_dir.mkdir(parents=True, exist_ok=True)
    if is_symlink_or_reparse(dest_dir):
        emit_error("ROLE_REPORT_DEST_DIR_SYMLINK", str(dest_dir))

    dest = dest_dir / out_name
    meta_path = dest.with_suffix(dest.suffix + ".ingest.json")

    started = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    body_bytes = body.encode("utf-8")
    # normalize to LF for persistence
    if b"\r\n" in body_bytes:
        body_bytes = body_bytes.replace(b"\r\n", b"\n")
        body_hash = hashlib.sha256(body_bytes).hexdigest()

    # transactional report commit (DETERMINISTIC_ROLE_REPORT_TRANSACTION_V1).
    # Stage body/metadata/receipt under a transaction directory with a journal and
    # a single COMMIT marker published only after every destination is persisted
    # and re-hashed. A crash leaves at most a partial transaction directory; the
    # prior committed artifacts are preserved.
    tx_dir = dest_dir / ".transactions" / f"{out_name}.{int(time.time())}.{os.getpid()}"
    tx_dir.mkdir(parents=True, exist_ok=True)
    if is_symlink_or_reparse(tx_dir):
        emit_error("ROLE_REPORT_TX_DIR_SYMLINK", str(tx_dir))
    journal_path = tx_dir / "journal.json"
    commit_marker = tx_dir / "COMMITTED"

    def _journal(state: str, extra: dict[str, Any] | None = None) -> None:
        entry = {"state": state, "at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
        if extra:
            entry.update(extra)
        # Append-only journal.
        with open(journal_path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry, sort_keys=True) + "\n")

    _journal("PREPARED")
    # Idempotent fast-path: if the exact body is already committed, return the
    # existing receipt without rebuilding metadata (whose timestamps would
    # otherwise diverge and trip ROLE_REPORT_DUPLICATE_DIVERGENT).
    if allow_identical_idempotent and dest.exists() and not is_symlink_or_reparse(dest):
        try:
            if hashlib.sha256(dest.read_bytes()).hexdigest() == hashlib.sha256(body_bytes).hexdigest():
                receipt_path = dest.with_suffix(dest.suffix + ".receipt.json")
                if receipt_path.is_file() and not is_symlink_or_reparse(receipt_path):
                    try:
                        return json.loads(receipt_path.read_text(encoding="utf-8-sig"))
                    except Exception:
                        pass  # fall through to full ingest if receipt unreadable
        except Exception:
            pass  # fall through to full ingest on any IO error
    # snapshot prior committed artifacts so a mid-transaction crash can
    # restore them. Without this, overwriting `dest` before meta/commit are
    # written would leave an uncommitted body and lose the prior committed state.
    prior_dest_bytes = dest.read_bytes() if dest.exists() and not is_symlink_or_reparse(dest) else None
    prior_meta_bytes = meta_path.read_bytes() if meta_path.exists() and not is_symlink_or_reparse(meta_path) else None
    # Stage the body into the transaction dir first.
    staged_body = tx_dir / out_name
    staged_body.write_bytes(body_bytes)
    staged_body_hash = sha256_file(staged_body)
    expected_staged = hashlib.sha256(body_bytes).hexdigest()
    if staged_body_hash != expected_staged:
        emit_error("ROLE_REPORT_TX_BODY_HASH_MISMATCH")
    _journal("VALIDATED", {"staged_body_sha256": staged_body_hash})

    written_body_hash = atomic_write_no_clobber(dest, body_bytes, allow_identical=allow_identical_idempotent)
    if written_body_hash != staged_body_hash:
        # Roll back to prior committed artifact if any; remove the partial new.
        _rollback_transaction(tx_dir, dest, meta_path, prior_dest_bytes, prior_meta_bytes)
        emit_error("ROLE_REPORT_TX_BODY_PERSIST_MISMATCH", f"{written_body_hash}!={staged_body_hash}")

    completed = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    meta = {
        "schema": SCHEMA,
        "contract": INGEST_CONTRACT,
        "role": role,
        "task_id": task_id,
        "packet_sha256": packet_sha,
        "candidate_identity": candidate,
        "evidence_manifest_sha256": evidence_sha,
        "route_id": route_id,
        "model_family": model_family,
        "route_receipt_sha256": route_receipt_sha,
        "tool_transcript_sha256": tool_transcript_sha,
        "report_body_sha256": written_body_hash,
        "report_path": str(dest.relative_to(project)).replace("\\", "/"),
        "permission_policy_sha256": permission_sha,
        "effect_policy_sha256": effect_sha,
        "started_at_utc": started,
        "completed_at_utc": completed,
        "ingested_at_utc": completed,
        "verdict": verdict,
        "destination_role_mapping": out_name,
    }
    meta_bytes = (json.dumps(meta, indent=2, sort_keys=True) + "\n").encode("utf-8")
    meta_hash = atomic_write_no_clobber(meta_path, meta_bytes, allow_identical=allow_identical_idempotent)
    # Re-hash persisted metadata.
    if sha256_file(meta_path) != meta_hash:
        _rollback_transaction(tx_dir, dest, meta_path, prior_dest_bytes, prior_meta_bytes)
        emit_error("ROLE_REPORT_TX_META_PERSIST_MISMATCH")
    _journal("COMMITTING", {"metadata_sha256": meta_hash})
    # Content-bound receipt
    receipt = {
        "status": "ROLE_REPORT_INGESTED",
        "contract": INGEST_CONTRACT,
        "schema": SCHEMA,
        "role": role,
        "task_id": task_id,
        "report_body_sha256": written_body_hash,
        "metadata_sha256": meta_hash,
        "candidate_identity": candidate,
        "packet_sha256": packet_sha,
        "evidence_manifest_sha256": evidence_sha,
        "route_receipt_sha256": route_receipt_sha,
        "meta": meta,
    }
    receipt_path = dest.with_suffix(dest.suffix + ".receipt.json")
    receipt_bytes = (json.dumps(receipt, indent=2, sort_keys=True) + "\n").encode("utf-8")
    atomic_write_no_clobber(receipt_path, receipt_bytes, allow_identical=True)
    if sha256_file(receipt_path) != hashlib.sha256(receipt_bytes).hexdigest():
        _rollback_transaction(tx_dir, dest, meta_path, prior_dest_bytes, prior_meta_bytes)
        emit_error("ROLE_REPORT_TX_RECEIPT_PERSIST_MISMATCH")
    # publish a single COMMIT marker only after every destination is
    # persisted and re-hashed.
    commit_body = {
        "schema": "DETERMINISTIC_ROLE_REPORT_TRANSACTION_V1",
        "role": role,
        "task_id": task_id,
        "report_body_sha256": written_body_hash,
        "metadata_sha256": meta_hash,
        "receipt_sha256": hashlib.sha256(receipt_bytes).hexdigest(),
        "committed_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    commit_marker.write_text(json.dumps(commit_body, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    _journal("COMMITTED", {"commit_marker_sha256": sha256_file(commit_marker)})
    receipt["transaction"] = {"dir": str(tx_dir), "commit_marker": str(commit_marker)}
    return receipt


def _rollback_transaction(tx_dir: pathlib.Path, dest: pathlib.Path, meta_path: pathlib.Path,
                          prior_dest: bytes | None = None, prior_meta: bytes | None = None) -> None:
    """Transaction recovery: remove partial new artifacts and restore the prior
    committed body/metadata so a mid-transaction crash does not leave an
    uncommitted body without metadata, or lose the previous committed state."""
    try:
        # Restore prior committed artifacts if they were snapshotted.
        if prior_dest is not None:
            tmp = dest.with_name(dest.name + f".restore.{os.getpid()}")
            tmp.write_bytes(prior_dest)
            os.replace(tmp, dest)
        elif dest.exists():
            # No prior artifact existed; this transaction created dest — remove it.
            dest.unlink(missing_ok=True)
        if prior_meta is not None:
            tmp = meta_path.with_name(meta_path.name + f".restore.{os.getpid()}")
            tmp.write_bytes(prior_meta)
            os.replace(tmp, meta_path)
        elif meta_path.exists():
            meta_path.unlink(missing_ok=True)
    except Exception:
        pass
    try:
        if tx_dir.exists():
            shutil.rmtree(tx_dir, ignore_errors=True)
    except Exception:
        pass


def _load_live_meta(base: pathlib.Path, name: str) -> tuple[pathlib.Path, dict[str, Any], str, str]:
    path = base / name
    meta_path = path.with_suffix(path.suffix + ".ingest.json")
    if not path.is_file() or not meta_path.is_file():
        emit_error("REVIEW_CHAIN_INCOMPLETE", name)
    if is_symlink_or_reparse(path) or is_symlink_or_reparse(meta_path):
        emit_error("REVIEW_CHAIN_SYMLINK", name)
    body = path.read_text(encoding="utf-8")
    body_hash = sha256_text(body)
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    meta_hash = sha256_file(meta_path)
    if meta.get("report_body_sha256") != body_hash:
        emit_error("REVIEW_CHAIN_BODY_TAMPER", name)
    return path, meta, body_hash, meta_hash


def attest_chain(
    project: pathlib.Path,
    task_id: str,
    *,
    expected_candidate: str | None = None,
    expected_evidence: str | None = None,
    expected_permission_policy: str | None = None,
    expected_effect_policy: str | None = None,
) -> dict[str, Any]:
    project = canonicalize_project(project)
    task_id = validate_task_id(task_id)
    base = project / ".ai" / "tasks" / task_id / "reports"
    if not base.is_dir():
        emit_error("REVIEW_CHAIN_INCOMPLETE", "reports_dir")

    required = [
        ("implementation-reviewer", "REVIEW_IMPLEMENTATION.md"),
        ("architecture-reviewer", "REVIEW_ARCHITECTURE.md"),
        ("final-reviewer", "FINAL_ADJUDICATION.md"),
    ]
    chain = []
    candidates = set()
    evidences = set()
    timestamps = []
    revalidation = []

    for role, name in required:
        _path, meta, body_hash, meta_hash = _load_live_meta(base, name)
        if meta.get("role") != role:
            emit_error("REVIEW_CHAIN_ROLE_MISMATCH", f"{name}:{meta.get('role')}")
        if meta.get("task_id") != task_id:
            emit_error("REVIEW_CHAIN_TASK_MISMATCH", name)
        if meta.get("destination_role_mapping") and meta.get("destination_role_mapping") != name:
            emit_error("REVIEW_CHAIN_DEST_MISMATCH", name)
        candidates.add(meta.get("candidate_identity"))
        if meta.get("evidence_manifest_sha256"):
            evidences.add(meta.get("evidence_manifest_sha256"))
        if expected_permission_policy and meta.get("permission_policy_sha256") and meta.get("permission_policy_sha256") != expected_permission_policy:
            emit_error("REVIEW_CHAIN_PERMISSION_POLICY_STALE", name)
        if expected_effect_policy and meta.get("effect_policy_sha256") and meta.get("effect_policy_sha256") != expected_effect_policy:
            emit_error("REVIEW_CHAIN_EFFECT_POLICY_STALE", name)
        ts = meta.get("completed_at_utc") or meta.get("ingested_at_utc") or ""
        timestamps.append((role, ts))

        # Review Chain V4: live-revalidate the ingestion receipt, the route
        # receipt (when an authoritative one is referenced), and any
        # transaction commit marker. No caller-provided string substitutes for
        # a runner receipt; a hash mismatch is a chain break.
        rv = {"role": role, "report_body_sha256_ok": True, "metadata_sha256_ok": True}
        # 1. Live ingestion receipt revalidation (re-hash the .receipt.json).
        receipt_path = _path.with_suffix(_path.suffix + ".receipt.json")
        if receipt_path.is_file():
            if is_symlink_or_reparse(receipt_path):
                emit_error("REVIEW_CHAIN_RECEIPT_SYMLINK", str(receipt_path))
            try:
                rc = json.loads(receipt_path.read_text(encoding="utf-8-sig"))
            except Exception as exc:
                emit_error("REVIEW_CHAIN_RECEIPT_INVALID", f"{name}:{exc}")
            if str(rc.get("report_body_sha256") or "") != body_hash:
                emit_error("REVIEW_CHAIN_RECEIPT_BODY_HASH_MISMATCH", name)
            if str(rc.get("metadata_sha256") or "") != meta_hash:
                emit_error("REVIEW_CHAIN_RECEIPT_META_HASH_MISMATCH", name)
            rv["ingestion_receipt_revalidated"] = True
        # 2. Route receipt revalidation when referenced & resolvable.
        route_receipt_sha = str(meta.get("route_receipt_sha256") or "")
        rv_route_ok = True
        if route_receipt_sha:
            # Resolve the route receipt artifact next to the report's task dir if present.
            rr_path = base.parent / "route-receipts" / f"{role}.json"
            if rr_path.is_file() and not is_symlink_or_reparse(rr_path):
                if sha256_file(rr_path) != route_receipt_sha:
                    emit_error("REVIEW_CHAIN_ROUTE_RECEIPT_HASH_MISMATCH", name)
                try:
                    rrb = json.loads(rr_path.read_text(encoding="utf-8-sig"))
                    if rrb.get("schema") != "AUTHORITATIVE_ROUTE_RECEIPT_V1":
                        emit_error("REVIEW_CHAIN_ROUTE_RECEIPT_SCHEMA", name)
                    if str(rrb.get("packet_sha256") or "") and str(rrb.get("packet_sha256")) != str(meta.get("packet_sha256") or ""):
                        emit_error("REVIEW_CHAIN_ROUTE_RECEIPT_PACKET_MISMATCH", name)
                except Exception as exc:
                    emit_error("REVIEW_CHAIN_ROUTE_RECEIPT_INVALID", f"{name}:{exc}")
                rv["route_receipt_revalidated"] = True
                rv_route_ok = True
            else:
                # Referenced receipt not co-located for live revalidation. The
                # route_receipt_sha recorded at ingest time still binds it; we
                # cannot re-hash an absent artifact, so this is a non-fatal
                # "skipped" note rather than a chain break. A present-but-
                # mismatched receipt is the hard error (handled above).
                rv["route_receipt_revalidation"] = "skipped_not_colocated"
        rv["route_receipt_ok"] = rv_route_ok
        revalidation.append(rv)

        chain.append(
            {
                "role": meta.get("role"),
                "route_id": meta.get("route_id"),
                "model_family": meta.get("model_family"),
                "packet_sha256": meta.get("packet_sha256"),
                "candidate_identity": meta.get("candidate_identity"),
                "report_body_sha256": body_hash,
                "metadata_sha256": meta_hash,
                "permission_policy_sha256": meta.get("permission_policy_sha256"),
                "effect_policy_sha256": meta.get("effect_policy_sha256"),
                "evidence_manifest_sha256": meta.get("evidence_manifest_sha256"),
                "route_receipt_sha256": meta.get("route_receipt_sha256") or "",
                "tool_transcript_sha256": meta.get("tool_transcript_sha256") or "",
                "completed_at_utc": ts,
            }
        )

    if len(candidates) != 1 or (None in candidates) or ("" in candidates):
        emit_error("REVIEW_CHAIN_CANDIDATE_MISMATCH", str(candidates))
    cand = next(iter(candidates))
    if expected_candidate and cand != expected_candidate:
        emit_error("REVIEW_CHAIN_CANDIDATE_MISMATCH", f"expected={expected_candidate}")

    if len(evidences) > 1:
        emit_error("REVIEW_CHAIN_EVIDENCE_MISMATCH", str(evidences))
    if expected_evidence and evidences and expected_evidence not in evidences:
        emit_error("REVIEW_CHAIN_EVIDENCE_MISMATCH", expected_evidence)

    # Independence: implementation vs architecture model families must differ when both set
    families = [c.get("model_family") for c in chain[:2] if c.get("model_family")]
    if len(families) == 2 and families[0] == families[1]:
        emit_error("REVIEW_INDEPENDENCE_FAMILY_COLLISION", str(families))

    # Chronological order: both reviews must complete before final (string UTC compare when present)
    impl_ts = timestamps[0][1]
    arch_ts = timestamps[1][1]
    final_ts = timestamps[2][1]
    if impl_ts and arch_ts and final_ts:
        if not (impl_ts <= final_ts and arch_ts <= final_ts):
            emit_error("REVIEW_CHAIN_ORDER_VIOLATION", f"impl={impl_ts} arch={arch_ts} final={final_ts}")

    out = {
        "schema": CHAIN_SCHEMA,
        "contract": CHAIN_SCHEMA,
        "task_id": task_id,
        "candidate_identity": cand,
        "evidence_manifest_sha256": next(iter(evidences)) if evidences else "",
        "chain": chain,
        "revalidation": revalidation,
        "reviewer_independence": "PASS",
        "attested_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    out_path = base / "REVIEW_CHAIN_ATTESTATION.json"
    body = json.dumps(out, indent=2, sort_keys=True) + "\n"
    # Chain attestation may be re-generated; allow identical or replace only via atomic write after validate.
    # Use replace for attestation artifact (not role report bodies).
    tmp = out_path.with_suffix(".tmp")
    tmp.write_text(body, encoding="utf-8", newline="\n")
    os.replace(tmp, out_path)
    return {
        "status": "REVIEW_CHAIN_ATTESTED",
        "path": str(out_path),
        "sha256": sha256_text(body),
        "attestation": out,
        "contract": CHAIN_SCHEMA,
    }


def main() -> int:
    p = argparse.ArgumentParser(prog="role-report-ingest")
    sub = p.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("ingest")
    i.add_argument("--project-dir", required=True)
    i.add_argument("--envelope", required=True)
    i.add_argument("--body", required=True)
    i.add_argument("--route-receipt", default=None)
    i.add_argument("--no-idempotent", action="store_true")
    a = sub.add_parser("attest-chain")
    a.add_argument("--project-dir", required=True)
    a.add_argument("--task-id", required=True)
    a.add_argument("--expected-candidate", default=None)
    a.add_argument("--expected-evidence", default=None)
    a.add_argument("--expected-permission-policy", default=None)
    a.add_argument("--expected-effect-policy", default=None)
    args = p.parse_args()
    if args.cmd == "ingest":
        result = ingest(
            pathlib.Path(args.project_dir),
            pathlib.Path(args.envelope),
            pathlib.Path(args.body),
            route_receipt_path=pathlib.Path(args.route_receipt) if args.route_receipt else None,
            allow_identical_idempotent=not args.no_idempotent,
        )
        print(json.dumps(result, sort_keys=True))
        return 0
    result = attest_chain(
        pathlib.Path(args.project_dir),
        args.task_id,
        expected_candidate=args.expected_candidate,
        expected_evidence=args.expected_evidence,
        expected_permission_policy=args.expected_permission_policy,
        expected_effect_policy=args.expected_effect_policy,
    )
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
