---
description: Run the complete governed multi-model development workflow
agent: architect
subtask: false
---

Run the complete governed development lifecycle for:

$ARGUMENTS

Do not edit source code yourself.

Lifecycle:

`INTAKE -> BASELINE -> PLANNING -> TASK_PLANNED -> READY_FOR_EXECUTION -> IMPLEMENTING -> TASK_VERIFYING -> TASK_VALIDATED -> DUAL_REVIEW -> FINAL_ADJUDICATION -> LOCAL_COMMITTED`

Rules:

1. if project governance is not initialized, establish `.ai/CODEBASE_BASELINE.md`, `.ai/DEPLOYMENT_SCOPE.md`, `.ai/PROJECT_HISTORY.md` and `.ai/STATUS.md` first;
2. before every task, reconcile the baseline with current repository state and create a fresh Architect-approved JIT plan;
3. delegate implementation only when the task is `READY_FOR_EXECUTION`;
4. after Executor reaches `TASK_VALIDATED`, freeze source edits for the current review cycle;
5. invoke `reviewer` and `reviewer-architecture` independently against the same requirement, plan, repository state and diff; never include one reviewer's output in the other reviewer's prompt;
6. request both reviews before consuming either result and run them concurrently when the runtime supports concurrent Task calls;
7. after both independent reviews complete, delegate adjudication to `final-reviewer` with both review artifacts plus the primary implementation evidence;
8. only `final-reviewer` may return the controlling `PASS`, `IMPLEMENTATION_DEFECT`, `PLAN_DEFECT` or `BLOCKED` verdict;
9. when final adjudication returns `IMPLEMENTATION_DEFECT`, send only validated required corrections to Executor, re-run validation and start a fresh dual-review cycle;
10. when final adjudication returns `PLAN_DEFECT`, re-investigate, revise the plan, explicitly restore `READY_FOR_EXECUTION`, execute the revised plan, validate it and start a fresh dual-review cycle;
11. when Executor returns `PLAN_CONFLICT`, re-investigate the conflicting assumption and revise or confirm the plan using evidence before execution continues;
12. after `final-reviewer` returns `PASS`, delegate finalization to Executor: inspect Git state/diff, scan staged changes for secrets, stage only task-scoped files plus relevant `.ai/` state/history, create the required local task commit, and set `LOCAL_COMMITTED`;
13. never push unless the user explicitly authorizes that specific push;
14. append material state transitions and evidence to `.ai/PROJECT_HISTORY.md` without secret values.

Reviewer independence is mandatory even if the runtime serializes the two review invocations. Neither reviewer may read the sibling review artifact for the active cycle.

Maximum automatic correction cycles: 3 final adjudications.

Finish a governed task only with `LOCAL_COMMITTED` or a justified `BLOCKED` state.