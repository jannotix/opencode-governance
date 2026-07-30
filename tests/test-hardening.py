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
    criteria = temp / "section-criteria.json"
    write_json(
        catalog,
        [
            {
                "schema": "SKILL_CAPABILITY_MANIFEST_V1",
                "skill_id": "section-skill",
                "version": "1",
                "content_sha256": "a" * 64,
                "source": "project",
                "trust_class": "PROJECT_AUTHORITATIVE",
                "triggers": ["review"],
                "supported_work_classes": ["MAJOR_FEATURE"],
                "languages": ["python"],
                "frameworks": [],
                "required_tools": [],
                "external_dependencies": [],
                "conflicts_with": [],
                "overlaps_with": [],
                "estimated_context_tokens": 100,
                "sections": [{"id": "available", "heading": "Available"}],
            }
        ],
    )
    write_json(
        criteria,
        {
            "triggers": ["review"],
            "languages": ["python"],
            "frameworks": [],
            "required_sections": ["missing"],
            "available_tools": [],
        },
    )
    selected = context(
        "select-skills",
        "--project-dir",
        project,
        "--task-id",
        "SECTION-1",
        "--catalog",
        catalog,
        "--input-json",
        criteria,
    )
    assert selected["selected"] == []
    assert selected["rejected"] == [
        {"skill_id": "section-skill", "reason": "REQUIRED_SECTION_UNAVAILABLE"}
    ]


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
        "MAJOR_FEATURE",
    )
    cycle = temp / "cycle.json"
    base = {
        "query": "entry points",
        "reason": "initial dispatch",
        "candidate_paths": ["src/a.py"],
        "admitted_paths": ["src/a.py"],
        "rejected_paths": [],
        "dependency_edges": [],
        "trust_boundaries": [],
        "tests": [],
        "context_gaps": [],
        "stop_reason": "REFINE",
    }
    write_json(cycle, base)
    context(
        "record-cycle",
        "--project-dir",
        project,
        "--task-id",
        "TERMINAL-1",
        "--cycle",
        "1",
        "--input-json",
        cycle,
    )
    invalid = context(
        "validate-task",
        "--project-dir",
        project,
        "--task-id",
        "TERMINAL-1",
    )
    assert invalid["valid"] is False
    assert "TERMINAL_STATE_REQUIRED" in invalid["errors"]

    write_json(cycle, {**base, "stop_reason": "CONTEXT_SUFFICIENT"})
    context(
        "record-cycle",
        "--project-dir",
        project,
        "--task-id",
        "TERMINAL-1",
        "--cycle",
        "2",
        "--input-json",
        cycle,
    )
    valid = context(
        "validate-task",
        "--project-dir",
        project,
        "--task-id",
        "TERMINAL-1",
    )
    assert valid["valid"] is True


def test_invalid_reinstall_preserves_current_routing(temp: pathlib.Path) -> None:
    config = temp / "routing-config"
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
    with tempfile.TemporaryDirectory(prefix="opencode-v341-hardening-") as directory:
        temp = pathlib.Path(directory)
        test_governance_state_symlink_is_rejected(temp)
        test_required_skill_section_must_exist(temp)
        test_context_validation_requires_terminal_state(temp)
        test_invalid_reinstall_preserves_current_routing(temp)
        test_reinstall_backup_contains_every_managed_tool(temp)
    print("PASS: repository hardening regressions")


if __name__ == "__main__":
    main()
