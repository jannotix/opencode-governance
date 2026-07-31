#!/usr/bin/env python3
"""Fail-closed terminal-state gate for OpenCode Governance top-level workflows."""
from __future__ import annotations

import argparse
import json
import pathlib
from typing import Any

SCHEMA = "WORKFLOW_CONTINUATION_GATE_V1"
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
}
TERMINAL_SUCCESS = {"LOCAL_COMMITTED"}
TERMINAL_BLOCKERS = {
    "BLOCKED",
    "HUMAN_INPUT_REQUIRED",
    "LICENSE_DECISION_REQUIRED",
    "GOVERNANCE_PERMISSION_BLOCKED",
    "EXECUTOR_FAILOVER_BLOCKED",
    "BASELINE_BLOCKED",
    "DISCOVERY_BLOCKED",
    "PRODUCT_BLOCKED",
    "RELEASE_BLOCKED",
    "CONTEXT_BLOCKED",
    "PLAN_BLOCKED",
    "PERMISSION_BLOCKED",
    "SAFETY_BLOCKED",
    "EXTERNAL_TOOL_BLOCKED",
}
REQUIRED_FIELDS = {
    "top_level_command",
    "current_phase",
    "next_required_phase",
    "terminal_reason",
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


def result(**values: Any) -> dict[str, Any]:
    return {"schema": SCHEMA, **values}


def load(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise ValueError(f"RUN_STATE_INVALID_JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError("RUN_STATE_MUST_BE_OBJECT")
    return value


def evaluate(state: dict[str, Any], expected_command: str) -> tuple[int, dict[str, Any]]:
    missing = sorted(REQUIRED_FIELDS - set(state))
    if missing:
        return 2, result(decision="INVALID_RUN_STATE", error="REQUIRED_FIELDS_MISSING", missing_fields=missing)

    command = state.get("top_level_command")
    phase = state.get("current_phase")
    next_phase = state.get("next_required_phase")
    reason = state.get("terminal_reason")

    if expected_command == "ai-workflow" and command != "ai-workflow":
        return 2, result(decision="INVALID_RUN_STATE", error="TOP_LEVEL_COMMAND_MISMATCH")
    if expected_command == "ai-resume" and command != "ai-workflow":
        return 2, result(decision="INVALID_RUN_STATE", error="ORIGINAL_TOP_LEVEL_COMMAND_REQUIRED")
    if not isinstance(phase, str) or not phase.strip():
        return 2, result(decision="INVALID_RUN_STATE", error="CURRENT_PHASE_REQUIRED")

    if phase in TERMINAL_SUCCESS:
        if next_phase not in (None, "") or reason not in (None, ""):
            return 2, result(decision="INVALID_RUN_STATE", error="SUCCESS_TERMINAL_FIELDS_INVALID")
        return 0, result(
            decision="TERMINAL_ALLOWED",
            terminal_class="SUCCESS",
            top_level_command=command,
            current_phase=phase,
            next_required_phase=None,
            terminal_reason=None,
        )

    if phase in TERMINAL_BLOCKERS:
        if next_phase not in (None, ""):
            return 2, result(decision="INVALID_RUN_STATE", error="BLOCKER_NEXT_PHASE_FORBIDDEN")
        if not isinstance(reason, str) or not reason.strip():
            return 2, result(decision="INVALID_RUN_STATE", error="TERMINAL_REASON_REQUIRED")
        return 0, result(
            decision="TERMINAL_ALLOWED",
            terminal_class="BLOCKER",
            top_level_command=command,
            current_phase=phase,
            next_required_phase=None,
            terminal_reason=reason.strip(),
        )

    if phase in NON_TERMINAL_PHASES:
        if not isinstance(next_phase, str) or not next_phase.strip():
            return 2, result(decision="INVALID_RUN_STATE", error="NEXT_REQUIRED_PHASE_REQUIRED")
        if reason not in (None, ""):
            return 2, result(decision="INVALID_RUN_STATE", error="NON_TERMINAL_REASON_FORBIDDEN")
        action = state.get("next_action")
        if not isinstance(action, dict):
            return 2, result(decision="INVALID_RUN_STATE", error="ACTIONABLE_CONTINUATION_REQUIRED")
        kind = action.get("kind")
        if kind == "execute":
            action_command = action.get("command")
            if action_command not in KNOWN_COMMANDS:
                return 2, result(decision="INVALID_RUN_STATE", error="NON_EXECUTABLE_CONTINUATION")
            arguments = action.get("arguments", [])
            if not isinstance(arguments, list) or any(not isinstance(item, str) for item in arguments):
                return 2, result(decision="INVALID_RUN_STATE", error="INVALID_CONTINUATION_ARGUMENTS")
            if not action.get("expected_postcondition"):
                return 2, result(decision="INVALID_RUN_STATE", error="CONTINUATION_POSTCONDITION_REQUIRED")
        elif kind == "human_decision":
            if not action.get("decision_required") or not isinstance(action.get("available_choices"), list):
                return 2, result(decision="INVALID_RUN_STATE", error="INVALID_HUMAN_DECISION")
        else:
            return 2, result(decision="INVALID_RUN_STATE", error="NON_EXECUTABLE_CONTINUATION")
        return 3, result(
            decision="CONTINUE_REQUIRED",
            terminal_class=None,
            top_level_command=command,
            current_phase=phase,
            next_required_phase=next_phase.strip(),
            terminal_reason=None,
            next_action_kind=kind,
        )

    return 2, result(decision="INVALID_RUN_STATE", error="UNKNOWN_WORKFLOW_PHASE", current_phase=phase)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(prog="workflow-continuation")
    value.add_argument("--run-state", required=True)
    value.add_argument("--expected-command", choices=("ai-workflow", "ai-resume"), required=True)
    return value


def main() -> int:
    args = parser().parse_args()
    try:
        state = load(pathlib.Path(args.run_state))
        code, payload = evaluate(state, args.expected_command)
    except ValueError as exc:
        code, payload = 2, result(decision="INVALID_RUN_STATE", error=str(exc))
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
