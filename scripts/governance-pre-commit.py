#!/usr/bin/env python3
"""Content-bound staged-receipt pre-commit gate for OpenCode Governance."""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
from datetime import datetime, timezone
from typing import Any

SCHEMA = "opencode-governance.pre-commit/v1"
MARKER_START = "# ======== OPENCODE GOVERNANCE PRE-COMMIT START ========"
MARKER_END = "# ======== OPENCODE GOVERNANCE PRE-COMMIT END ========"


def fail(code: str, detail: str = "") -> None:
    payload = {"status": "ERROR", "code": code}
    if detail:
        payload["detail"] = detail
    print(json.dumps(payload, sort_keys=True), file=sys.stderr)
    raise SystemExit(2)


def run_git(root: pathlib.Path, *arguments: str) -> str:
    process = subprocess.run(
        ["git", "-C", str(root), *arguments],
        text=True,
        capture_output=True,
    )
    if process.returncode:
        fail("GIT_COMMAND_FAILED", process.stderr.strip())
    return process.stdout.strip()


def project_root(value: str) -> pathlib.Path:
    root = pathlib.Path(value).expanduser().resolve()
    if not root.is_dir():
        fail("PROJECT_DIR_NOT_FOUND", str(root))
    run_git(root, "rev-parse", "--git-dir")
    return root


def git_path(root: pathlib.Path, name: str) -> pathlib.Path:
    value = pathlib.Path(run_git(root, "rev-parse", "--git-path", name))
    return value.resolve() if value.is_absolute() else (root / value).resolve()


def common_dir(root: pathlib.Path) -> pathlib.Path:
    value = pathlib.Path(run_git(root, "rev-parse", "--git-common-dir"))
    return value.resolve() if value.is_absolute() else (root / value).resolve()


def pointer_path(root: pathlib.Path) -> pathlib.Path:
    return common_dir(root) / "opencode-governance" / "pre-commit.json"


def load_object(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        fail("INVALID_JSON", f"{path}: {exc}")
    if not isinstance(value, dict):
        fail("INVALID_JSON_OBJECT", str(path))
    return value


def write_object(path: pathlib.Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def strip_managed_block(text: str) -> str:
    pattern = re.compile(
        rf"(?:\r?\n)?{re.escape(MARKER_START)}\r?\n.*?{re.escape(MARKER_END)}(?:\r?\n)?",
        re.S,
    )
    return pattern.sub("\n", text)


def hook_block(script: pathlib.Path, root: pathlib.Path, python_command: str) -> str:
    command = " ".join(
        (
            shlex.quote(python_command),
            shlex.quote(str(script)),
            "validate",
            "--project-dir",
            shlex.quote(str(root)),
        )
    )
    return (
        f"{MARKER_START}\n"
        f"{command}\n"
        "governance_status=$?\n"
        "if [ \"$governance_status\" -ne 0 ]; then exit \"$governance_status\"; fi\n"
        f"{MARKER_END}\n"
    )


def install(root: pathlib.Path, script: pathlib.Path, python_command: str) -> None:
    hook = git_path(root, "hooks/pre-commit")
    hook.parent.mkdir(parents=True, exist_ok=True)
    existing = hook.read_text(encoding="utf-8", errors="surrogateescape") if hook.exists() else "#!/usr/bin/env sh\n"
    clean = strip_managed_block(existing)
    lines = clean.splitlines(keepends=True)
    block = hook_block(script, root, python_command)
    if lines and lines[0].startswith("#!"):
        rendered = lines[0] + block + "".join(lines[1:])
    else:
        rendered = "#!/usr/bin/env sh\n" + block + clean
    hook.write_text(rendered, encoding="utf-8", errors="surrogateescape")
    hook.chmod(hook.stat().st_mode | 0o111)
    print(json.dumps({"status": "PRE_COMMIT_GATE_INSTALLED", "hook": str(hook)}, sort_keys=True))


def receipt_inside_ai(root: pathlib.Path, value: str) -> pathlib.Path:
    receipt = pathlib.Path(value).expanduser()
    receipt = receipt.resolve() if receipt.is_absolute() else (root / receipt).resolve()
    ai_root = (root / ".ai").resolve()
    try:
        receipt.relative_to(ai_root)
    except ValueError:
        fail("RECEIPT_OUTSIDE_GOVERNANCE_STATE", str(receipt))
    if not receipt.is_file():
        fail("RECEIPT_NOT_FOUND", str(receipt))
    return receipt


def arm(root: pathlib.Path, receipt_value: str, authority_value: str) -> None:
    receipt = receipt_inside_ai(root, receipt_value)
    authority = pathlib.Path(authority_value).expanduser().resolve()
    if not authority.is_file():
        fail("AUTHORITY_TOOL_NOT_FOUND", str(authority))
    candidate = load_object(receipt).get("candidate")
    if not isinstance(candidate, dict) or candidate.get("projection") != "staged":
        fail("STAGED_RECEIPT_REQUIRED")
    pointer = {
        "schema": SCHEMA,
        "project_root": str(root),
        "receipt": str(receipt.relative_to(root)),
        "authority_tool": str(authority),
        "armed_at": datetime.now(timezone.utc).isoformat(),
    }
    write_object(pointer_path(root), pointer)
    print(json.dumps({"status": "PRE_COMMIT_GATE_ARMED", "receipt": pointer["receipt"]}, sort_keys=True))


def validate(root: pathlib.Path) -> None:
    pointer_file = pointer_path(root)
    if not pointer_file.is_file():
        fail("PRE_COMMIT_RECEIPT_NOT_ARMED")
    pointer = load_object(pointer_file)
    if pointer.get("schema") != SCHEMA or pointer.get("project_root") != str(root):
        fail("PRE_COMMIT_POINTER_INVALID")
    receipt = receipt_inside_ai(root, str(pointer.get("receipt", "")))
    authority = pathlib.Path(str(pointer.get("authority_tool", ""))).resolve()
    if not authority.is_file():
        fail("AUTHORITY_TOOL_NOT_FOUND", str(authority))
    process = subprocess.run(
        [
            sys.executable,
            str(authority),
            "receipt",
            "validate",
            "--receipt",
            str(receipt),
            "--project-dir",
            str(root),
            "--gate",
            "pre-commit",
        ],
        text=True,
        capture_output=True,
    )
    if process.returncode:
        sys.stderr.write(process.stderr)
        raise SystemExit(process.returncode)
    print(process.stdout.strip())


def uninstall(root: pathlib.Path) -> None:
    hook = git_path(root, "hooks/pre-commit")
    if hook.exists():
        clean = strip_managed_block(hook.read_text(encoding="utf-8", errors="surrogateescape"))
        meaningful = [line for line in clean.splitlines() if line.strip() and not line.startswith("#!")]
        if meaningful:
            hook.write_text(clean.rstrip() + "\n", encoding="utf-8", errors="surrogateescape")
        else:
            hook.unlink()
    pointer = pointer_path(root)
    pointer.unlink(missing_ok=True)
    if pointer.parent.exists() and not any(pointer.parent.iterdir()):
        pointer.parent.rmdir()
    print(json.dumps({"status": "PRE_COMMIT_GATE_REMOVED"}, sort_keys=True))


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(prog="governance-pre-commit")
    subcommands = value.add_subparsers(dest="command", required=True)
    for name in ("install", "validate", "uninstall"):
        command = subcommands.add_parser(name)
        command.add_argument("--project-dir", required=True)
        if name == "install":
            command.add_argument("--python-command", default=os.environ.get("OPENCODE_GOVERNANCE_PYTHON", "python"))
    arm_parser = subcommands.add_parser("arm")
    arm_parser.add_argument("--project-dir", required=True)
    arm_parser.add_argument("--receipt", required=True)
    arm_parser.add_argument("--authority-tool", required=True)
    return value


def main() -> None:
    args = parser().parse_args()
    root = project_root(args.project_dir)
    script = pathlib.Path(__file__).resolve()
    if args.command == "install":
        install(root, script, args.python_command)
    elif args.command == "arm":
        arm(root, args.receipt, args.authority_tool)
    elif args.command == "validate":
        validate(root)
    else:
        uninstall(root)


if __name__ == "__main__":
    main()
