#!/usr/bin/env python3
"""Install, verify or remove the OpenCode Governance 3.6 runtime overlay."""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import pathlib
import re
import shutil
import stat
import sys
from typing import Any

VERSION = "3.6.0"
SCHEMA = "opencode-governance.runtime-overlay/v1"
TOOL_NAMES = (
    "governance-authority.py",
    "governance-memory.py",
    "governance-evidence.py",
    "governance-simulation.py",
    "governance-pre-commit.py",
)
AGENT_NAMES = (
    "architect",
    "build",
    "plan",
    "executor",
    "reviewer",
    "reviewer-architecture",
    "final-reviewer",
)
COMMAND_NAMES = (
    "ai-review",
    "ai-workflow",
    "ai-resume",
    "ai-release",
    "ai-status",
    "ai-metrics",
)


def fail(code: str, detail: str = "") -> None:
    payload = {"status": "ERROR", "code": code}
    if detail:
        payload["detail"] = detail
    print(json.dumps(payload, sort_keys=True), file=sys.stderr)
    raise SystemExit(2)


def hash_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256(path: pathlib.Path) -> str:
    return hash_bytes(path.read_bytes())


def write_json(path: pathlib.Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def section_pattern(heading: str) -> re.Pattern[str]:
    return re.compile(rf"\n## {re.escape(heading)}\n.*?(?=\n## |\Z)", re.S)


def insert_section(text: str, heading: str, body: str, before_core: bool = False) -> str:
    text = section_pattern(heading).sub("", text)
    section = f"\n\n## {heading}\n\n{body.strip()}\n"
    if before_core and "\n## Core invariants" in text:
        return text.replace("\n## Core invariants", section + "\n## Core invariants", 1)
    return text.rstrip() + section


def extract_section(text: str, heading: str) -> str:
    matches = section_pattern(heading).findall(text)
    if len(matches) != 1:
        fail("RUNTIME_SECTION_COUNT_INVALID", f"{heading}:{len(matches)}")
    return matches[0].lstrip("\n")


def remove_section(text: str, heading: str) -> str:
    return section_pattern(heading).sub("", text).rstrip() + "\n"


def paths(config: pathlib.Path) -> dict[str, pathlib.Path]:
    tools = config / "opencode-governance-tools"
    return {
        "tools": tools,
        "manifest": config / "opencode-governance-runtime.json",
        "memory": config / "opencode-governance-memory" / "memory.db",
    }


def policy_blocks(tool_paths: dict[str, pathlib.Path], memory_store: pathlib.Path) -> dict[str, str]:
    authority = tool_paths["authority"]
    memory = tool_paths["memory"]
    evidence = tool_paths["evidence"]
    simulation = tool_paths["simulation"]
    pre_commit = tool_paths["pre_commit"]
    return {
        "authority": f"""
GOVERNANCE_AUTHORITY_VERSION: 1
CANDIDATE_PROJECTIONS: WORKSPACE|STAGED|COMMIT|BASE_DIFF
AUTHORITY_TOOL: {authority}

Freeze the exact candidate before review. Approval must be represented by `GOVERNANCE_APPROVAL_RECEIPT_V1`, binding candidate identity, approved requirements, execution packet, verification profile, evidence manifest, both independent reviews, Final Reviewer adjudication and actual model families. A receipt validates only against the identical live projection. `APPROVAL_RECEIPT_MISMATCH` invalidates delivery. Never treat a previous receipt as fresh after a dependency changes.
""",
        "memory": f"""
GOVERNED_ENGINEERING_MEMORY_VERSION: 2
MEMORY_TOOL: {memory}
MEMORY_DB: {memory_store}

Memory is advisory and never outranks current requirements or primary repository evidence. Executor and reviewers may propose a `CANDIDATE`; only an exact `MEMORY_DECISION: APPROVE` from Final Reviewer with candidate and evidence bindings permits activation. Retrieve progressively: compact topic index first, full lesson only when admitted by Context Intelligence. Superseded, contradicted, stale, rejected or quarantined memories are not active guidance. Policy promotion requires recurring validated occurrences and explicit owner authorization.
""",
        "evidence": f"""
EVIDENCE_REUSE_LEDGER_VERSION: 1
EVIDENCE_REUSE_TOOL: {evidence}

Reuse evidence only when its outcome is `PASS` and every declared dependency hash is identical, including candidate bytes, affected call-path or contract fingerprints, validation command, toolchain/environment identity, selected policy and skill sources. A per-file hash or historical model approval alone is insufficient. Any dependency delta returns `EVIDENCE_STALE` and invalidates dependent reviews.
""",
        "simulation": f"""
GOVERNANCE_SIMULATION_HARNESS_VERSION: 1
SIMULATION_TOOL: {simulation}

The simulation runner can drive a real OpenCode process against a loopback OpenAI-compatible scripted model while keeping the shipped prompts, Git repository and governance tools real. Scenarios must cover all twelve `/ai-*` contracts and reject automatic push, merge, deployment, publication and production rollback. Simulation proves deterministic orchestration behavior, not live-model quality, and supplements rather than replaces repository-native verification.
""",
        "pre_commit": f"""
PRE_COMMIT_RECEIPT_GATE_VERSION: 1
PRE_COMMIT_TOOL: {pre_commit}

A project may install and arm the staged receipt gate after `/ai-review` or `/ai-workflow` approves the exact Git index. The hook performs no model call: it revalidates the content-bound staged receipt and blocks commit on index drift, missing authority or stale approval. Installing the runtime does not silently modify project Git hooks; hook installation and removal are explicit project-scoped owner actions.
""",
        "continuation": f"""
ACTIONABLE_CONTINUATION_CONTRACT_VERSION: 1
AUTHORITY_TOOL: {authority}

Every non-terminal `RUN_STATE.json` must contain a typed `next_action`. An executable action names one real `/ai-*` command, exact argument tokens and an expected postcondition. A human-decision action names the required decision and concrete choices. Narrative instructions such as “retry”, “continue” or “fix it” are not executable recovery and fail closed with `NON_EXECUTABLE_CONTINUATION`.
""",
        "lenses": f"""
REVIEW_LENS_MATRIX_VERSION: 1
AUTHORITY_TOOL: {authority}

Derive focused review lenses from `TASK_RISK_PROFILE` and current primary evidence. Implementation review always retains correctness, regression, test quality and maintainability. Architecture/Security review always retains architecture, security boundaries, data safety and recovery. Add authorization, public-contract, migration, dependency supply-chain, performance, accessibility, deployment, observability and other lenses only when applicable. Lens selection changes focus; it never removes either independent reviewer or Final Reviewer adjudication.
""",
    }


def validate_base(config: pathlib.Path) -> None:
    for name in AGENT_NAMES:
        if not (config / "agents" / f"{name}.md").is_file():
            fail("BASE_AGENT_MISSING", name)
    for name in COMMAND_NAMES:
        if not (config / "commands" / f"{name}.md").is_file():
            fail("BASE_COMMAND_MISSING", name)


def backup(config: pathlib.Path, affected: list[pathlib.Path]) -> pathlib.Path:
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    destination = config / "backups" / f"opencode-governance-runtime-{stamp}"
    destination.mkdir(parents=True, exist_ok=False)
    for path in affected:
        if path.is_file():
            relative = path.relative_to(config)
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    return destination


def restore_backup(
    config: pathlib.Path,
    backup_dir: pathlib.Path,
    affected: list[pathlib.Path],
    existed: dict[pathlib.Path, bool],
) -> None:
    for path in affected:
        source = backup_dir / path.relative_to(config)
        if existed[path]:
            if not source.is_file():
                fail("RUNTIME_ROLLBACK_BACKUP_MISSING", str(source))
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, path)
        else:
            path.unlink(missing_ok=True)


def section_key(path: pathlib.Path, config: pathlib.Path, heading: str) -> str:
    return f"{path.relative_to(config).as_posix()}#{heading}"


def install(source: pathlib.Path, config: pathlib.Path) -> None:
    validate_base(config)
    resolved = paths(config)
    resolved["tools"].mkdir(parents=True, exist_ok=True)
    source_tools = [source / name for name in TOOL_NAMES]
    for item in source_tools:
        if not item.is_file():
            fail("RUNTIME_SOURCE_MISSING", str(item))
    agent_paths = [config / "agents" / f"{name}.md" for name in AGENT_NAMES]
    command_paths = [config / "commands" / f"{name}.md" for name in COMMAND_NAMES]
    destination_tools = [resolved["tools"] / name for name in TOOL_NAMES]
    affected = [*destination_tools, *agent_paths, *command_paths, resolved["manifest"]]
    existed = {path: path.is_file() for path in affected}
    backup_dir = backup(config, affected)
    try:
        for source_tool, destination in zip(source_tools, destination_tools):
            shutil.copy2(source_tool, destination)
            destination.chmod(destination.stat().st_mode | stat.S_IXUSR)

        tools = {
            "authority": destination_tools[0],
            "memory": destination_tools[1],
            "evidence": destination_tools[2],
            "simulation": destination_tools[3],
            "pre_commit": destination_tools[4],
        }
        blocks = policy_blocks(tools, resolved["memory"])
        section_hashes: dict[str, str] = {}
        for name in AGENT_NAMES:
            path = config / "agents" / f"{name}.md"
            text = path.read_text(encoding="utf-8")
            headings = [
                ("GOVERNANCE_AUTHORITY_V1", blocks["authority"]),
                ("GOVERNED_ENGINEERING_MEMORY_V2", blocks["memory"]),
                ("EVIDENCE_REUSE_LEDGER_V1", blocks["evidence"]),
                ("PRE_COMMIT_RECEIPT_GATE_V1", blocks["pre_commit"]),
            ]
            if name in {"reviewer", "reviewer-architecture", "final-reviewer"}:
                headings.append(("REVIEW_LENS_MATRIX_V1", blocks["lenses"]))
            if name == "final-reviewer":
                headings.append(
                    (
                        "MEMORY_ADJUDICATION_AUTHORITY_V1",
                        "Only this role may approve or reject a memory candidate. Approval must identify the exact validated lesson, candidate hash, evidence hash, staleness conditions and scope. Reviewer agreement is not memory authority.",
                    )
                )
            for heading, body in headings:
                text = insert_section(
                    text,
                    heading,
                    body,
                    before_core=name in {"architect", "build", "plan"},
                )
            path.write_text(text, encoding="utf-8")
            for heading, _body in headings:
                section_hashes[section_key(path, config, heading)] = hash_bytes(
                    extract_section(text, heading).encode("utf-8")
                )

        command_sections = {
            "ai-review": (
                "GOVERNANCE_AUTHORITY_ENTRY_V1",
                blocks["authority"] + "\n" + blocks["lenses"] + "\n" + blocks["pre_commit"],
            ),
            "ai-workflow": (
                "GOVERNANCE_RUNTIME_ENTRY_V1",
                blocks["authority"]
                + "\n"
                + blocks["continuation"]
                + "\n"
                + blocks["memory"]
                + "\n"
                + blocks["evidence"]
                + "\n"
                + blocks["pre_commit"],
            ),
            "ai-resume": (
                "GOVERNANCE_RUNTIME_ENTRY_V1",
                blocks["authority"]
                + "\n"
                + blocks["continuation"]
                + "\n"
                + blocks["memory"]
                + "\n"
                + blocks["evidence"],
            ),
            "ai-release": (
                "GOVERNANCE_RELEASE_RECEIPT_GATE_V1",
                blocks["authority"]
                + "\nValidate the same content-bound receipt at the release candidate projection; release assessment never fabricates or silently renews approval.",
            ),
            "ai-status": (
                "GOVERNANCE_RUNTIME_STATUS_V1",
                "Report active candidate projection, receipt validity, actionable continuation, pre-commit gate state, memory candidates/review-due state and evidence reuse/staleness without exposing source contents or secrets.",
            ),
            "ai-metrics": (
                "GOVERNANCE_RUNTIME_METRICS_V1",
                "Report receipt validations, projection mismatches, pre-commit gate outcomes, selected review lenses, memory admissions/rejections, evidence reuse hits/stale misses and simulation results when recorded. Do not fabricate unavailable token or cost data.",
            ),
        }
        for name, (heading, body) in command_sections.items():
            path = config / "commands" / f"{name}.md"
            text = insert_section(path.read_text(encoding="utf-8"), heading, body)
            path.write_text(text, encoding="utf-8")
            section_hashes[section_key(path, config, heading)] = hash_bytes(
                extract_section(text, heading).encode("utf-8")
            )

        manifest = {
            "schema": SCHEMA,
            "governance_version": VERSION,
            "base_governance_version": "3.4.4",
            "candidate_authority_version": "1.0",
            "governed_memory_version": "2.0",
            "evidence_reuse_version": "1.0",
            "simulation_harness_version": "1.0",
            "pre_commit_receipt_gate_version": "1.0",
            "actionable_continuation_version": "1.0",
            "managed_tools": [str(path) for path in destination_tools],
            "tool_hashes": {path.name: sha256(path) for path in destination_tools},
            "section_hashes": section_hashes,
            "memory_store": str(resolved["memory"]),
            "backup_dir": str(backup_dir),
            "installed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        }
        write_json(resolved["manifest"], manifest)
        verify(config, emit=False)
    except BaseException:
        restore_backup(config, backup_dir, affected, existed)
        raise
    print(
        json.dumps(
            {
                "status": "GOVERNANCE_RUNTIME_INSTALLED",
                "version": VERSION,
                "backup_dir": str(backup_dir),
            },
            sort_keys=True,
        )
    )


def verify(config: pathlib.Path, emit: bool = True) -> dict[str, Any]:
    resolved = paths(config)
    if not resolved["manifest"].is_file():
        fail("RUNTIME_MANIFEST_MISSING")
    try:
        manifest = json.loads(resolved["manifest"].read_text(encoding="utf-8-sig"))
    except Exception as exc:
        fail("RUNTIME_MANIFEST_INVALID", str(exc))
    if manifest.get("schema") != SCHEMA or manifest.get("governance_version") != VERSION:
        fail("RUNTIME_MANIFEST_VERSION_MISMATCH")
    expected = [resolved["tools"] / name for name in TOOL_NAMES]
    if manifest.get("managed_tools") != [str(path) for path in expected]:
        fail("UNSAFE_RUNTIME_TOOL_SET")
    for path in expected:
        if not path.is_file() or manifest.get("tool_hashes", {}).get(path.name) != sha256(path):
            fail("RUNTIME_TOOL_INTEGRITY_FAILURE", path.name)
    section_hashes = manifest.get("section_hashes")
    if not isinstance(section_hashes, dict) or not section_hashes:
        fail("RUNTIME_SECTION_HASHES_MISSING")
    for key, expected_hash in section_hashes.items():
        if not isinstance(key, str) or "#" not in key or not isinstance(expected_hash, str):
            fail("RUNTIME_SECTION_MANIFEST_INVALID", str(key))
        relative, heading = key.rsplit("#", 1)
        path = config / pathlib.PurePosixPath(relative)
        if not path.is_file():
            fail("RUNTIME_SECTION_FILE_MISSING", relative)
        actual = hash_bytes(extract_section(path.read_text(encoding="utf-8"), heading).encode("utf-8"))
        if actual != expected_hash:
            fail("RUNTIME_SECTION_INTEGRITY_FAILURE", key)
    result = {"status": "GOVERNANCE_RUNTIME_VERIFIED", "version": VERSION}
    if emit:
        print(json.dumps(result, sort_keys=True))
    return result


def uninstall(config: pathlib.Path) -> None:
    verify(config, emit=False)
    resolved = paths(config)
    manifest = json.loads(resolved["manifest"].read_text(encoding="utf-8-sig"))
    expected = [resolved["tools"] / name for name in TOOL_NAMES]
    affected = [
        *expected,
        *[config / "agents" / f"{name}.md" for name in AGENT_NAMES],
        *[config / "commands" / f"{name}.md" for name in COMMAND_NAMES],
        resolved["manifest"],
    ]
    backup_dir = backup(config, affected)
    sections_by_file: dict[pathlib.Path, list[str]] = {}
    for key in manifest["section_hashes"]:
        relative, heading = key.rsplit("#", 1)
        sections_by_file.setdefault(config / pathlib.PurePosixPath(relative), []).append(heading)
    for path, headings in sections_by_file.items():
        text = path.read_text(encoding="utf-8")
        for heading in headings:
            text = remove_section(text, heading)
        path.write_text(text, encoding="utf-8")
    for path in expected:
        path.unlink(missing_ok=True)
    resolved["manifest"].unlink()
    print(
        json.dumps(
            {
                "status": "GOVERNANCE_RUNTIME_REMOVED",
                "backup_dir": str(backup_dir),
                "project_pre_commit_note": "Remove any project-scoped gate with governance-pre-commit.py uninstall before deleting the runtime.",
            },
            sort_keys=True,
        )
    )


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(prog="governance-runtime-install")
    value.add_argument("action", choices=("install", "verify", "uninstall"))
    value.add_argument("--config-dir", required=True)
    value.add_argument("--source-dir", default=str(pathlib.Path(__file__).resolve().parent))
    return value


def main() -> None:
    args = parser().parse_args()
    config = pathlib.Path(args.config_dir).expanduser().resolve()
    source = pathlib.Path(args.source_dir).expanduser().resolve()
    if args.action == "install":
        install(source, config)
    elif args.action == "verify":
        verify(config)
    else:
        uninstall(config)


if __name__ == "__main__":
    main()
