#!/usr/bin/env python3
"""Unified 3.7.0 backup and routing-preservation hardening regressions."""
from __future__ import annotations

import json
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
INSTALL = ROOT / "scripts" / "install.sh"
VALID_PROFILE = ROOT / "tests" / "fixtures" / "routing" / "reviewer-failover.valid.json"
MANAGED_TOOLS = (
    "architect-attempt.ps1", "architect-attempt.sh", "architect-headless-contract.py",
    "executor-attempt.ps1", "executor-attempt.sh",
    "context-intelligence.ps1", "context-intelligence.sh", "context-intelligence.py",
    "workflow-continuation.ps1", "workflow-continuation.py",
    "governance-authority.py", "governance-memory.py", "governance-evidence.py",
    "governance-simulation.py", "governance-pre-commit.py",
)


def invoke(*arguments: object) -> subprocess.CompletedProcess[str]:
    result = subprocess.run([str(value) for value in arguments], text=True, capture_output=True)
    if result.returncode:
        raise AssertionError(f"exit={result.returncode}\nstdout={result.stdout}\nstderr={result.stderr}")
    return result


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="opencode-unified-release-") as directory:
        config = pathlib.Path(directory) / "config"
        invoke(INSTALL, "--config-dir", config, "--routing-config", VALID_PROFILE)
        manifest_path = config / "opencode-governance-routing.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        assert manifest["governance_version"] == "3.7.5"
        assert len(manifest["managed_tools"]) == 15
        assert not (config / "opencode-governance-runtime.json").exists()
        before_settings = manifest["settings"]
        before_roles = manifest["roles"]
        tools = config / "opencode-governance-tools"
        for name in MANAGED_TOOLS:
            (tools / name).write_text(f"sentinel:{name}\n", encoding="utf-8")
        invoke(INSTALL, "--config-dir", config, "--routing-config", VALID_PROFILE)
        latest = sorted((config / "backups").glob("opencode-governance-*"))[-1]
        for name in MANAGED_TOOLS:
            path = latest / name
            assert path.is_file(), f"missing canonical backup: {name}"
            assert path.read_text(encoding="utf-8") == f"sentinel:{name}\n"
        after = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        assert after["settings"] == before_settings
        assert after["roles"] == before_roles
    print("PASS: unified 3.7.0 backup and routing preservation")


if __name__ == "__main__":
    main()
