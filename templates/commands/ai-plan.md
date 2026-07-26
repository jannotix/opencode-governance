---
description: Analyse a task and create a governed implementation plan
agent: architect
subtask: false
---

Analyse this request without implementing source changes:

$ARGUMENTS

Ensure project-local governance has been initialized. If `.ai/CODEBASE_BASELINE.md` is missing, create it before planning. Refresh it only when materially stale.

For routine tasks, reuse the existing baseline, architecture map and dependency/call-path map. Reconcile them with repository changes since the recorded reference point or last validated task using targeted Git history/diff/status inspection, then inspect only the affected modules, callers, callees, dependencies and data flows required to establish the task impact. Expand analysis only when evidence indicates a wider surface.

Perform an adversarial impact analysis covering scope, affected components, dependencies, regression surface, tests, database/schema and data-change impact, deployment impact, external validation, security/secrets and maintainability.

Create or update the task records under `.ai/tasks/<TASK-ID>/` with the specification, architecture analysis, exact implementation plan, acceptance criteria and evidence.

Set the task state:

`PLANNING -> TASK_PLANNED -> READY_FOR_EXECUTION`

Only set `READY_FOR_EXECUTION` when the task is fully planned, evidence-backed and executable. Otherwise return `BLOCKED` with the missing evidence or prerequisite.

Stop after planning is complete. Do not implement source changes.