---
description: Execute an explicit approved governance plan
agent: executor
subtask: true
---

Execute the approved task identified by:

$ARGUMENTS

Locate exactly one matching task under `.ai/tasks/`.

Do not implement unless:

- the task has an Architect-approved plan;
- the current task state is `READY_FOR_EXECUTION`;
- required prerequisites are available.

If any condition is missing or ambiguous, return `BLOCKED` instead of guessing.

Implement only the approved scope. Preserve architecture unless the plan explicitly changes it. Use existing project libraries where adequate and do not introduce duplicate dependencies.

Set state `IMPLEMENTING`, then `TASK_VERIFYING` during validation. Run required tests and record evidence. When all acceptance criteria pass, set `TASK_VALIDATED` and return the execution report for independent review.

Do not create the final task commit until Reviewer returns `PASS` and Architect requests finalization.

Never push by default. A push requires explicit user authorization for that specific push.
