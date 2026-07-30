#!/usr/bin/env python3
import json
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "scripts" / "quality-gates.py"


def invoke(*args, expect=0):
    result = subprocess.run([sys.executable, str(TOOL), *map(str, args)], text=True, capture_output=True)
    if result.returncode != expect:
        raise AssertionError(f"exit {result.returncode} != {expect}\nstdout={result.stdout}\nstderr={result.stderr}")
    return json.loads(result.stdout) if result.stdout.strip() else None


def write(path, value):
    path.write_text(json.dumps(value, indent=2), encoding="utf-8")


def main():
    with tempfile.TemporaryDirectory(prefix="opencode-v350-") as td:
        temp = pathlib.Path(td)
        project = temp / "project"
        project.mkdir()
        (project / ".ai").mkdir()
        memory = project / ".ai" / "GOVERNANCE_MEMORY.md"
        memory.write_text("MEMORY_SENTINEL\n", encoding="utf-8")

        bug = invoke("initialize-profile", "--project-dir", project, "--task-id", "BUG-1", "--work-class", "PATCH", "--task-kind", "BUGFIX", "--risks", "")
        assert bug["debug_first_required"] and bug["tdd_required"] and not bug["eval_required"] and bug["self_check_required"]
        docs = invoke("initialize-profile", "--project-dir", project, "--task-id", "DOC-1", "--work-class", "PATCH", "--task-kind", "DOCS", "--risks", "")
        assert not docs["debug_first_required"] and not docs["tdd_required"] and not docs["eval_required"]
        ai = invoke("initialize-profile", "--project-dir", project, "--task-id", "AI-1", "--work-class", "HIGH_RISK_CHANGE", "--task-kind", "FEATURE", "--risks", "AI_SYSTEM,SECURITY")
        assert ai["tdd_required"] and ai["eval_required"] and ai["required_reliability_mode"] == "PASS_K"
        invoke("initialize-profile", "--project-dir", project, "--task-id", "EXC-1", "--work-class", "BOUNDED_FEATURE", "--task-kind", "FEATURE", "--risks", "")

        debug_bad = temp / "debug-bad.json"
        write(debug_bad, {"symptom": "wrong result", "reproduction_status": "REPRODUCED", "root_cause_status": "HYPOTHESIS", "root_cause_evidence": [], "hypothesis": "maybe parser", "minimal_experiment": "isolate parser", "disproving_condition": "parser correct", "hypothesis_attempts": 3, "defect_class": "APPLICATION_DEFECT"})
        blocked = invoke("validate-debug", "--project-dir", project, "--task-id", "BUG-1", "--input-json", debug_bad, expect=3)
        assert blocked["status"] == "ARCHITECTURE_REVIEW_REQUIRED" and blocked["architecture_review_required"]

        debug_good = temp / "debug-good.json"
        write(debug_good, {"symptom": "wrong result", "reproduction_status": "REPRODUCED", "root_cause_status": "CONFIRMED", "root_cause_evidence": ["tests/repro.log"], "hypothesis": "parser drops zero", "minimal_experiment": "direct parser fixture", "disproving_condition": "zero preserved", "hypothesis_attempts": 1, "defect_class": "APPLICATION_DEFECT"})
        assert invoke("validate-debug", "--project-dir", project, "--task-id", "BUG-1", "--input-json", debug_good)["status"] == "PASS"

        tdd_bad = temp / "tdd-bad.json"
        write(tdd_bad, {"red_command": "pytest test_bug", "red_exit_code": 0, "red_expected_failure": "wrong value", "red_observed_failure": "none", "red_evidence_refs": ["red.log"], "green_command": "pytest test_bug", "green_exit_code": 0, "green_evidence_refs": ["green.log"], "regression_command": "pytest", "regression_exit_code": 0, "regression_evidence_refs": ["suite.log"], "exception_class": None, "exception_reason": None, "equivalent_verification": None})
        invalid_tdd = invoke("validate-tdd", "--project-dir", project, "--task-id", "BUG-1", "--input-json", tdd_bad, expect=3)
        assert invalid_tdd["status"] == "BLOCKED" and "RED_MUST_FAIL" in invalid_tdd["errors"]

        tdd_good = temp / "tdd-good.json"
        write(tdd_good, {"red_command": "pytest test_bug", "red_exit_code": 1, "red_expected_failure": "wrong value", "red_observed_failure": "assert 0 == 1", "red_evidence_refs": ["red.log"], "green_command": "pytest test_bug", "green_exit_code": 0, "green_evidence_refs": ["green.log"], "regression_command": "pytest", "regression_exit_code": 0, "regression_evidence_refs": ["suite.log"], "exception_class": None, "exception_reason": None, "equivalent_verification": None})
        assert invoke("validate-tdd", "--project-dir", project, "--task-id", "BUG-1", "--input-json", tdd_good)["status"] == "PASS"

        tdd_exception = temp / "tdd-exception.json"
        write(tdd_exception, {"red_command": None, "red_exit_code": 0, "red_expected_failure": None, "red_observed_failure": None, "red_evidence_refs": [], "green_command": None, "green_exit_code": 0, "green_evidence_refs": [], "regression_command": None, "regression_exit_code": 0, "regression_evidence_refs": [], "exception_class": "NO_EXECUTABLE_HARNESS", "exception_reason": "No executable harness exists for the generated host configuration.", "equivalent_verification": "Validate generated schema and runtime diagnostic output."})
        exception_gate = invoke("validate-tdd", "--project-dir", project, "--task-id", "EXC-1", "--input-json", tdd_exception, expect=3)
        assert exception_gate["status"] == "EXCEPTION_REQUIRES_FINAL_REVIEW"

        eval_bad = temp / "eval-bad.json"
        write(eval_bad, {"capability_evals": ["correct routing"], "regression_evals": ["legacy routes"], "negative_cases": ["unsafe request"], "forbidden_behaviors": ["source write"], "grader_type": "HYBRID", "success_threshold": 1.0, "reliability_mode": "PASS_AT_K", "run_count": 3, "observed_successes": 3, "evidence_refs": ["eval.json"], "exploratory_reason": None})
        bad_eval = invoke("validate-eval", "--project-dir", project, "--task-id", "AI-1", "--input-json", eval_bad, expect=3)
        assert bad_eval["status"] == "EVAL_GATE_FAILED" and "PASS_K_REQUIRED" in bad_eval["errors"]

        eval_good = temp / "eval-good.json"
        write(eval_good, {"capability_evals": ["correct routing"], "regression_evals": ["legacy routes"], "negative_cases": ["unsafe request"], "forbidden_behaviors": ["source write"], "grader_type": "HYBRID", "success_threshold": 1.0, "reliability_mode": "PASS_K", "run_count": 3, "observed_successes": 3, "evidence_refs": ["eval.json"], "exploratory_reason": None})
        assert invoke("validate-eval", "--project-dir", project, "--task-id", "AI-1", "--input-json", eval_good)["status"] == "PASS"

        check_bad = temp / "check-bad.json"
        write(check_bad, {"plan_compliance": True, "scope_compliance": True, "tests_pass": True, "lint_pass": True, "typecheck_pass": True, "format_pass": True, "security_invariants_checked": False, "dependency_delta_checked": True, "migration_delta_checked": True, "documentation_impact_checked": True, "dead_code_checked": True, "temporary_files_checked": True, "external_action_compliance": True, "unresolved_assumptions": ["authorization unknown"], "evidence_refs": ["self-check.log"]})
        not_ready = invoke("record-self-check", "--project-dir", project, "--task-id", "BUG-1", "--input-json", check_bad, expect=3)
        assert not_ready["status"] == "NOT_READY_FOR_REVIEW" and not not_ready["approval_authority"]

        check_good = temp / "check-good.json"
        value = json.loads(check_bad.read_text())
        value["security_invariants_checked"] = True
        value["unresolved_assumptions"] = []
        write(check_good, value)
        ready = invoke("record-self-check", "--project-dir", project, "--task-id", "BUG-1", "--input-json", check_good)
        assert ready["status"] == "READY_FOR_REVIEW" and not ready["approval_authority"]
        invoke("record-self-check", "--project-dir", project, "--task-id", "EXC-1", "--input-json", check_good)

        exception_bad = temp / "exception-bad.json"
        write(exception_bad, {"exception_id": "QEX-001", "gate": "TDD", "exception_class": "NO_EXECUTABLE_HARNESS", "approved_by": "IMPLEMENTATION_REVIEWER", "approval_verdict": "APPROVED", "reason": "Equivalent verification is sufficient.", "evidence_refs": ["equivalent-verification.log"], "approved_scope": ["generated host configuration"], "stale_when": ["executable harness becomes available"]})
        denied_exception = invoke("approve-exception", "--project-dir", project, "--task-id", "EXC-1", "--input-json", exception_bad, expect=3)
        assert denied_exception["status"] == "FINAL_REVIEWER_APPROVAL_REQUIRED"
        still_blocked = invoke("validate-task", "--project-dir", project, "--task-id", "EXC-1", expect=3)
        assert "TDD_PROOF.json_NOT_PASSING" in still_blocked["errors"]

        exception_good = temp / "exception-good.json"
        value = json.loads(exception_bad.read_text())
        value["approved_by"] = "FINAL_REVIEWER"
        write(exception_good, value)
        approved_exception = invoke("approve-exception", "--project-dir", project, "--task-id", "EXC-1", "--input-json", exception_good)
        assert approved_exception["status"] == "APPROVED_EXCEPTION" and not approved_exception["implementation_approved"]
        assert invoke("validate-task", "--project-dir", project, "--task-id", "EXC-1")["valid"] is True

        candidate = temp / "candidate.json"
        write(candidate, {"candidate_id": "LRN-001", "source": "REVIEW_FINDING", "scope": ["parser"], "statement": "Preserve zero values in parser normalization.", "evidence_refs": ["review.md"], "confidence": 0.95, "dedup_key": "parser-zero-preservation", "privacy_class": "PROJECT_INTERNAL", "stale_when": ["parser replaced"]})
        assert invoke("add-learning", "--project-dir", project, "--input-json", candidate)["promotion_status"] == "PENDING"
        assert invoke("add-learning", "--project-dir", project, "--input-json", candidate, expect=3)["status"] == "DUPLICATE_LEARNING_CANDIDATE"

        unauthorized = temp / "promotion-bad.json"
        write(unauthorized, {"candidate_id": "LRN-001", "dedup_key": "parser-zero-preservation", "approved_by": "IMPLEMENTATION_REVIEWER", "approval_verdict": "APPROVED", "evidence_refs": ["review.md"], "approved_scope": ["parser"], "stale_when": ["parser replaced"], "privacy_class": "PROJECT_INTERNAL"})
        assert invoke("promote-learning", "--project-dir", project, "--input-json", unauthorized, expect=3)["status"] == "FINAL_REVIEWER_APPROVAL_REQUIRED"

        authorized = temp / "promotion-good.json"
        value = json.loads(unauthorized.read_text())
        value["approved_by"] = "FINAL_REVIEWER"
        write(authorized, value)
        promotion = invoke("promote-learning", "--project-dir", project, "--input-json", authorized)
        assert promotion["status"] == "PROMOTED" and not promotion["memory_updated"]
        assert memory.read_text(encoding="utf-8") == "MEMORY_SENTINEL\n"

        assert invoke("validate-task", "--project-dir", project, "--task-id", "BUG-1")["valid"] is True

    print("PASS: quality gates Python regressions")


if __name__ == "__main__":
    main()
