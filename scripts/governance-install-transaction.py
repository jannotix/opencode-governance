#!/usr/bin/env python3
"""Pre-install snapshot and full rollback for canonical OpenCode Governance updates."""
from __future__ import annotations

import argparse
import datetime
import json
import os
import pathlib
import shutil
import sys
from typing import Any

AGENTS = (
    "architect", "build", "plan", "executor", "reviewer",
    "reviewer-architecture", "final-reviewer",
)
COMMANDS = (
    "ai-init", "ai-audit", "ai-docs", "ai-discover", "ai-plan",
    "ai-execute", "ai-review", "ai-workflow", "ai-status", "ai-resume",
    "ai-metrics", "ai-release",
)
KNOWN_TOOLS = (
    "architect-attempt.ps1", "architect-attempt.sh",
    "architect-headless-contract.py",
    "executor-attempt.ps1", "executor-attempt.sh",
    "context-intelligence.ps1", "context-intelligence.sh",
    "context-intelligence.py", "workflow-continuation.ps1",
    "workflow-continuation.py", "governance-authority.py",
    "governance-memory.py", "governance-evidence.py",
    "governance-simulation.py", "governance-pre-commit.py",
)
SNAPSHOT_SCHEMA = "opencode-governance.install-snapshot/v1"


def fail(code: str, detail: str = "") -> None:
    payload = {"status": "ERROR", "code": code}
    if detail:
        payload["detail"] = detail
    print(json.dumps(payload, sort_keys=True), file=sys.stderr)
    raise SystemExit(2)


def surface(config: pathlib.Path) -> list[pathlib.Path]:
    values = [config / "agents" / f"{name}.md" for name in AGENTS]
    values += [config / "commands" / f"{name}.md" for name in COMMANDS]
    values += [config / "opencode-governance-tools" / name for name in KNOWN_TOOLS]
    values += [
        config / "opencode-governance-routing.json",
        config / "opencode-governance-runtime.json",
        config / "opencode.jsonc",
        config / "opencode.json",
    ]
    manifest = config / "opencode-governance-routing.json"
    if manifest.is_file():
        try:
            data = json.loads(manifest.read_text(encoding="utf-8-sig"))
        except Exception as exc:
            fail("ROUTING_MANIFEST_INVALID", str(exc))
        for raw in data.get("managed_tools", []):
            path = pathlib.Path(str(raw)).expanduser()
            try:
                resolved = path.resolve()
                resolved.relative_to(config.resolve())
            except Exception:
                fail("UNSAFE_MANAGED_TOOL_PATH", str(path))
            values.append(resolved)
        for alias in data.get("managed_aliases", []):
            name = str(alias)
            if not name or any(part in name for part in ("/", "\\", "..")):
                fail("UNSAFE_MANAGED_ALIAS", name)
            values.append(config / "agents" / f"{name}.md")
    unique: dict[str, pathlib.Path] = {}
    for path in values:
        unique[str(path.resolve())] = path.resolve()
    return sorted(unique.values(), key=lambda item: str(item).casefold())


def snapshot(config: pathlib.Path) -> pathlib.Path:
    config.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    destination = config / "backups" / f"opencode-governance-z-preinstall-{stamp}"
    destination.mkdir(parents=True, exist_ok=False)
    entries: list[dict[str, Any]] = []
    for path in surface(config):
        relative = path.relative_to(config).as_posix()
        exists = path.is_file()
        entries.append({"path": relative, "existed": exists})
        if not exists:
            continue
        target = destination / "tree" / pathlib.PurePosixPath(relative)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        if path.parent.name == "opencode-governance-tools":
            shutil.copy2(path, destination / path.name)
    metadata = {
        "schema": SNAPSHOT_SCHEMA,
        "config_dir": str(config),
        "entries": entries,
        "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    (destination / "snapshot.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return destination


def restore(config: pathlib.Path, backup: pathlib.Path) -> None:
    metadata_path = backup / "snapshot.json"
    if not metadata_path.is_file():
        fail("INSTALL_SNAPSHOT_MISSING", str(metadata_path))
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        fail("INSTALL_SNAPSHOT_INVALID", str(exc))
    if metadata.get("schema") != SNAPSHOT_SCHEMA or pathlib.Path(str(metadata.get("config_dir"))).resolve() != config.resolve():
        fail("INSTALL_SNAPSHOT_SCOPE_MISMATCH")
    entries = metadata.get("entries")
    if not isinstance(entries, list):
        fail("INSTALL_SNAPSHOT_INVALID", "entries")
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str) or not isinstance(entry.get("existed"), bool):
            fail("INSTALL_SNAPSHOT_INVALID", "entry")
        relative = pathlib.PurePosixPath(entry["path"])
        if relative.is_absolute() or ".." in relative.parts:
            fail("INSTALL_SNAPSHOT_PATH_INVALID", entry["path"])
        path = config / relative
        source = backup / "tree" / relative
        if entry["existed"]:
            if not source.is_file():
                fail("INSTALL_SNAPSHOT_CONTENT_MISSING", entry["path"])
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, path)
        else:
            path.unlink(missing_ok=True)
    print(json.dumps({"status": "GOVERNANCE_INSTALL_ROLLED_BACK", "backup_dir": str(backup)}, sort_keys=True))


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(prog="governance-install-transaction")
    value.add_argument("action", choices=("snapshot", "restore"))
    value.add_argument("--config-dir", required=True)
    value.add_argument("--backup-dir")
    return value


def main() -> None:
    args = parser().parse_args()
    config = pathlib.Path(args.config_dir).expanduser().resolve()
    if args.action == "snapshot":
        backup = snapshot(config)
        print(json.dumps({"status": "GOVERNANCE_INSTALL_SNAPSHOT_CREATED", "backup_dir": str(backup)}, sort_keys=True))
    else:
        if not args.backup_dir:
            fail("BACKUP_DIR_REQUIRED")
        restore(config, pathlib.Path(args.backup_dir).expanduser().resolve())


if __name__ == "__main__":
    main()
