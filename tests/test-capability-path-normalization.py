#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
INSTALL = ROOT / "scripts" / "install.sh"
CAPABILITIES = ROOT / "scripts" / "governance-capabilities.py"
PROFILE = ROOT / "tests" / "fixtures" / "routing" / "architect-failover.valid.json"


def run(*args: object) -> subprocess.CompletedProcess[str]:
    result = subprocess.run([str(arg) for arg in args], text=True, capture_output=True)
    if result.returncode != 0:
        raise AssertionError(f"stdout={result.stdout}\nstderr={result.stderr}")
    return result


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="opencode-capability-paths-") as directory:
        config = pathlib.Path(directory) / "config"
        run(INSTALL, "--config-dir", config, "--routing-config", PROFILE)
        manifest_path = config / "opencode-governance-routing.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        tools = config / "opencode-governance-tools"
        manifest["governance_version"] = "3.4.4"
        manifest["architect_runner_version"] = "3.4.4"
        manifest["context_intelligence_version"] = "3.4.4"
        manifest["workflow_continuation_version"] = "3.4.4"
        manifest["managed_tools"] = [
            str(tools / ".." / "opencode-governance-tools" / pathlib.Path(value).name)
            for value in manifest["managed_tools"][:9]
        ]
        for field in list(manifest):
            if field.startswith("capability_") or field in {
                "candidate_authority_version",
                "governed_memory_version",
                "evidence_reuse_version",
                "simulation_harness_version",
                "pre_commit_receipt_gate_version",
                "actionable_continuation_version",
                "memory_store",
                "capabilities_installed_at",
            }:
                manifest.pop(field, None)
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        for name in (
            "governance-authority.py",
            "governance-memory.py",
            "governance-evidence.py",
            "governance-simulation.py",
            "governance-pre-commit.py",
        ):
            (tools / name).unlink(missing_ok=True)
        run(sys.executable, CAPABILITIES, "install", "--source-dir", ROOT / "scripts", "--config-dir", config)
        final = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        assert final["governance_version"] == "3.7.2"
    print("PASS: equivalent managed-tool paths are normalized before comparison")


if __name__ == "__main__":
    main()
