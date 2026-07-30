#!/usr/bin/env python3
"""Deterministic Quality Gates and governed learning for OpenCode Governance 3.5."""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from datetime import datetime, timezone
from typing import Any

TASK_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$")
DEDUP_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,191}$")
WORK_CLASSES = {"PATCH", "BOUNDED_FEATURE", "MAJOR_FEATURE", "EXISTING_PRODUCT_EVOLUTION", "NEW_PRODUCT", "HIGH_RISK_CHANGE"}
TASK_KINDS = {"BUGFIX", "FEATURE", "REFACTOR", "DOCS", "CONFIG", "GENERATED", "SPIKE"}
MANDATORY_TDD_RISKS = {"SECURITY", "AUTHORIZATION", "ROUTING", "PARSER", "DATA_MIGRATION", "PUBLIC_CONTRACT", "HIGH_RISK"}
EXCEPTIONS = {"DOCUMENTATION_ONLY", "GENERATED_ARTIFACT", "ENVIRONMENT_CONFIGURATION_ONLY", "NO_EXECUTABLE_HARNESS", "NON_PROMOTABLE_SPIKE"}
DEFECT_CLASSES = {"APPLICATION_DEFECT", "ENVIRONMENT_DEFECT", "GOVERNANCE_DEFECT"}
LEARNING_SOURCES = {"USER_CORRECTION", "FAILED_TASK", "REVIEW_FINDING", "SUCCESSFUL_PATTERN"}
GRADERS = {"CODE_BASED", "MODEL_BASED", "HUMAN", "HYBRID"}


class GateError(RuntimeError):
    pass


class Blocked(RuntimeError):
    def __init__(self, result: dict[str, Any]):
        super().__init__(result.get("status", "BLOCKED"))
        self.result = result


def now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def read(path: pathlib.Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise GateError(f"INVALID_JSON: {path.name}: {exc}") from exc


def write(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def append(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n")


def project(value: str) -> pathlib.Path:
    result = pathlib.Path(value).expanduser().resolve()
    if not result.is_dir():
        raise GateError("INVALID_PROJECT_DIR")
    return result


def valid_task(value: str) -> str:
    if not TASK_RE.fullmatch(value):
        raise GateError("INVALID_TASK_ID")
    return value


def task_dir(root: pathlib.Path, task_id: str) -> pathlib.Path:
    valid_task(task_id)
    base = (root / ".ai" / "tasks").resolve()
    result = (base / task_id).resolve()
    if result.parent != base:
        raise GateError("TASK_PATH_ESCAPE")
    return result


def exact(value: Any, fields: set[str], error: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != fields:
        raise GateError(error)
    return value


def strings(value: Any, field: str, allow_empty: bool = True) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) or not item.strip() for item in value):
        raise GateError(f"INVALID_STRING_LIST: {field}")
    if not allow_empty and not value:
        raise GateError(f"EMPTY_STRING_LIST: {field}")
    return value


def load_profile(root: pathlib.Path, task_id: str) -> dict[str, Any]:
    path = task_dir(root, task_id) / "QUALITY_PROFILE.json"
    if not path.is_file():
        raise GateError("QUALITY_PROFILE_MISSING")
    result = read(path)
    if result.get("schema") != "QUALITY_PROFILE_V1":
        raise GateError("QUALITY_PROFILE_INVALID")
    return result


def save_result(root: pathlib.Path, task_id: str, name: str, value: dict[str, Any]) -> dict[str, Any]:
    write(task_dir(root, task_id) / name, value)
    if value.get("status") in {"BLOCKED", "ARCHITECTURE_REVIEW_REQUIRED", "EVAL_GATE_FAILED", "NOT_READY_FOR_REVIEW", "EXCEPTION_REQUIRES_FINAL_REVIEW"}:
        raise Blocked(value)
    return value


def initialize(args: argparse.Namespace) -> dict[str, Any]:
    root = project(args.project_dir)
    valid_task(args.task_id)
    risks = sorted({item.strip().upper() for item in args.risks.split(",") if item.strip()})
    if args.work_class not in WORK_CLASSES or args.task_kind not in TASK_KINDS:
        raise GateError("QUALITY_PROFILE_INPUT_INVALID")
    debug = args.task_kind == "BUGFIX"
    tdd = args.task_kind in {"BUGFIX", "FEATURE", "REFACTOR"} or args.work_class == "HIGH_RISK_CHANGE" or bool(set(risks) & MANDATORY_TDD_RISKS)
    eval_required = "AI_SYSTEM" in risks
    value = {
        "schema": "QUALITY_PROFILE_V1",
        "task_id": args.task_id,
        "work_class": args.work_class,
        "task_kind": args.task_kind,
        "risks": risks,
        "debug_first_required": debug,
        "tdd_required": tdd,
        "eval_required": eval_required,
        "self_check_required": True,
        "learning_capture_enabled": args.task_kind != "SPIKE",
        "required_reliability_mode": "PASS_K" if eval_required else "NOT_APPLICABLE",
        "allowed_exception_classes": sorted(EXCEPTIONS),
        "created_at": now(),
    }
    write(task_dir(root, args.task_id) / "QUALITY_PROFILE.json", value)
    return value


def validate_debug(args: argparse.Namespace) -> dict[str, Any]:
    root = project(args.project_dir)
    profile = load_profile(root, args.task_id)
    value = exact(read(pathlib.Path(args.input_json)), {"symptom", "reproduction_status", "root_cause_status", "root_cause_evidence", "hypothesis", "minimal_experiment", "disproving_condition", "hypothesis_attempts", "defect_class"}, "DEBUG_PROOF_FIELDS_INVALID")
    if value["reproduction_status"] not in {"REPRODUCED", "EQUIVALENT_PROOF", "BLOCKED"} or value["root_cause_status"] not in {"CONFIRMED", "HYPOTHESIS", "BLOCKED"} or value["defect_class"] not in DEFECT_CLASSES:
        raise GateError("DEBUG_PROOF_ENUM_INVALID")
    strings(value["root_cause_evidence"], "root_cause_evidence")
    attempts = int(value["hypothesis_attempts"])
    errors = []
    if profile["debug_first_required"]:
        if value["reproduction_status"] not in {"REPRODUCED", "EQUIVALENT_PROOF"}: errors.append("REPRODUCTION_REQUIRED")
        if value["root_cause_status"] != "CONFIRMED": errors.append("ROOT_CAUSE_CONFIRMATION_REQUIRED")
        if not value["root_cause_evidence"]: errors.append("ROOT_CAUSE_EVIDENCE_REQUIRED")
        for field in ("symptom", "hypothesis", "minimal_experiment", "disproving_condition"):
            if not isinstance(value[field], str) or not value[field].strip(): errors.append(f"{field.upper()}_REQUIRED")
    architecture = attempts >= 3 and value["root_cause_status"] != "CONFIRMED"
    status = "ARCHITECTURE_REVIEW_REQUIRED" if architecture else ("BLOCKED" if errors else ("PASS" if profile["debug_first_required"] else "NOT_REQUIRED"))
    result = {"schema": "DEBUG_PROOF_V1", "task_id": args.task_id, **value, "architecture_review_required": architecture, "errors": sorted(set(errors)), "status": status, "validated_at": now()}
    return save_result(root, args.task_id, "DEBUG_PROOF.json", result)


def validate_tdd(args: argparse.Namespace) -> dict[str, Any]:
    root = project(args.project_dir)
    profile = load_profile(root, args.task_id)
    fields = {"red_command", "red_exit_code", "red_expected_failure", "red_observed_failure", "red_evidence_refs", "green_command", "green_exit_code", "green_evidence_refs", "regression_command", "regression_exit_code", "regression_evidence_refs", "exception_class", "exception_reason", "equivalent_verification"}
    value = exact(read(pathlib.Path(args.input_json)), fields, "TDD_PROOF_FIELDS_INVALID")
    errors = []
    exception = value["exception_class"]
    if exception is not None:
        if exception not in EXCEPTIONS: errors.append("TDD_EXCEPTION_INVALID")
        if not value["exception_reason"] or not value["equivalent_verification"]: errors.append("TDD_EXCEPTION_EVIDENCE_REQUIRED")
        status = "EXCEPTION_REQUIRES_FINAL_REVIEW" if profile["tdd_required"] and not errors else ("BLOCKED" if errors else "NOT_REQUIRED")
    else:
        for field in ("red_command", "red_expected_failure", "red_observed_failure", "green_command", "regression_command"):
            if not isinstance(value[field], str) or not value[field].strip(): errors.append(f"{field.upper()}_REQUIRED")
        for field in ("red_evidence_refs", "green_evidence_refs", "regression_evidence_refs"):
            try: strings(value[field], field, allow_empty=False)
            except GateError: errors.append(f"{field.upper()}_REQUIRED")
        if int(value["red_exit_code"]) == 0: errors.append("RED_MUST_FAIL")
        if int(value["green_exit_code"]) != 0: errors.append("GREEN_MUST_PASS")
        if int(value["regression_exit_code"]) != 0: errors.append("REGRESSION_MUST_PASS")
        status = "BLOCKED" if profile["tdd_required"] and errors else ("PASS" if profile["tdd_required"] else "NOT_REQUIRED")
    result = {"schema": "TDD_PROOF_V1", "task_id": args.task_id, **value, "errors": sorted(set(errors)), "status": status, "validated_at": now()}
    return save_result(root, args.task_id, "TDD_PROOF.json", result)


def validate_eval(args: argparse.Namespace) -> dict[str, Any]:
    root = project(args.project_dir)
    profile = load_profile(root, args.task_id)
    fields = {"capability_evals", "regression_evals", "negative_cases", "forbidden_behaviors", "grader_type", "success_threshold", "reliability_mode", "run_count", "observed_successes", "evidence_refs", "exploratory_reason"}
    value = exact(read(pathlib.Path(args.input_json)), fields, "EVAL_PLAN_FIELDS_INVALID")
    errors = []
    for field in ("capability_evals", "regression_evals", "negative_cases", "forbidden_behaviors", "evidence_refs"):
        try: strings(value[field], field, allow_empty=False)
        except GateError: errors.append(f"{field.upper()}_REQUIRED")
    if value["grader_type"] not in GRADERS: errors.append("GRADER_TYPE_INVALID")
    if value["reliability_mode"] not in {"PASS_K", "PASS_AT_K"}: errors.append("RELIABILITY_MODE_INVALID")
    runs, successes, threshold = int(value["run_count"]), int(value["observed_successes"]), float(value["success_threshold"])
    if runs < 1 or successes < 0 or successes > runs or not 0 < threshold <= 1: errors.append("EVAL_COUNTS_INVALID")
    if profile["eval_required"] and value["reliability_mode"] != profile["required_reliability_mode"]: errors.append("PASS_K_REQUIRED")
    if value["reliability_mode"] == "PASS_K" and successes != runs: errors.append("PASS_K_NOT_MET")
    if runs > 0 and successes / runs < threshold: errors.append("SUCCESS_THRESHOLD_NOT_MET")
    if value["reliability_mode"] == "PASS_AT_K" and not value["exploratory_reason"]: errors.append("EXPLORATORY_REASON_REQUIRED")
    status = "EVAL_GATE_FAILED" if profile["eval_required"] and errors else ("PASS" if profile["eval_required"] else "NOT_REQUIRED")
    result = {"schema": "EVAL_PLAN_V1", "task_id": args.task_id, **value, "errors": sorted(set(errors)), "status": status, "validated_at": now()}
    return save_result(root, args.task_id, "EVAL_PLAN.json", result)


def self_check(args: argparse.Namespace) -> dict[str, Any]:
    root = project(args.project_dir)
    profile = load_profile(root, args.task_id)
    booleans = {"plan_compliance", "scope_compliance", "tests_pass", "lint_pass", "typecheck_pass", "format_pass", "security_invariants_checked", "dependency_delta_checked", "migration_delta_checked", "documentation_impact_checked", "dead_code_checked", "temporary_files_checked", "external_action_compliance"}
    fields = booleans | {"unresolved_assumptions", "evidence_refs"}
    value = exact(read(pathlib.Path(args.input_json)), fields, "SELF_CHECK_FIELDS_INVALID")
    errors = [field.upper() for field in booleans if value[field] is not True]
    try: strings(value["unresolved_assumptions"], "unresolved_assumptions")
    except GateError: errors.append("UNRESOLVED_ASSUMPTIONS_INVALID")
    try: strings(value["evidence_refs"], "evidence_refs", allow_empty=False)
    except GateError: errors.append("SELF_CHECK_EVIDENCE_REQUIRED")
    if value["unresolved_assumptions"]: errors.append("UNRESOLVED_ASSUMPTIONS")
    status = "NOT_READY_FOR_REVIEW" if profile["self_check_required"] and errors else "READY_FOR_REVIEW"
    result = {"schema": "IMPLEMENTATION_SELF_CHECK_V1", "task_id": args.task_id, **value, "errors": sorted(set(errors)), "status": status, "approval_authority": False, "recorded_at": now()}
    return save_result(root, args.task_id, "IMPLEMENTATION_SELF_CHECK.json", result)


def learning_paths(root: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path]:
    return root / ".ai" / "learning" / "CANDIDATES.jsonl", root / ".ai" / "learning" / "PROMOTIONS.jsonl"


def lines(path: pathlib.Path) -> list[dict[str, Any]]:
    if not path.is_file(): return []
    try: return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    except Exception as exc: raise GateError(f"INVALID_JSONL: {path.name}: {exc}") from exc


def add_learning(args: argparse.Namespace) -> dict[str, Any]:
    root = project(args.project_dir)
    fields = {"candidate_id", "source", "scope", "statement", "evidence_refs", "confidence", "dedup_key", "privacy_class", "stale_when"}
    value = exact(read(pathlib.Path(args.input_json)), fields, "LEARNING_CANDIDATE_FIELDS_INVALID")
    if not TASK_RE.fullmatch(str(value["candidate_id"])) or value["source"] not in LEARNING_SOURCES or not DEDUP_RE.fullmatch(str(value["dedup_key"])):
        raise GateError("LEARNING_CANDIDATE_IDENTITY_INVALID")
    for field in ("scope", "evidence_refs", "stale_when"): strings(value[field], field, allow_empty=False)
    if not isinstance(value["statement"], str) or not value["statement"].strip() or not isinstance(value["privacy_class"], str) or not value["privacy_class"].strip() or not 0 <= float(value["confidence"]) <= 1:
        raise GateError("LEARNING_CANDIDATE_VALUE_INVALID")
    candidates, promotions = learning_paths(root)
    if any(item.get("dedup_key") == value["dedup_key"] for item in lines(candidates)):
        raise Blocked({"schema": "LEARNING_CANDIDATE_RESULT_V1", "status": "DUPLICATE_LEARNING_CANDIDATE", "dedup_key": value["dedup_key"]})
    result = {"schema": "LEARNING_CANDIDATE_V1", **value, "promotion_status": "PENDING", "created_at": now()}
    append(candidates, result)
    return result


def promote_learning(args: argparse.Namespace) -> dict[str, Any]:
    root = project(args.project_dir)
    fields = {"candidate_id", "dedup_key", "approved_by", "approval_verdict", "evidence_refs", "approved_scope", "stale_when", "privacy_class"}
    value = exact(read(pathlib.Path(args.input_json)), fields, "LEARNING_PROMOTION_FIELDS_INVALID")
    candidates_path, promotions_path = learning_paths(root)
    candidates = lines(candidates_path)
    matching = [item for item in candidates if item.get("candidate_id") == value["candidate_id"] and item.get("dedup_key") == value["dedup_key"]]
    if not matching: raise GateError("LEARNING_CANDIDATE_NOT_FOUND")
    if value["approved_by"] != "FINAL_REVIEWER" or value["approval_verdict"] != "APPROVED":
        raise Blocked({"schema": "LEARNING_PROMOTION_RESULT_V1", "status": "FINAL_REVIEWER_APPROVAL_REQUIRED", "candidate_id": value["candidate_id"]})
    for field in ("evidence_refs", "approved_scope", "stale_when"): strings(value[field], field, allow_empty=False)
    if any(item.get("candidate_id") == value["candidate_id"] for item in lines(promotions_path)):
        raise Blocked({"schema": "LEARNING_PROMOTION_RESULT_V1", "status": "DUPLICATE_PROMOTION", "candidate_id": value["candidate_id"]})
    result = {"schema": "LEARNING_PROMOTION_V1", **value, "status": "PROMOTED", "memory_updated": False, "promoted_at": now()}
    append(promotions_path, result)
    return result


def validate_task(args: argparse.Namespace) -> dict[str, Any]:
    root = project(args.project_dir)
    profile = load_profile(root, args.task_id)
    directory = task_dir(root, args.task_id)
    errors = []
    requirements = [("debug_first_required", "DEBUG_PROOF.json", {"PASS"}), ("tdd_required", "TDD_PROOF.json", {"PASS"}), ("eval_required", "EVAL_PLAN.json", {"PASS"}), ("self_check_required", "IMPLEMENTATION_SELF_CHECK.json", {"READY_FOR_REVIEW"})]
    for flag, name, passing in requirements:
        if not profile[flag]: continue
        path = directory / name
        if not path.is_file(): errors.append(f"{name}_MISSING"); continue
        result = read(path)
        if result.get("status") not in passing: errors.append(f"{name}_NOT_PASSING")
    value = {"schema": "QUALITY_VALIDATION_V1", "task_id": args.task_id, "valid": not errors, "errors": errors, "validated_at": now()}
    write(directory / "QUALITY_VALIDATION.json", value)
    if errors: raise Blocked({**value, "status": "BLOCKED"})
    return value


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="quality-gates")
    commands = parser.add_subparsers(dest="action", required=True)
    def common(command: argparse.ArgumentParser, task: bool = False):
        command.add_argument("--project-dir", required=True)
        if task: command.add_argument("--task-id", required=True)
    command = commands.add_parser("initialize-profile"); common(command, True); command.add_argument("--work-class", required=True, choices=sorted(WORK_CLASSES)); command.add_argument("--task-kind", required=True, choices=sorted(TASK_KINDS)); command.add_argument("--risks", default=""); command.set_defaults(handler=initialize)
    for name, handler in (("validate-debug", validate_debug), ("validate-tdd", validate_tdd), ("validate-eval", validate_eval), ("record-self-check", self_check)):
        command = commands.add_parser(name); common(command, True); command.add_argument("--input-json", required=True); command.set_defaults(handler=handler)
    command = commands.add_parser("add-learning"); common(command); command.add_argument("--input-json", required=True); command.set_defaults(handler=add_learning)
    command = commands.add_parser("promote-learning"); common(command); command.add_argument("--input-json", required=True); command.set_defaults(handler=promote_learning)
    command = commands.add_parser("validate-task"); common(command, True); command.set_defaults(handler=validate_task)
    return parser


def main() -> int:
    try:
        args = build_parser().parse_args()
        print(json.dumps(args.handler(args), ensure_ascii=False, separators=(",", ":")))
        return 0
    except Blocked as exc:
        print(json.dumps(exc.result, ensure_ascii=False, separators=(",", ":")))
        return 3
    except GateError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except Exception as exc:
        print(f"QUALITY_GATES_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
