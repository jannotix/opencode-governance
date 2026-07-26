---
description: Run the complete governed multi-model development workflow
agent: architect
subtask: false
---

Run the complete governed development lifecycle for:

$ARGUMENTS

Do not edit source code yourself.

Lifecycle:

`INTAKE -> BASELINE_DRAFT -> BASELINE_DUAL_AUDIT -> BASELINE_ADJUDICATION -> BASELINE_VALIDATED -> PLANNING -> TASK_PLANNED -> READY_FOR_EXECUTION -> IMPLEMENTING -> TASK_VERIFYING -> TASK_VALIDATED -> DUAL_REVIEW -> FINAL_ADJUDICATION -> LOCAL_COMMITTED`

Rules:

1. if project governance is not initialized, establish `.ai/CODEBASE_BASELINE.md`, `.ai/DEPLOYMENT_SCOPE.md`, `.ai/PROJECT_HISTORY.md`, `.ai/STATUS.md` and `.ai/baseline-audits/` first;
2. before the first implementation, create a draft codebase baseline, architecture map and dependency/call-path map, then run mandatory independent `BASELINE_AUDIT` reviews with `reviewer` and `reviewer-architecture` followed by `final-reviewer` adjudication;
3. no source implementation may begin until the baseline state is `BASELINE_VALIDATED`;
4. if baseline adjudication returns `BASELINE_DEFECT`, apply only validated corrections to `.ai/` and repeat a fresh independent baseline-audit cycle; after three failed baseline adjudications set `BASELINE_BLOCKED` and stop;
5. for later routine tasks, reuse the validated baseline, inspect repository changes since its reference point or the last validated task, and perform targeted search/read analysis around affected modules, callers, callees, dependencies and data flows;
6. expand beyond the targeted surface only when evidence indicates wider impact;
7. if evidence shows the baseline is materially stale after major structural/architectural/dependency/import changes, set `BASELINE_REVALIDATION_REQUIRED` and run adversarial baseline revalidation before planning continues;
8. create a fresh Architect-approved JIT plan from the validated incremental analysis;
9. delegate implementation only when the task is `READY_FOR_EXECUTION`;
10. after Executor reaches `TASK_VALIDATED`, freeze source edits for the current review cycle;
11. invoke `reviewer` and `reviewer-architecture` independently in `TASK_REVIEW` mode against the same requirement, plan, repository state and diff; never include one reviewer's output in the other reviewer's prompt;
12. request both task reviews before consuming either result and run them concurrently when the runtime supports concurrent Task calls;
13. after both independent reviews complete, delegate adjudication to `final-reviewer` in `TASK_REVIEW` mode with the validated baseline/maps, approved plan, current diff, tests, execution evidence and both review artifacts;
14. Final Reviewer must use targeted verification of changed files, affected call paths and reported findings rather than a new repository-wide scan unless evidence requires broader inspection;
15. only `final-reviewer` may return the controlling task `PASS`, `IMPLEMENTATION_DEFECT`, `PLAN_DEFECT` or `BLOCKED` verdict;
16. when final adjudication returns `IMPLEMENTATION_DEFECT`, send only validated required corrections to Executor, re-run validation and start a fresh dual-review cycle;
17. when final adjudication returns `PLAN_DEFECT`, re-investigate, revise the plan, explicitly restore `READY_FOR_EXECUTION`, execute the revised plan, validate it and start a fresh dual-review cycle;
18. when Executor returns `PLAN_CONFLICT`, re-investigate the conflicting assumption and revise or confirm the plan using evidence before execution continues;
19. after `final-reviewer` returns `PASS`, delegate finalization to Executor: inspect Git state/diff, scan staged changes for secrets, stage only task-scoped files plus relevant `.ai/` state/history, create the required local task commit, and set `LOCAL_COMMITTED`;
20. never push unless the user explicitly authorizes that specific push;
21. append material baseline/task state transitions and evidence to `.ai/PROJECT_HISTORY.md` without secret values.

Reviewer independence is mandatory in both baseline and task review cycles even if the runtime serializes the two review invocations. Neither reviewer may read the sibling review artifact for the active cycle.

Maximum automatic cycles:

- 3 baseline adjudications before `BASELINE_BLOCKED`;
- 3 task final adjudications before `BLOCKED`.

Finish a governed task only with `LOCAL_COMMITTED` or a justified `BLOCKED`/`BASELINE_BLOCKED` state.