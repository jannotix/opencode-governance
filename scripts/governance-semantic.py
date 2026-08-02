#!/usr/bin/env python3
"""SEMANTIC_WORKFLOW_STATE_MACHINE_V1 — shared semantic evaluation for continuation and authority."""
from __future__ import annotations

import pathlib
import sys
from typing import Any

# Allow import of generated module next to this file.
_SCRIPTS = pathlib.Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))
from generated import governance_contract_data as G  # noqa: E402

SCHEMA = "SEMANTIC_WORKFLOW_STATE_MACHINE_V1"
LEGACY_SCHEMA = "WORKFLOW_CONTINUATION_GATE_V1"

# Re-export single authority constants
NON_TERMINAL_PHASES = G.NON_TERMINAL_PHASES
TERMINAL_SUCCESS = G.TERMINAL_SUCCESS
TERMINAL_BLOCKERS = G.TERMINAL_BLOCKERS
KNOWN_COMMANDS = G.KNOWN_COMMANDS
TERMINAL_REASONS = G.TERMINAL_REASONS
TRANSITIONS = G.TRANSITIONS
PHASES = G.PHASES
GOVERNANCE_VERSION = G.GOVERNANCE_VERSION
COMMANDS = G.COMMANDS
MANAGED_TOOLS = G.MANAGED_TOOLS
ASSURANCE_LEVELS = G.ASSURANCE_LEVELS
SUPPORTED_OPENCODE_VERSIONS = G.SUPPORTED_OPENCODE_VERSIONS
SHARED_PROMPT_SECTIONS = G.SHARED_PROMPT_SECTIONS
SOURCE_SPEC_SHA256 = G.SOURCE_SPEC_SHA256


class SemanticError(Exception):
    def __init__(self, code: str, detail: str = "") -> None:
        self.code = code
        self.detail = detail
        super().__init__(code if not detail else f"{code}: {detail}")


def _artifacts_present(state: dict[str, Any], required: list[str]) -> None:
    if not required:
        return
    declared = state.get("artifacts") if isinstance(state.get("artifacts"), dict) else {}
    present = state.get("present_artifacts") if isinstance(state.get("present_artifacts"), list) else None
    for name in required:
        if present is not None:
            if name not in present:
                raise SemanticError("REQUIRED_ARTIFACT_MISSING", name)
            continue
        if name not in declared:
            raise SemanticError("REQUIRED_ARTIFACT_MISSING", name)
        meta = declared[name]
        if not isinstance(meta, dict):
            raise SemanticError("ARTIFACT_META_INVALID", name)
        if state.get("task_id") and meta.get("task_id") not in (None, "", state.get("task_id")):
            raise SemanticError("ARTIFACT_TASK_MISMATCH", name)
        if meta.get("stale") is True:
            raise SemanticError("ARTIFACT_STALE", name)
        cand = state.get("candidate_identity") or state.get("frozen_candidate")
        req_cand = meta.get("candidate_identity")
        if cand and req_cand and cand != req_cand:
            raise SemanticError("ARTIFACT_CANDIDATE_MISMATCH", name)


def _receipts_present(state: dict[str, Any], required: list[str]) -> None:
    if not required:
        return
    declared = state.get("receipts") if isinstance(state.get("receipts"), dict) else {}
    present = state.get("present_receipts") if isinstance(state.get("present_receipts"), list) else None
    for name in required:
        if present is not None:
            if name not in present:
                raise SemanticError("REQUIRED_RECEIPT_MISSING", name)
            continue
        if name not in declared:
            raise SemanticError("REQUIRED_RECEIPT_MISSING", name)
        meta = declared[name]
        if isinstance(meta, dict) and meta.get("stale") is True:
            raise SemanticError("RECEIPT_STALE", name)


def _owner_decision(state: dict[str, Any], required: bool) -> None:
    if not required:
        return
    decision = state.get("owner_decision")
    if not isinstance(decision, dict) or not decision.get("decision"):
        raise SemanticError("OWNER_DECISION_REQUIRED")


def _candidate_state(state: dict[str, Any], required: str | None) -> None:
    if not required:
        return
    cand = state.get("candidate_state") or state.get("candidate_identity_state")
    if cand != required:
        # Allow frozen_candidate present as FROZEN
        if required == "FROZEN" and state.get("frozen_candidate"):
            return
        raise SemanticError("CANDIDATE_STATE_MISMATCH", f"required={required} actual={cand}")


def _review_state(state: dict[str, Any], required: str | None) -> None:
    if not required:
        return
    rev = state.get("review_state")
    if rev == required:
        return
    if required == "BOTH_INDEPENDENT_REPORTS":
        reports = state.get("review_reports") if isinstance(state.get("review_reports"), dict) else {}
        if reports.get("implementation") and reports.get("architecture"):
            return
        present = state.get("present_receipts") if isinstance(state.get("present_receipts"), list) else []
        if "IMPLEMENTATION_REVIEW" in present and "ARCHITECTURE_REVIEW" in present:
            return
    if required == "FINAL_PASS":
        if state.get("final_verdict") == "PASS":
            return
        present = state.get("present_receipts") if isinstance(state.get("present_receipts"), list) else []
        if "FINAL_ADJUDICATION" in present:
            return
    raise SemanticError("REVIEW_STATE_MISMATCH", f"required={required} actual={rev}")


def _lifecycle_ok(transition: dict[str, Any], state: dict[str, Any]) -> None:
    modes = transition.get("lifecycle_modes") or ["STANDARD", "LIGHT", "FULL"]
    mode = state.get("lifecycle_mode") or "STANDARD"
    if mode not in modes:
        raise SemanticError("LIFECYCLE_MODE_FORBIDDEN", str(mode))


def _attempt_ok(transition: dict[str, Any], state: dict[str, Any]) -> None:
    expected = bool(transition.get("attempt_consumed"))
    actual = state.get("attempt_consumed")
    if actual is None:
        # Infer from next_action if present
        action = state.get("next_action") if isinstance(state.get("next_action"), dict) else {}
        if "attempt_consumed" in action:
            actual = action.get("attempt_consumed")
    if actual is None:
        # Default: assume transition rule when not declared only if not expected
        if expected:
            raise SemanticError("ATTEMPT_CONSUMPTION_UNDECLARED")
        return
    if bool(actual) != expected:
        raise SemanticError("ATTEMPT_CONSUMPTION_MISMATCH", f"expected={expected} actual={actual}")


def validate_transition_semantics(state: dict[str, Any]) -> dict[str, Any]:
    """Validate non-terminal continuation against the generated transition table."""
    phase = str(state.get("current_phase") or "").strip()
    next_phase = str(state.get("next_required_phase") or "").strip()
    if not phase:
        raise SemanticError("CURRENT_PHASE_REQUIRED")
    if phase not in PHASES:
        raise SemanticError("UNKNOWN_WORKFLOW_PHASE", phase)
    if not next_phase:
        raise SemanticError("NEXT_REQUIRED_PHASE_REQUIRED")
    if next_phase not in PHASES and next_phase not in TERMINAL_SUCCESS and next_phase not in TERMINAL_BLOCKERS:
        # allow successor that is defined as phase
        if next_phase not in PHASES:
            raise SemanticError("UNKNOWN_SUCCESSOR_PHASE", next_phase)

    action = state.get("next_action")
    if not isinstance(action, dict):
        raise SemanticError("ACTIONABLE_CONTINUATION_REQUIRED")
    kind = action.get("kind")
    phase_meta = PHASES.get(phase) or {}
    allowed_kinds = set(phase_meta.get("allowed_next_action_kinds") or [])
    if allowed_kinds and kind not in allowed_kinds:
        raise SemanticError("NEXT_ACTION_KIND_FORBIDDEN", str(kind))

    command: str | None = None
    if kind == "execute":
        command = action.get("command")
        if command not in KNOWN_COMMANDS:
            raise SemanticError("NON_EXECUTABLE_CONTINUATION", str(command))
        arguments = action.get("arguments", [])
        if not isinstance(arguments, list) or any(not isinstance(item, str) for item in arguments):
            raise SemanticError("INVALID_CONTINUATION_ARGUMENTS")
        post = action.get("expected_postcondition")
        if not post:
            raise SemanticError("CONTINUATION_POSTCONDITION_REQUIRED")
    elif kind == "human_decision":
        command = ""
        if not action.get("decision_required") or not isinstance(action.get("available_choices"), list):
            raise SemanticError("INVALID_HUMAN_DECISION")
        post = next_phase
    else:
        raise SemanticError("NON_EXECUTABLE_CONTINUATION", str(kind))

    # Successor allow-list from phase definition
    allowed = set(phase_meta.get("allowed_successors") or [])
    if allowed and next_phase not in allowed:
        raise SemanticError("DISALLOWED_SUCCESSOR", f"{phase}->{next_phase}")

    transition = G.find_transition(phase, next_phase, command)
    if transition is None:
        raise SemanticError("TRANSITION_NOT_DEFINED", f"{phase}->{next_phase}|{command}")

    # Command must match transition (empty command for human_decision)
    t_cmd = transition.get("command") or ""
    if (command or "") != t_cmd:
        raise SemanticError("TRANSITION_COMMAND_MISMATCH", f"required={t_cmd} actual={command}")

    if kind == "execute":
        required_post = transition.get("required_postcondition") or next_phase
        if action.get("expected_postcondition") != required_post:
            raise SemanticError(
                "TRANSITION_POSTCONDITION_MISMATCH",
                f"required={required_post} actual={action.get('expected_postcondition')}",
            )

    _artifacts_present(state, list(transition.get("required_artifacts") or []))
    _receipts_present(state, list(transition.get("required_receipts") or []))
    _owner_decision(state, bool(transition.get("required_owner_decision")))
    _candidate_state(state, transition.get("required_candidate_state"))
    _review_state(state, transition.get("required_review_state"))
    _lifecycle_ok(transition, state)
    _attempt_ok(transition, state)

    # Planning must not claim executor started
    if phase in {"CONTEXT_ROUTING", "DELIVERY_ARCHITECTURE", "OPERATIONAL_PLANNING", "READY_FOR_EXECUTION"}:
        if state.get("executor_started") is True or state.get("a5_started") is True:
            raise SemanticError("PLANNING_EXECUTOR_START_CLAIM_FORBIDDEN")

    return {
        "status": "SEMANTIC_TRANSITION_VALID",
        "schema": SCHEMA,
        "transition_id": transition.get("transition_id"),
        "from": phase,
        "to": next_phase,
        "command": command,
        "attempt_consumed": bool(transition.get("attempt_consumed")),
    }


def evaluate_continuation(state: dict[str, Any], expected_command: str) -> tuple[int, dict[str, Any]]:
    """Full gate evaluation compatible with WORKFLOW_CONTINUATION_GATE_V1 exit codes."""
    required_fields = {"top_level_command", "current_phase", "next_required_phase", "terminal_reason"}
    missing = sorted(required_fields - set(state))
    if missing:
        return 2, {
            "schema": SCHEMA,
            "compatibility": LEGACY_SCHEMA,
            "decision": "INVALID_RUN_STATE",
            "error": "REQUIRED_FIELDS_MISSING",
            "missing_fields": missing,
        }

    command = state.get("top_level_command")
    phase = state.get("current_phase")
    next_phase = state.get("next_required_phase")
    reason = state.get("terminal_reason")

    if expected_command == "ai-workflow" and command != "ai-workflow":
        return 2, _invalid("TOP_LEVEL_COMMAND_MISMATCH")
    if expected_command == "ai-resume" and command != "ai-workflow":
        return 2, _invalid("ORIGINAL_TOP_LEVEL_COMMAND_REQUIRED")
    if not isinstance(phase, str) or not phase.strip():
        return 2, _invalid("CURRENT_PHASE_REQUIRED")
    phase = phase.strip()

    if phase in TERMINAL_SUCCESS:
        if next_phase not in (None, "") or reason not in (None, ""):
            return 2, _invalid("SUCCESS_TERMINAL_FIELDS_INVALID")
        return 0, {
            "schema": SCHEMA,
            "compatibility": LEGACY_SCHEMA,
            "decision": "TERMINAL_ALLOWED",
            "terminal_class": "SUCCESS",
            "top_level_command": command,
            "current_phase": phase,
            "next_required_phase": None,
            "terminal_reason": None,
        }

    if phase in TERMINAL_BLOCKERS:
        if next_phase not in (None, ""):
            return 2, _invalid("BLOCKER_NEXT_PHASE_FORBIDDEN")
        if not isinstance(reason, str) or not reason.strip():
            return 2, _invalid("TERMINAL_REASON_REQUIRED")
        # Blocker must not claim executable next action
        action = state.get("next_action")
        if isinstance(action, dict) and action.get("kind") == "execute":
            return 2, _invalid("BLOCKER_EXECUTABLE_ACTION_FORBIDDEN")
        return 0, {
            "schema": SCHEMA,
            "compatibility": LEGACY_SCHEMA,
            "decision": "TERMINAL_ALLOWED",
            "terminal_class": "BLOCKER",
            "top_level_command": command,
            "current_phase": phase,
            "next_required_phase": None,
            "terminal_reason": reason.strip(),
        }

    if phase in NON_TERMINAL_PHASES:
        if not isinstance(next_phase, str) or not next_phase.strip():
            return 2, _invalid("NEXT_REQUIRED_PHASE_REQUIRED")
        if reason not in (None, ""):
            return 2, _invalid("NON_TERMINAL_REASON_FORBIDDEN")
        try:
            semantic = validate_transition_semantics(state)
        except SemanticError as exc:
            return 2, _invalid(exc.code, detail=exc.detail, current_phase=phase)
        action = state.get("next_action") if isinstance(state.get("next_action"), dict) else {}
        return 3, {
            "schema": SCHEMA,
            "compatibility": LEGACY_SCHEMA,
            "decision": "CONTINUE_REQUIRED",
            "terminal_class": None,
            "top_level_command": command,
            "current_phase": phase,
            "next_required_phase": next_phase.strip(),
            "terminal_reason": None,
            "next_action_kind": action.get("kind"),
            "transition_id": semantic.get("transition_id"),
            "semantic": "PASS",
        }

    return 2, _invalid("UNKNOWN_WORKFLOW_PHASE", current_phase=phase)


def _invalid(error: str, detail: str = "", **extra: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "schema": SCHEMA,
        "compatibility": LEGACY_SCHEMA,
        "decision": "INVALID_RUN_STATE",
        "error": error,
    }
    if detail:
        payload["detail"] = detail
    payload.update(extra)
    return payload


def validate_continuation_authority(state: dict[str, Any]) -> dict[str, Any]:
    """Authority-facing wrapper raising SemanticError-compatible codes via dict."""
    # Map evaluate codes into authority-style status
    code, payload = evaluate_continuation(state, "ai-workflow")
    if code == 0:
        return {
            "status": "TERMINAL_CONTINUATION_VALID",
            "terminal_reason": payload.get("terminal_reason"),
            "current_phase": payload.get("current_phase"),
            "schema": SCHEMA,
        }
    if code == 3:
        return {
            "status": "ACTIONABLE_CONTINUATION_VALID",
            "kind": payload.get("next_action_kind"),
            "current_phase": payload.get("current_phase"),
            "next_required_phase": payload.get("next_required_phase"),
            "transition_id": payload.get("transition_id"),
            "schema": SCHEMA,
        }
    raise SemanticError(str(payload.get("error") or "INVALID_RUN_STATE"), str(payload.get("detail") or ""))
