#!/usr/bin/env python3
"""Deterministic local context intelligence for OpenCode Governance 3.4."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import sys
from datetime import datetime, timezone
from typing import Any

BUDGETS = {
    "PATCH": (1, 1, 20, 20),
    "BOUNDED_FEATURE": (2, 2, 40, 40),
    "MAJOR_FEATURE": (3, 3, 80, 80),
    "EXISTING_PRODUCT_EVOLUTION": (3, 3, 100, 100),
    "NEW_PRODUCT": (3, 3, 120, 120),
    "HIGH_RISK_CHANGE": (3, 3, 120, 120),
}
TRUST_RANK = {"PROJECT_AUTHORITATIVE": 4, "PROJECT_ADVISORY": 3, "WORKSPACE_ADVISORY": 2, "EXTERNAL_UNTRUSTED": 1}
SUMMARY_FIELDS = {"responsibility", "public_symbols", "entry_points", "callers", "callees", "side_effects", "trust_boundaries", "tests", "documentation", "risks"}
METRIC_FIELDS = {"files_considered", "files_admitted", "files_rejected", "retrieval_cycles", "loaded_skills", "estimated_skill_tokens", "cache_hits", "cache_misses", "cache_invalidations", "repeated_file_reads", "context_budget_overrides", "packet_references", "input_tokens", "output_tokens", "fallback_discarded_tokens"}
TASK_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$")


class ContractError(RuntimeError):
    pass


def now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def hash_text(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def hash_file(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path: pathlib.Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise ContractError(f"INVALID_JSON: {path.name}: {exc}") from exc


def store(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def append(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(canonical(value) + "\n")


def task_id(value: str) -> str:
    if not TASK_RE.fullmatch(value):
        raise ContractError("INVALID_TASK_ID: use 1-128 ASCII letters, digits, underscore or hyphen")
    return value


def root(value: str) -> pathlib.Path:
    result = pathlib.Path(value).expanduser().resolve()
    if not result.is_dir():
        raise ContractError("INVALID_PROJECT_DIR: directory does not exist")
    return result


def task_path(project: pathlib.Path, value: str) -> pathlib.Path:
    task_id(value)
    base = (project / ".ai" / "tasks").resolve()
    result = (base / value).resolve()
    if result.parent != base:
        raise ContractError("TASK_PATH_ESCAPE")
    return result


def default_cache() -> pathlib.Path:
    if os.environ.get("OPENCODE_GOVERNANCE_CONTEXT_CACHE"):
        return pathlib.Path(os.environ["OPENCODE_GOVERNANCE_CONTEXT_CACHE"]).expanduser().resolve()
    base = pathlib.Path(os.environ.get("XDG_CACHE_HOME", pathlib.Path.home() / ".cache"))
    return (base / "opencode-governance" / "context-cache").resolve()


def cache_path(value: str | None, project: pathlib.Path) -> pathlib.Path:
    result = pathlib.Path(value).expanduser().resolve() if value else default_cache()
    if result == project or project in result.parents or result in project.parents:
        raise ContractError("CACHE_ROOT_OVERLAP: cache root must be outside the project")
    return result


def project_id(project: pathlib.Path) -> str:
    marker = "\nGIT_METADATA_PRESENT" if (project / ".git").exists() else ""
    return hash_text(f"PROJECT_IDENTITY_V1\n{os.path.normcase(str(project))}{marker}")


def budget(project: pathlib.Path, value: str) -> dict[str, Any]:
    result = load(task_path(project, value) / "CONTEXT_BUDGET.json")
    if result.get("schema") != "CONTEXT_BUDGET_V1":
        raise ContractError("CONTEXT_BUDGET_SCHEMA_INVALID")
    return result


def project_file(project: pathlib.Path, value: str) -> tuple[pathlib.Path, str]:
    path = pathlib.Path(value).expanduser().resolve()
    try:
        relative = path.relative_to(project).as_posix()
    except ValueError as exc:
        raise ContractError("FILE_PATH_ESCAPE") from exc
    if not path.is_file():
        raise ContractError("FILE_PATH_NOT_FOUND")
    if relative == ".ai" or relative.startswith(".ai/"):
        raise ContractError("CACHE_GOVERNANCE_STATE_FORBIDDEN")
    return path, relative


def initialize(args: argparse.Namespace) -> dict[str, Any]:
    project = root(args.project_dir)
    task_id(args.task_id)
    cycles, skills, refs, paths = BUDGETS[args.work_class]
    external = cache_path(args.cache_root, project)
    value = {"schema": "CONTEXT_BUDGET_V1", "task_id": args.task_id, "work_class": args.work_class, "max_retrieval_cycles": cycles, "max_loaded_skills": skills, "max_packet_references": refs, "max_admitted_paths": paths, "max_cycles_global": 3, "cache_namespace": project_id(project), "cache_root_id": hash_text(str(external)), "override_requires_reason": True, "created_at": now()}
    store(task_path(project, args.task_id) / "CONTEXT_BUDGET.json", value)
    return value


def record_cycle(args: argparse.Namespace) -> dict[str, Any]:
    project = root(args.project_dir)
    limits = budget(project, args.task_id)
    if args.cycle < 1 or args.cycle > min(3, int(limits["max_retrieval_cycles"])):
        raise ContractError("RETRIEVAL_CYCLE_LIMIT")
    value = load(pathlib.Path(args.input_json))
    fields = {"query", "reason", "candidate_paths", "admitted_paths", "rejected_paths", "dependency_edges", "trust_boundaries", "tests", "context_gaps", "stop_reason"}
    if not isinstance(value, dict) or set(value) != fields:
        raise ContractError("RETRIEVAL_RECORD_SCHEMA_INVALID")
    if len(value["admitted_paths"]) > int(limits["max_admitted_paths"]):
        raise ContractError("CONTEXT_PATH_BUDGET_EXCEEDED")
    destination = task_path(project, args.task_id) / "CONTEXT_RETRIEVAL.jsonl"
    existing = [json.loads(line) for line in destination.read_text(encoding="utf-8").splitlines() if line.strip()] if destination.exists() else []
    if args.cycle != len(existing) + 1:
        raise ContractError("RETRIEVAL_CYCLE_SEQUENCE_INVALID")
    result = {"schema": "CONTEXT_RETRIEVAL_CYCLE_V1", "task_id": args.task_id, "cycle": args.cycle, "recorded_at": now(), **value}
    append(destination, result)
    return result


def strings(value: Any, field: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise ContractError(f"SKILL_MANIFEST_INVALID: {field}")
    return value


def skill(raw: Any) -> dict[str, Any]:
    fields = {"schema", "skill_id", "version", "content_sha256", "source", "trust_class", "triggers", "supported_work_classes", "languages", "frameworks", "required_tools", "external_dependencies", "conflicts_with", "overlaps_with", "estimated_context_tokens", "sections"}
    if not isinstance(raw, dict) or set(raw) != fields or raw.get("schema") != "SKILL_CAPABILITY_MANIFEST_V1":
        raise ContractError("SKILL_MANIFEST_SCHEMA_INVALID")
    task_id(str(raw["skill_id"]))
    if raw["trust_class"] not in TRUST_RANK or not re.fullmatch(r"[0-9a-fA-F]{64}", str(raw["content_sha256"])):
        raise ContractError("SKILL_MANIFEST_IDENTITY_INVALID")
    for name in ("triggers", "supported_work_classes", "languages", "frameworks", "required_tools", "external_dependencies", "conflicts_with", "overlaps_with"):
        strings(raw[name], name)
    if not isinstance(raw["estimated_context_tokens"], int) or raw["estimated_context_tokens"] < 0:
        raise ContractError("SKILL_TOKEN_ESTIMATE_INVALID")
    if not isinstance(raw["sections"], list) or any(not isinstance(item, dict) or set(item) != {"id", "heading"} for item in raw["sections"]):
        raise ContractError("SKILL_SECTIONS_INVALID")
    return raw


def applicable(values: list[str], requested: list[str]) -> bool:
    return not values or bool(set(values) & set(requested))


def select_skills(args: argparse.Namespace) -> dict[str, Any]:
    project = root(args.project_dir)
    limits = budget(project, args.task_id)
    catalog, criteria = load(pathlib.Path(args.catalog)), load(pathlib.Path(args.input_json))
    fields = {"triggers", "languages", "frameworks", "required_sections", "available_tools"}
    if not isinstance(catalog, list) or not isinstance(criteria, dict) or set(criteria) != fields:
        raise ContractError("SKILL_SELECTION_INPUT_INVALID")
    for name in fields:
        strings(criteria[name], name)
    candidates, rejected = [], []
    available = set(criteria["available_tools"])
    for item in map(skill, catalog):
        sid, reason = item["skill_id"], None
        if item["supported_work_classes"] and limits["work_class"] not in item["supported_work_classes"]:
            reason = "WORK_CLASS_NOT_APPLICABLE"
        elif not applicable(item["triggers"], criteria["triggers"]):
            reason = "TRIGGER_NOT_APPLICABLE"
        elif not applicable(item["languages"], criteria["languages"]):
            reason = "LANGUAGE_NOT_APPLICABLE"
        elif not applicable(item["frameworks"], criteria["frameworks"]):
            reason = "FRAMEWORK_NOT_APPLICABLE"
        elif item["external_dependencies"]:
            reason = "EXTERNAL_DEPENDENCY_UNAVAILABLE"
        elif not set(item["required_tools"]).issubset(available):
            reason = "REQUIRED_TOOL_UNAVAILABLE"
        if reason:
            rejected.append({"skill_id": sid, "reason": reason})
        else:
            candidates.append(item)
    candidates.sort(key=lambda item: (-TRUST_RANK[item["trust_class"]], item["estimated_context_tokens"], item["skill_id"]))
    selected_internal, selected_public = [], []
    for item in candidates:
        sid = item["skill_id"]
        if len(selected_internal) >= int(limits["max_loaded_skills"]):
            rejected.append({"skill_id": sid, "reason": "SKILL_BUDGET_EXCEEDED"})
            continue
        ids = {chosen["skill_id"] for chosen in selected_internal}
        conflict = bool(ids & set(item["conflicts_with"])) or any(sid in set(chosen["conflicts_with"]) for chosen in selected_internal)
        overlap = bool(ids & set(item["overlaps_with"])) or any(sid in set(chosen["overlaps_with"]) for chosen in selected_internal)
        if conflict or overlap:
            rejected.append({"skill_id": sid, "reason": "SKILL_CONFLICT" if conflict else "OVERLAP_DEDUPLICATED"})
            continue
        selected_internal.append(item)
        section_ids = [section["id"] for section in item["sections"]]
        chosen_sections = [value for value in criteria["required_sections"] if value in section_ids] if section_ids else ["FULL"]
        selected_public.append({"skill_id": sid, "version": item["version"], "content_sha256": item["content_sha256"].lower(), "source": item["source"], "trust_class": item["trust_class"], "estimated_context_tokens": item["estimated_context_tokens"], "sections": chosen_sections, "selection_reason": "HIGHEST_TRUST_NARROW_APPLICABLE_CAPABILITY"})
    result = {"schema": "SKILL_SELECTION_V1", "task_id": args.task_id, "work_class": limits["work_class"], "max_loaded_skills": limits["max_loaded_skills"], "selected": selected_public, "rejected": sorted(rejected, key=lambda value: value["skill_id"]), "selected_at": now()}
    store(task_path(project, args.task_id) / "SKILL_SELECTION.json", result)
    return result


def cache_info(args: argparse.Namespace) -> tuple[pathlib.Path, str, str, str]:
    project = root(args.project_dir)
    path, relative = project_file(project, args.file_path)
    digest, rel_hash, skill_hash = hash_file(path), hash_text(relative), hash_text(args.skill_context)
    material = canonical({"schema": "CONTENT_SUMMARY_CACHE_KEY_V1", "project": project_id(project), "relative_path_hash": rel_hash, "file_sha256": digest, "summary_schema": "CONTENT_SUMMARY_V1", "parser_version": args.parser_version, "skill_context_hash": skill_hash})
    key = hash_text(material)
    return cache_path(args.cache_root, project) / project_id(project) / "entries" / f"{key}.json", digest, rel_hash, skill_hash


def cache_put(args: argparse.Namespace) -> dict[str, Any]:
    destination, digest, rel_hash, skill_hash = cache_info(args)
    summary = load(pathlib.Path(args.input_json))
    if not isinstance(summary, dict) or set(summary) != SUMMARY_FIELDS or any(not isinstance(summary[name], (str, list)) for name in SUMMARY_FIELDS):
        raise ContractError("CONTENT_SUMMARY_FIELDS_INVALID")
    store(destination, {"schema": "CONTENT_SUMMARY_CACHE_ENTRY_V1", "file_sha256": digest, "relative_path_hash": rel_hash, "parser_version": args.parser_version, "skill_context_hash": skill_hash, "summary": summary, "stored_at": now()})
    return {"schema": "CONTENT_SUMMARY_CACHE_RESULT_V1", "status": "PUT", "cache_key": destination.stem, "file_sha256": digest}


def cache_get(args: argparse.Namespace) -> dict[str, Any]:
    destination, digest, _, _ = cache_info(args)
    if not destination.is_file():
        return {"schema": "CONTENT_SUMMARY_CACHE_RESULT_V1", "status": "MISS", "file_sha256": digest}
    try:
        entry = load(destination)
        if entry.get("schema") != "CONTENT_SUMMARY_CACHE_ENTRY_V1" or entry.get("file_sha256") != digest or set(entry.get("summary", {})) != SUMMARY_FIELDS:
            raise ValueError
    except Exception:
        return {"schema": "CONTENT_SUMMARY_CACHE_RESULT_V1", "status": "MISS", "file_sha256": digest, "reason": "CACHE_INVALID"}
    return {"schema": "CONTENT_SUMMARY_CACHE_RESULT_V1", "status": "HIT", "file_sha256": digest, "summary": entry["summary"]}


def metrics(args: argparse.Namespace) -> dict[str, Any]:
    project = root(args.project_dir)
    task_id(args.task_id)
    values = load(pathlib.Path(args.input_json))
    if not isinstance(values, dict) or set(values) != METRIC_FIELDS:
        raise ContractError("CONTEXT_METRICS_FIELDS_INVALID")
    for name, value in values.items():
        if name.endswith("tokens") and value == "UNAVAILABLE":
            continue
        if not isinstance(value, int) or value < 0:
            raise ContractError(f"CONTEXT_METRIC_INVALID: {name}")
    result = {"schema": "CONTEXT_METRICS_V1", "task_id": args.task_id, "recorded_at": now(), **values}
    append(project / ".ai" / "metrics" / "CONTEXT_METRICS.jsonl", result)
    append(task_path(project, args.task_id) / "CONTEXT_METRICS.jsonl", result)
    return result


def validate(args: argparse.Namespace) -> dict[str, Any]:
    project = root(args.project_dir)
    limits = budget(project, args.task_id)
    directory, errors = task_path(project, args.task_id), []
    retrieval = directory / "CONTEXT_RETRIEVAL.jsonl"
    try:
        cycles = [json.loads(line) for line in retrieval.read_text(encoding="utf-8").splitlines() if line.strip()] if retrieval.exists() else []
    except Exception:
        cycles, errors = [], ["CONTEXT_RETRIEVAL_INVALID"]
    if len(cycles) > min(3, int(limits["max_retrieval_cycles"])):
        errors.append("RETRIEVAL_CYCLE_LIMIT")
    if [item.get("cycle") for item in cycles] != list(range(1, len(cycles) + 1)):
        errors.append("RETRIEVAL_CYCLE_SEQUENCE_INVALID")
    selection = directory / "SKILL_SELECTION.json"
    if selection.exists() and len(load(selection).get("selected", [])) > int(limits["max_loaded_skills"]):
        errors.append("SKILL_BUDGET_EXCEEDED")
    return {"schema": "CONTEXT_TASK_VALIDATION_V1", "task_id": args.task_id, "valid": not errors, "errors": errors}


def build_parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(prog="context-intelligence")
    commands = result.add_subparsers(dest="action", required=True)

    def common(command: argparse.ArgumentParser, task=False):
        command.add_argument("--project-dir", required=True)
        if task:
            command.add_argument("--task-id", required=True)

    command = commands.add_parser("initialize-budget"); common(command, True); command.add_argument("--work-class", choices=sorted(BUDGETS), required=True); command.add_argument("--cache-root"); command.set_defaults(handler=initialize)
    command = commands.add_parser("record-cycle"); common(command, True); command.add_argument("--cycle", type=int, required=True); command.add_argument("--input-json", required=True); command.set_defaults(handler=record_cycle)
    command = commands.add_parser("select-skills"); common(command, True); command.add_argument("--catalog", required=True); command.add_argument("--input-json", required=True); command.set_defaults(handler=select_skills)
    for name, handler, write in (("cache-get", cache_get, False), ("cache-put", cache_put, True)):
        command = commands.add_parser(name); common(command); command.add_argument("--file-path", required=True); command.add_argument("--cache-root"); command.add_argument("--parser-version", default="1"); command.add_argument("--skill-context", default="")
        if write: command.add_argument("--input-json", required=True)
        command.set_defaults(handler=handler)
    command = commands.add_parser("record-metrics"); common(command, True); command.add_argument("--input-json", required=True); command.set_defaults(handler=metrics)
    command = commands.add_parser("validate-task"); common(command, True); command.set_defaults(handler=validate)
    return result


def main() -> int:
    try:
        args = build_parser().parse_args()
        print(json.dumps(args.handler(args), ensure_ascii=False, separators=(",", ":")))
        return 0
    except ContractError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except Exception as exc:
        print(f"CONTEXT_INTELLIGENCE_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
