#!/usr/bin/env python3
"""Regression for the shipped simulation fixture shape."""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "governance-simulation.py"
FIXTURE = ROOT / "tests" / "fixtures" / "governance-simulation-all-commands.json"

process = subprocess.run(
    [sys.executable, str(SCRIPT), "validate", "--scenario", str(FIXTURE)],
    text=True,
    capture_output=True,
)
assert process.returncode == 0, process.stdout + process.stderr
payload = json.loads(process.stdout)
assert payload["status"] == "SIMULATION_SCENARIO_VALID"
assert payload["covered_command_count"] >= 1
assert payload["terminal"] == "LOCAL_COMMITTED"
print("PASS: shipped simulation fixture validates")
