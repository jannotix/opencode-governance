#!/usr/bin/env python3
"""Install, verify or remove OpenCode Governance capability tools."""
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

VERSION = "3.7.3"
BASE_VERSION = "3.4.4"
CAPABILITY_TOOL_NAMES = (
    "governance-authority.py",
    "governance-memory.py",
    "governance-evidence.py",
    "governance-simulation.py",
    "governance-pre-commit.py",
)
BASE_TOOL_NAMES = (
    "architect-attempt.ps1",
    "architect-attempt.sh",
    "architect-headless-contract.py",
    "executor-attempt.ps1",
    "executor-attempt.sh",
    "context-intelligence.ps1",
    "context-intelligence.sh",
    "context-intelligence.py",
    "workflow-continuation.ps1",
    "workflow-continuation.py",
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
)
CAPABILITY_FIELDS = (
    "candidate_authority_version",
    "governed_memory_version",
    "evidence_reuse_version",
    "simulation_harness_version",
    "pre_commit_receipt_gate_version",
    "actionable_continuation_version",
    "capability_tool_hashes",
    "capability_section_hashes",
    "memory_store",
    "capabilities_installed_at",
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


def read_json(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        fail("ROUTING_MANIFEST_INVALID", f"{path}: {exc}")
    if not isinstance(value, dict):
        fail("ROUTING_MANIFEST_INVALID", str(path))
    return value


def write_json(path: pathlib.Path, value: dict[str, Any]) -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
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
        fail("CAPABILITY_SECTION_COUNT_INVALID", f"{heading}:{len(matches)}")
    return matches[0].lstrip("\n")


def remove_section(text: str, heading: str) -> str:
    return section_pattern(heading).sub("", text).rstrip() + "\n"


def config_paths(config: pathlib.Path) -> dict[str, pathlib.Path]:
    return {
        "tools": config / "opencode-governance-tools",
        "manifest": config / "opencode-governance-routing.json",
        "legacy_manifest": config / "opencode-governance-runtime.json",
        "memory": config / "opencode-governance-memory" / "memory.db",
    }


def base_tools(config: pathlib.Path) -> list[pathlib.Path]:
    tools = config_paths(config)["tools"]
    return [tools / name for name in BASE_TOOL_NAMES]


def capability_tools(config: pathlib.Path) -> list[pathlib.Path]:
    tools = config_paths(config)["tools"]
    return [tools / name for name in CAPABILITY_TOOL_NAMES]


def expected_tools(config: pathlib.Path) -> list[pathlib.Path]:
    return [*base_tools(config), *capability_tools(config)]


def section_key(path: pathlib.Path, config: pathlib.Path, heading: str) -> str:
    return f"{path.relative_to(config).as_posix()}#{heading}"


def backup(config: pathlib.Path, affected: list[pathlib.Path]) -> tuple[pathlib.Path, dict[pathlib.Path, bool]]:
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    destination = config / "backups" / f"opencode-governance-{VERSION}-{stamp}"
    destination.mkdir(parents=True, exist_ok=False)
    existed = {path: path.is_file() for path in affected}
    for path in affected:
        if not path.is_file():
            continue
        target = destination / path.relative_to(config)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    return destination, existed


def restore(config: pathlib.Path, backup_dir: pathlib.Path, affected: list[pathlib.Path], existed: dict[pathlib.Path, bool]) -> None:
    for path in affected:
        source = backup_dir / path.relative_to(config)
        if existed[path]:
            if not source.is_file():
                fail("CAPABILITY_ROLLBACK_BACKUP_MISSING", str(source))
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, path)
        else:
            path.unlink(missing_ok=True)


def validate_rendered_base(config: pathlib.Path) -> dict[str, Any]:
    resolved = config_paths(config)
    for name in AGENT_NAMES:
        if not (config / "agents" / f"{name}.md").is_file():
            fail("BASE_AGENT_MISSING", name)
    for name in COMMAND_NAMES:
        if not (config / "commands" / f"{name}.md").is_file():
            fail("BASE_COMMAND_MISSING", name)
    if not resolved["manifest"].is_file():
        fail("ROUTING_MANIFEST_MISSING")
    manifest = read_json(resolved["manifest"])
    if manifest.get("schema_version") != "1.0":
        fail("ROUTING_SCHEMA_VERSION_INVALID")
    version = manifest.get("governance_version")
    if version not in {BASE_VERSION, VERSION}:
        fail("CAPABILITY_UPGRADE_SOURCE_UNSUPPORTED", str(version))
    expected = base_tools(config) if version == BASE_VERSION else expected_tools(config)
    if manifest.get("managed_tools") != [str(path) for path in expected]:
        fail("UNSAFE_MANAGED_TOOL_SET", str(version))
    for path in base_tools(config):
        if not path.is_file():
            fail("BASE_MANAGED_TOOL_MISSING", path.name)
    return manifest


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

Freeze the exact candidate before review. Approval must be represented by schema `opencode-governance.approval-receipt/v1` (alias `GOVERNANCE_APPROVAL_RECEIPT_V1`), binding candidate identity, approved requirements, execution packet, verification profile, evidence manifest, both independent reviews, Final Reviewer adjudication and actual model families. A receipt validates only against the identical live projection. `APPROVAL_RECEIPT_MISMATCH` invalidates delivery. Never treat a previous receipt as fresh after a dependency changes.
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

The optional simulation harness can drive a real OpenCode process against a loopback OpenAI-compatible scripted model while keeping shipped prompts, Git state and governance tools real. It is a deterministic orchestration fixture, not live-model quality coverage, and never replaces repository-native verification.
""",
        "pre_commit": f"""
PRE_COMMIT_RECEIPT_GATE_VERSION: 1
PRE_COMMIT_TOOL: {pre_commit}

A project may install and arm the staged receipt gate after `/ai-review` or `/ai-workflow` approves the exact Git index. The hook performs no model call: it revalidates the content-bound staged receipt and blocks commit on index drift, missing authority or stale approval. Governance installation does not silently modify project Git hooks; hook installation and removal are explicit project-scoped owner actions.
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


def projected_sections(config: pathlib.Path, blocks: dict[str, str]) -> dict[pathlib.Path, list[tuple[str, str, bool]]]:
    result: dict[pathlib.Path, list[tuple[str, str, bool]]] = {}
    for name in AGENT_NAMES:
        entries: list[tuple[str, str, bool]] = [
            ("GOVERNANCE_AUTHORITY_V1", blocks["authority"], name in {"architect", "build", "plan"}),
            ("GOVERNED_ENGINEERING_MEMORY_V2", blocks["memory"], name in {"architect", "build", "plan"}),
            ("EVIDENCE_REUSE_LEDGER_V1", blocks["evidence"], name in {"architect", "build", "plan"}),
            ("PRE_COMMIT_RECEIPT_GATE_V1", blocks["pre_commit"], name in {"architect", "build", "plan"}),
        ]
        if name in {"reviewer", "reviewer-architecture", "final-reviewer"}:
            entries.append(("REVIEW_LENS_MATRIX_V1", blocks["lenses"], False))
        if name == "final-reviewer":
            entries.append((
                "MEMORY_ADJUDICATION_AUTHORITY_V1",
                "Only this role may approve or reject a memory candidate. Approval must identify the exact validated lesson, candidate hash, evidence hash, staleness conditions and scope. Reviewer agreement is not memory authority.",
                False,
            ))
        result[config / "agents" / f"{name}.md"] = entries
    command_entries = {
        "ai-review": (
            "GOVERNANCE_AUTHORITY_ENTRY_V1",
            blocks["authority"] + "\n" + blocks["lenses"] + "\n" + blocks["pre_commit"],
        ),
        "ai-workflow": (
            "GOVERNANCE_CAPABILITIES_ENTRY_V1",
            blocks["authority"] + "\n" + blocks["continuation"] + "\n" + blocks["memory"] + "\n" + blocks["evidence"] + "\n" + blocks["pre_commit"],
        ),
        "ai-resume": (
            "GOVERNANCE_CAPABILITIES_ENTRY_V1",
            blocks["authority"] + "\n" + blocks["continuation"] + "\n" + blocks["memory"] + "\n" + blocks["evidence"],
        ),
        "ai-release": (
            "GOVERNANCE_RELEASE_RECEIPT_GATE_V1",
            blocks["authority"] + "\nValidate the same content-bound receipt at the release candidate projection; release assessment never fabricates or silently renews approval.",
        ),
        "ai-status": (
            "GOVERNANCE_CAPABILITIES_STATUS_V1",
            "Report active candidate projection, receipt validity, actionable continuation, pre-commit gate state, memory candidates/review-due state and evidence reuse/staleness without exposing source contents or secrets.",
        ),
        "ai-metrics": (
            "GOVERNANCE_CAPABILITIES_METRICS_V1",
            "Report receipt validations, projection mismatches, pre-commit gate outcomes, selected review lenses, memory admissions/rejections, evidence reuse hits/stale misses and simulation results when recorded. Do not fabricate unavailable token or cost data.",
        ),
    }
    for name, (heading, body) in command_entries.items():
        result[config / "commands" / f"{name}.md"] = [(heading, body, False)]
    return result


def install(source: pathlib.Path, config: pathlib.Path) -> None:
    manifest = validate_rendered_base(config)
    resolved = config_paths(config)
    resolved["tools"].mkdir(parents=True, exist_ok=True)
    source_tools = [source / name for name in CAPABILITY_TOOL_NAMES]
    for path in source_tools:
        if not path.is_file():
            fail("CAPABILITY_SOURCE_MISSING", str(path))
    destinations = capability_tools(config)
    section_files = [config / "agents" / f"{name}.md" for name in AGENT_NAMES]
    section_files += [config / "commands" / f"{name}.md" for name in ("ai-review", "ai-workflow", "ai-resume", "ai-release", "ai-status", "ai-metrics")]
    affected = [*destinations, *section_files, resolved["manifest"], resolved["legacy_manifest"]]
    backup_dir, existed = backup(config, affected)
    try:
        for source_tool, destination in zip(source_tools, destinations):
            shutil.copy2(source_tool, destination)
            destination.chmod(destination.stat().st_mode | stat.S_IXUSR)
        tool_map = {
            "authority": destinations[0],
            "memory": destinations[1],
            "evidence": destinations[2],
            "simulation": destinations[3],
            "pre_commit": destinations[4],
        }
        blocks = policy_blocks(tool_map, resolved["memory"])
        section_hashes: dict[str, str] = {}
        for path, entries in projected_sections(config, blocks).items():
            text = path.read_text(encoding="utf-8")
            for heading, body, before_core in entries:
                text = insert_section(text, heading, body, before_core)
            path.write_text(text, encoding="utf-8")
            for heading, _body, _before_core in entries:
                section_hashes[section_key(path, config, heading)] = hash_bytes(
                    extract_section(text, heading).encode("utf-8")
                )
        manifest["governance_version"] = VERSION
        manifest["architect_runner_version"] = VERSION
        manifest["context_intelligence_version"] = VERSION
        manifest["workflow_continuation_version"] = VERSION
        manifest["candidate_authority_version"] = "1.0"
        manifest["governed_memory_version"] = "2.0"
        manifest["evidence_reuse_version"] = "1.0"
        manifest["simulation_harness_version"] = "1.0"
        manifest["pre_commit_receipt_gate_version"] = "1.0"
        manifest["actionable_continuation_version"] = "1.0"
        manifest["managed_tools"] = [str(path) for path in expected_tools(config)]
        manifest["capability_tool_hashes"] = {path.name: sha256(path) for path in destinations}
        manifest["capability_section_hashes"] = section_hashes
        manifest["memory_store"] = str(resolved["memory"])
        manifest["capabilities_installed_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        write_json(resolved["manifest"], manifest)
        resolved["legacy_manifest"].unlink(missing_ok=True)
        verify(config, emit=False)
    except BaseException:
        restore(config, backup_dir, affected, existed)
        raise
    print(json.dumps({"status": "GOVERNANCE_CAPABILITIES_INSTALLED", "version": VERSION, "backup_dir": str(backup_dir)}, sort_keys=True))


def verify(config: pathlib.Path, emit: bool = True) -> dict[str, Any]:
    resolved = config_paths(config)
    if resolved["legacy_manifest"].exists():
        fail("LEGACY_RUNTIME_MANIFEST_PRESENT")
    manifest = read_json(resolved["manifest"])
    if manifest.get("schema_version") != "1.0" or manifest.get("governance_version") != VERSION:
        fail("CAPABILITY_MANIFEST_VERSION_MISMATCH")
    for field in ("architect_runner_version", "context_intelligence_version", "workflow_continuation_version"):
        if manifest.get(field) != VERSION:
            fail("CAPABILITY_COMPONENT_VERSION_MISMATCH", field)
    expected_versions = {
        "candidate_authority_version": "1.0",
        "governed_memory_version": "2.0",
        "evidence_reuse_version": "1.0",
        "simulation_harness_version": "1.0",
        "pre_commit_receipt_gate_version": "1.0",
        "actionable_continuation_version": "1.0",
    }
    for field, value in expected_versions.items():
        if manifest.get(field) != value:
            fail("CAPABILITY_COMPONENT_VERSION_MISMATCH", field)
    tools = expected_tools(config)
    if manifest.get("managed_tools") != [str(path) for path in tools]:
        fail("UNSAFE_MANAGED_TOOL_SET", VERSION)
    for path in base_tools(config):
        if not path.is_file():
            fail("BASE_MANAGED_TOOL_MISSING", path.name)
    hashes = manifest.get("capability_tool_hashes")
    if not isinstance(hashes, dict) or set(hashes) != set(CAPABILITY_TOOL_NAMES):
        fail("CAPABILITY_TOOL_HASHES_INVALID")
    for path in capability_tools(config):
        if not path.is_file() or hashes.get(path.name) != sha256(path):
            fail("CAPABILITY_TOOL_INTEGRITY_FAILURE", path.name)
    section_hashes = manifest.get("capability_section_hashes")
    if not isinstance(section_hashes, dict) or not section_hashes:
        fail("CAPABILITY_SECTION_HASHES_MISSING")
    for key, expected_hash in section_hashes.items():
        if not isinstance(key, str) or "#" not in key or not isinstance(expected_hash, str):
            fail("CAPABILITY_SECTION_MANIFEST_INVALID", str(key))
        relative, heading = key.rsplit("#", 1)
        path = config / pathlib.PurePosixPath(relative)
        if not path.is_file():
            fail("CAPABILITY_SECTION_FILE_MISSING", relative)
        actual = hash_bytes(extract_section(path.read_text(encoding="utf-8"), heading).encode("utf-8"))
        if actual != expected_hash:
            fail("CAPABILITY_SECTION_INTEGRITY_FAILURE", key)
    result = {"status": "GOVERNANCE_CAPABILITIES_VERIFIED", "version": VERSION, "managed_tool_count": len(tools)}
    if emit:
        print(json.dumps(result, sort_keys=True))
    return result


def uninstall(config: pathlib.Path) -> None:
    """Best-effort removal. Does not require a healthy install (broken hashes still uninstall)."""
    resolved = config_paths(config)
    if not resolved["manifest"].is_file():
        for path in capability_tools(config):
            path.unlink(missing_ok=True)
        print(json.dumps({"status": "GOVERNANCE_CAPABILITIES_REMOVED", "backup_dir": None, "mode": "tools-only"}, sort_keys=True))
        return

    manifest = read_json(resolved["manifest"])
    section_hashes = dict(manifest.get("capability_section_hashes") or {})
    section_files = {config / pathlib.PurePosixPath(key.rsplit("#", 1)[0]) for key in section_hashes if isinstance(key, str) and "#" in key}
    affected = [*capability_tools(config), *sorted(section_files), resolved["manifest"]]
    backup_dir, existed = backup(config, affected)
    try:
        sections_by_file: dict[pathlib.Path, list[str]] = {}
        for key in section_hashes:
            if not isinstance(key, str) or "#" not in key:
                continue
            relative, heading = key.rsplit("#", 1)
            path = config / pathlib.PurePosixPath(relative)
            if path.is_file():
                sections_by_file.setdefault(path, []).append(heading)
        for path, headings in sections_by_file.items():
            text = path.read_text(encoding="utf-8")
            for heading in headings:
                try:
                    text = remove_section(text, heading)
                except Exception:
                    continue
            path.write_text(text, encoding="utf-8")
        for path in capability_tools(config):
            path.unlink(missing_ok=True)
        manifest["governance_version"] = BASE_VERSION
        manifest["architect_runner_version"] = BASE_VERSION
        manifest["context_intelligence_version"] = BASE_VERSION
        manifest["workflow_continuation_version"] = BASE_VERSION
        manifest["managed_tools"] = [str(path) for path in base_tools(config)]
        for field in CAPABILITY_FIELDS:
            manifest.pop(field, None)
        write_json(resolved["manifest"], manifest)
    except BaseException:
        restore(config, backup_dir, affected, existed)
        raise
    print(json.dumps({"status": "GOVERNANCE_CAPABILITIES_REMOVED", "backup_dir": str(backup_dir), "mode": "best-effort"}, sort_keys=True))


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(prog="governance-capabilities")
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
