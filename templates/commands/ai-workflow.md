---
description: Run the complete Architect -> Executor -> Reviewer workflow
agent: architect
subtask: false
---

Run the complete governed development lifecycle for:

$ARGUMENTS

Do not edit source code yourself.

Lifecycle:

`INTAKE -> BASELINE -> PLANNING -> TASK_PLANNED -> READY_FOR_EXECUTION -> IMPLEMENTING -> TASK_VERIFYING -> TASK_VALIDATED -> REVIEW -> LOCAL_COMMITTED`

Rules:

1. if project governance is not initialized, establish `.ai/CODEBASE_BASELINE.md`, `.ai/DEPLOYMENT_SCOPE.md`, `.ai/PROJECT_HISTORY.md` and `.ai/STATUS.md` first;
2. before every task, reconcile the baseline with current repository state and create a fresh Architect-approved JIT plan;
3. delegate implementation only when the task is `READY_FOR_EXECUTION`;
4. delegate independent verification to a fresh `reviewer` invocation;
5. when review returns `IMPLEMENTATION_DEFECT`, coordinate only the required implementation corrections and request a fresh review;
6. when review returns `PLAN_DEFECT`, re-investigate, revise the plan, explicitly restore `READY_FOR_EXECUTION`, then send it to Executor and request a fresh review;
7. when Executor returns `PLAN_CONFLICT`, re-investigate the conflicting assumption and revise or confirm the plan using evidence before execution continues;
8. after Reviewer returns `PASS`, delegate finalization to Executor: inspect Git state/diff, scan staged changes for secrets, stage only task-scoped files plus relevant `.ai/` state/history, create the required local task commit, and set `LOCAL_COMMITTED`;
9. never push unless the user explicitly authorizes that specific push;
10. append material state transitions and evidence to `.ai/PROJECT_HISTORY.md` without secret values.

Maximum automatic correction cycles: 3.

Finish a governed task only with `LOCAL_COMMITTED` or a justified `BLOCKED` state.
