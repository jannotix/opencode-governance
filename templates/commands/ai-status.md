---
description: Show the current governed task, baseline and documentation status
agent: architect
subtask: false
---

Read the current project's governance state without changing source code or project documentation and report:

- current governance state;
- baseline validation state: `BASELINE_DRAFT` / `BASELINE_REVALIDATION_REQUIRED` / `BASELINE_VALIDATED` / `BASELINE_BLOCKED`;
- validated baseline repository reference when available;
- latest baseline AUDIT ID and cycle number;
- Implementation Baseline Reviewer recommendation/status;
- Architecture/Security Baseline Reviewer recommendation/status;
- Final Baseline Reviewer verdict/status;
- outstanding validated baseline gaps, recorded codebase defects/risks and unresolved unknowns;
- baseline/map freshness and last refresh/revalidation reason;
- documentation root and `.ai/DOCUMENTATION_SCOPE.md` status;
- required documentation present/current/stale/missing summary;
- documentation synchronization reference/task when known;
- project license state, including `LICENSE_DECISION_REQUIRED` when unresolved;
- production exclusion status for `docs/**` and `.ai/**` plus explicit legal/runtime exceptions;
- TASK ID when a task exists;
- current task stage;
- Architect status and latest plan ID/version;
- outstanding clarification questions or unresolved material decisions;
- clarification decisions recorded for the current task;
- whether the task is `READY_FOR_EXECUTION`;
- current `DOCUMENTATION_IMPACT` and required canonical documents/sections;
- Executor status;
- implementation Task Reviewer verdict/status;
- architecture Task Reviewer verdict/status;
- final Task Reviewer/adjudicator verdict/status;
- outstanding validated task findings/blockers;
- task review cycle number;
- whether the current source/documentation tree is frozen for review;
- repository delta considered by the current plan when known;
- deployment scope status;
- latest `.ai/PROJECT_HISTORY.md` event;
- git status summary;
- last validated task local commit when identifiable;
- push status: NOT_AUTHORIZED / AUTHORIZED / PERFORMED;
- missing mandatory external validation;
- release readiness when known.

Never expose secret values while reporting status.