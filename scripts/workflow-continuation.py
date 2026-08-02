#!/usr/bin/env python3
"""Fail-closed terminal-state + semantic transition gate for OpenCode Governance.

SEMANTIC_WORKFLOW_STATE_MACHINE_V1 (compatibility: WORKFLOW_CONTINUATION_GATE_V1).
Constants are loaded exclusively from the generated contract module via governance-semantic.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any

_SCRIPTS = pathlib.Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

import importlib.util


def _load_semantic():
    path = _SCRIPTS / "governance-semantic.py"
    spec = importlib.util.spec_from_file_location("governance_semantic", path)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_SEM = _load_semantic()
KNOWN_COMMANDS = _SEM.KNOWN_COMMANDS
NON_TERMINAL_PHASES = _SEM.NON_TERMINAL_PHASES
SCHEMA = _SEM.SCHEMA
TERMINAL_BLOCKERS = _SEM.TERMINAL_BLOCKERS
TERMINAL_SUCCESS = _SEM.TERMINAL_SUCCESS
evaluate_continuation = _SEM.evaluate_continuation

# Back-compat alias for importers/tests that looked for the old schema name.
LEGACY_SCHEMA = "WORKFLOW_CONTINUATION_GATE_V1"


def result(**values: Any) -> dict[str, Any]:
    return {"schema": SCHEMA, "compatibility": LEGACY_SCHEMA, **values}


def load(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise ValueError(f"RUN_STATE_INVALID_JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError("RUN_STATE_MUST_BE_OBJECT")
    return value


def evaluate(state: dict[str, Any], expected_command: str) -> tuple[int, dict[str, Any]]:
    return evaluate_continuation(state, expected_command)


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
    # Silence unused import warnings for re-export consumers
    _ = (NON_TERMINAL_PHASES, TERMINAL_SUCCESS, TERMINAL_BLOCKERS, KNOWN_COMMANDS)
    raise SystemExit(main())
