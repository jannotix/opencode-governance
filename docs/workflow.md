# Workflow

## Initialize a repository

```text
/ai-init
```

Creates the project-local governance state without modifying source code:

- `.ai/CODEBASE_BASELINE.md`
- `.ai/DEPLOYMENT_SCOPE.md`
- `.ai/PROJECT_HISTORY.md`
- `.ai/STATUS.md`
- `.ai/tasks/`

Before first implementation, Architect performs a complete repository baseline containing the repository reference commit, architecture map, dependency/call-path map, data flows, trust boundaries, tests, deployment boundary and other required technical context.

The baseline is reusable. Later tasks do not repeat a repository-wide scan by default. Architect inspects the repository delta since the baseline or last validated task, then performs targeted analysis of the affected modules, callers, callees, dependencies and data flows. The analysis expands only when evidence indicates wider impact. Baseline sections are refreshed only when materially stale.

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

Architect must reconcile the reusable baseline with the current repository before every task handoff. Executor never implements unless the task is `READY_FOR_EXECUTION`.

After `TASK_VALIDATED`, source edits are frozen for the active review cycle.

Architect then requests two independent reviews of the same task state and diff:

- `reviewer`: implementation, behaviour, regressions and tests;
- `reviewer-architecture`: architecture, security, dependencies, data/schema safety, deployment scope and maintainability.

Neither reviewer may receive or read the other reviewer's current-cycle findings. Architect requests both reviews before consuming either result and runs them concurrently when the OpenCode runtime supports concurrent Task calls. If the runtime serializes them, the same independence rules still apply.

After both reviews complete, `final-reviewer` receives the original requirement, approved plan, reusable baseline/maps, current diff, tests, execution evidence and both review reports. It validates findings using targeted repository inspection of changed files and affected call paths. It does not perform a new repository-wide scan unless evidence indicates broader dependency, regression, security or architectural impact, or the baseline is materially stale.

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

Architect reuses the baseline and repository maps, inspects the delta since the recorded reference point, and performs targeted impact analysis, acceptance/test planning, data/schema analysis, dependency governance and external-validation planning. No implementation is performed.

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

The final release gate validates the production artifact, secret safety, data/schema safety, clean installation/startup from the artifact itself, required tests and real external integration validation.

It then runs two fresh independent release reviews and sends both reports plus the production evidence to Final Reviewer for adjudication.

Final verdict is exactly one of:

- `READY_FOR_PRODUCTION`
- `NOT_READY_FOR_PRODUCTION`