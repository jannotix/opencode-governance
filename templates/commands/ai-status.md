---
description: Show the current governed task status
agent: architect
subtask: false
---

Read the current project's governance state without changing source code and report:

- current governance state;
- TASK ID;
- current stage;
- Architect status and latest plan ID/version;
- whether the task is `READY_FOR_EXECUTION`;
- Executor status;
- Reviewer verdict;
- outstanding findings/blockers;
- review cycle number;
- baseline status and last refresh reason;
- deployment scope status;
- latest `.ai/PROJECT_HISTORY.md` event;
- git status summary;
- last validated task local commit when identifiable;
- push status: NOT_AUTHORIZED / AUTHORIZED / PERFORMED;
- missing mandatory external validation;
- release readiness when known.

Never expose secret values while reporting status.
