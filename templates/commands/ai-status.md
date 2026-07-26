---
description: Show the current governed task and baseline status
agent: architect
subtask: false
---

Read the current project's governance state without changing source code and report:

- current governance state;
- baseline validation state: `BASELINE_DRAFT` / `BASELINE_REVALIDATION_REQUIRED` / `BASELINE_VALIDATED` / `BASELINE_BLOCKED`;
- validated baseline repository reference when available;
- latest baseline AUDIT ID and cycle number;
- Implementation Baseline Reviewer recommendation/status;
- Architecture/Security Baseline Reviewer recommendation/status;
- Final Baseline Reviewer verdict/status;
- outstanding validated baseline gaps, recorded codebase defects/risks and unresolved unknowns;
- baseline/map freshness and last refresh/revalidation reason;
- TASK ID when a task exists;
- current task stage;
- Architect status and latest plan ID/version;
- whether the task is `READY_FOR_EXECUTION`;
- Executor status;
- implementation Task Reviewer verdict/status;
- architecture Task Reviewer verdict/status;
- final Task Reviewer/adjudicator verdict/status;
- outstanding validated task findings/blockers;
- task review cycle number;
- whether the current source tree is frozen for review;
- repository delta considered by the current plan when known;
- deployment scope status;
- latest `.ai/PROJECT_HISTORY.md` event;
- git status summary;
- last validated task local commit when identifiable;
- push status: NOT_AUTHORIZED / AUTHORIZED / PERFORMED;
- missing mandatory external validation;
- release readiness when known.

Never expose secret values while reporting status.