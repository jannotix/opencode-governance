# Workflow

## Initialize and validate a repository

```text
/ai-init
```

Creates the project-local governance state without modifying source code:

- `.ai/CODEBASE_BASELINE.md`
- `.ai/DEPLOYMENT_SCOPE.md`
- `.ai/PROJECT_HISTORY.md`
- `.ai/STATUS.md`
- `.ai/baseline-audits/`
- `.ai/tasks/`

Before first implementation, Architect performs comprehensive repository reverse engineering and creates a DRAFT baseline containing the repository reference commit, architecture map, dependency/call-path map, data flows, trust boundaries, tests, deployment boundary, security-sensitive areas, known defects/risks, material exclusions and unresolved unknowns.

The Architect draft is not authoritative.

It must pass an independent baseline validation pipeline:

```text
BASELINE_DRAFT
→ BASELINE_DUAL_AUDIT
   ├── reviewer / BASELINE_AUDIT
   └── reviewer-architecture / BASELINE_AUDIT
→ final-reviewer / BASELINE_AUDIT
→ BASELINE_VALIDATED
```

The two reviewers receive the same repository reference and draft baseline but not each other's current audit findings. They are requested before either result is consumed and run concurrently when supported.

Final Reviewer independently validates allegations against primary repository evidence and returns exactly one baseline verdict:

- `BASELINE_PASS`
- `BASELINE_DEFECT`
- `BLOCKED`

On `BASELINE_DEFECT`, Architect may update only governance evidence under `.ai/` using validated corrections, then must run a fresh independent baseline-audit cycle. After three failed baseline adjudications the state becomes `BASELINE_BLOCKED`.

A validated baseline may document pre-existing bugs. `BASELINE_PASS` means the material architecture, known defects/risks, important paths, unknowns and audit exclusions are represented accurately enough for reuse; it does not mean the source is defect-free.

No source implementation may begin without `BASELINE_VALIDATED`.

## Explicit baseline audit

```text
/ai-audit
```

Revalidates the reusable baseline without modifying application source code.

Use it after a material architecture change, broad milestone, large merge/rebase, major dependency upgrade, substantial imported code, evidence of a stale/incomplete baseline, or an explicit request for a codebase audit.

Do not run a complete baseline audit for every routine task.

## Large repositories

For very large repositories, comprehensive baseline analysis means broad structural and risk-based coverage rather than blindly reading every generated, vendored, cached or binary artifact. Material exclusions and unresolved unknowns must be recorded.

After validation, routine tasks reuse the baseline. Architect inspects repository delta since the baseline or last validated task, then performs targeted analysis of affected modules, callers, callees, dependencies and data flows. Analysis expands only when evidence indicates wider impact.

Minor task-local baseline refreshes may be targeted. If evidence shows material staleness, set `BASELINE_REVALIDATION_REQUIRED` and complete the adversarial baseline audit before planning or implementation continues.

## Primary entry points

`architect` remains the default primary agent.

The installer also overrides OpenCode's built-in primary agents:

- `Build`: governed full lifecycle using the Architect model. It cannot edit application source directly; it can perform/coordinate baseline validation and delegates implementation only to `executor`, followed by independent task review and final adjudication.
- `Plan`: governed planning-only mode using the Architect model. It cannot edit application source or delegate subagents. It requires an existing `BASELINE_VALIDATED` baseline and returns `BASELINE_AUDIT_REQUIRED` when validation/revalidation is needed.

This prevents manually switching to OpenCode Build or Plan from bypassing governance.

## Complete workflow

```text
/ai-workflow <task>
```

Full lifecycle:

```text
INTAKE
→ BASELINE_DRAFT
→ BASELINE_DUAL_AUDIT
→ BASELINE_ADJUDICATION
→ BASELINE_VALIDATED
→ PLANNING
→ TASK_PLANNED
→ READY_FOR_EXECUTION
→ IMPLEMENTING
→ TASK_VERIFYING
→ TASK_VALIDATED
→ DUAL_REVIEW
→ FINAL_ADJUDICATION
→ LOCAL_COMMITTED
```

For repositories that already have a current `BASELINE_VALIDATED` baseline, the baseline audit phases are reused/skipped and the workflow starts from incremental planning.

Architect must reconcile the validated baseline with the current repository before every task handoff. Executor never implements unless the baseline is validated and the task is `READY_FOR_EXECUTION`.

After `TASK_VALIDATED`, source edits are frozen for the active review cycle.

Architect requests two independent `TASK_REVIEW` assessments of the same task state and diff:

- `reviewer`: implementation, behaviour, regressions and tests;
- `reviewer-architecture`: architecture, security, dependencies, data/schema safety, deployment scope and maintainability.

Neither reviewer may receive or read the other reviewer's current-cycle findings. Architect requests both reviews before consuming either result and runs them concurrently when OpenCode supports concurrent Task calls. If runtime execution is serialized, the same independence rules still apply.

After both reviews complete, `final-reviewer` in `TASK_REVIEW` mode receives the original requirement, approved plan, validated baseline/maps, current diff, tests, execution evidence and both reports. It validates findings using targeted repository inspection of changed files and affected call paths. It does not perform a new repository-wide audit unless evidence indicates broader impact or material baseline staleness.

Final task verdicts:

- `PASS`
- `IMPLEMENTATION_DEFECT`
- `PLAN_DEFECT`
- `BLOCKED`

Implementation defects go back to Executor only after Final Reviewer validates the required corrections.

Plan defects go back to Architect for re-investigation and a revised plan that must explicitly return to `READY_FOR_EXECUTION` before execution resumes.

Automatic task correction is limited to three final-adjudication cycles. After the third failed cycle the workflow stops with `BLOCKED` and preserves unresolved evidence.

After Final Reviewer `PASS`, Executor creates one scoped local task commit. Push is separate and requires explicit user authorization.

## Planning only

```text
/ai-plan <task>
```

The `/ai-plan` command runs under Architect and can complete mandatory baseline validation first when needed. It then reuses the validated baseline/maps and performs targeted impact analysis, acceptance/test planning, data/schema analysis, dependency governance and external-validation planning. No source implementation is performed.

The built-in `Plan` primary agent cannot delegate; therefore it requires a pre-existing validated baseline rather than certifying one itself.

## Execute an existing plan

```text
/ai-execute <task-id-or-plan-id>
```

Execution is blocked unless the baseline is `BASELINE_VALIDATED`, the plan is Architect-approved and task state is `READY_FOR_EXECUTION`.

## Independent task review panel

```text
/ai-review <task-id>
```

Runs the two independent reviewers in `TASK_REVIEW` mode and then Final Reviewer adjudication without implementing new source changes.

## Status

```text
/ai-status
```

Reports baseline validation/audit status, task state, reviewer statuses, final adjudication, latest history event, Git/commit state, push authorization and unresolved external validation.

## Final release

```text
/ai-release
```

The release gate requires a current `BASELINE_VALIDATED` state, then validates the production artifact, secret safety, data/schema safety, clean installation/startup from the artifact itself, required tests and real external integration validation.

It runs two fresh independent `RELEASE_REVIEW` assessments and sends both reports plus production evidence to Final Reviewer for adjudication.

Final verdict is exactly one of:

- `READY_FOR_PRODUCTION`
- `NOT_READY_FOR_PRODUCTION`