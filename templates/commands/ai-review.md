---
description: Run the independent dual-review and final-adjudication pipeline
agent: architect
subtask: false
---

Review the governed task identified by:

$ARGUMENTS

Do not modify source code or project documentation.

Requirements:

1. locate exactly one matching governed task and confirm it is ready for review;
2. require repository baseline to be currently `BASELINE_VALIDATED`;
3. require canonical requirement artifacts:
   - `.ai/tasks/<TASK-ID>/ORIGINAL_USER_REQUEST.md`;
   - `.ai/tasks/<TASK-ID>/CLARIFICATION_TRANSCRIPT.md`;
   - `.ai/tasks/<TASK-ID>/APPROVED_REQUIREMENTS.md`;
4. inspect those three artifacts directly; do not substitute an Architect summary for the original request;
5. inspect approved plan, `.ai/DOCUMENTATION_SCOPE.md`, task state, execution evidence and current source/documentation Git diff;
6. confirm required documentation sync completed and plan's `DOCUMENTATION_IMPACT` was satisfied;
7. freeze source and task-documentation edits for the review cycle;
8. invoke `reviewer` and `reviewer-architecture` independently in `TASK_REVIEW` mode against the same canonical requirement trail, task state, code diff and documentation diff;
9. do not expose either reviewer's output to the other reviewer;
10. request both reviews before consuming either result and run them concurrently when supported by runtime;
11. after both reviews complete, invoke `final-reviewer` in `TASK_REVIEW` mode with original request, clarification transcript, approved requirements, validated baseline/maps, documentation scope, approved plan, execution evidence, source/documentation diff and both review artifacts;
12. require Final Reviewer to first compare `APPROVED_REQUIREMENTS.md` and the plan against `ORIGINAL_USER_REQUEST.md` plus controlling clarification answers;
13. a material user requirement omitted, weakened, contradicted or broadened without authorization is `PLAN_DEFECT`, even if implementation matches plan and both advisory reviewers pass;
14. require Final Reviewer to verify user-facing docs, installation steps, wiki/manual, changelog, configuration/API/security guidance and licensing documentation are accurate wherever applicable;
15. return only controlling verdict from `final-reviewer`:
   - `PASS`
   - `IMPLEMENTATION_DEFECT`
   - `PLAN_DEFECT`
   - `BLOCKED`.

The two independent reviewers are advisory. Their agreement is not sufficient for approval, and disagreement is not automatically a failure. `final-reviewer` must validate findings and Architect interpretation against primary evidence.

Required documentation that is missing, stale, contradictory, unsafe or inconsistent with implementation prevents `PASS`.

`PASS` authorizes Architect to request validated local task commit from Executor. It does not authorize `git push`.