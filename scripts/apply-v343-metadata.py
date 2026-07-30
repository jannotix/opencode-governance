#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise SystemExit(f"{label} was not found exactly once in {path}.")
    path.write_text(text.replace(old, new), encoding="utf-8")


def main() -> None:
    version = Path("VERSION")
    current = version.read_text(encoding="utf-8").strip()
    if current == "3.4.3":
        return
    if current != "3.4.2":
        raise SystemExit(f"Expected VERSION 3.4.2 before migration, found {current!r}.")
    version.write_text("3.4.3\n", encoding="utf-8")

    replace_once(
        Path("README.md"),
        "Current release: **3.4.2 — Cross-Platform Schema Parity**.\n\nVersion 3.4.2 makes routing-profile and skill-manifest JSON type validation identical across Windows and Unix entrypoints; scalar strings no longer pass where the schema requires arrays or integers.",
        "Current release: **3.4.3 — Release Integrity & JSONC Readability**.\n\nVersion 3.4.3 preserves readable URL literals during Windows and Unix JSONC normalization, cleans the routing compatibility matrix and adds fail-closed release publication checks without changing local model routing.",
        "README release marker",
    )

    changelog = Path("CHANGELOG.md")
    marker = "All released versions are recorded in this single file. Dates use `YYYY-MM-DD`.\n\n"
    entry = """## 3.4.3 - 2026-07-30

- Preserved literal `/` characters in normalized OpenCode JSONC so schema and provider URLs remain readable while comment markers inside strings stay safe.
- Added Windows and Unix regressions for readable URL serialization in addition to semantic JSONC preservation.
- Cleaned duplicated 3.4.2 entries from routing verification and uninstall compatibility matrices and added explicit 3.4.3 support.
- Added fail-closed release publication checks that verify release metadata and repair the incorrectly moved 3.4.1 tag only after confirming its historical commit.
- Preserved every local provider/model route, variant, fallback priority, work class, reviewer-independence rule, authentication and no-push/no-deploy governance contract.

"""
    text = changelog.read_text(encoding="utf-8")
    if text.count(marker) != 1:
        raise SystemExit("CHANGELOG insertion marker was not found exactly once.")
    changelog.write_text(text.replace(marker, marker + entry), encoding="utf-8")

    for name in ("scripts/install.ps1", "scripts/install.sh"):
        path = Path(name)
        text = path.read_text(encoding="utf-8")
        if "3.4.2" not in text:
            raise SystemExit(f"{name}: current release marker not found.")
        text = text.replace("3.4.2", "3.4.3")
        text = text.replace("Cleanup & Hardening", "Release Integrity & JSONC Readability")
        path.write_text(text, encoding="utf-8")

    path = Path("docs/architect-runner-integration.md")
    replace_once(
        path,
        "Version 3.4.2 enforces identical JSON array and integer types across Windows and Unix entrypoints.",
        "Version 3.4.2 enforces identical JSON array and integer types across Windows and Unix entrypoints. Version 3.4.3 preserves readable JSONC URL literals and publishes releases through verified repository metadata.",
        "Architect runner release sentence",
    )
    text = path.read_text(encoding="utf-8")
    text = text.replace("The 3.4.2 routing manifest records:", "The 3.4.3 routing manifest records:")
    text = text.replace(
        "governance_version: 3.4.2\narchitect_runner_version: 3.4.2\ncontext_intelligence_version: 3.4.2",
        "governance_version: 3.4.3\narchitect_runner_version: 3.4.3\ncontext_intelligence_version: 3.4.3",
    )
    text = text.replace("A 3.4.2 installation preserves", "A 3.4.3 installation preserves")
    path.write_text(text, encoding="utf-8")

    path = Path("docs/context-intelligence-skill-routing.md")
    replace_once(
        path,
        "Version 3.4.2 rejects string-encoded token estimates and aligns the PowerShell schema with the Python core.",
        "Version 3.4.2 rejects string-encoded token estimates and aligns the PowerShell schema with the Python core. Version 3.4.3 keeps normalized URL literals human-readable on both platforms.",
        "Context Intelligence release sentence",
    )
    text = path.read_text(encoding="utf-8")
    text = text.replace(
        "governance_version: 3.4.2\narchitect_runner_version: 3.4.2\ncontext_intelligence_version: 3.4.2",
        "governance_version: 3.4.3\narchitect_runner_version: 3.4.3\ncontext_intelligence_version: 3.4.3",
    )
    text = text.replace("A 3.4.2 installation preserves", "A 3.4.3 installation preserves")
    path.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
