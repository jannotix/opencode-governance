---
description: Run the complete Architect -> Executor -> Reviewer workflow
agent: architect
subtask: false
---

Run the complete governed development lifecycle for:

$ARGUMENTS

Lifecycle:

DISCOVER → ANALYSE → PLAN → EXECUTE → REVIEW → CORRECT IF REQUIRED → RE-REVIEW → FINAL VERDICT

Do not edit source code yourself.

Delegate implementation to `executor` and verification to a fresh `reviewer` invocation.

When review returns `IMPLEMENTATION_DEFECT`, coordinate only the required implementation corrections and request a fresh review.

When review returns `PLAN_DEFECT`, re-investigate, revise the plan, send the revised plan to Executor, then request a fresh review.

When Executor returns `PLAN_CONFLICT`, re-investigate the conflicting assumption and revise or confirm the plan using evidence before execution continues.

Maximum automatic correction cycles: 3.

Finish only with `PASS` or a justified `BLOCKED` state.
