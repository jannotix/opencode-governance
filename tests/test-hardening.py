#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTEXT = ROOT / "scripts" / "context-intelligence.py"
INSTALL = ROOT / "scripts" / "install.sh"
VALID_PROFILE = ROOT / "tests" / "fixtures" / "routing" / "reviewer-failover.valid.json"
INVALID_PROFILE = ROOT / "tests" / "fixtures" / "routing" / "unresolved-variant.invalid.json"
MANAGED_TOOLS = [
    "architect-attempt.ps1",
    "architect-attempt.sh",
    "executor-attempt.ps1",
    "executor-attempt.sh",
    "context-intelligence.ps1",
    "context-intelligence.sh",
    "context-intelligence.py",
    "workflow-continuation.ps1",
    "workflow-continuation.py",
    "governance-authority.py",
    "governance-memory.py",
    "governance-evidence.py",
    "governance-simulation.py",
    "governance-pre-commit.py",
]


def invoke(*args: object, expect: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run([str(arg) for arg in args], text=True, capture_output=True)
    if result.returncode != expect:
        raise AssertionError(
            f"exit {result.returncode} != {expect}\nstdout={result.stdout}\nstderr={result.stderr}"
        )
    return result


def context(*args: object, expect: int = 0) -> dict:
    result = invoke(sys.executable, CONTEXT, *args, expect=expect)
    return json.loads(result.stdout) if result.stdout.strip() else {}


def write_json(path: pathlib.Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2), encoding="utf-8")


def test_governance_state_symlink_is_rejected(temp: pathlib.Path) -> None:
    project = temp / "symlink-project"
    outside = temp / "outside-governance-state"
    (project / ".ai").mkdir(parents=True)
    outside.mkdir()
    os.symlink(outside, project / ".ai" / "tasks", target_is_directory=True)

    result = invoke(
        sys.executable,
        CONTEXT,
        "initialize-budget",
        "--project-dir",
        project,
        "--task-id",
        "SAFE-1",
        "--work-class",
        "PATCH",
        expect=2,
    )
    assert "GOVERNANCE_STATE_LINK_FORBIDDEN" in result.stderr
    assert list(outside.iterdir()) == []


def test_required_skill_section_must_exist(temp: pathlib.Path) -> None:
    project = temp / "section-project"
    project.mkdir()
    context(
        "initialize-budget",
        "--project-dir",
        project,
        "--task-id",
        "SECTION-1",
        "--work-class",
        "MAJOR_FEATURE",
    )
    catalog = temp / "section-catalog.json"
    write_json(
        catalog,
        {
            "schema": "SKILL_CAPABILITY_MANIFEST_V1",
            "skills": [
                {
                    "id": "trusted-skill",
                    "source": "OFFICIAL_PROJECT",
                    "path": str(ROOT / "tests" / "fixtures" / "context-intelligence" / "skills" / "trusted.md"),
                    "work_classes": ["MAJOR_FEATURE"],
                    "technologies": [],
                    "capabilities": ["security"],
                    "conflicts": [],
                    "sections": ["Security", "Missing"],
                    "estimated_tokens": 200,
                }
            ],
        },
    )
    result = invoke(
        sys.executable,
        CONTEXT,
        "select-skills",
        "--project-dir",
        project,
        "--task-id",
        "SECTION-1",
        "--catalog",
        catalog,
        "--work-class",
        "MAJOR_FEATURE",
        "--capability",
        "security",
        expect=2,
    )
    assert "REQUIRED_SECTION_UNAVAILABLE" in result.stderr


def test_context_validation_requires_terminal_state(temp: pathlib.Path) -> None:
    project = temp / "terminal-project"
    project.mkdir()
    context(
        "initialize-budget",
        "--project-dir",
        project,
        "--task-id",
        "TERMINAL-1",
        "--work-class",
        "PATCH",
    )
    result = invoke(
        sys.executable,
        CONTEXT,
        "validate",
        "--project-dir",
        project,
        "--task-id",
        "TERMINAL-1",
        expect=2,
    )
    assert "TERMINAL_STATE_REQUIRED" in result.stderr


def test_invalid_reinstall_preserves_current_routing(temp: pathlib.Path) -> None:
    config = temp / "rollback-config"
    invoke(INSTALL, "--config-dir", config, "--routing-config", VALID_PROFILE)
    manifest = config / "opencode-governance-routing.json"
    before_manifest = manifest.read_bytes()
    aliases = sorted((config / "agents").glob("*-fallback-*.md"))
    before_aliases = {path.name: path.read_bytes() for path in aliases}
    assert before_aliases

    failed = subprocess.run(
        [str(INSTALL), "--config-dir", str(config), "--routing-config", str(INVALID_PROFILE)],
        text=True,
        capture_output=True,
    )
    assert failed.returncode != 0
    assert manifest.read_bytes() == before_manifest
    for name, content in before_aliases.items():
        assert (config / "agents" / name).read_bytes() == content


def test_reinstall_backup_contains_every_managed_tool(temp: pathlib.Path) -> None:
    config = temp / "backup-config"
    invoke(INSTALL, "--config-dir", config, "--routing-config", VALID_PROFILE)
    tools = config / "opencode-governance-tools"
    for name in MANAGED_TOOLS:
        (tools / name).write_text(f"sentinel:{name}\n", encoding="utf-8")

    invoke(INSTALL, "--config-dir", config, "--routing-config", VALID_PROFILE)
    backups = sorted((config / "backups").glob("opencode-governance-*"))
    assert backups
    latest = backups[-1]
    for name in MANAGED_TOOLS:
        backup = latest / name
        assert backup.is_file(), f"missing managed-tool backup: {name}"
        assert backup.read_text(encoding="utf-8") == f"sentinel:{name}\n"


def main() -> None:
    if os.name == "nt":
        raise SystemExit("This test is intended for the Unix CI job.")
    with tempfile.TemporaryDirectory(prefix="opencode-v360-hardening-") as directory:
        temp = pathlib.Path(directory)
        test_governance_state_symlink_is_rejected(temp)
        test_required_skill_section_must_exist(temp)
        test_context_validation_requires_terminal_state(temp)
        test_invalid_reinstall_preserves_current_routing(temp)
        test_reinstall_backup_contains_every_managed_tool(temp)
    print("PASS: repository hardening regressions")


if __name__ == "__main__":
    main()
