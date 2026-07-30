#!/usr/bin/env python3
"""End-to-end loopback hosting regressions for governance simulation."""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SIMULATION = ROOT / "scripts" / "governance-simulation.py"


class SimulationRunTests(unittest.TestCase):
    def test_loopback_fixture_drives_agent_client_to_terminal(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            scenario = root / "scenario.json"
            scenario.write_text(
                json.dumps(
                    {
                        "name": "loopback-agent",
                        "request": "exercise governed status",
                        "covers_commands": ["ai-status"],
                        "steps": [
                            {
                                "tool": "bash",
                                "arguments": {"command": "/ai-status"},
                                "expect_request_contains": ["messages"],
                            },
                            {
                                "assistant_text": "LOCAL_COMMITTED",
                                "expect_request_contains": ["simulated tool output"],
                            },
                        ],
                        "terminal": "LOCAL_COMMITTED",
                    }
                ),
                encoding="utf-8",
            )
            fake = root / "fake-opencode.py"
            fake.write_text(
                textwrap.dedent(
                    """
                    import json
                    import os
                    import pathlib
                    import sys
                    import urllib.request

                    config = json.loads((pathlib.Path(os.environ["OPENCODE_CONFIG_DIR"]) / "opencode.json").read_text())
                    endpoint = config["provider"]["fixture"]["options"]["baseURL"] + "/chat/completions"
                    messages = [{"role": "user", "content": sys.argv[-1]}]
                    tools = [{"type": "function", "function": {"name": "bash", "description": "run command", "parameters": {"type": "object"}}}]
                    while True:
                        body = json.dumps({"model": "fixture", "messages": messages, "tools": tools}).encode()
                        request = urllib.request.Request(endpoint, data=body, headers={"Content-Type": "application/json"})
                        response = json.loads(urllib.request.urlopen(request, timeout=10).read())
                        message = response["choices"][0]["message"]
                        messages.append(message)
                        calls = message.get("tool_calls", [])
                        if calls:
                            for call in calls:
                                messages.append({"role": "tool", "tool_call_id": call["id"], "content": "simulated tool output"})
                            continue
                        print(message.get("content", ""))
                        break
                    """
                ).strip()
                + "\n",
                encoding="utf-8",
            )
            process = subprocess.run(
                [
                    sys.executable,
                    str(SIMULATION),
                    "run",
                    "--scenario",
                    str(scenario),
                    "--opencode-bin",
                    str(fake),
                    "--project-dir",
                    str(root),
                    "--timeout",
                    "30",
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(0, process.returncode, process.stdout + process.stderr)
            payload = json.loads(process.stdout)
            self.assertEqual("SIMULATION_RUN_PASS", payload["status"])
            self.assertEqual(2, payload["model_call_count"])

    def test_run_fails_when_terminal_is_not_observed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            scenario = root / "scenario.json"
            scenario.write_text(
                json.dumps(
                    {
                        "name": "missing-terminal",
                        "request": "test",
                        "covers_commands": [],
                        "steps": [{"assistant_text": "NOT_THE_TERMINAL"}],
                        "terminal": "LOCAL_COMMITTED",
                    }
                ),
                encoding="utf-8",
            )
            fake = root / "fake-opencode.py"
            fake.write_text("print('NOT_THE_TERMINAL')\n", encoding="utf-8")
            process = subprocess.run(
                [
                    sys.executable,
                    str(SIMULATION),
                    "run",
                    "--scenario",
                    str(scenario),
                    "--opencode-bin",
                    str(fake),
                    "--project-dir",
                    str(root),
                ],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(0, process.returncode)
            self.assertIn("TERMINAL_MARKER_NOT_EMITTED", process.stdout + process.stderr)


if __name__ == "__main__":
    unittest.main()
