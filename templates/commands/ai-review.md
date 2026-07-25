---
description: Run an independent adversarial review of a governed task
agent: reviewer
subtask: true
---

Review the governed task identified by:

$ARGUMENTS

Independently inspect the original request/specification, `.ai/CODEBASE_BASELINE.md`, `.ai/DEPLOYMENT_SCOPE.md`, Architect-approved plan, task state, current Git diff, implementation report, tests, dependency changes and repository configuration.

Verify requirement compliance, architecture, plan adherence, implementation correctness, regression risk, dependency/library necessity, migration safety, external validation, maintainability/modularity, deployment scope and secret handling.

Perform an independent plaintext-secret/tracked-secret check without reproducing secret values.

Write the review artifact under the task's `.ai/tasks/` directory and return one allowed task verdict:

- `PASS`
- `IMPLEMENTATION_DEFECT`
- `PLAN_DEFECT`
- `BLOCKED`

`PASS` authorizes Architect to request the validated local task commit from Executor. It does not authorize `git push`.
