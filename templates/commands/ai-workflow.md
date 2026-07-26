---
description: Run the complete governed multi-model development workflow
agent: architect
subtask: false
---

Run the complete governed development lifecycle for:

$ARGUMENTS

Do not edit source code yourself.

Lifecycle:

`INTAKE -> BASELINE_OR_REUSE -> PLANNING -> TASK_PLANNED -> READY_FOR_EXECUTION -> IMPLEMENTING -> TASK_VERIFYING -> TASK_VALIDATED -> DUAL_REVIEW -> FINAL_ADJUDICATION -> LOCAL_COMMITTED`

Rules:

1. if project governance is not initialized, establish `.ai/CODEBASE_BASELINE.md`, `.ai/DEPLOYMENT_SCOPE.md`, `.ai/PROJECT_HISTORY.md` and `.ai/STATUS.md` first;
2. build the complete codebase baseline, architecture map and dependency/call-path map only for initial intake or when they are materially stale;
3. for later tasks, reuse the baseline, inspect repository changes since its reference point or the last validated task, and perform targeted search/read analysis around affected modules, callers, callees, dependencies and data flows;
4. expand beyond the targeted surface only when evidence indicates wider impact;
5. create a fresh Architect-approved JIT plan from that incremental analysis;
6. delegate implementation only when the task is `READY_FOR_EXECUTION`;
7. after Executor reaches `TASK_VALIDATED`, freeze source edits for the current review cycle;
8. invoke `reviewer` and `reviewer-architecture` independently against the same requirement, plan, repository state and diff; never include one reviewer's output in the other reviewer's prompt;
9. request both reviews before consuming either result and run them concurrently when the runtime supports concurrent Task calls;
10. after both independent reviews complete, delegate adjudication to `final-reviewer` with the reusable baseline/maps, approved plan, current diff, tests, execution evidence and both review artifacts;
11. Final Reviewer must use targeted verification of changed files, affected call paths and reported findings rather than a new repository-wide scan unless evidence requires broader inspection;
12. only `final-reviewer` may return the controlling `PASS`, `IMPLEMENTATION_DEFECT`, `PLAN_DEFECT` or `BLOCKED` verdict;
13. when final adjudication returns `IMPLEMENTATION_DEFECT`, send only validated required corrections to Executor, re-run validation and start a fresh dual-review cycle;
14. when final adjudication returns `PLAN_DEFECT`, re-investigate, revise the plan, explicitly restore `READY_FOR_EXECUTION`, execute the revised plan, validate it and start a fresh dual-review cycle;
15. when Executor returns `PLAN_CONFLICT`, re-investigate the conflicting assumption and revise or confirm the plan using evidence before execution continues;
16. after `final-reviewer` returns `PASS`, delegate finalization to Executor: inspect Git state/diff, scan staged changes for secrets, stage only task-scoped files plus relevant `.ai/` state/history, create the required local task commit, and set `LOCAL_COMMITTED`;
17. never push unless the user explicitly authorizes that specific push;
18. append material state transitions and evidence to `.ai/PROJECT_HISTORY.md` without secret values.

Reviewer independence is mandatory even if the runtime serializes the two review invocations. Neither reviewer may read the sibling review artifact for the active cycle.

Maximum automatic correction cycles: 3 final adjudications.

Finish a governed task only with `LOCAL_COMMITTED` or a justified `BLOCKED` state.