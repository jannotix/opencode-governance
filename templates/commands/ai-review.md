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
2. require the repository baseline to be currently `BASELINE_VALIDATED`;
3. inspect the original requirement, clarification answers, approved plan, `.ai/DOCUMENTATION_SCOPE.md`, task state, execution evidence and current source/documentation Git diff;
4. confirm required documentation sync completed and the plan's `DOCUMENTATION_IMPACT` was satisfied;
5. freeze source and task-documentation edits for the review cycle;
6. invoke `reviewer` and `reviewer-architecture` independently in `TASK_REVIEW` mode against the same task state, code diff and documentation diff;
7. do not expose either reviewer's output to the other reviewer;
8. request both reviews before consuming either result and run them concurrently when supported by the runtime;
9. after both reviews complete, invoke `final-reviewer` in `TASK_REVIEW` mode with the original requirement, clarification answers, validated baseline/maps, documentation scope, approved plan, execution evidence, current source/documentation diff and both review artifacts;
10. require Final Reviewer to verify that user-facing docs, installation steps, wiki/manual, changelog, configuration/API/security guidance and licensing documentation are accurate wherever applicable;
11. return only the controlling verdict from `final-reviewer`:
   - `PASS`
   - `IMPLEMENTATION_DEFECT`
   - `PLAN_DEFECT`
   - `BLOCKED`.

The two independent reviewers are advisory. Their agreement is not sufficient for approval, and disagreement is not automatically a failure. `final-reviewer` must validate findings against primary evidence.

Required documentation that is missing, stale, contradictory, unsafe, or inconsistent with the implementation prevents `PASS`.

`PASS` authorizes Architect to request the validated local task commit from Executor. It does not authorize `git push`.