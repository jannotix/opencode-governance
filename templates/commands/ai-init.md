---
description: Initialize project-local governance state
agent: architect
subtask: false
---

Initialize governance for the current repository without modifying source code.

Create the project-local governance artifacts if missing:

- `.ai/CODEBASE_BASELINE.md`
- `.ai/DEPLOYMENT_SCOPE.md`
- `.ai/PROJECT_HISTORY.md`
- `.ai/STATUS.md`
- `.ai/tasks/`

Do not overwrite valid existing project state.

Before first implementation, perform a complete adversarial reverse-engineering analysis of the repository and populate `CODEBASE_BASELINE.md` with:

- baseline repository commit/reference;
- stack and supported runtimes;
- entry points;
- architecture map covering major modules, boundaries and responsibilities;
- dependency/call-path map covering important module relationships and high-value execution paths;
- data flows and trust boundaries;
- database/schema state and change mechanism;
- external integrations;
- tests and validation capabilities;
- deployment boundary;
- security-sensitive areas;
- known defects and regression risks;
- technical constraints;
- blocking unknowns.

Treat this baseline and its maps as reusable repository context. Do not rebuild them from scratch for every task. Refresh only the portions made materially stale by repository changes or when evidence shows the existing baseline is insufficient.

Populate `DEPLOYMENT_SCOPE.md` with the production runtime boundary and explicitly identify tests, development documentation, `.ai/`, review evidence, local tooling, IDE/temp files and secrets as development-only unless the project demonstrably requires a specific file at runtime.

Initialize `PROJECT_HISTORY.md` as an append-only chronological ledger. Each event should record timestamp, role, configured model when known, task/milestone/slice, action, result, evidence, state transition, Git action/commit message and push status. Never store secret values.

Set `.ai/STATUS.md` to the current governance state. If the baseline is complete and no task is planned, use `PLANNING`.