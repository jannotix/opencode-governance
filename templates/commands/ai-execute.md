---
description: Execute an explicit approved governance plan
agent: executor
subtask: true
---

Execute the approved task identified by:

$ARGUMENTS

Locate exactly one matching task under `.ai/tasks/`.

Do not implement unless:

- the repository baseline state is `BASELINE_VALIDATED`;
- the task has an Architect-approved plan;
- the current task state is `READY_FOR_EXECUTION`;
- the plan contains a resolved `DOCUMENTATION_IMPACT` decision;
- required prerequisites are available;
- no unresolved material implementation ambiguity remains.

If the baseline is missing, draft, materially stale, revalidation-required or blocked, return `BASELINE_AUDIT_REQUIRED` or `BLOCKED` instead of implementing.

If any required decision, condition or documentation scope is missing or ambiguous, return `PLAN_CONFLICT` or `BLOCKED` instead of guessing.

Implement only the approved scope. Preserve architecture unless the plan explicitly changes it. Use existing project libraries where adequate and do not introduce duplicate dependencies.

Read `.ai/DOCUMENTATION_SCOPE.md` and execute the approved documentation work as part of the same task:

- `DOCUMENTATION_IMPACT: NONE` — record why no canonical document changes are required;
- `UPDATE_REQUIRED` — update every approved canonical document/section;
- `CREATE_REQUIRED` — create the approved missing applicable documents, normally under top-level `docs/`.

For distributable applications, ensure approved scope covers the applicable overview/readme, step-by-step installation guide, user manual, wiki/index, changelog and licensing documentation, plus other applicable documentation.

Never choose or fabricate license terms. If the license decision required by the plan is unresolved, return `PLAN_CONFLICT` / `LICENSE_DECISION_REQUIRED` instead of creating a license file.

Set state `IMPLEMENTING`, perform approved source and documentation changes, then set `TASK_VERIFYING` during validation. Run required tests and documentation consistency checks. Verify documented commands, paths, configuration examples and installation steps against actual implementation where locally possible. Confirm `docs/**` and `.ai/**` are excluded from production/runtime packaging by default except explicit approved exceptions.

When all acceptance criteria including required documentation checks pass, set `TASK_VALIDATED` and return the execution report for the independent dual-review pipeline.

Do not create the final task commit until `final-reviewer` returns `PASS` and Architect requests finalization.

Never push by default. A push requires explicit user authorization for that specific push.