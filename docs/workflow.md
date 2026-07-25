# Workflow

## Initialize a repository

```text
/ai-init
```

Creates or upgrades the project-local governance state without modifying source code:

- `.ai/CODEBASE_BASELINE.md`
- `.ai/DEPLOYMENT_SCOPE.md`
- `.ai/PROJECT_HISTORY.md`
- `.ai/STATUS.md`
- `.ai/tasks/`

Before first implementation, Architect performs a complete adversarial repository baseline. Later tasks use targeted just-in-time impact analysis and refresh the baseline only when materially necessary.

## Complete workflow

```text
/ai-workflow <task>
```

Task lifecycle:

```text
PLANNING
→ TASK_PLANNED
→ READY_FOR_EXECUTION
→ IMPLEMENTING
→ TASK_VERIFYING
→ TASK_VALIDATED
→ REVIEW
→ LOCAL_COMMITTED
```

Architect must re-check the current repository before every task handoff. Executor never implements unless the task is `READY_FOR_EXECUTION`.

Reviewer verdicts:

- `PASS`
- `IMPLEMENTATION_DEFECT`
- `PLAN_DEFECT`
- `BLOCKED`

Implementation defects go back to Executor for targeted correction.

Plan defects go back to Architect for re-investigation and a revised plan that must be explicitly returned to `READY_FOR_EXECUTION`.

Automatic correction is limited to three review cycles.

After Reviewer `PASS`, Executor creates one scoped local task commit. Push is separate and requires explicit user authorization.

## Planning only

```text
/ai-plan <task>
```

Architect performs current-state reconciliation, adversarial impact analysis, acceptance/test planning, migration/deployment analysis, dependency governance and external-validation planning. No implementation is performed.

## Execute an existing plan

```text
/ai-execute <task-id-or-plan-id>
```

Execution is blocked unless the plan is Architect-approved and state is `READY_FOR_EXECUTION`.

## Independent review

```text
/ai-review <task-id>
```

Reviewer independently verifies the specification, baseline, plan, diff, tests, dependencies, migration safety, deployment scope, secrets and maintainability.

## Status

```text
/ai-status
```

Reports task state, baseline status, latest history event, Git/commit state, push authorization and unresolved external validation.

## Final release

```text
/ai-release
```

The final release gate validates the runtime-only production artifact, secret safety, migrations, clean installation/startup from the artifact itself, required tests and real external integration validation.

Final verdict is exactly one of:

- `READY_FOR_PRODUCTION`
- `NOT_READY_FOR_PRODUCTION`
