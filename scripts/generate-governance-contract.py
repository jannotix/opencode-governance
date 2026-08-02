#!/usr/bin/env python3
"""Deterministic generator for OpenCode Governance semantic contract surfaces.

GENERATOR_VERSION is independent of product VERSION; product version lives in the
canonical specification (governance-spec/governance-contract.json).

Usage:
  python scripts/generate-governance-contract.py --root <repo> [--check]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys
from typing import Any

GENERATOR_VERSION = "1.0.0"
SPEC_REL = "governance-spec/governance-contract.json"
OUT_PY = "scripts/generated/governance_contract_data.py"
OUT_PS1 = "scripts/generated/governance-contract-data.ps1"
OUT_SH = "scripts/generated/governance-contract-data.sh"
OUT_DOC = "docs/generated/semantic-contract-tables.md"
OUT_SIM = "tests/fixtures/simulation/all-commands-manifest.json"
OUT_EXEC = "tests/fixtures/executor-transaction-scenarios.json"
MARKER = "DO_NOT_EDIT_MANUALLY"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    return sha256_bytes(path.read_bytes())


def load_spec(root: pathlib.Path) -> tuple[dict[str, Any], str]:
    path = root / SPEC_REL
    raw = path.read_bytes()
    # Normalise to LF for stable hashing of committed JSON when loaded
    text = raw.decode("utf-8-sig")
    if text.startswith("\ufeff"):
        text = text.lstrip("\ufeff")
    data = json.loads(text)
    # Canonical digest of committed file bytes (as on disk)
    return data, sha256_file(path)


def emit_py(spec: dict[str, Any], source_sha: str) -> str:
    phases = {p["phase_id"]: p for p in spec["phases"]}
    transitions = list(spec["transitions"])
    commands = list(spec["commands"])
    terminal_success = sorted(
        p["phase_id"] for p in spec["phases"] if p.get("phase_class") == "TERMINAL_SUCCESS"
    )
    terminal_blockers = sorted(
        p["phase_id"] for p in spec["phases"] if p.get("phase_class") == "TERMINAL_BLOCKER"
    )
    non_terminal = sorted(
        p["phase_id"]
        for p in spec["phases"]
        if p.get("phase_class") in {"NON_TERMINAL", "REPAIR", "GATE"}
    )
    # Index transitions
    by_key: dict[str, dict[str, Any]] = {}
    for t in transitions:
        key = f"{t['from']}->{t['to']}|{t.get('command') or ''}"
        by_key[key] = t
    payload = {
        "SCHEMA": "SEMANTIC_WORKFLOW_STATE_MACHINE_V1",
        "GOVERNANCE_VERSION": spec["governance_version"],
        "CONTRACT_VERSIONS": spec.get("contract_versions", {}),
        "COMMANDS": commands,
        "KNOWN_COMMANDS": [f"/{c}" if not c.startswith("/") else c for c in commands],
        "ROLES": spec.get("roles", []),
        "PHASES": phases,
        "NON_TERMINAL_PHASES": non_terminal,
        "TERMINAL_SUCCESS": terminal_success,
        "TERMINAL_BLOCKERS": terminal_blockers,
        "TRANSITIONS": transitions,
        "TRANSITION_INDEX": by_key,
        "ARTIFACT_TYPES": spec.get("artifact_types", []),
        "RECEIPT_TYPES": spec.get("receipt_types", []),
        "EVIDENCE_CLASSES": spec.get("evidence_classes", []),
        "MANAGED_TOOLS": spec.get("managed_tools", []),
        "SUPPORTED_OPENCODE_VERSIONS": spec.get("supported_opencode_versions", {}),
        "ASSURANCE_LEVELS": spec.get("assurance_levels", {}),
        "SHARED_PROMPT_SECTIONS": spec.get("shared_prompt_sections", {}),
        "SIMULATION_SCENARIOS": spec.get("simulation_scenarios", []),
        "TERMINAL_REASONS": spec.get("terminal_reasons", []),
    }
    body = json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False)
    lines = [
        "#!/usr/bin/env python3",
        f'"""GENERATED_FROM={SPEC_REL}',
        f"SOURCE_SPEC_SHA256={source_sha}",
        f"GENERATOR_VERSION={GENERATOR_VERSION}",
        f"{MARKER}",
        '"""',
        "from __future__ import annotations",
        "",
        "import json",
        "from typing import Any",
        "",
        f"GENERATED_FROM = {SPEC_REL!r}",
        f"SOURCE_SPEC_SHA256 = {source_sha!r}",
        f"GENERATOR_VERSION = {GENERATOR_VERSION!r}",
        f"{MARKER} = True",
        "",
        f"_PAYLOAD = json.loads({body!r})",
        "",
        "SCHEMA: str = _PAYLOAD['SCHEMA']",
        "GOVERNANCE_VERSION: str = _PAYLOAD['GOVERNANCE_VERSION']",
        "CONTRACT_VERSIONS: dict[str, str] = _PAYLOAD['CONTRACT_VERSIONS']",
        "COMMANDS: list[str] = list(_PAYLOAD['COMMANDS'])",
        "KNOWN_COMMANDS: set[str] = set(_PAYLOAD['KNOWN_COMMANDS'])",
        "ROLES: list[dict[str, Any]] = list(_PAYLOAD['ROLES'])",
        "PHASES: dict[str, dict[str, Any]] = dict(_PAYLOAD['PHASES'])",
        "NON_TERMINAL_PHASES: set[str] = set(_PAYLOAD['NON_TERMINAL_PHASES'])",
        "TERMINAL_SUCCESS: set[str] = set(_PAYLOAD['TERMINAL_SUCCESS'])",
        "TERMINAL_BLOCKERS: set[str] = set(_PAYLOAD['TERMINAL_BLOCKERS'])",
        "TRANSITIONS: list[dict[str, Any]] = list(_PAYLOAD['TRANSITIONS'])",
        "TRANSITION_INDEX: dict[str, dict[str, Any]] = dict(_PAYLOAD['TRANSITION_INDEX'])",
        "ARTIFACT_TYPES: list[str] = list(_PAYLOAD['ARTIFACT_TYPES'])",
        "RECEIPT_TYPES: list[str] = list(_PAYLOAD['RECEIPT_TYPES'])",
        "EVIDENCE_CLASSES: list[str] = list(_PAYLOAD['EVIDENCE_CLASSES'])",
        "MANAGED_TOOLS: list[str] = list(_PAYLOAD['MANAGED_TOOLS'])",
        "SUPPORTED_OPENCODE_VERSIONS: dict[str, Any] = dict(_PAYLOAD['SUPPORTED_OPENCODE_VERSIONS'])",
        "ASSURANCE_LEVELS: dict[str, Any] = dict(_PAYLOAD['ASSURANCE_LEVELS'])",
        "SHARED_PROMPT_SECTIONS: dict[str, str] = dict(_PAYLOAD['SHARED_PROMPT_SECTIONS'])",
        "SIMULATION_SCENARIOS: list[dict[str, Any]] = list(_PAYLOAD['SIMULATION_SCENARIOS'])",
        "TERMINAL_REASONS: set[str] = set(_PAYLOAD['TERMINAL_REASONS'])",
        "",
        "",
        "def find_transition(from_phase: str, to_phase: str, command: str | None) -> dict[str, Any] | None:",
        "    key = f'{from_phase}->{to_phase}|{command or \"\"}'",
        "    hit = TRANSITION_INDEX.get(key)",
        "    if hit is not None:",
        "        return hit",
        "    # Allow command-agnostic human_decision transitions recorded with empty command.",
        "    if command:",
        "        return TRANSITION_INDEX.get(f'{from_phase}->{to_phase}|')",
        "    return None",
        "",
        "",
        "def allowed_successors(phase_id: str) -> set[str]:",
        "    phase = PHASES.get(phase_id) or {}",
        "    return set(phase.get('allowed_successors') or [])",
        "",
    ]
    return "\n".join(lines) + "\n"


def emit_ps1(spec: dict[str, Any], source_sha: str) -> str:
    cmds = ", ".join(f"'{c}'" for c in spec["commands"])
    tools = ", ".join(f"'{t}'" for t in spec.get("managed_tools", []))
    return (
        f"# GENERATED_FROM={SPEC_REL}\n"
        f"# SOURCE_SPEC_SHA256={source_sha}\n"
        f"# GENERATOR_VERSION={GENERATOR_VERSION}\n"
        f"# {MARKER}\n"
        f"$script:GovernanceVersion = '{spec['governance_version']}'\n"
        f"$script:GovernanceCommands = @({cmds})\n"
        f"$script:GovernanceManagedTools = @({tools})\n"
        f"$script:SemanticMachineSchema = 'SEMANTIC_WORKFLOW_STATE_MACHINE_V1'\n"
    )


def emit_sh(spec: dict[str, Any], source_sha: str) -> str:
    cmds = " ".join(spec["commands"])
    tools = " ".join(spec.get("managed_tools", []))
    return (
        f"# GENERATED_FROM={SPEC_REL}\n"
        f"# SOURCE_SPEC_SHA256={source_sha}\n"
        f"# GENERATOR_VERSION={GENERATOR_VERSION}\n"
        f"# {MARKER}\n"
        f"GOVERNANCE_VERSION='{spec['governance_version']}'\n"
        f"GOVERNANCE_COMMANDS='{cmds}'\n"
        f"GOVERNANCE_MANAGED_TOOLS='{tools}'\n"
        f"SEMANTIC_MACHINE_SCHEMA='SEMANTIC_WORKFLOW_STATE_MACHINE_V1'\n"
    )


def emit_doc(spec: dict[str, Any], source_sha: str) -> str:
    lines = [
        f"<!-- GENERATED_FROM={SPEC_REL} -->",
        f"<!-- SOURCE_SPEC_SHA256={source_sha} -->",
        f"<!-- GENERATOR_VERSION={GENERATOR_VERSION} -->",
        f"<!-- {MARKER} -->",
        "",
        f"# Semantic governance contract tables ({spec['governance_version']})",
        "",
        f"- Schema: `{spec.get('schema_version')}`",
        f"- Machine: `SEMANTIC_WORKFLOW_STATE_MACHINE_V1`",
        f"- Spec SHA-256: `{source_sha}`",
        f"- Transitions: **{len(spec['transitions'])}**",
        f"- Phases: **{len(spec['phases'])}**",
        f"- Commands: **{len(spec['commands'])}**",
        "",
        "## Commands",
        "",
        "| Command |",
        "|---------|",
    ]
    for c in spec["commands"]:
        lines.append(f"| `{c}` |")
    lines += ["", "## Managed tools", "", "| Tool |", "|------|"]
    for t in spec.get("managed_tools", []):
        lines.append(f"| `{t}` |")
    lines += ["", "## Transitions", "", "| ID | From | To | Command | Attempt consumed |", "|----|------|----|---------|------------------|"]
    for t in spec["transitions"]:
        lines.append(
            f"| `{t['transition_id']}` | `{t['from']}` | `{t['to']}` | `{t.get('command') or ''}` | `{t.get('attempt_consumed')}` |"
        )
    lines += ["", "## Assurance levels (3.8.0 claims)", ""]
    for level, meta in (spec.get("assurance_levels") or {}).items():
        claim = meta.get("claimed_in_3_8_0", False)
        lines.append(f"- `{level}`: claimed={claim} — {meta.get('description', '')}")
    lines += ["", "## Supported OpenCode versions", ""]
    for ver, meta in (spec.get("supported_opencode_versions") or {}).items():
        lines.append(f"- `{ver}`: `{meta.get('class')}` — {meta.get('notes', '')}")
    lines.append("")
    return "\n".join(lines)


def emit_sim_manifest(spec: dict[str, Any], source_sha: str) -> str:
    body = {
        "schema": "ALL_COMMANDS_SIMULATION_CONTRACT_V1",
        "GENERATED_FROM": SPEC_REL,
        "SOURCE_SPEC_SHA256": source_sha,
        "GENERATOR_VERSION": GENERATOR_VERSION,
        "DO_NOT_EDIT_MANUALLY": True,
        "required_commands": list(spec["commands"]),
        "scenarios": list(spec.get("simulation_scenarios") or []),
    }
    return json.dumps(body, indent=2, sort_keys=True) + "\n"


def emit_executor_scenarios(source_sha: str) -> str:
    scenarios = [
        "clean_isolated_worktree_prepare",
        "frozen_target_mismatch",
        "dirty_tracked_overlap",
        "dirty_untracked_overlap",
        "staged_overlap",
        "binary_patch",
        "rename",
        "deletion",
        "path_with_spaces",
        "unicode_path",
        "patch_generation_failure",
        "apply_failure",
        "failure_after_apply",
        "incomplete_attempt_report",
        "packet_hash_mismatch",
        "report_path_tampering",
        "candidate_drift",
        "child_worktree_cleanup",
        "promotion_rollback",
        "residual_worktree_detection",
        "concurrent_attempt_collision",
    ]
    body = {
        "schema": "EXECUTOR_TRANSACTION_SCENARIO_MANIFEST_V1",
        "GENERATED_FROM": SPEC_REL,
        "SOURCE_SPEC_SHA256": source_sha,
        "GENERATOR_VERSION": GENERATOR_VERSION,
        "DO_NOT_EDIT_MANUALLY": True,
        "mandatory_scenarios": scenarios,
        "platforms": ["windows", "unix"],
    }
    return json.dumps(body, indent=2, sort_keys=True) + "\n"


def write_file(path: pathlib.Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Force LF for cross-platform determinism
    data = content.replace("\r\n", "\n").encode("utf-8")
    path.write_bytes(data)


def generate(root: pathlib.Path) -> dict[str, str]:
    spec, source_sha = load_spec(root)
    outputs = {
        OUT_PY: emit_py(spec, source_sha),
        OUT_PS1: emit_ps1(spec, source_sha),
        OUT_SH: emit_sh(spec, source_sha),
        OUT_DOC: emit_doc(spec, source_sha),
        OUT_SIM: emit_sim_manifest(spec, source_sha),
        OUT_EXEC: emit_executor_scenarios(source_sha),
    }
    for rel, content in outputs.items():
        write_file(root / rel, content)
    return {rel: sha256_bytes(content.replace("\r\n", "\n").encode("utf-8")) for rel, content in outputs.items()}


def check(root: pathlib.Path) -> int:
    import tempfile
    import shutil

    spec, source_sha = load_spec(root)
    with tempfile.TemporaryDirectory(prefix="gov-gen-check-") as tmp:
        troot = pathlib.Path(tmp)
        # Copy only the spec path structure needed
        (troot / "governance-spec").mkdir(parents=True)
        shutil.copy2(root / SPEC_REL, troot / SPEC_REL)
        expected = generate(troot)
        mismatches = []
        for rel, digest in expected.items():
            committed = root / rel
            if not committed.is_file():
                mismatches.append(f"MISSING {rel}")
                continue
            actual = sha256_file(committed)
            # Compare content LF-normalised
            committed_norm = committed.read_bytes().replace(b"\r\n", b"\n")
            if sha256_bytes(committed_norm) != digest:
                mismatches.append(f"STALE {rel}: committed={actual} expected={digest}")
        if mismatches:
            print("GENERATED_CONTRACT_STALE", file=sys.stderr)
            for m in mismatches:
                print(m, file=sys.stderr)
            return 2
    print(
        json.dumps(
            {
                "status": "GENERATED_CONTRACT_FRESH",
                "source_spec_sha256": source_sha,
                "generator_version": GENERATOR_VERSION,
                "files": list(expected),
            },
            sort_keys=True,
        )
    )
    return 0


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--root", default=".")
    p.add_argument("--check", action="store_true")
    args = p.parse_args()
    root = pathlib.Path(args.root).resolve()
    if args.check:
        return check(root)
    out = generate(root)
    print(json.dumps({"status": "GENERATED", "files": out, "generator_version": GENERATOR_VERSION}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
