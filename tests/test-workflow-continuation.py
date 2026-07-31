#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
CORE = ROOT / "scripts" / "workflow-continuation.py"

DEFAULT_ACTION = {
    "kind": "execute",
    "command": "/ai-plan",
    "arguments": [],
    "expected_postcondition": "READY_FOR_EXECUTION",
}


def run_gate(state: dict[str, object], expected_command: str = "ai-workflow") -> tuple[int, dict[str, object], str]:
    with tempfile.TemporaryDirectory(prefix="opencode-workflow-continuation-") as directory:
        path = pathlib.Path(directory) / "RUN_STATE.json"
        path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
        result = subprocess.run(
            ["python3", str(CORE), "--run-state", str(path), "--expected-command", expected_command],
            text=True,
            capture_output=True,
        )
        payload: dict[str, object] = {}
        if result.stdout.strip():
            payload = json.loads(result.stdout)
        return result.returncode, payload, result.stderr


def continuing(phase: str, next_phase: str) -> dict[str, object]:
    return {
        "top_level_command": "ai-workflow",
        "current_phase": phase,
        "next_required_phase": next_phase,
        "terminal_reason": None,
        "next_action": DEFAULT_ACTION,
    }


def main() -> None:
    code, payload, _ = run_gate(continuing("AUDIT_PASS", "IDEA_INTAKE"))
    assert code == 3
    assert payload["decision"] == "CONTINUE_REQUIRED"
    assert payload["current_phase"] == "AUDIT_PASS"
    assert payload["next_required_phase"] == "IDEA_INTAKE"
    assert payload["next_action_kind"] == "execute"

    for phase, next_phase in (
        ("BASELINE_DEFECT", "BASELINE_DUAL_AUDIT"),
        ("DISCOVERY_DEFECT", "ADAPTIVE_PRODUCT_DISCOVERY"),
        ("PASS", "PRODUCT_COMPLETENESS_RECONCILIATION"),
        ("IMPLEMENTATION_DEFECT", "IMPLEMENTING"),
        ("PLAN_DEFECT", "CONTEXT_ROUTING"),
        ("PRODUCT_DEFECT", "IMPLEMENTING"),
        ("NOT_READY_FOR_PRODUCTION", "VALIDATED_LEARNING"),
    ):
        code, payload, _ = run_gate(continuing(phase, next_phase))
        assert code == 3, (phase, payload)
        assert payload["decision"] == "CONTINUE_REQUIRED"

    code, payload, _ = run_gate(
        {
            "top_level_command": "ai-workflow",
            "current_phase": "AUDIT_PASS",
            "next_required_phase": "IDEA_INTAKE",
            "terminal_reason": None,
        }
    )
    assert code == 2
    assert payload["error"] == "ACTIONABLE_CONTINUATION_REQUIRED"

    code, payload, _ = run_gate(
        {
            "top_level_command": "ai-workflow",
            "current_phase": "LOCAL_COMMITTED",
            "next_required_phase": None,
            "terminal_reason": None,
        }
    )
    assert code == 0
    assert payload["decision"] == "TERMINAL_ALLOWED"

    code, payload, _ = run_gate(
        {
            "top_level_command": "ai-workflow",
            "current_phase": "HUMAN_INPUT_REQUIRED",
            "next_required_phase": None,
            "terminal_reason": "A material product decision requires owner approval.",
        }
    )
    assert code == 0
    assert payload["decision"] == "TERMINAL_ALLOWED"

    code, payload, _ = run_gate(
        {
            "top_level_command": "ai-workflow",
            "current_phase": "BLOCKED",
            "next_required_phase": None,
            "terminal_reason": None,
        }
    )
    assert code == 2
    assert payload["decision"] == "INVALID_RUN_STATE"
    assert payload["error"] == "TERMINAL_REASON_REQUIRED"

    code, payload, _ = run_gate(
        {
            "top_level_command": "ai-workflow",
            "current_phase": "UNRECOGNIZED_PHASE",
            "next_required_phase": "IMPLEMENTING",
            "terminal_reason": None,
            "next_action": DEFAULT_ACTION,
        }
    )
    assert code == 2
    assert payload["error"] == "UNKNOWN_WORKFLOW_PHASE"

    code, payload, _ = run_gate(
        {
            "top_level_command": "ai-resume",
            "current_phase": "AUDIT_PASS",
            "next_required_phase": "IDEA_INTAKE",
            "terminal_reason": None,
            "next_action": DEFAULT_ACTION,
        },
        expected_command="ai-resume",
    )
    assert code == 2
    assert payload["error"] == "ORIGINAL_TOP_LEVEL_COMMAND_REQUIRED"

    code, payload, _ = run_gate(
        continuing("AUDIT_PASS", "IDEA_INTAKE"),
        expected_command="ai-resume",
    )
    assert code == 3
    assert payload["decision"] == "CONTINUE_REQUIRED"
    assert payload["top_level_command"] == "ai-workflow"

    for relative in (
        "templates/commands/ai-workflow.md",
        "templates/commands/ai-resume.md",
        "templates/agents/architect.md",
        "templates/agents/build.md",
        "templates/agents/plan.md",
    ):
        text = (ROOT / relative).read_text(encoding="utf-8")
        for marker in (
            "WORKFLOW_CONTINUATION_GATE_V1",
            "top_level_command",
            "current_phase",
            "next_required_phase",
            "terminal_reason",
            "CONTINUE_REQUIRED",
        ):
            assert marker in text, f"{relative} missing {marker}"
        if relative != "templates/agents/plan.md":
            assert "TERMINAL_ALLOWED" in text, f"{relative} missing TERMINAL_ALLOWED"

    print("PASS: deterministic workflow continuation contract")


if __name__ == "__main__":
    main()
