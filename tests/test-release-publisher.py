#!/usr/bin/env python3
"""Regression for annotated-tag identity in the verified release publisher."""
from __future__ import annotations

import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "publish-release.yml"


def main() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    name_index = text.find("git config user.name")
    email_index = text.find("git config user.email")
    repair_index = text.find("- name: Repair historical release tag integrity")
    create_index = text.find("- name: Create verified tag")
    assert name_index >= 0, "publisher must configure git user.name"
    assert email_index >= 0, "publisher must configure git user.email"
    assert repair_index >= 0 and create_index >= 0, "publisher tag stages are missing"
    assert name_index < repair_index < create_index
    assert email_index < repair_index < create_index
    assert "git tag -a \"$VERSION\" \"$RELEASE_SHA\"" in text
    print("PASS: release publisher configures annotated-tag identity")


if __name__ == "__main__":
    main()
