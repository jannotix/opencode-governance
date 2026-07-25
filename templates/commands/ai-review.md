---
description: Run an independent adversarial review of a governed task
agent: reviewer
subtask: true
---

Review the governed task identified by:

$ARGUMENTS

Inspect the original request, architecture, approved plan, current git diff, implementation report, tests and repository state. Write the review artifact under the task's `.ai/tasks/` directory and return one allowed verdict.
