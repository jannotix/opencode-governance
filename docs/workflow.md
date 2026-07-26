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
→ DUAL_REVIEW
→ FINAL_ADJUDICATION
→ LOCAL_COMMITTED
```

Architect must re-check the current repository before every task handoff. Executor never implements unless the task is `READY_FOR_EXECUTION`.

After `TASK_VALIDATED`, source edits are frozen for the active review cycle.

Architect then requests two independent reviews of the same task state and diff:

- `reviewer`: implementation, behaviour, regressions and tests;
- `reviewer-architecture`: architecture, security, dependencies, migrations, deployment scope and maintainability.

Neither reviewer may receive or read the other reviewer's current-cycle findings. Architect requests both reviews before consuming either result and runs them concurrently when the OpenCode runtime supports concurrent Task calls. If the runtime serializes them, the same independence rules still apply.

After both reviews complete, `final-reviewer` independently checks the primary repository evidence and adjudicates every material finding. Reviewer agreement is not treated as proof, and disagreement does not automatically mean failure.

Final task verdicts:

- `PASS`
- `IMPLEMENTATION_DEFECT`
- `PLAN_DEFECT`
- `BLOCKED`

Implementation defects go back to Executor only after Final Reviewer validates the required corrections.

Plan defects go back to Architect for re-investigation and a revised plan that must be explicitly returned to `READY_FOR_EXECUTION` before execution resumes.

Automatic correction is limited to three final-adjudication cycles. After the third failed cycle the workflow stops with `BLOCKED` and preserves the unresolved evidence.

After Final Reviewer `PASS`, Executor creates one scoped local task commit. Push is separate and requires explicit user authorization.

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

## Independent review panel

```text
/ai-review <task-id>
```

Runs the two independent reviewers and then Final Reviewer adjudication without implementing new source changes.

## Status

```text
/ai-status
```

Reports task state, baseline status, both reviewer statuses, final adjudication, latest history event, Git/commit state, push authorization and unresolved external validation.

## Final release

```text
/ai-release
```

The final release gate validates the runtime-only production artifact, secret safety, migrations, clean installation/startup from the artifact itself, required tests and real external integration validation.

It then runs two fresh independent release reviews and sends both reports plus the production evidence to Final Reviewer for adjudication.

Final verdict is exactly one of:

- `READY_FOR_PRODUCTION`
- `NOT_READY_FOR_PRODUCTION`