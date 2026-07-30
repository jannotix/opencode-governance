#!/usr/bin/env python3
"""Deterministic governance scenario contracts and fixture validation."""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any

ALL_COMMANDS = {
    "ai-init",
    "ai-audit",
    "ai-docs",
    "ai-discover",
    "ai-plan",
    "ai-execute",
    "ai-review",
    "ai-workflow",
    "ai-status",
    "ai-resume",
    "ai-metrics",
    "ai-release",
}
FORBIDDEN_EXTERNAL_ACTIONS = (
    "git push",
    "git merge",
    "gh pr merge",
    "deploy",
    "production rollback",
)


def fail(code: str, detail: str = "") -> None:
    payload = {"status": "ERROR", "code": code}
    if detail:
        payload["detail"] = detail
    print(json.dumps(payload, sort_keys=True), file=sys.stderr)
    raise SystemExit(2)


def load_scenario(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        fail("INVALID_SCENARIO_JSON", str(exc))
    if not isinstance(value, dict):
        fail("INVALID_SCENARIO_OBJECT")
    return value


def validate_scenario(scenario: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(scenario.get("name"), str) or not scenario["name"].strip():
        fail("SCENARIO_NAME_REQUIRED")
    if not isinstance(scenario.get("request"), str):
        fail("SCENARIO_REQUEST_REQUIRED")
    steps = scenario.get("steps")
    if not isinstance(steps, list) or not steps:
        fail("SCENARIO_STEPS_REQUIRED")
    for index, step in enumerate(steps):
        if not isinstance(step, dict):
            fail("INVALID_SCENARIO_STEP", str(index))
        arguments = step.get("arguments", {})
        command = arguments.get("command", "") if isinstance(arguments, dict) else ""
        lowered = command.lower()
        if any(forbidden in lowered for forbidden in FORBIDDEN_EXTERNAL_ACTIONS):
            fail("FORBIDDEN_EXTERNAL_ACTION", command)
    terminal = scenario.get("terminal")
    if not isinstance(terminal, str) or not terminal.strip():
        fail("SCENARIO_TERMINAL_REQUIRED")
    coverage = scenario.get("covers_commands", [])
    if not isinstance(coverage, list) or any(command not in ALL_COMMANDS for command in coverage):
        fail("INVALID_COMMAND_COVERAGE")
    if len(set(coverage)) != len(coverage):
        fail("DUPLICATE_COMMAND_COVERAGE")
    if len(coverage) == len(ALL_COMMANDS) and set(coverage) != ALL_COMMANDS:
        fail("INCOMPLETE_COMMAND_COVERAGE")
    return {
        "status": "SIMULATION_SCENARIO_VALID",
        "name": scenario["name"],
        "covered_command_count": len(coverage),
        "terminal": terminal,
        "step_count": len(steps),
    }


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(prog="governance-simulation")
    subcommands = value.add_subparsers(dest="command", required=True)
    validate = subcommands.add_parser("validate")
    validate.add_argument("--scenario", required=True)
    return value


def main() -> None:
    args = parser().parse_args()
    print(json.dumps(validate_scenario(load_scenario(pathlib.Path(args.scenario))), sort_keys=True))


if __name__ == "__main__":
    main()
