#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import re

COMMANDS = {
    "ai-init": ("PERMISSION_BOOTSTRAP_PROBE", "BASELINE_DUAL_AUDIT", "GOVERNANCE_PERMISSION_BLOCKED"),
    "ai-audit": ("Final Reviewer", "OPERATIONAL_ASSURANCE", "Maximum three"),
    "ai-docs": ("Executor", "DOCUMENTATION_IMPACT", "NO_AUTOMATIC_EXTERNAL_ACTION"),
    "ai-discover": ("ADAPTIVE_PRODUCT_DISCOVERY", "DISCOVERY_PASS", "NO_AUTOMATIC_EXTERNAL_ACTION"),
    "ai-plan": ("READY_FOR_EXECUTION", "EXECUTION_PACKET.md", "NO_AUTOMATIC_EXTERNAL_ACTION"),
    "ai-execute": ("READY_FOR_EXECUTION", "EXECUTOR_FAILOVER_BLOCKED", "NO_AUTOMATIC_EXTERNAL_ACTION"),
    "ai-review": ("REVIEW_FREEZE", "FINAL_PACKET.md", "NO_AUTOMATIC_EXTERNAL_ACTION"),
    "ai-workflow": ("WORKFLOW_CONTINUATION_GATE_V1", "CONTINUE_REQUIRED", "LOCAL_COMMITTED"),
    "ai-status": ("EVIDENCE_STATUS", "REMAINING_REQUIRED_CAPABILITIES", "Status integrity contract"),
    "ai-resume": ("WORKFLOW_CONTINUATION_GATE_V1", "LEGACY_RUN_STATE_MIGRATION_V1", "top_level_command", "CONTINUE_REQUIRED"),
    "ai-metrics": ("GOVERNANCE_METRICS", "ESTIMATED_VALUES: NONE", "UNAVAILABLE"),
    "ai-release": ("PRODUCT_COMPLETENESS_VERDICT", "RELEASE_VERDICT", "NO_AUTOMATIC_EXTERNAL_ACTION"),
}
FRONTMATTER = re.compile(
    r"\A---\r?\ndescription: .+\r?\nagent: architect\r?\nsubtask: false\r?\n---\r?\n",
    re.MULTILINE,
)


def validate(directory: pathlib.Path, label: str) -> None:
    actual = {path.stem for path in directory.glob("ai-*.md")}
    expected = set(COMMANDS)
    if actual != expected:
        raise AssertionError(f"{label}: command set mismatch missing={sorted(expected-actual)} extra={sorted(actual-expected)}")
    for name, markers in COMMANDS.items():
        path = directory / f"{name}.md"
        text = path.read_text(encoding="utf-8-sig")
        if not FRONTMATTER.search(text):
            raise AssertionError(f"{label}/{name}: invalid frontmatter or agent binding")
        if re.search(r"__[A-Z0-9_]+__", text):
            raise AssertionError(f"{label}/{name}: unrendered placeholder")
        if "NO_AUTOMATIC_EXTERNAL_ACTION" not in text:
            raise AssertionError(f"{label}/{name}: missing universal external-action boundary")
        if text.count("## ARCHITECT_RUNNER_ENTRY_GATE") > 1:
            raise AssertionError(f"{label}/{name}: duplicate Architect entry gate")
        if text.count("## CONTEXT_INTELLIGENCE_ENTRY") > 1:
            raise AssertionError(f"{label}/{name}: duplicate Context Intelligence entry")
        if text.count("## WORKFLOW_CONTINUATION_GATE_V1") > 1:
            raise AssertionError(f"{label}/{name}: duplicate continuation gate")
        if text.count("## LEGACY_RUN_STATE_MIGRATION_V1") > 1:
            raise AssertionError(f"{label}/{name}: duplicate legacy run-state migration contract")
        for marker in markers:
            if marker not in text:
                raise AssertionError(f"{label}/{name}: missing {marker}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=str(pathlib.Path(__file__).resolve().parents[1]))
    parser.add_argument("--config-dir")
    args = parser.parse_args()
    root = pathlib.Path(args.root).resolve()
    validate(root / "templates" / "commands", "templates")
    if args.config_dir:
        validate(pathlib.Path(args.config_dir).resolve() / "commands", "installed")
    print("PASS: all 12 AI command contracts are coherent")


if __name__ == "__main__":
    main()
