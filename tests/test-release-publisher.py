#!/usr/bin/env python3
"""Regression tests for the verified release publisher contract."""
from __future__ import annotations

import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "publish-release.yml"


def main() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    name_index = text.find("git config user.name")
    email_index = text.find("git config user.email")
    create_index = text.find("- name: Create verified tag")
    assert name_index >= 0, "publisher must configure git user.name"
    assert email_index >= 0, "publisher must configure git user.email"
    assert create_index >= 0, "publisher tag stage is missing"
    assert name_index < create_index
    assert email_index < create_index
    assert "git tag -a \"$VERSION\" \"$RELEASE_SHA\"" in text
    assert "git push --force" not in text
    assert "Repair historical release tag integrity" not in text

    canonical = {"Verify governance", "Verify repository hardening"}
    for workflow in canonical:
        assert f"'{workflow}'" in text, f"missing canonical verification dependency: {workflow}"
    obsolete = {
        "Verify Context Intelligence v3.4+",
        "Verify Architect Runner Integration v3.3.2+",
        "Verify Project State Integrity v3.3.4",
        "Verify Executor failover v3.3",
        "Verify PowerShell Host and Verifier Reliability v3.3.3+",
        "Verify Local Configuration Durability v3.3.1",
    }
    for workflow in obsolete:
        assert workflow not in text, f"publisher still waits for removed workflow: {workflow}"

    assert "SHOULD_PUBLISH=false" in text
    assert text.count("if: env.SHOULD_PUBLISH == 'true'") == 3
    print("PASS: release publisher uses canonical checks and skips already-published versions")


if __name__ == "__main__":
    main()
