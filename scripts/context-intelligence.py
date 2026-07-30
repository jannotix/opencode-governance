#!/usr/bin/env python3
"""Deterministic local context intelligence for OpenCode Governance 3.4.x."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import stat
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
TRUST_RANK = {
    "PROJECT_AUTHORITATIVE": 4,
    "PROJECT_ADVISORY": 3,
    "WORKSPACE_ADVISORY": 2,
    "EXTERNAL_UNTRUSTED": 1,
}
SUMMARY_FIELDS = {
    "responsibility",
    "public_symbols",
    "entry_points",
    "callers",
    "callees",
    "side_effects",
    "trust_boundaries",
    "tests",
    "documentation",
    "risks",
}
SUMMARY_LIST_FIELDS = SUMMARY_FIELDS - {"responsibility"}
METRIC_FIELDS = {
    "files_considered",
    "files_admitted",
    "files_rejected",
    "retrieval_cycles",
    "loaded_skills",
    "estimated_skill_tokens",
    "cache_hits",
    "cache_misses",
    "cache_invalidations",
    "repeated_file_reads",
    "context_budget_overrides",
    "packet_references",
    "input_tokens",
    "output_tokens",
    "fallback_discarded_tokens",
}
RETRIEVAL_LIST_FIELDS = {
    "candidate_paths",
    "admitted_paths",
    "rejected_paths",
    "dependency_edges",
    "trust_boundaries",
    "tests",
    "context_gaps",
}
STOP_REASONS = {"REFINE", "CONTEXT_SUFFICIENT", "BLOCKED_CONTEXT_GAP"}
TERMINAL_REASONS = STOP_REASONS - {"REFINE"}
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
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


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


def is_link_like(path: pathlib.Path) -> bool:
    if not os.path.lexists(path):
        return False
    try:
        metadata = os.lstat(path)
    except OSError as exc:
        raise ContractError(f"GOVERNANCE_STATE_INSPECTION_FAILED: {path.name}: {exc}") from exc
    reparse = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0)
    attributes = getattr(metadata, "st_file_attributes", 0)
    return stat.S_ISLNK(metadata.st_mode) or bool(reparse and attributes & reparse)


def inside(path: pathlib.Path, parent: pathlib.Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def governance_path(project: pathlib.Path, *parts: str) -> pathlib.Path:
    current = project
    for part in (".ai", *parts):
        current = current / part
        if os.path.lexists(current):
            if is_link_like(current):
                raise ContractError("GOVERNANCE_STATE_LINK_FORBIDDEN")
            resolved = current.resolve()
            if not inside(resolved, project):
                raise ContractError("GOVERNANCE_STATE_PATH_ESCAPE")
    if not inside(current.absolute(), project):
        raise ContractError("GOVERNANCE_STATE_PATH_ESCAPE")
    return current


def task_path(project: pathlib.Path, value: str) -> pathlib.Path:
    return governance_path(project, "tasks", task_id(value))


def default_cache() -> pathlib.Path:
    configured = os.environ.get("OPENCODE_GOVERNANCE_CONTEXT_CACHE")
    if configured:
        return pathlib.Path(configured).expanduser().resolve()
    base = pathlib.Path(os.environ.get("XDG_CACHE_HOME", pathlib.Path.home() / ".cache"))
    return (base / "opencode-governance" / "context-cache").resolve()


def cache_path(value: str | None, project: pathlib.Path) -> pathlib.Path:
    result = pathlib.Path(value).expanduser().resolve() if value else default_cache()
    if result == project or inside(result, project) or inside(project, result):
        raise ContractError("CACHE_ROOT_OVERLAP: cache root must be outside the project")
    return result


def project_id(project: pathlib.Path) -> str:
    marker = "\nGIT_METADATA_PRESENT" if (project / ".git").exists() else ""
    return hash_text(f"PROJECT_IDENTITY_V1\n{os.path.normcase(str(project))}{marker}")


def budget(project: pathlib.Path, value: str) -> dict[str, Any]:
    path = task_path(project, value) / "CONTEXT_BUDGET.json"
    if not path.is_file():
        raise ContractError("CONTEXT_BUDGET_MISSING")
    result = load(path)
    required = {
        "schema",
        "task_id",
        "work_class",
        "max_retrieval_cycles",
        "max_loaded_skills",
        "max_packet_references",
        "max_admitted_paths",
        "max_cycles_global",
        "cache_namespace",
        "cache_root_id",
        "override_requires_reason",
        "created_at",
    }
    if not isinstance(result, dict) or set(result) != required or result.get("schema") != "CONTEXT_BUDGET_V1" or result.get("task_id") != value:
        raise ContractError("CONTEXT_BUDGET_SCHEMA_INVALID")
    return result


def ensure_project_file(project: pathlib.Path, value: str) -> tuple[pathlib.Path, str]:
    candidate = pathlib.Path(value).expanduser()
    if not candidate.is_absolute():
        candidate = project / candidate
    if is_link_like(candidate):
        raise ContractError("FILE_LINK_FORBIDDEN")
    path = candidate.resolve()
    if not inside(path, project):
        raise ContractError("FILE_PATH_ESCAPE")
    if not path.is_file():
        raise ContractError("FILE_PATH_NOT_FOUND")
    relative = path.relative_to(project).as_posix()
    if relative == ".ai" or relative.startswith(".ai/"):
        raise ContractError("CACHE_GOVERNANCE_STATE_FORBIDDEN")
    current = path.parent
    while current != project:
        if is_link_like(current):
            raise ContractError("FILE_LINK_FORBIDDEN")
        current = current.parent
    return path, relative


def string_list(value: Any, field: str, *, nonempty: bool = False) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) or not item.strip() for item in value):
        raise ContractError(f"INVALID_STRING_LIST: {field}")
    if nonempty and not value:
        raise ContractError(f"EMPTY_STRING_LIST: {field}")
    return value


def initialize(args: argparse.Namespace) -> dict[str, Any]:
    project = root(args.project_dir)
    task_id(args.task_id)
    cycles, skills, refs, paths = BUDGETS[args.work_class]
    external = cache_path(args.cache_root, project)
    value = {
        "schema": "CONTEXT_BUDGET_V1",
        "task_id": args.task_id,
        "work_class": args.work_class,
        "max_retrieval_cycles": cycles,
        "max_loaded_skills": skills,
        "max_packet_references": refs,
        "max_admitted_paths": paths,
        "max_cycles_global": 3,
        "cache_namespace": project_id(project),
        "cache_root_id": hash_text(str(external)),
        "override_requires_reason": True,
        "created_at": now(),
    }
    store(task_path(project, args.task_id) / "CONTEXT_BUDGET.json", value)
    return value


def read_cycles(path: pathlib.Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    try:
        return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    except Exception as exc:
        raise ContractError("CONTEXT_RETRIEVAL_INVALID") from exc


def validate_cycle_input(value: Any) -> dict[str, Any]:
    fields = {"query", "reason", *RETRIEVAL_LIST_FIELDS, "stop_reason"}
    if not isinstance(value, dict) or set(value) != fields:
        raise ContractError("RETRIEVAL_RECORD_SCHEMA_INVALID")
    for field in ("query", "reason"):
        if not isinstance(value[field], str) or not value[field].strip():
            raise ContractError(f"RETRIEVAL_RECORD_INVALID: {field}")
    for field in RETRIEVAL_LIST_FIELDS:
        if not isinstance(value[field], list):
            raise ContractError(f"RETRIEVAL_RECORD_INVALID: {field}")
    for field in {"candidate_paths", "admitted_paths"}:
        string_list(value[field], field)
    if value["stop_reason"] not in STOP_REASONS:
        raise ContractError("RETRIEVAL_STOP_REASON_INVALID")
    if value["stop_reason"] == "BLOCKED_CONTEXT_GAP" and not value["context_gaps"]:
        raise ContractError("BLOCKED_CONTEXT_GAP_REASON_REQUIRED")
    return value


def record_cycle(args: argparse.Namespace) -> dict[str, Any]:
    project = root(args.project_dir)
    limits = budget(project, args.task_id)
    if args.cycle < 1 or args.cycle > min(3, int(limits["max_retrieval_cycles"])):
        raise ContractError("RETRIEVAL_CYCLE_LIMIT")
    value = validate_cycle_input(load(pathlib.Path(args.input_json)))
    if len(value["admitted_paths"]) > int(limits["max_admitted_paths"]):
        raise ContractError("CONTEXT_PATH_BUDGET_EXCEEDED")
    destination = task_path(project, args.task_id) / "CONTEXT_RETRIEVAL.jsonl"
    existing = read_cycles(destination)
    if existing and existing[-1].get("stop_reason") in TERMINAL_REASONS:
        raise ContractError("RETRIEVAL_ALREADY_TERMINAL")
    if args.cycle != len(existing) + 1:
        raise ContractError("RETRIEVAL_CYCLE_SEQUENCE_INVALID")
    result = {
        "schema": "CONTEXT_RETRIEVAL_CYCLE_V1",
        "task_id": args.task_id,
        "cycle": args.cycle,
        "recorded_at": now(),
        **value,
    }
    append(destination, result)
    return result


def normalize_skill(raw: Any) -> dict[str, Any]:
    fields = {
        "schema",
        "skill_id",
        "version",
        "content_sha256",
        "source",
        "trust_class",
        "triggers",
        "supported_work_classes",
        "languages",
        "frameworks",
        "required_tools",
        "external_dependencies",
        "conflicts_with",
        "overlaps_with",
        "estimated_context_tokens",
        "sections",
    }
    if not isinstance(raw, dict) or set(raw) != fields or raw.get("schema") != "SKILL_CAPABILITY_MANIFEST_V1":
        raise ContractError("SKILL_MANIFEST_SCHEMA_INVALID")
    task_id(str(raw["skill_id"]))
    if raw["trust_class"] not in TRUST_RANK or not re.fullmatch(r"[0-9a-fA-F]{64}", str(raw["content_sha256"])):
        raise ContractError("SKILL_MANIFEST_IDENTITY_INVALID")
    for name in ("triggers", "supported_work_classes", "languages", "frameworks", "required_tools", "external_dependencies", "conflicts_with", "overlaps_with"):
        string_list(raw[name], name)
    if any(value not in BUDGETS for value in raw["supported_work_classes"]):
        raise ContractError("SKILL_WORK_CLASS_INVALID")
    if not isinstance(raw["estimated_context_tokens"], int) or raw["estimated_context_tokens"] < 0:
        raise ContractError("SKILL_TOKEN_ESTIMATE_INVALID")
    if not isinstance(raw["sections"], list) or any(not isinstance(item, dict) or set(item) != {"id", "heading"} for item in raw["sections"]):
        raise ContractError("SKILL_SECTIONS_INVALID")
    section_ids = [str(item["id"]) for item in raw["sections"]]
    if any(not value.strip() for value in section_ids) or len(section_ids) != len(set(section_ids)):
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
        string_list(criteria[name], name)
    candidates: list[dict[str, Any]] = []
    rejected: list[dict[str, str]] = []
    available = set(criteria["available_tools"])
    required_sections = list(dict.fromkeys(criteria["required_sections"]))
    for item in map(normalize_skill, catalog):
        sid, reason = item["skill_id"], None
        section_ids = {section["id"] for section in item["sections"]}
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
        elif section_ids and any(section not in section_ids for section in required_sections):
            reason = "REQUIRED_SECTION_UNAVAILABLE"
        if reason:
            rejected.append({"skill_id": sid, "reason": reason})
        else:
            candidates.append(item)
    candidates.sort(key=lambda item: (-TRUST_RANK[item["trust_class"]], item["estimated_context_tokens"], item["skill_id"]))
    selected_internal: list[dict[str, Any]] = []
    selected_public: list[dict[str, Any]] = []
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
        section_ids = {section["id"] for section in item["sections"]}
        chosen_sections = required_sections if section_ids and required_sections else (["FULL"] if not section_ids else sorted(section_ids))
        selected_public.append(
            {
                "skill_id": sid,
                "version": item["version"],
                "content_sha256": item["content_sha256"].lower(),
                "source": item["source"],
                "trust_class": item["trust_class"],
                "estimated_context_tokens": item["estimated_context_tokens"],
                "sections": chosen_sections,
                "selection_reason": "HIGHEST_TRUST_NARROW_APPLICABLE_CAPABILITY",
            }
        )
    result = {
        "schema": "SKILL_SELECTION_V1",
        "task_id": args.task_id,
        "work_class": limits["work_class"],
        "max_loaded_skills": limits["max_loaded_skills"],
        "selected": selected_public,
        "rejected": sorted(rejected, key=lambda value: value["skill_id"]),
        "selected_at": now(),
    }
    store(task_path(project, args.task_id) / "SKILL_SELECTION.json", result)
    return result


def cache_info(args: argparse.Namespace) -> tuple[pathlib.Path, str, str, str, str]:
    project = root(args.project_dir)
    path, relative = ensure_project_file(project, args.file_path)
    digest, rel_hash, skill_hash = hash_file(path), hash_text(relative), hash_text(args.skill_context)
    material = canonical(
        {
            "schema": "CONTENT_SUMMARY_CACHE_KEY_V1",
            "project": project_id(project),
            "relative_path_hash": rel_hash,
            "file_sha256": digest,
            "summary_schema": "CONTENT_SUMMARY_V1",
            "parser_version": args.parser_version,
            "skill_context_hash": skill_hash,
        }
    )
    key = hash_text(material)
    destination = cache_path(args.cache_root, project) / project_id(project) / "entries" / f"{key}.json"
    return destination, digest, rel_hash, skill_hash, args.parser_version


def validate_summary(summary: Any) -> dict[str, Any]:
    if not isinstance(summary, dict) or set(summary) != SUMMARY_FIELDS:
        raise ContractError("CONTENT_SUMMARY_FIELDS_INVALID")
    if not isinstance(summary["responsibility"], str) or not summary["responsibility"].strip():
        raise ContractError("CONTENT_SUMMARY_FIELDS_INVALID")
    for field in SUMMARY_LIST_FIELDS:
        string_list(summary[field], field)
    return summary


def cache_put(args: argparse.Namespace) -> dict[str, Any]:
    destination, digest, rel_hash, skill_hash, parser_version = cache_info(args)
    summary = validate_summary(load(pathlib.Path(args.input_json)))
    store(
        destination,
        {
            "schema": "CONTENT_SUMMARY_CACHE_ENTRY_V1",
            "file_sha256": digest,
            "relative_path_hash": rel_hash,
            "parser_version": parser_version,
            "skill_context_hash": skill_hash,
            "summary": summary,
            "stored_at": now(),
        },
    )
    return {"schema": "CONTENT_SUMMARY_CACHE_RESULT_V1", "status": "PUT", "cache_key": destination.stem, "file_sha256": digest}


def cache_get(args: argparse.Namespace) -> dict[str, Any]:
    destination, digest, rel_hash, skill_hash, parser_version = cache_info(args)
    if not destination.is_file():
        return {"schema": "CONTENT_SUMMARY_CACHE_RESULT_V1", "status": "MISS", "file_sha256": digest}
    try:
        entry = load(destination)
        fields = {"schema", "file_sha256", "relative_path_hash", "parser_version", "skill_context_hash", "summary", "stored_at"}
        if not isinstance(entry, dict) or set(entry) != fields:
            raise ValueError
        if (
            entry["schema"] != "CONTENT_SUMMARY_CACHE_ENTRY_V1"
            or entry["file_sha256"] != digest
            or entry["relative_path_hash"] != rel_hash
            or entry["parser_version"] != parser_version
            or entry["skill_context_hash"] != skill_hash
        ):
            raise ValueError
        summary = validate_summary(entry["summary"])
    except Exception:
        return {"schema": "CONTENT_SUMMARY_CACHE_RESULT_V1", "status": "MISS", "file_sha256": digest, "reason": "CACHE_INVALID"}
    return {"schema": "CONTENT_SUMMARY_CACHE_RESULT_V1", "status": "HIT", "file_sha256": digest, "summary": summary}


def metrics(args: argparse.Namespace) -> dict[str, Any]:
    project = root(args.project_dir)
    task_id(args.task_id)
    values = load(pathlib.Path(args.input_json))
    if not isinstance(values, dict) or set(values) != METRIC_FIELDS:
        raise ContractError("CONTEXT_METRICS_FIELDS_INVALID")
    for name, value in values.items():
        if name.endswith("tokens") and value == "UNAVAILABLE":
            continue
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            raise ContractError(f"CONTEXT_METRIC_INVALID: {name}")
    result = {"schema": "CONTEXT_METRICS_V1", "task_id": args.task_id, "recorded_at": now(), **values}
    append(governance_path(project, "metrics", "CONTEXT_METRICS.jsonl"), result)
    append(task_path(project, args.task_id) / "CONTEXT_METRICS.jsonl", result)
    return result


def validate(args: argparse.Namespace) -> dict[str, Any]:
    project = root(args.project_dir)
    limits = budget(project, args.task_id)
    directory, errors = task_path(project, args.task_id), []
    retrieval = directory / "CONTEXT_RETRIEVAL.jsonl"
    try:
        cycles = read_cycles(retrieval)
    except ContractError:
        cycles, errors = [], ["CONTEXT_RETRIEVAL_INVALID"]
    if len(cycles) > min(3, int(limits["max_retrieval_cycles"])):
        errors.append("RETRIEVAL_CYCLE_LIMIT")
    if [item.get("cycle") for item in cycles] != list(range(1, len(cycles) + 1)):
        errors.append("RETRIEVAL_CYCLE_SEQUENCE_INVALID")
    for index, item in enumerate(cycles):
        if item.get("schema") != "CONTEXT_RETRIEVAL_CYCLE_V1" or item.get("task_id") != args.task_id or item.get("stop_reason") not in STOP_REASONS:
            errors.append("CONTEXT_RETRIEVAL_SCHEMA_INVALID")
            break
        if len(item.get("admitted_paths", [])) > int(limits["max_admitted_paths"]):
            errors.append("CONTEXT_PATH_BUDGET_EXCEEDED")
        if index < len(cycles) - 1 and item.get("stop_reason") in TERMINAL_REASONS:
            errors.append("RETRIEVAL_ALREADY_TERMINAL")
    if not cycles or cycles[-1].get("stop_reason") not in TERMINAL_REASONS:
        errors.append("TERMINAL_STATE_REQUIRED")
    elif cycles[-1].get("stop_reason") == "BLOCKED_CONTEXT_GAP":
        errors.append("BLOCKED_CONTEXT_GAP")
    selection = directory / "SKILL_SELECTION.json"
    if selection.exists():
        selected = load(selection)
        if selected.get("schema") != "SKILL_SELECTION_V1" or selected.get("task_id") != args.task_id or selected.get("work_class") != limits["work_class"]:
            errors.append("SKILL_SELECTION_SCHEMA_INVALID")
        elif len(selected.get("selected", [])) > int(limits["max_loaded_skills"]):
            errors.append("SKILL_BUDGET_EXCEEDED")
        elif any(not item.get("sections") for item in selected.get("selected", [])):
            errors.append("SKILL_SECTION_SELECTION_REQUIRED")
    return {"schema": "CONTEXT_TASK_VALIDATION_V1", "task_id": args.task_id, "valid": not errors, "errors": sorted(set(errors))}


def build_parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(prog="context-intelligence")
    commands = result.add_subparsers(dest="action", required=True)

    def common(command: argparse.ArgumentParser, task: bool = False) -> None:
        command.add_argument("--project-dir", required=True)
        if task:
            command.add_argument("--task-id", required=True)

    command = commands.add_parser("initialize-budget")
    common(command, True)
    command.add_argument("--work-class", choices=sorted(BUDGETS), required=True)
    command.add_argument("--cache-root")
    command.set_defaults(handler=initialize)

    command = commands.add_parser("record-cycle")
    common(command, True)
    command.add_argument("--cycle", type=int, required=True)
    command.add_argument("--input-json", required=True)
    command.set_defaults(handler=record_cycle)

    command = commands.add_parser("select-skills")
    common(command, True)
    command.add_argument("--catalog", required=True)
    command.add_argument("--input-json", required=True)
    command.set_defaults(handler=select_skills)

    for name, handler, write_input in (("cache-get", cache_get, False), ("cache-put", cache_put, True)):
        command = commands.add_parser(name)
        common(command)
        command.add_argument("--file-path", required=True)
        command.add_argument("--cache-root")
        command.add_argument("--parser-version", default="1")
        command.add_argument("--skill-context", default="")
        if write_input:
            command.add_argument("--input-json", required=True)
        command.set_defaults(handler=handler)

    command = commands.add_parser("record-metrics")
    common(command, True)
    command.add_argument("--input-json", required=True)
    command.set_defaults(handler=metrics)

    command = commands.add_parser("validate-task")
    common(command, True)
    command.set_defaults(handler=validate)
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
