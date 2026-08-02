#!/usr/bin/env python3
"""Deterministic candidate authority, approval receipts and review lenses."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import stat
import subprocess
import sys
from datetime import datetime, timezone
from typing import Any

CANDIDATE_SCHEMA = "opencode-governance.candidate/v1"
RECEIPT_SCHEMA = "opencode-governance.approval-receipt/v1"
# Historical prose name accepted on validate only; new receipts always emit RECEIPT_SCHEMA.
RECEIPT_SCHEMA_ALIASES = {RECEIPT_SCHEMA, "GOVERNANCE_APPROVAL_RECEIPT_V1"}
PROJECTIONS = {"workspace", "staged", "commit", "base-diff"}
# Keep in lockstep with scripts/workflow-continuation.py NON_TERMINAL_PHASES.
NON_TERMINAL_PHASES = {
    "IDEA_INTAKE",
    "PRODUCT_CLASSIFICATION",
    "ADAPTIVE_PRODUCT_DISCOVERY",
    "ADAPTIVE_DISCOVERY",
    "GOVERNED_DOMAIN_RESEARCH",
    "CONSTRUCTIVE_CHALLENGE",
    "PRODUCT_DEFINITION",
    "DISCOVERY_DUAL_REVIEW",
    "DISCOVERY_ADJUDICATION",
    "DISCOVERY_PASS",
    "DISCOVERY_DEFECT",
    "PRODUCT_SCOPE_APPROVAL",
    "PRODUCT_SCOPE_APPROVED",
    "CONTEXT_ROUTING",
    "CONTEXT_SUFFICIENT",
    "DELIVERY_ARCHITECTURE",
    "VERTICAL_MILESTONE_PLANNING",
    "EVIDENCE_PLANNING",
    "OPERATIONAL_PLANNING",
    "READY_FOR_EXECUTION",
    "PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED",
    "IMPLEMENTING",
    "IMPLEMENTATION",
    "DOCUMENTATION_SYNC",
    "EVIDENCE_VALIDATION",
    "OPERATIONAL_VALIDATION",
    "EVIDENCE_AND_OPERATIONAL_VALIDATION",
    "TASK_VALIDATED",
    "DUAL_REVIEW",
    "DUAL_REVIEW_COMPLETE",
    "TASK_DUAL_REVIEW",
    "FINAL_ADJUDICATION",
    "FINAL_ADJUDICATION_PASS",
    "TASK_FINAL_ADJUDICATION",
    "PASS",
    "IMPLEMENTATION_DEFECT",
    "PLAN_DEFECT",
    "PRODUCT_COMPLETENESS_RECONCILIATION",
    "PRODUCT_COMPLETE",
    "PRODUCT_DEFECT",
    "PRODUCT_INCOMPLETE",
    "MILESTONE_VALIDATED",
    "RELEASE_READINESS",
    "RELEASE_READY",
    "READY_FOR_PRODUCTION",
    "NOT_READY_FOR_PRODUCTION",
    "VALIDATED_LEARNING",
    "AUDIT_PASS",
    "BASELINE_PASS",
    "BASELINE_DEFECT",
    "BASELINE_VALIDATED",
    "TASK_REVIEW",
}
GATES = {"post-apply", "pre-commit", "pre-push", "pre-pr", "release"}
APPROVING_VERDICTS = {"PASS", "READY_FOR_PRODUCTION", "LOCAL_COMMITTED"}
HASH_FIELDS = (
    "approved_requirements_hash",
    "execution_packet_hash",
    "verification_profile_hash",
    "evidence_manifest_hash",
    "implementation_review_hash",
    "architecture_review_hash",
    "final_adjudication_hash",
)
# Map receipt hash field -> default relative artifact path under the project root.
DEFAULT_ARTIFACT_PATHS = {
    "approved_requirements_hash": ".ai/APPROVED_REQUIREMENTS.md",
    "execution_packet_hash": ".ai/EXECUTION_PACKET.md",
    "verification_profile_hash": ".ai/VERIFICATION_PROFILE.md",
    "evidence_manifest_hash": ".ai/EVIDENCE_MANIFEST.md",
    "implementation_review_hash": ".ai/REVIEW_IMPLEMENTATION.md",
    "architecture_review_hash": ".ai/REVIEW_ARCHITECTURE.md",
    "final_adjudication_hash": ".ai/FINAL_ADJUDICATION.md",
}
KNOWN_COMMANDS = {
    "/ai-init",
    "/ai-audit",
    "/ai-docs",
    "/ai-discover",
    "/ai-plan",
    "/ai-execute",
    "/ai-review",
    "/ai-workflow",
    "/ai-status",
    "/ai-resume",
    "/ai-metrics",
    "/ai-release",
}
# Terminal reasons that may appear when a run is finished or blocked.
# Phase-aware validation below prevents using these on non-terminal phases.
TERMINAL_REASONS = {
    "LOCAL_COMMITTED",
    "READY_FOR_PRODUCTION",
    "NOT_READY_FOR_PRODUCTION",
    "BLOCKED",
    "PLAN_ONLY_COMPLETE",
    "REVIEW_COMPLETE",
    "AUDIT_COMPLETE",
    "DOCUMENTATION_COMPLETE",
}


class ContractError(Exception):
    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(detail)
        self.code = code
        self.detail = detail


def fail(code: str, detail: str = "") -> None:
    payload = {"status": "ERROR", "code": code}
    if detail:
        payload["detail"] = detail
    print(json.dumps(payload, sort_keys=True), file=sys.stderr)
    raise SystemExit(2)


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def digest(value: Any) -> str:
    raw = value if isinstance(value, (bytes, bytearray)) else canonical(value)
    return hashlib.sha256(raw).hexdigest()


def valid_hash(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(char in "0123456789abcdef" for char in value)


def file_digest(path: pathlib.Path) -> str:
    digest_value = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest_value.update(chunk)
    return digest_value.hexdigest()


def contained_path(root: pathlib.Path, relative: str) -> pathlib.Path:
    if not isinstance(relative, str) or not relative.strip():
        raise ContractError("ARTIFACT_PATH_REQUIRED", relative if isinstance(relative, str) else "")
    normalized = relative.replace("\\", "/")
    while normalized.startswith("./"):
        normalized = normalized[2:]
    if normalized.startswith("/") or normalized.startswith("../") or normalized == "..":
        raise ContractError("ARTIFACT_PATH_ESCAPE", relative)
    parts = pathlib.PurePosixPath(normalized).parts
    if not parts or any(part in {"", ".", ".."} for part in parts):
        raise ContractError("ARTIFACT_PATH_ESCAPE", relative)
    root_resolved = root.resolve()
    current = root_resolved
    for part in parts:
        current = current / part
        if current.exists() and current.is_symlink():
            raise ContractError("ARTIFACT_PATH_SYMLINK", relative)
    if not current.is_file():
        raise ContractError("ARTIFACT_PATH_MISSING", relative)
    resolved = current.resolve()
    try:
        resolved.relative_to(root_resolved)
    except ValueError as exc:
        raise ContractError("ARTIFACT_PATH_ESCAPE", relative) from exc
    return resolved


def resolve_artifact_paths(bindings: dict[str, Any]) -> dict[str, str]:
    raw = bindings.get("artifact_paths")
    if raw is None:
        return dict(DEFAULT_ARTIFACT_PATHS)
    if not isinstance(raw, dict):
        raise ContractError("INVALID_ARTIFACT_PATHS")
    resolved: dict[str, str] = {}
    for field in HASH_FIELDS:
        value = raw.get(field, DEFAULT_ARTIFACT_PATHS[field])
        if not isinstance(value, str) or not value.strip():
            raise ContractError("ARTIFACT_PATH_REQUIRED", field)
        cleaned = value.replace("\\", "/")
        while cleaned.startswith("./"):
            cleaned = cleaned[2:]
        resolved[field] = cleaned
    return resolved


def bind_artifact_hashes(
    root: pathlib.Path,
    bindings: dict[str, Any],
    *,
    require_files: bool,
) -> tuple[dict[str, str], dict[str, str]]:
    """Return (hash_bindings, artifact_paths). When require_files, hashes are taken from disk."""
    paths = resolve_artifact_paths(bindings)
    if not require_files:
        hashes: dict[str, str] = {}
        for field in HASH_FIELDS:
            value = bindings.get(field)
            if not valid_hash(value):
                raise ContractError("INVALID_HASH", field)
            hashes[field] = value
        return hashes, paths

    hashes = {}
    for field, relative in paths.items():
        path = contained_path(root, relative)
        content_hash = file_digest(path)
        provided = bindings.get(field)
        if provided is not None and valid_hash(provided) and provided != content_hash:
            raise ContractError("BINDING_HASH_MISMATCH", field)
        hashes[field] = content_hash
    return hashes, paths


def read_object(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise ContractError("INVALID_JSON", f"{path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ContractError("INVALID_JSON_OBJECT", str(path))
    return value


def write_object(path: pathlib.Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def project_root(value: str) -> pathlib.Path:
    root = pathlib.Path(value).expanduser().resolve()
    if not root.is_dir():
        raise ContractError("PROJECT_DIR_NOT_FOUND", str(root))
    return root


def run_git(root: pathlib.Path, *arguments: str, binary: bool = False) -> str | bytes:
    process = subprocess.run(
        ["git", "-C", str(root), *arguments],
        capture_output=True,
        text=not binary,
    )
    if process.returncode:
        stderr = process.stderr if not binary else process.stderr.decode(errors="replace")
        raise ContractError("GIT_COMMAND_FAILED", f"git {' '.join(arguments)}: {stderr}")
    return process.stdout


def project_identity(root: pathlib.Path) -> str:
    try:
        origin = str(run_git(root, "config", "--get", "remote.origin.url")).strip()
    except ContractError:
        origin = ""
    return digest({"resolved_path": str(root.resolve()), "origin": origin})


def workspace_entries(root: pathlib.Path) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    for current_root, directories, files in os.walk(root, topdown=True, followlinks=False):
        base = pathlib.Path(current_root)
        relative_base = base.relative_to(root)
        if relative_base == pathlib.Path("."):
            directories[:] = sorted(name for name in directories if name not in {".git", ".ai"})
        else:
            directories[:] = sorted(directories)
        for directory in directories:
            candidate = base / directory
            if candidate.is_symlink():
                raise ContractError("UNSAFE_PROJECT_PATH", candidate.relative_to(root).as_posix())
        for filename in sorted(files):
            path = base / filename
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                raise ContractError("UNSAFE_PROJECT_PATH", relative)
            info = path.stat()
            if not stat.S_ISREG(info.st_mode):
                raise ContractError("UNSUPPORTED_PROJECT_ENTRY", relative)
            entries.append(
                {
                    "path": relative,
                    "mode": stat.S_IMODE(info.st_mode),
                    "size": info.st_size,
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                }
            )
    return sorted(entries, key=lambda item: item["path"])


def staged_entries(root: pathlib.Path) -> list[dict[str, Any]]:
    raw = run_git(root, "ls-files", "--stage", "-z", binary=True)
    entries: list[dict[str, Any]] = []
    for item in raw.split(b"\0"):
        if not item:
            continue
        metadata, raw_path = item.split(b"\t", 1)
        mode, blob, stage_value = metadata.decode().split()
        if stage_value != "0":
            raise ContractError("UNMERGED_INDEX", raw_path.decode(errors="replace"))
        entries.append(
            {
                "path": raw_path.decode("utf-8", "surrogateescape"),
                "mode": mode,
                "blob": blob,
            }
        )
    return sorted(entries, key=lambda item: item["path"])


def tree_entries(root: pathlib.Path, reference: str) -> tuple[str, list[dict[str, Any]]]:
    resolved = str(run_git(root, "rev-parse", "--verify", f"{reference}^{{commit}}")).strip()
    raw = run_git(root, "ls-tree", "-r", "-z", "--full-tree", resolved, binary=True)
    entries: list[dict[str, Any]] = []
    for item in raw.split(b"\0"):
        if not item:
            continue
        metadata, raw_path = item.split(b"\t", 1)
        mode, kind, object_id = metadata.decode().split()
        entries.append(
            {
                "path": raw_path.decode("utf-8", "surrogateescape"),
                "mode": mode,
                "kind": kind,
                "object": object_id,
            }
        )
    return resolved, sorted(entries, key=lambda item: item["path"])


def freeze_candidate(
    root: pathlib.Path,
    projection: str,
    reference: str = "HEAD",
    base_reference: str | None = None,
) -> dict[str, Any]:
    if projection not in PROJECTIONS:
        raise ContractError("INVALID_PROJECTION", projection)
    candidate: dict[str, Any] = {
        "schema": CANDIDATE_SCHEMA,
        "project_identity": project_identity(root),
        "projection": projection,
    }
    if projection == "workspace":
        candidate["entries"] = workspace_entries(root)
        try:
            candidate["head"] = str(run_git(root, "rev-parse", "HEAD")).strip()
        except ContractError:
            candidate["head"] = None
    elif projection == "staged":
        candidate["entries"] = staged_entries(root)
        candidate["head"] = str(run_git(root, "rev-parse", "HEAD")).strip()
    elif projection == "commit":
        resolved, entries = tree_entries(root, reference)
        candidate.update(ref=reference, resolved_ref=resolved, entries=entries)
    else:
        if not base_reference:
            raise ContractError("BASE_REF_REQUIRED")
        resolved, entries = tree_entries(root, reference)
        merge_base = str(run_git(root, "merge-base", base_reference, resolved)).strip()
        resolved_base = str(
            run_git(root, "rev-parse", "--verify", f"{base_reference}^{{commit}}")
        ).strip()
        candidate.update(
            ref=reference,
            resolved_ref=resolved,
            base_ref=base_reference,
            resolved_base_ref=resolved_base,
            merge_base=merge_base,
            entries=entries,
        )
    identity_payload = {
        key: value
        for key, value in candidate.items()
        if key not in {"schema", "candidate_identity"}
    }
    candidate["candidate_identity"] = digest(identity_payload)
    return candidate


def validate_candidate(candidate: dict[str, Any]) -> None:
    if candidate.get("schema") != CANDIDATE_SCHEMA:
        raise ContractError("INVALID_CANDIDATE_SCHEMA")
    if candidate.get("projection") not in PROJECTIONS:
        raise ContractError("INVALID_CANDIDATE_PROJECTION", str(candidate.get("projection")))
    if not valid_hash(candidate.get("project_identity")):
        raise ContractError("INVALID_PROJECT_IDENTITY")
    if not isinstance(candidate.get("entries"), list):
        raise ContractError("INVALID_CANDIDATE_ENTRIES")
    identity = candidate.get("candidate_identity")
    if not valid_hash(identity):
        raise ContractError("INVALID_CANDIDATE_IDENTITY")
    expected = digest(
        {
            key: value
            for key, value in candidate.items()
            if key not in {"schema", "candidate_identity"}
        }
    )
    if identity != expected:
        raise ContractError("CANDIDATE_INTEGRITY_FAILURE")


def normalize_model_families(value: Any) -> list[str]:
    if not isinstance(value, list):
        raise ContractError("MODEL_INDEPENDENCE_CONFLICT")
    normalized: list[str] = []
    for family in value:
        if not isinstance(family, str) or not family.strip():
            raise ContractError("MODEL_INDEPENDENCE_CONFLICT")
        normalized.append(family.strip())
    unique = sorted(set(normalized))
    if len(unique) < 2:
        raise ContractError("MODEL_INDEPENDENCE_CONFLICT")
    return unique


def validate_receipt_bindings(receipt: dict[str, Any]) -> tuple[dict[str, Any], list[str], str]:
    bindings = receipt.get("bindings")
    if not isinstance(bindings, dict):
        raise ContractError("INVALID_RECEIPT_BINDINGS")
    for field in HASH_FIELDS:
        if not valid_hash(bindings.get(field)):
            raise ContractError("INVALID_HASH", field)
    families = normalize_model_families(receipt.get("actual_model_families"))
    if receipt.get("reviewer_independence") != "PASS":
        raise ContractError("MODEL_INDEPENDENCE_CONFLICT")
    verdict = receipt.get("final_verdict")
    if verdict not in APPROVING_VERDICTS:
        raise ContractError("NON_APPROVING_FINAL_VERDICT", str(verdict))
    task_id = receipt.get("task_id")
    if not isinstance(task_id, str) or not task_id.strip():
        raise ContractError("TASK_ID_REQUIRED")
    return bindings, families, task_id.strip()


def issue_receipt(
    candidate: dict[str, Any],
    bindings: dict[str, Any],
    project: pathlib.Path | None = None,
) -> dict[str, Any]:
    validate_candidate(candidate)
    require_files = project is not None
    hash_bindings, artifact_paths = bind_artifact_hashes(
        project or pathlib.Path("."),
        bindings,
        require_files=require_files,
    )
    families = normalize_model_families(bindings.get("actual_model_families"))
    if bindings.get("reviewer_independence") != "PASS":
        raise ContractError("MODEL_INDEPENDENCE_CONFLICT")
    if bindings.get("final_verdict") not in APPROVING_VERDICTS:
        raise ContractError("NON_APPROVING_FINAL_VERDICT", str(bindings.get("final_verdict")))
    task_id = bindings.get("task_id")
    if not isinstance(task_id, str) or not task_id.strip():
        raise ContractError("TASK_ID_REQUIRED")
    receipt = {
        "schema": RECEIPT_SCHEMA,
        "governance_version": "3.7.6",
        "task_id": task_id.strip(),
        "candidate": candidate,
        "bindings": hash_bindings,
        "artifact_paths": artifact_paths,
        "binding_mode": "content-bound" if require_files else "opaque",
        "actual_model_families": families,
        "reviewer_independence": "PASS",
        "final_verdict": bindings["final_verdict"],
        "issued_at": datetime.now(timezone.utc).isoformat(),
        "freshness_dependencies": ["candidate_identity", *HASH_FIELDS, "artifact_paths"],
    }
    receipt["receipt_hash"] = digest(receipt)
    return receipt


def validate_receipt(
    root: pathlib.Path,
    receipt: dict[str, Any],
    gate: str,
) -> dict[str, Any]:
    if gate not in GATES:
        raise ContractError("INVALID_GATE", gate)
    if receipt.get("schema") not in RECEIPT_SCHEMA_ALIASES:
        raise ContractError("INVALID_RECEIPT_SCHEMA")
    if receipt.get("governance_version") != "3.7.6":
        raise ContractError("INVALID_RECEIPT_VERSION", str(receipt.get("governance_version")))
    receipt_hash = receipt.get("receipt_hash")
    if not valid_hash(receipt_hash):
        raise ContractError("RECEIPT_INTEGRITY_FAILURE")
    expected_hash = digest({key: value for key, value in receipt.items() if key != "receipt_hash"})
    if receipt_hash != expected_hash:
        raise ContractError("RECEIPT_INTEGRITY_FAILURE")
    expected_deps = ["candidate_identity", *HASH_FIELDS, "artifact_paths"]
    legacy_deps = ["candidate_identity", *HASH_FIELDS]
    if receipt.get("freshness_dependencies") not in (expected_deps, legacy_deps):
        raise ContractError("INVALID_RECEIPT_DEPENDENCIES")
    _, _, task_id = validate_receipt_bindings(receipt)
    candidate = receipt.get("candidate")
    if not isinstance(candidate, dict):
        raise ContractError("INVALID_RECEIPT_CANDIDATE")
    validate_candidate(candidate)
    current = freeze_candidate(
        root,
        candidate["projection"],
        candidate.get("ref", "HEAD"),
        candidate.get("base_ref"),
    )
    if current["candidate_identity"] != candidate["candidate_identity"]:
        raise ContractError(
            "APPROVAL_RECEIPT_MISMATCH",
            f"approved={candidate['candidate_identity']} current={current['candidate_identity']}",
        )
    binding_mode = receipt.get("binding_mode", "opaque")
    if binding_mode == "content-bound":
        paths = receipt.get("artifact_paths")
        if not isinstance(paths, dict):
            raise ContractError("ARTIFACT_PATHS_REQUIRED")
        for field in HASH_FIELDS:
            relative = paths.get(field)
            if not isinstance(relative, str):
                raise ContractError("ARTIFACT_PATH_REQUIRED", field)
            path = contained_path(root, relative)
            if file_digest(path) != receipt["bindings"][field]:
                raise ContractError("RECEIPT_ARTIFACT_MISMATCH", field)
    return {
        "status": "RECEIPT_VALID",
        "gate": gate,
        "task_id": task_id,
        "candidate_identity": current["candidate_identity"],
        "receipt_hash": receipt_hash,
        "binding_mode": binding_mode if binding_mode in {"content-bound", "opaque"} else "opaque",
    }


def validate_continuation(state: dict[str, Any]) -> dict[str, Any]:
    """Validate RUN_STATE continuation in lockstep with WORKFLOW_CONTINUATION_GATE_V1."""
    for field in ("top_level_command", "current_phase", "next_required_phase", "terminal_reason"):
        if field not in state:
            raise ContractError("RUN_STATE_FIELD_MISSING", field)
    phase = state.get("current_phase")
    if not isinstance(phase, str) or not phase.strip():
        raise ContractError("CURRENT_PHASE_REQUIRED")
    phase = phase.strip()
    next_phase = state.get("next_required_phase")
    terminal_reason = state.get("terminal_reason")

    if phase == "LOCAL_COMMITTED":
        if next_phase not in (None, "") or terminal_reason not in (None, ""):
            raise ContractError("SUCCESS_TERMINAL_FIELDS_INVALID")
        return {
            "status": "TERMINAL_CONTINUATION_VALID",
            "terminal_reason": None,
            "current_phase": phase,
        }

    if terminal_reason not in (None, ""):
        if phase in NON_TERMINAL_PHASES:
            raise ContractError("NON_TERMINAL_REASON_FORBIDDEN", phase)
        if terminal_reason not in TERMINAL_REASONS:
            raise ContractError("INVALID_TERMINAL_REASON", str(terminal_reason))
        return {
            "status": "TERMINAL_CONTINUATION_VALID",
            "terminal_reason": terminal_reason,
            "current_phase": phase,
        }

    if not isinstance(next_phase, str) or not next_phase.strip():
        raise ContractError("NEXT_REQUIRED_PHASE_REQUIRED")
    action = state.get("next_action")
    if not isinstance(action, dict):
        raise ContractError("ACTIONABLE_CONTINUATION_REQUIRED")
    kind = action.get("kind")
    if kind == "execute":
        command = action.get("command")
        if command not in KNOWN_COMMANDS:
            raise ContractError("NON_EXECUTABLE_CONTINUATION", str(command))
        arguments = action.get("arguments", [])
        if not isinstance(arguments, list) or any(not isinstance(item, str) for item in arguments):
            raise ContractError("INVALID_CONTINUATION_ARGUMENTS")
        if not action.get("expected_postcondition"):
            raise ContractError("CONTINUATION_POSTCONDITION_REQUIRED")
    elif kind == "human_decision":
        if not action.get("decision_required") or not isinstance(action.get("available_choices"), list):
            raise ContractError("INVALID_HUMAN_DECISION")
    else:
        raise ContractError("NON_EXECUTABLE_CONTINUATION", str(kind))
    return {
        "status": "ACTIONABLE_CONTINUATION_VALID",
        "kind": kind,
        "current_phase": phase,
        "next_required_phase": next_phase.strip(),
    }


LENS_MAP = {
    "SECURITY": ["AUTHORIZATION", "INPUT_VALIDATION", "SECRET_HANDLING"],
    "DATA_MIGRATION": ["DATA_SAFETY", "MIGRATION", "RECOVERY"],
    "PUBLIC_CONTRACT": ["PUBLIC_CONTRACT", "BACKWARD_COMPATIBILITY"],
    "DEPENDENCY": ["DEPENDENCY_SUPPLY_CHAIN", "LICENSE_COMPATIBILITY"],
    "DEPLOYMENT": ["DEPLOYMENT", "OBSERVABILITY", "RECOVERY"],
    "PERFORMANCE": ["PERFORMANCE"],
    "GENERATED_ARTIFACT": ["GENERATED_ARTIFACT"],
    "DESTRUCTIVE_ACTION": ["DATA_SAFETY", "RECOVERY"],
    "INPUT_VALIDATION": ["INPUT_VALIDATION", "ADVERSARIAL_INPUT"],
    "TEST_RELIABILITY": ["TEST_RELIABILITY", "FLAKINESS"],
    "USER_FLOW": ["USER_FLOW"],
    "VISUAL_BEHAVIOR": ["ACCESSIBILITY", "VISUAL_BEHAVIOR"],
    "EXTERNAL_TOOLING": ["TOOL_CAPABILITY"],
    "RECOVERY": ["RECOVERY", "RESILIENCE"],
    "EXPERIMENTATION": ["EXPERIMENT_ISOLATION"],
}
IMPLEMENTATION_LENSES = {
    "USER_FLOW",
    "VISUAL_BEHAVIOR",
    "ACCESSIBILITY",
    "TEST_RELIABILITY",
    "FLAKINESS",
    "PERFORMANCE",
}


def derive_lenses(risk: dict[str, Any]) -> dict[str, Any]:
    implementation = {"CORRECTNESS", "REGRESSION", "TEST_QUALITY", "MAINTAINABILITY"}
    architecture = {"ARCHITECTURE", "SECURITY_BOUNDARIES", "DATA_SAFETY", "RECOVERY"}
    for dimension, level in risk.items():
        if str(level).upper() not in {"LOW", "HIGH"}:
            continue
        for lens in LENS_MAP.get(dimension, []):
            if lens in IMPLEMENTATION_LENSES:
                implementation.add(lens)
            else:
                architecture.add(lens)
    return {
        "schema": "opencode-governance.review-lens-matrix/v1",
        "implementation": sorted(implementation),
        "architecture_security": sorted(architecture),
        "selection_basis": "TASK_RISK_PROFILE_AND_PRIMARY_EVIDENCE",
    }


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(prog="governance-authority")
    groups = value.add_subparsers(dest="group", required=True)

    candidate = groups.add_parser("candidate")
    candidate_actions = candidate.add_subparsers(dest="action", required=True)
    freeze = candidate_actions.add_parser("freeze")
    freeze.add_argument("--project-dir", required=True)
    freeze.add_argument("--projection", required=True, choices=sorted(PROJECTIONS))
    freeze.add_argument("--ref", default="HEAD")
    freeze.add_argument("--base-ref")
    freeze.add_argument("--output", required=True)

    receipt = groups.add_parser("receipt")
    receipt_actions = receipt.add_subparsers(dest="action", required=True)
    issue = receipt_actions.add_parser("issue")
    issue.add_argument("--candidate", required=True)
    issue.add_argument("--bindings", required=True)
    issue.add_argument("--output", required=True)
    issue.add_argument(
        "--project-dir",
        help="When set, binding hashes are computed from artifact files under the project (content-bound).",
    )
    validate = receipt_actions.add_parser("validate")
    validate.add_argument("--receipt", required=True)
    validate.add_argument("--project-dir", required=True)
    validate.add_argument("--gate", required=True, choices=sorted(GATES))

    continuation = groups.add_parser("continuation")
    continuation_actions = continuation.add_subparsers(dest="action", required=True)
    continuation_validate = continuation_actions.add_parser("validate")
    continuation_validate.add_argument("--run-state", required=True)

    lenses = groups.add_parser("lenses")
    lens_actions = lenses.add_subparsers(dest="action", required=True)
    derive = lens_actions.add_parser("derive")
    derive.add_argument("--risk-profile", required=True)
    return value


def main() -> None:
    args = parser().parse_args()
    try:
        if args.group == "candidate":
            candidate = freeze_candidate(
                project_root(args.project_dir),
                args.projection,
                args.ref,
                args.base_ref,
            )
            write_object(pathlib.Path(args.output), candidate)
            output = {
                "status": "CANDIDATE_FROZEN",
                "candidate_identity": candidate["candidate_identity"],
                "projection": candidate["projection"],
            }
        elif args.group == "receipt" and args.action == "issue":
            project = project_root(args.project_dir) if getattr(args, "project_dir", None) else None
            receipt = issue_receipt(
                read_object(pathlib.Path(args.candidate)),
                read_object(pathlib.Path(args.bindings)),
                project,
            )
            write_object(pathlib.Path(args.output), receipt)
            output = {
                "status": "RECEIPT_ISSUED",
                "receipt_hash": receipt["receipt_hash"],
                "binding_mode": receipt.get("binding_mode", "opaque"),
            }
        elif args.group == "receipt":
            output = validate_receipt(
                project_root(args.project_dir),
                read_object(pathlib.Path(args.receipt)),
                args.gate,
            )
        elif args.group == "continuation":
            output = validate_continuation(read_object(pathlib.Path(args.run_state)))
        else:
            output = derive_lenses(read_object(pathlib.Path(args.risk_profile)))
        print(json.dumps(output, sort_keys=True))
    except ContractError as exc:
        fail(exc.code, exc.detail)


if __name__ == "__main__":
    main()
