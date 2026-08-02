#!/usr/bin/env python3
"""Local opt-in governance tax metrics foundation (no external telemetry)."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import time
from typing import Any

SCHEMA = "GOVERNANCE_TAX_METRICS_V1"
ALLOWED_FIELDS = {
    "task_id_hash",
    "work_class",
    "lifecycle_duration_ms",
    "phase_duration_ms",
    "prompt_tokens_when_available",
    "completion_tokens_when_available",
    "context_bytes_loaded",
    "model_calls",
    "fallbacks",
    "permission_blocks",
    "false_blocker_overrides",
    "repair_cycles",
    "review_cycles",
    "human_decisions",
    "evidence_reuse_hits",
    "evidence_reuse_misses",
    "final_verdict",
    "defect_escape_when_recorded",
    "recorded_at_utc",
    "schema",
}


def task_hash(task_id: str) -> str:
    return hashlib.sha256(task_id.encode("utf-8")).hexdigest()


def metrics_path(config_dir: pathlib.Path) -> pathlib.Path:
    return config_dir / "opencode-governance-metrics" / "metrics.jsonl"


def append_event(config_dir: pathlib.Path, event: dict[str, Any]) -> pathlib.Path:
    clean = {k: v for k, v in event.items() if k in ALLOWED_FIELDS}
    # Strip any accidental secret-like values
    for key in list(clean):
        val = clean[key]
        if isinstance(val, str) and any(s in key.lower() for s in ("secret", "token", "password", "key", "path")):
            if key not in {"task_id_hash", "final_verdict", "work_class"}:
                clean.pop(key, None)
    clean["schema"] = SCHEMA
    clean.setdefault("recorded_at_utc", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
    path = metrics_path(config_dir)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(clean, sort_keys=True, separators=(",", ":")) + "\n")
    return path


def summarise(config_dir: pathlib.Path) -> dict[str, Any]:
    path = metrics_path(config_dir)
    if not path.is_file():
        return {"schema": SCHEMA, "status": "EMPTY", "events": 0}
    counts: dict[str, int] = {}
    events = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        events += 1
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        wc = str(row.get("work_class") or "UNKNOWN")
        counts[wc] = counts.get(wc, 0) + 1
    return {
        "schema": SCHEMA,
        "status": "OK",
        "events": events,
        "by_work_class": counts,
        "path": str(path),
        "authority": False,
        "note": "Metrics never become approval authority.",
    }


def main() -> int:
    p = argparse.ArgumentParser(prog="governance-metrics")
    p.add_argument("command", choices=["record", "summary", "schema"])
    p.add_argument("--config-dir", default=os.environ.get("OPENCODE_CONFIG_DIR", ""))
    p.add_argument("--task-id", default="")
    p.add_argument("--work-class", default="")
    p.add_argument("--event-json", default="")
    args = p.parse_args()
    if args.command == "schema":
        print(json.dumps({"schema": SCHEMA, "fields": sorted(ALLOWED_FIELDS)}, sort_keys=True))
        return 0
    if not args.config_dir:
        print(json.dumps({"status": "ERROR", "code": "CONFIG_DIR_REQUIRED"}))
        return 2
    config = pathlib.Path(args.config_dir)
    if args.command == "summary":
        print(json.dumps(summarise(config), sort_keys=True))
        return 0
    event: dict[str, Any] = {}
    if args.event_json:
        event = json.loads(pathlib.Path(args.event_json).read_text(encoding="utf-8"))
    if args.task_id:
        event["task_id_hash"] = task_hash(args.task_id)
    if args.work_class:
        event["work_class"] = args.work_class
    path = append_event(config, event)
    print(json.dumps({"status": "RECORDED", "path": str(path), "schema": SCHEMA}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
