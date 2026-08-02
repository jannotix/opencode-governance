#!/usr/bin/env python3
"""ALL_COMMANDS_SIMULATION_CONTRACT_V1 — honest twelve-command coverage."""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "governance-simulation.py"
MANIFEST = ROOT / "tests" / "fixtures" / "simulation" / "all-commands-manifest.json"
REQUIRED = {
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


def main() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert manifest.get("schema") == "ALL_COMMANDS_SIMULATION_CONTRACT_V1"
    assert set(manifest["required_commands"]) == REQUIRED
    covered = set()
    for scenario in manifest["scenarios"]:
        fixture = ROOT / scenario["fixture"]
        assert fixture.is_file(), fixture
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), "validate", "--scenario", str(fixture)],
            text=True,
            capture_output=True,
        )
        assert proc.returncode == 0, fixture.name + proc.stdout + proc.stderr
        body = json.loads(fixture.read_text(encoding="utf-8"))
        cmds = body.get("covers_commands") or []
        assert len(cmds) == 1
        covered.add(cmds[0])
        assert body.get("forbids_external_action") is True
        assert body.get("terminal")
    assert covered == REQUIRED, sorted(REQUIRED - covered)
    # Partial fixture must not claim complete coverage
    partial = ROOT / "tests" / "fixtures" / "governance-simulation-all-commands.json"
    pbody = json.loads(partial.read_text(encoding="utf-8"))
    assert pbody.get("coverage_claim") == "PROTOCOL_ONLY_PARTIAL"
    print("PASS: twelve-command simulation suite complete")


if __name__ == "__main__":
    main()
