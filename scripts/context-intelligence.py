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
TASK_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$")


class ContractError(RuntimeError):
    pass


def now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_text(value: str) -> str:
    return sha256_bytes(value.encode("utf-8"))


def read_json(path: pathlib.Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise ContractError(f"INVALID_JSON: {path.name}: {exc}") from exc


def write_json(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def write_jsonl(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(canonical_json(value) + "\n")


def validate_task_id(task_id: str) -> str:
    if not TASK_RE.fullmatch(task_id):
        raise ContractError("INVALID_TASK_ID: use 1-128 ASCII letters, digits, underscore or hyphen")
    return task_id


def project_root(value: str) -> pathlib.Path:
    root = pathlib.Path(value).expanduser().resolve()
    if not root.is_dir():
        raise ContractError("INVALID_PROJECT_DIR: directory does not exist")
    return root


def task_dir(root: pathlib.Path, task_id: str) -> pathlib.Path:
    validate_task_id(task_id)
    base = (root / ".ai" / "tasks").resolve()
    target = (base / task_id).resolve()
    if base != target.parent:
        raise ContractError("TASK_PATH_ESCAPE")
    return target


def default_cache_root() -> pathlib.Path:
    configured = os.environ.get("OPENCODE_GOVERNANCE_CONTEXT_CACHE")
    if configured:
        return pathlib.Path(configured).expanduser().resolve()
    base = os.environ.get("XDG_CACHE_HOME")
    if base:
        return (pathlib.Path(base) / "opencode-governance" / "context-cache").resolve()
    return (pathlib.Path.home() / ".cache" / "opencode-governance" / "context-cache").resolve()


def cache_root(value: str | None, root: pathlib.Path) -> pathlib.Path:
    cache = pathlib.Path(value).expanduser().resolve() if value else default_cache_root()
    if cache == root or root in cache.parents or cache in root.parents:
        raise ContractError("CACHE_ROOT_OVERLAP: cache root must be outside the project")
    return cache


def project_identity(root: pathlib.Path) -> str:
    identity = f"PROJECT_IDENTITY_V1\n{os.path.normcase(str(root))}"
    git_dir = root / ".git"
    if git_dir.exists():
        identity += "\nGIT_METADATA_PRESENT"
    return sha256_text(identity)


def relative_file(root: pathlib.Path, value: str) -> tuple[pathlib.Path, str]:
    path = pathlib.Path(value).expanduser().resolve()
    try:
        relative = path.relative_to(root)
    except ValueError as exc:
        raise ContractError("FILE_PATH_ESCAPE") from exc
    if not path.is_file():
        raise ContractError("FILE_PATH_NOT_FOUND")
    rel = relative.as_posix()
    if rel == ".ai" or rel.startswith(".ai/"):
        raise ContractError("CACHE_GOVERNANCE_STATE_FORBIDDEN")
    return path, rel


def load_budget(root: pathlib.Path, task_id: str) -> dict[str, Any]:
    path = task_dir(root, task_id) / "CONTEXT_BUDGET.json"
    if not path.is_file():
        raise ContractError("CONTEXT_BUDGET_MISSING")
    budget = read_json(path)
    if budget.get("schema") != "CONTEXT_BUDGET_V1":
        raise ContractError("CONTEXT_BUDGET_SCHEMA_INVALID")
    return budget


def action_initialize_budget(args: argparse.Namespace) -> dict[str, Any]:
    root = project_root(args.project_dir)
    validate_task_id(args.task_id)
    if args.work_class not in BUDGETS:
        raise ContractError("INVALID_WORK_CLASS")
    cycles, skills, refs, paths = BUDGETS[args.work_class]
    cache = cache_root(args.cache_root, root)
    value = {
        "schema": "CONTEXT_BUDGET_V1",
        "task_id": args.task_id,
        "work_class": args.work_class,
        "max_retrieval_cycles": cycles,
        "max_loaded_skills": skills,
        "max_packet_references": refs,
        "max_admitted_paths": paths,
        "max_cycles_global": 3,
        "cache_namespace": project_identity(root),
        "cache_root_id": sha256_text(str(cache)),
        "override_requires_reason": True,
        "created_at": now(),
    }
    write_json(task_dir(root, args.task_id) / "CONTEXT_BUDGET.json", value)
    return value


def action_record_cycle(args: argparse.Namespace) -> dict[str, Any]:
    root = project_root(args.project_dir)
    budget = load_budget(root, args.task_id)
    cycle = int(args.cycle)
    if cycle < 1 or cycle > min(3, int(budget["max_retrieval_cycles"])):
        raise ContractError("RETRIEVAL_CYCLE_LIMIT")
    record = read_json(pathlib.Path(args.input_json))
    required = {
        "query",
        "reason",
        "candidate_paths",
        "admitted_paths",
        "rejected_paths",
        "dependency_edges",
        "trust_boundaries",
        "tests",
        "context_gaps",
        "stop_reason",
    }
    if not isinstance(record, dict) or set(record) != required:
        raise ContractError("RETRIEVAL_RECORD_SCHEMA_INVALID")
    if len(record["admitted_paths"]) > int(budget["max_admitted_paths"]):
        raise ContractError("CONTEXT_PATH_BUDGET_EXCEEDED")
    path = task_dir(root, args.task_id) / "CONTEXT_RETRIEVAL.jsonl"
    existing = []
    if path.is_file():
        existing = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if cycle != len(existing) + 1:
        raise ContractError("RETRIEVAL_CYCLE_SEQUENCE_INVALID")
    value = {"schema": "CONTEXT_RETRIEVAL_CYCLE_V1", "task_id": args.task_id, "cycle": cycle, "recorded_at": now(), **record}
    write_jsonl(path, value)
    return value


def list_of_strings(value: Any, field: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise ContractError(f"SKILL_MANIFEST_INVALID: {field}")
    return value


def validate_skill(skill: Any) -> dict[str, Any]:
    if not isinstance(skill, dict) or skill.get("schema") != "SKILL_CAPABILITY_MANIFEST_V1":
        raise ContractError("SKILL_MANIFEST_SCHEMA_INVALID")
    required = {
        "schema", "skill_id", "version", "content_sha256", "source", "trust_class", "triggers",
        "supported_work_classes", "languages", "frameworks", "required_tools", "external_dependencies",
        "conflicts_with", "overlaps_with", "estimated_context_tokens", "sections",
    }
    if set(skill) != required:
        raise ContractError(f"SKILL_MANIFEST_FIELDS_INVALID: {skill.get('skill_id', 'UNKNOWN')}")
    if not TASK_RE.fullmatch(str(skill["skill_id"])):
        raise ContractError("SKILL_ID_INVALID")
    if skill["trust_class"] not in TRUST_RANK:
        raise ContractError("SKILL_TRUST_CLASS_INVALID")
    if not re.fullmatch(r"[0-9a-fA-F]{64}", str(skill["content_sha256"])):
        raise ContractError("SKILL_CONTENT_HASH_INVALID")
    for field in ("triggers", "supported_work_classes", "languages", "frameworks", "required_tools", "external_dependencies", "conflicts_with", "overlaps_with"):
        list_of_strings(skill[field], field)
    if not isinstance(skill["estimated_context_tokens"], int) or skill["estimated_context_tokens"] < 0:
        raise ContractError("SKILL_TOKEN_ESTIMATE_INVALID")
    if not isinstance(skill["sections"], list):
        raise ContractError("SKILL_SECTIONS_INVALID")
    for section in skill["sections"]:
        if not isinstance(section, dict) or set(section) != {"id", "heading"} or not section["id"]:
            raise ContractError("SKILL_SECTION_INVALID")
    return skill


def intersects(candidate: list[str], requested: list[str]) -> bool:
    return not candidate or bool(set(candidate) & set(requested))


def action_select_skills(args: argparse.Namespace) -> dict[str, Any]:
    root = project_root(args.project_dir)
    budget = load_budget(root, args.task_id)
    catalog = read_json(pathlib.Path(args.catalog))
    criteria = read_json(pathlib.Path(args.input_json))
    if not isinstance(catalog, list) or not isinstance(criteria, dict):
        raise ContractError("SKILL_SELECTION_INPUT_INVALID")
    expected_criteria = {"triggers", "languages", "frameworks", "required_sections", "available_tools"}
    if set(criteria) != expected_criteria:
        raise ContractError("SKILL_SELECTION_CRITERIA_INVALID")
    for field in expected_criteria:
        list_of_strings(criteria[field], field)
    available_tools = set(criteria["available_tools"])
    accepted: list[dict[str, Any]] = []
    rejected: list[dict[str, str]] = []
    candidates: list[dict[str, Any]] = []
    work_class = str(budget["work_class"])
    for raw in catalog:
        skill = validate_skill(raw)
        skill_id = skill["skill_id"]
        if skill["supported_work_classes"] and work_class not in skill["supported_work_classes"]:
            rejected.append({"skill_id": skill_id, "reason": "WORK_CLASS_NOT_APPLICABLE"})
        elif not intersects(skill["triggers"], criteria["triggers"]):
            rejected.append({"skill_id": skill_id, "reason": "TRIGGER_NOT_APPLICABLE"})
        elif not intersects(skill["languages"], criteria["languages"]):
            rejected.append({"skill_id": skill_id, "reason": "LANGUAGE_NOT_APPLICABLE"})
        elif not intersects(skill["frameworks"], criteria["frameworks"]):
            rejected.append({"skill_id": skill_id, "reason": "FRAMEWORK_NOT_APPLICABLE"})
        elif skill["external_dependencies"]:
            rejected.append({"skill_id": skill_id, "reason": "EXTERNAL_DEPENDENCY_UNAVAILABLE"})
        elif not set(skill["required_tools"]).issubset(available_tools):
            rejected.append({"skill_id": skill_id, "reason": "REQUIRED_TOOL_UNAVAILABLE"})
        else:
            candidates.append(skill)
    candidates.sort(key=lambda item: (-TRUST_RANK[item["trust_class"]], item["estimated_context_tokens"], item["skill_id"]))
    max_skills = int(budget["max_loaded_skills"])
    for skill in candidates:
        if len(accepted) >= max_skills:
            rejected.append({"skill_id": skill["skill_id"], "reason": "SKILL_BUDGET_EXCEEDED"})
            continue
        selected_ids = {item["skill_id"] for item in accepted}
        overlap = bool(selected_ids & set(skill["overlaps_with"])) or any(skill["skill_id"] in set(item["overlaps_with"]) for item in accepted)
        conflict = bool(selected_ids & set(skill["conflicts_with"])) or any(skill["skill_id"] in set(item["conflicts_with"]) for item in accepted)
        if conflict:
            rejected.append({"skill_id": skill["skill_id"], "reason": "SKILL_CONFLICT"})
            continue
        if overlap:
            rejected.append({"skill_id": skill["skill_id"], "reason": "OVERLAP_DEDUPLICATED"})
            continue
        section_ids = [section["id"] for section in skill["sections"]]
        requested = criteria["required_sections"]
        sections = [value for value in requested if value in section_ids] if section_ids else ["FULL"]
        accepted.append({
            "skill_id": skill["skill_id"],
            "version": skill["version"],
            "content_sha256": skill["content_sha256"].lower(),
            "source": skill["source"],
            "trust_class": skill["trust_class"],
            "estimated_context_tokens": skill["estimated_context_tokens"],
            "sections": sections,
            "selection_reason": "HIGHEST_TRUST_NARROW_APPLICABLE_CAPABILITY",
        })
    value = {
        "schema": "SKILL_SELECTION_V1",
        "task_id": args.task_id,
        "work_class": work_class,
        "max_loaded_skills": max_skills,
        "selected": accepted,
        "rejected": sorted(rejected, key=lambda item: item["skill_id"]),
        "selected_at": now(),
    }
    write_json(task_dir(root, args.task_id) / "SKILL_SELECTION.json", value)
    return value


def cache_key(root: pathlib.Path, file_path: str, cache_value: str | None, parser_version: str, skill_context: str) -> tuple[pathlib.Path, str, str]:
    path, relative = relative_file(root, file_path)
    cache = cache_root(cache_value, root)
    file_hash = sha256_bytes(path.read_bytes())
    key_material = canonical_json({
        "schema": "CONTENT_SUMMARY_CACHE_KEY_V1",
        "project": project_identity(root),
        "relative_path_hash": sha256_text(relative),
        "file_sha256": file_hash,
        "summary_schema": "CONTENT_SUMMARY_V1",
        "parser_version": parser_version,
        "skill_context_hash": sha256_text(skill_context),
    })
    return cache / project_identity(root) / "entries" / f"{sha256_text(key_material)}.json", file_hash, sha256_text(relative)


def action_cache_put(args: argparse.Namespace) -> dict[str, Any]:
    root = project_root(args.project_dir)
    target, file_hash, relative_hash = cache_key(root, args.file_path, args.cache_root, args.parser_version, args.skill_context)
    summary = read_json(pathlib.Path(args.input_json))
    if not isinstance(summary, dict) or set(summary) != SUMMARY_FIELDS:
        raise ContractError("CONTENT_SUMMARY_FIELDS_INVALID")
    if any(not isinstance(summary[field], (str, list)) for field in SUMMARY_FIELDS):
        raise ContractError("CONTENT_SUMMARY_TYPES_INVALID")
    value = {
        "schema": "CONTENT_SUMMARY_CACHE_ENTRY_V1",
        "file_sha256": file_hash,
        "relative_path_hash": relative_hash,
        "parser_version": args.parser_version,
        "skill_context_hash": sha256_text(args.skill_context),
        "summary": summary,
        "stored_at": now(),
    }
    write_json(target, value)
    return {"schema": "CONTENT_SUMMARY_CACHE_RESULT_V1", "status": "PUT", "cache_key": target.stem, "file_sha256": file_hash}


def action_cache_get(args: argparse.Namespace) -> dict[str, Any]:
    root = project_root(args.project_dir)
    target, file_hash, _ = cache_key(root, args.file_path, args.cache_root, args.parser_version, args.skill_context)
    if not target.is_file():
        return {"schema": "CONTENT_SUMMARY_CACHE_RESULT_V1", "status": "MISS", "file_sha256": file_hash}
    try:
        value = read_json(target)
        if value.get("schema") != "CONTENT_SUMMARY_CACHE_ENTRY_V1" or value.get("file_sha256") != file_hash or set(value.get("summary", {})) != SUMMARY_FIELDS:
            raise ContractError("CACHE_ENTRY_INVALID")
    except Exception:
        return {"schema": "CONTENT_SUMMARY_CACHE_RESULT_V1", "status": "MISS", "file_sha256": file_hash, "reason": "CACHE_INVALID"}
    return {"schema": "CONTENT_SUMMARY_CACHE_RESULT_V1", "status": "HIT", "file_sha256": file_hash, "summary": value["summary"]}


def action_record_metrics(args: argparse.Namespace) -> dict[str, Any]:
    root = project_root(args.project_dir)
    validate_task_id(args.task_id)
    metrics = read_json(pathlib.Path(args.input_json))
    if not isinstance(metrics, dict) or set(metrics) != METRIC_FIELDS:
        raise ContractError("CONTEXT_METRICS_FIELDS_INVALID")
    for field, value in metrics.items():
        if field.endswith("tokens") and value == "UNAVAILABLE":
            continue
        if not isinstance(value, int) or value < 0:
            raise ContractError(f"CONTEXT_METRIC_INVALID: {field}")
    value = {"schema": "CONTEXT_METRICS_V1", "task_id": args.task_id, "recorded_at": now(), **metrics}
    write_jsonl(root / ".ai" / "metrics" / "CONTEXT_METRICS.jsonl", value)
    write_jsonl(task_dir(root, args.task_id) / "CONTEXT_METRICS.jsonl", value)
    return value


def action_validate_task(args: argparse.Namespace) -> dict[str, Any]:
    root = project_root(args.project_dir)
    budget = load_budget(root, args.task_id)
    task = task_dir(root, args.task_id)
    errors: list[str] = []
    retrieval = task / "CONTEXT_RETRIEVAL.jsonl"
    cycles = []
    if retrieval.is_file():
        try:
            cycles = [json.loads(line) for line in retrieval.read_text(encoding="utf-8").splitlines() if line.strip()]
        except Exception:
            errors.append("CONTEXT_RETRIEVAL_INVALID")
    if len(cycles) > min(3, int(budget["max_retrieval_cycles"])):
        errors.append("RETRIEVAL_CYCLE_LIMIT")
    if [item.get("cycle") for item in cycles] != list(range(1, len(cycles) + 1)):
        errors.append("RETRIEVAL_CYCLE_SEQUENCE_INVALID")
    selection_path = task / "SKILL_SELECTION.json"
    if selection_path.is_file():
        selection = read_json(selection_path)
        if len(selection.get("selected", [])) > int(budget["max_loaded_skills"]):
            errors.append("SKILL_BUDGET_EXCEEDED")
    return {"schema": "CONTEXT_TASK_VALIDATION_V1", "task_id": args.task_id, "valid": not errors, "errors": errors}


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(prog="context-intelligence")
    sub = result.add_subparsers(dest="action", required=True)

    def common(command: argparse.ArgumentParser, task: bool = False) -> None:
        command.add_argument("--project-dir", required=True)
        if task:
            command.add_argument("--task-id", required=True)

    init = sub.add_parser("initialize-budget")
    common(init, True)
    init.add_argument("--work-class", required=True, choices=sorted(BUDGETS))
    init.add_argument("--cache-root")
    init.set_defaults(handler=action_initialize_budget)

    cycle = sub.add_parser("record-cycle")
    common(cycle, True)
    cycle.add_argument("--cycle", required=True, type=int)
    cycle.add_argument("--input-json", required=True)
    cycle.set_defaults(handler=action_record_cycle)

    skills = sub.add_parser("select-skills")
    common(skills, True)
    skills.add_argument("--catalog", required=True)
    skills.add_argument("--input-json", required=True)
    skills.set_defaults(handler=action_select_skills)

    for name, handler, needs_input in (("cache-get", action_cache_get, False), ("cache-put", action_cache_put, True)):
        command = sub.add_parser(name)
        common(command)
        command.add_argument("--file-path", required=True)
        command.add_argument("--cache-root")
        command.add_argument("--parser-version", default="1")
        command.add_argument("--skill-context", default="")
        if needs_input:
            command.add_argument("--input-json", required=True)
        command.set_defaults(handler=handler)

    metrics = sub.add_parser("record-metrics")
    common(metrics, True)
    metrics.add_argument("--input-json", required=True)
    metrics.set_defaults(handler=action_record_metrics)

    validate = sub.add_parser("validate-task")
    common(validate, True)
    validate.set_defaults(handler=action_validate_task)
    return result


def main() -> int:
    try:
        args = parser().parse_args()
        value = args.handler(args)
        sys.stdout.write(json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n")
        return 0
    except ContractError as exc:
        sys.stderr.write(str(exc) + "\n")
        return 2
    except Exception as exc:
        sys.stderr.write(f"CONTEXT_INTELLIGENCE_ERROR: {exc}\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
