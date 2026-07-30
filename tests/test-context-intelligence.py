#!/usr/bin/env python3
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "scripts" / "context-intelligence.py"


def run(*args, expect=0):
    result = subprocess.run([sys.executable, str(TOOL), *map(str, args)], text=True, capture_output=True)
    if result.returncode != expect:
        raise AssertionError(f"command failed ({result.returncode} != {expect})\nstdout={result.stdout}\nstderr={result.stderr}")
    return json.loads(result.stdout) if result.stdout.strip() else None


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2), encoding="utf-8")


def main():
    with tempfile.TemporaryDirectory(prefix="opencode-v340-") as td:
        temp = pathlib.Path(td)
        project = temp / "project"
        cache = temp / "cache"
        project.mkdir()

        expected = {
            "PATCH": (1, 1, 20, 20),
            "BOUNDED_FEATURE": (2, 2, 40, 40),
            "MAJOR_FEATURE": (3, 3, 80, 80),
            "EXISTING_PRODUCT_EVOLUTION": (3, 3, 100, 100),
            "NEW_PRODUCT": (3, 3, 120, 120),
            "HIGH_RISK_CHANGE": (3, 3, 120, 120),
        }
        for index, (work_class, values) in enumerate(expected.items(), 1):
            task_id = f"CTX-{index}"
            output = run("initialize-budget", "--project-dir", project, "--task-id", task_id, "--work-class", work_class, "--cache-root", cache)
            assert output["schema"] == "CONTEXT_BUDGET_V1"
            assert (output["max_retrieval_cycles"], output["max_loaded_skills"], output["max_packet_references"], output["max_admitted_paths"]) == values
            stored = json.loads((project / ".ai" / "tasks" / task_id / "CONTEXT_BUDGET.json").read_text(encoding="utf-8"))
            assert stored == output

        bad = subprocess.run([sys.executable, str(TOOL), "initialize-budget", "--project-dir", str(project), "--task-id", "../escape", "--work-class", "PATCH"], text=True, capture_output=True)
        assert bad.returncode != 0
        assert "INVALID_TASK_ID" in bad.stderr
        assert not (project.parent / "escape").exists()

        task_id = "CTX-CYCLES"
        run("initialize-budget", "--project-dir", project, "--task-id", task_id, "--work-class", "MAJOR_FEATURE", "--cache-root", cache)
        cycle = temp / "cycle.json"
        write_json(cycle, {"query": "entry points", "reason": "initial dispatch", "candidate_paths": ["src/a.py"], "admitted_paths": ["src/a.py"], "rejected_paths": [], "dependency_edges": [], "trust_boundaries": [], "tests": [], "context_gaps": [], "stop_reason": "REFINE"})
        for number in (1, 2, 3):
            result = run("record-cycle", "--project-dir", project, "--task-id", task_id, "--cycle", str(number), "--input-json", cycle)
            assert result["cycle"] == number
        fourth = subprocess.run([sys.executable, str(TOOL), "record-cycle", "--project-dir", str(project), "--task-id", task_id, "--cycle", "4", "--input-json", str(cycle)], text=True, capture_output=True)
        assert fourth.returncode != 0
        assert "RETRIEVAL_CYCLE_LIMIT" in fourth.stderr

        catalog = temp / "skills.json"
        criteria = temp / "criteria.json"
        write_json(catalog, [
            {"schema": "SKILL_CAPABILITY_MANIFEST_V1", "skill_id": "trusted-debug", "version": "1", "content_sha256": "a" * 64, "source": "project", "trust_class": "PROJECT_AUTHORITATIVE", "triggers": ["debug"], "supported_work_classes": ["MAJOR_FEATURE"], "languages": ["python"], "frameworks": [], "required_tools": [], "external_dependencies": [], "conflicts_with": [], "overlaps_with": ["generic-debug"], "estimated_context_tokens": 600, "sections": [{"id": "root-cause", "heading": "Root cause"}]},
            {"schema": "SKILL_CAPABILITY_MANIFEST_V1", "skill_id": "generic-debug", "version": "1", "content_sha256": "b" * 64, "source": "workspace", "trust_class": "WORKSPACE_ADVISORY", "triggers": ["debug"], "supported_work_classes": ["MAJOR_FEATURE"], "languages": ["python"], "frameworks": [], "required_tools": [], "external_dependencies": [], "conflicts_with": [], "overlaps_with": ["trusted-debug"], "estimated_context_tokens": 200, "sections": []},
            {"schema": "SKILL_CAPABILITY_MANIFEST_V1", "skill_id": "network-skill", "version": "1", "content_sha256": "c" * 64, "source": "external", "trust_class": "EXTERNAL_UNTRUSTED", "triggers": ["debug"], "supported_work_classes": ["MAJOR_FEATURE"], "languages": ["python"], "frameworks": [], "required_tools": [], "external_dependencies": ["remote-service"], "conflicts_with": [], "overlaps_with": [], "estimated_context_tokens": 100, "sections": []}
        ])
        write_json(criteria, {"triggers": ["debug"], "languages": ["python"], "frameworks": [], "required_sections": ["root-cause"], "available_tools": []})
        selection = run("select-skills", "--project-dir", project, "--task-id", task_id, "--catalog", catalog, "--input-json", criteria)
        assert [item["skill_id"] for item in selection["selected"]] == ["trusted-debug"]
        rejected = {item["skill_id"]: item["reason"] for item in selection["rejected"]}
        assert rejected["generic-debug"] == "OVERLAP_DEDUPLICATED"
        assert rejected["network-skill"] == "EXTERNAL_DEPENDENCY_UNAVAILABLE"
        assert selection["selected"][0]["sections"] == ["root-cause"]

        source = project / "source.txt"
        source.write_text("secret-source-value\n", encoding="utf-8")
        summary = temp / "summary.json"
        write_json(summary, {"responsibility": "Example module", "public_symbols": ["run"], "entry_points": ["run"], "callers": [], "callees": [], "side_effects": [], "trust_boundaries": [], "tests": ["test_run"], "documentation": [], "risks": []})
        put = run("cache-put", "--project-dir", project, "--file-path", source, "--input-json", summary, "--cache-root", cache, "--parser-version", "1")
        assert put["status"] == "PUT"
        hit = run("cache-get", "--project-dir", project, "--file-path", source, "--cache-root", cache, "--parser-version", "1")
        assert hit["status"] == "HIT"
        assert hit["summary"]["responsibility"] == "Example module"
        for cache_file in cache.rglob("*.json"):
            text = cache_file.read_text(encoding="utf-8")
            assert "secret-source-value" not in text
            assert str(project) not in text
        source.write_text("changed-source-value\n", encoding="utf-8")
        miss = run("cache-get", "--project-dir", project, "--file-path", source, "--cache-root", cache, "--parser-version", "1")
        assert miss["status"] == "MISS"

        metrics = temp / "metrics.json"
        write_json(metrics, {"files_considered": 12, "files_admitted": 4, "files_rejected": 8, "retrieval_cycles": 2, "loaded_skills": 1, "estimated_skill_tokens": 600, "cache_hits": 1, "cache_misses": 1, "cache_invalidations": 0, "repeated_file_reads": 0, "context_budget_overrides": 0, "packet_references": 7, "input_tokens": "UNAVAILABLE", "output_tokens": "UNAVAILABLE", "fallback_discarded_tokens": "UNAVAILABLE"})
        recorded = run("record-metrics", "--project-dir", project, "--task-id", task_id, "--input-json", metrics)
        assert recorded["schema"] == "CONTEXT_METRICS_V1"
        metrics_text = (project / ".ai" / "metrics" / "CONTEXT_METRICS.jsonl").read_text(encoding="utf-8")
        assert "secret-source-value" not in metrics_text

        validated = run("validate-task", "--project-dir", project, "--task-id", task_id)
        assert validated["valid"] is True

    print("PASS: context intelligence Python regressions")


if __name__ == "__main__":
    main()
