#!/usr/bin/env python3
"""Deterministic governance scenario contracts and loopback agent simulation."""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
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
    "gh release",
    "deploy",
    "production rollback",
    "kubectl apply",
    "terraform apply",
    "rm -rf /",
    "format c:",
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
        has_tool = isinstance(step.get("tool"), str) and bool(step.get("tool"))
        has_text = isinstance(step.get("assistant_text"), str)
        if has_tool == has_text:
            fail("SCENARIO_STEP_SHAPE_INVALID", str(index))
        arguments = step.get("arguments", {})
        if has_tool and not isinstance(arguments, dict):
            fail("INVALID_SCENARIO_ARGUMENTS", str(index))
        command = arguments.get("command", "") if isinstance(arguments, dict) else ""
        lowered = str(command).lower()
        if any(forbidden in lowered for forbidden in FORBIDDEN_EXTERNAL_ACTIONS):
            fail("FORBIDDEN_EXTERNAL_ACTION", str(command))
        expected = step.get("expect_request_contains", [])
        if not isinstance(expected, list) or any(not isinstance(item, str) for item in expected):
            fail("INVALID_REQUEST_EXPECTATION", str(index))
    terminal = scenario.get("terminal")
    if not isinstance(terminal, str) or not terminal.strip():
        fail("SCENARIO_TERMINAL_REQUIRED")
    if terminal not in str(steps[-1].get("assistant_text", "")):
        fail("TERMINAL_MARKER_NOT_EMITTED")
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


class FixtureState:
    def __init__(self, scenario: dict[str, Any]) -> None:
        self.scenario = scenario
        self.requests: list[dict[str, Any]] = []
        self.error: str | None = None
        self.lock = threading.Lock()

    def next_response(self, payload: dict[str, Any]) -> dict[str, Any]:
        with self.lock:
            index = len(self.requests)
            self.requests.append(payload)
            steps = self.scenario["steps"]
            if index >= len(steps):
                self.error = "UNEXPECTED_EXTRA_MODEL_CALL"
                raise ValueError(self.error)
            step = steps[index]
            serialized = json.dumps(payload, sort_keys=True, ensure_ascii=False)
            for expected in step.get("expect_request_contains", []):
                if expected not in serialized:
                    self.error = f"REQUEST_EXPECTATION_MISSING:{index}:{expected}"
                    raise ValueError(self.error)
            if "tool" in step:
                message = {
                    "role": "assistant",
                    "content": None,
                    "tool_calls": [
                        {
                            "id": f"call-{index + 1}",
                            "type": "function",
                            "function": {
                                "name": step["tool"],
                                "arguments": json.dumps(step.get("arguments", {}), separators=(",", ":")),
                            },
                        }
                    ],
                }
                finish_reason = "tool_calls"
            else:
                message = {"role": "assistant", "content": step["assistant_text"]}
                finish_reason = "stop"
            return {
                "id": f"governance-fixture-{index + 1}",
                "object": "chat.completion",
                "created": 0,
                "model": "fixture",
                "choices": [{"index": 0, "message": message, "finish_reason": finish_reason}],
                "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
            }


class FixtureHandler(BaseHTTPRequestHandler):
    state: FixtureState

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("request must be a JSON object")
            response = self.state.next_response(payload)
            body = json.dumps(response).encode("utf-8")
            self.send_response(200)
        except Exception as exc:
            body = json.dumps({"error": {"message": str(exc), "type": "fixture_error"}}).encode("utf-8")
            self.send_response(500)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format: str, *_args: object) -> None:
        return


def write_opencode_config(config_dir: pathlib.Path, base_url: str) -> None:
    config_dir.mkdir(parents=True, exist_ok=True)
    config = {
        "$schema": "https://opencode.ai/config.json",
        "provider": {
            "fixture": {
                "npm": "@ai-sdk/openai-compatible",
                "name": "Governance Simulation Fixture",
                "options": {"baseURL": f"{base_url}/v1", "apiKey": "fixture"},
                "models": {"fixture": {"name": "Fixture"}},
            }
        },
        "agent": {
            "governance-simulation": {
                "mode": "primary",
                "model": "fixture/fixture",
                "prompt": "Follow the fixture tool sequence exactly and return its final terminal marker.",
                "permission": {"bash": "deny", "task": "allow", "edit": "deny"},
            }
        },
    }
    (config_dir / "opencode.json").write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")


def opencode_command(binary: pathlib.Path, root: pathlib.Path, request: str) -> list[str]:
    prefix = [sys.executable, str(binary)] if binary.suffix.lower() == ".py" else [str(binary)]
    return [
        *prefix,
        "run",
        "--pure",
        "--format",
        "json",
        "--agent",
        "governance-simulation",
        "--model",
        "fixture/fixture",
        "--dir",
        str(root),
        request,
    ]


def run_scenario(scenario: dict[str, Any], binary: pathlib.Path, root: pathlib.Path, timeout: int) -> dict[str, Any]:
    validation = validate_scenario(scenario)
    if not binary.is_file():
        fail("OPENCODE_BINARY_NOT_FOUND", str(binary))
    if not root.is_dir():
        fail("PROJECT_DIR_NOT_FOUND", str(root))
    state = FixtureState(scenario)
    handler = type("BoundFixtureHandler", (FixtureHandler,), {"state": state})
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix="opencode-governance-simulation-") as temporary:
            config_dir = pathlib.Path(temporary) / "config"
            write_opencode_config(config_dir, f"http://127.0.0.1:{server.server_port}")
            environment = os.environ.copy()
            environment["OPENCODE_CONFIG_DIR"] = str(config_dir)
            process = subprocess.run(
                opencode_command(binary, root, scenario["request"]),
                text=True,
                capture_output=True,
                timeout=max(1, timeout),
                env=environment,
            )
    except subprocess.TimeoutExpired:
        fail("SIMULATION_TIMEOUT")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
    if process.returncode:
        fail("OPENCODE_SIMULATION_FAILED", (process.stdout + "\n" + process.stderr).strip())
    if state.error:
        fail("FIXTURE_CONTRACT_FAILED", state.error)
    if len(state.requests) != len(scenario["steps"]):
        fail("MODEL_CALL_COUNT_MISMATCH", f"expected={len(scenario['steps'])} actual={len(state.requests)}")
    combined = process.stdout + "\n" + process.stderr
    if scenario["terminal"] not in combined:
        fail("TERMINAL_MARKER_NOT_OBSERVED")
    return {
        **validation,
        "status": "SIMULATION_RUN_PASS",
        "model_call_count": len(state.requests),
        "opencode_exit_code": process.returncode,
    }


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(prog="governance-simulation")
    subcommands = value.add_subparsers(dest="command", required=True)
    validate = subcommands.add_parser("validate")
    validate.add_argument("--scenario", required=True)
    run = subcommands.add_parser("run")
    run.add_argument("--scenario", required=True)
    run.add_argument("--opencode-bin", required=True)
    run.add_argument("--project-dir", required=True)
    run.add_argument("--timeout", type=int, default=120)
    return value


def main() -> None:
    args = parser().parse_args()
    scenario = load_scenario(pathlib.Path(args.scenario))
    if args.command == "validate":
        result = validate_scenario(scenario)
    else:
        result = run_scenario(
            scenario,
            pathlib.Path(args.opencode_bin).expanduser().resolve(),
            pathlib.Path(args.project_dir).expanduser().resolve(),
            args.timeout,
        )
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
