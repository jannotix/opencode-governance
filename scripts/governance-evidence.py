#!/usr/bin/env python3
"""Content-bound evidence reuse ledger for OpenCode Governance."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import sys
from datetime import datetime, timezone
from typing import Any

SCHEMA = "opencode-governance.evidence-reuse/v1"
OUTCOMES = {"PASS", "FAIL", "UNAVAILABLE", "BLOCKED"}


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


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
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def valid_hash(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(char in "0123456789abcdef" for char in value)


def validate_dependencies(value: dict[str, Any]) -> None:
    if not value:
        fail("EMPTY_EVIDENCE_DEPENDENCIES")
    for name, dependency_hash in value.items():
        if not isinstance(name, str) or not name.strip() or not valid_hash(dependency_hash):
            fail("INVALID_DEPENDENCY_HASH", str(name))


def fail(code: str, detail: str = "") -> None:
    payload = {"status": "ERROR", "code": code}
    if detail:
        payload["detail"] = detail
    print(json.dumps(payload, sort_keys=True), file=sys.stderr)
    raise SystemExit(2)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(prog="governance-evidence")
    subcommands = value.add_subparsers(dest="command", required=True)

    record = subcommands.add_parser("record")
    record.add_argument("--task-id", required=True)
    record.add_argument("--evidence-type", required=True)
    record.add_argument("--outcome", required=True, choices=sorted(OUTCOMES))
    record.add_argument("--dependencies", required=True)
    record.add_argument("--output", required=True)

    validate = subcommands.add_parser("validate")
    validate.add_argument("--record", required=True)
    validate.add_argument("--dependencies", required=True)
    return value


def main() -> None:
    args = parser().parse_args()
    dependencies = load_object(pathlib.Path(args.dependencies))
    validate_dependencies(dependencies)

    if args.command == "record":
        record = {
            "schema": SCHEMA,
            "task_id": args.task_id,
            "evidence_type": args.evidence_type,
            "outcome": args.outcome,
            "dependencies": dependencies,
            "dependency_digest": digest(dependencies),
            "recorded_at": datetime.now(timezone.utc).isoformat(),
        }
        record["record_hash"] = digest(record)
        write_object(pathlib.Path(args.output), record)
        print(json.dumps({"status": "EVIDENCE_RECORDED", "record_hash": record["record_hash"]}, sort_keys=True))
        return

    record = load_object(pathlib.Path(args.record))
    expected_hash = digest({key: item for key, item in record.items() if key != "record_hash"})
    if record.get("schema") != SCHEMA or record.get("record_hash") != expected_hash:
        fail("EVIDENCE_RECORD_CORRUPT")
    if record.get("outcome") != "PASS":
        fail("NON_PASS_EVIDENCE", str(record.get("outcome")))
    if record.get("dependencies") != dependencies:
        fail("EVIDENCE_STALE")
    print(json.dumps({"status": "EVIDENCE_REUSABLE", "record_hash": record["record_hash"]}, sort_keys=True))


if __name__ == "__main__":
    main()
