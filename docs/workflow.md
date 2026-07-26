# Workflow

## Initialize and validate a repository

```text
/ai-init
```

Creates the project-local governance state without modifying application source or project documentation:

- `.ai/CODEBASE_BASELINE.md`
- `.ai/DEPLOYMENT_SCOPE.md`
- `.ai/DOCUMENTATION_SCOPE.md`
- `.ai/PROJECT_HISTORY.md`
- `.ai/STATUS.md`
- `.ai/baseline-audits/`
- `.ai/tasks/`

Before first implementation, Architect performs comprehensive repository reverse engineering and creates a DRAFT baseline plus documentation inventory.

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

A validated baseline may document pre-existing bugs, documentation gaps or unresolved license state. `BASELINE_PASS` means those material facts are represented accurately enough for reuse; it does not mean the source or docs are defect-free.

No source implementation may begin without `BASELINE_VALIDATED`.

## Clarification gate

Architect, governed Build and governed Plan explicitly use OpenCode's `question` tool when approved requirements and primary evidence do not resolve a material project decision.

They must ask the developer/project owner rather than inventing or silently assuming decisions that can affect:

- product behaviour or UX;
- compatibility;
- data handling;
- integrations;
- deployment or packaging;
- documentation;
- software licensing.

They must not repeat questions already answered by the user or authoritative project evidence.

`READY_FOR_EXECUTION` is prohibited while an unresolved material ambiguity could change implementation, acceptance criteria, safety, compatibility or required documentation.

## Project documentation governance

`.ai/DOCUMENTATION_SCOPE.md` records the canonical documentation layout, applicability, current/stale/missing state, synchronization reference and project license state.

When no coherent project convention exists, the default documentation root is top-level `docs/`, outside the production/runtime code boundary.

For distributable applications, the default minimum applicable documentation set is:

```text
docs/
├── README.md
├── INSTALLATION.md
├── USER_MANUAL.md
├── CHANGELOG.md
├── LICENSE.md          # only after an explicit license decision
└── wiki/
    └── README.md
```

Add admin, upgrade, architecture, configuration, API, security, troubleshooting, release notes and additional wiki pages when applicable.

Do not create filler documents. Preserve coherent existing conventions and root-level ecosystem/legal files when they are authoritative.

`docs/**` and `.ai/**` are excluded from the production/runtime artifact by default. Specific legal/notice/runtime exceptions must be recorded in `.ai/DEPLOYMENT_SCOPE.md`.

Every task records exactly one:

- `DOCUMENTATION_IMPACT: NONE`
- `DOCUMENTATION_IMPACT: UPDATE_REQUIRED`
- `DOCUMENTATION_IMPACT: CREATE_REQUIRED`

Required documentation is synchronized by Executor before `TASK_VALIDATED` and reviewed with the implementation.

Governance never chooses a software license automatically. Missing explicit license state is recorded as:

```text
LICENSE_DECISION_REQUIRED
```

Architect asks the developer/project owner when that decision is needed. Release readiness remains blocked until it is resolved.

## Explicit documentation workflow

```text
/ai-docs
```

Creates a governed documentation task for an existing project. Architect inventories/clarifies/plans, Executor writes the approved docs, then both independent reviewers and Final Reviewer validate them against primary project evidence.

Use it to create or synchronize README, installation guide, user manual, wiki, changelog, licensing documentation and other applicable project docs without changing application source unless the approved task explicitly requires it.

## Explicit baseline audit

```text
/ai-audit
```

Revalidates the reusable baseline and documentation inventory without modifying application source or project documentation.

Use it after a material architecture change, broad milestone, large merge/rebase, major dependency upgrade, substantial imported code, evidence of stale/incomplete baseline/documentation scope, or an explicit audit request.

Do not run a complete baseline audit for every routine task.

## Large repositories

For very large repositories, comprehensive baseline analysis means broad structural and risk-based coverage rather than blindly reading every generated, vendored, cached or binary artifact. Material exclusions and unresolved unknowns must be recorded.

After validation, routine tasks reuse the baseline. Architect inspects repository delta since the baseline or last validated task, then performs targeted analysis of affected modules, callers, callees, dependencies, data flows and impacted canonical documentation. Analysis expands only when evidence indicates wider impact.

If evidence shows material staleness, set `BASELINE_REVALIDATION_REQUIRED` and complete adversarial baseline validation before planning or implementation continues.

## Primary entry points

`architect` remains the default primary agent.

The installer also overrides OpenCode's built-in primary agents:

- `Build`: governed full lifecycle using the Architect model. It cannot edit application source/project docs directly; it can clarify requirements, coordinate baseline validation and delegates writes only to `executor`.
- `Plan`: governed planning-only mode using the Architect model. It cannot edit source/docs or delegate subagents. It can ask clarification questions but requires an existing `BASELINE_VALIDATED` baseline.

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
→ CLARIFICATION
→ PLANNING
→ TASK_PLANNED
→ READY_FOR_EXECUTION
→ IMPLEMENTING
→ DOCUMENTATION_SYNC
→ TASK_VERIFYING
→ TASK_VALIDATED
→ DUAL_REVIEW
→ FINAL_ADJUDICATION
→ LOCAL_COMMITTED
```

For repositories that already have a current `BASELINE_VALIDATED` baseline, the baseline audit phases are reused/skipped and the workflow starts from incremental clarification/planning.

Architect must reconcile the validated baseline and documentation scope with the current repository before every task handoff. Executor never implements unless the baseline is validated and the task is `READY_FOR_EXECUTION`.

Before execution, Architect determines documentation impact and resolves material ambiguity through `question` when necessary.

Executor performs the approved source work and required project-documentation sync. `TASK_VALIDATED` requires both implementation acceptance criteria and required documentation checks to pass.

After `TASK_VALIDATED`, source and task-documentation edits are frozen for the active review cycle.

Architect requests two independent `TASK_REVIEW` assessments of the same code/documentation state:

- `reviewer`: implementation, behaviour, regressions, tests and user-facing documentation accuracy;
- `reviewer-architecture`: architecture, security, dependencies, data/schema safety, deployment scope, documentation structure and licensing consistency.

Neither reviewer may receive or read the other reviewer's current-cycle findings. Architect requests both reviews before consuming either result and runs them concurrently when OpenCode supports concurrent Task calls.

After both reviews complete, `final-reviewer` validates the original requirement, clarification decisions, approved plan, validated baseline/maps, documentation scope, current code/documentation diff, tests, execution evidence and both reports.

Required documentation that is missing, materially stale, contradictory, unsafe or claims functionality not actually implemented prevents `PASS`.

Final task verdicts:

- `PASS`
- `IMPLEMENTATION_DEFECT`
- `PLAN_DEFECT`
- `BLOCKED`

Implementation/documentation defects go back to Executor only after Final Reviewer validates the required corrections.

Plan defects go back to Architect for re-investigation and clarification where needed. A revised plan must explicitly return to `READY_FOR_EXECUTION` before execution resumes.

Automatic task correction is limited to three final-adjudication cycles. After the third failed cycle the workflow stops with `BLOCKED` and preserves unresolved evidence.

After Final Reviewer `PASS`, Executor creates one scoped local task commit containing validated task source, required project documentation and relevant `.ai/` evidence. Push is separate and requires explicit user authorization.

## Planning only

```text
/ai-plan <task>
```

Architect can complete mandatory baseline validation first when needed, asks clarification questions instead of inventing decisions, determines documentation impact and produces an implementation-ready plan. No source/project-documentation implementation is performed.

The built-in `Plan` primary agent cannot delegate; therefore it requires a pre-existing validated baseline rather than certifying one itself.

## Execute an existing plan

```text
/ai-execute <task-id-or-plan-id>
```

Execution is blocked unless the baseline is `BASELINE_VALIDATED`, the plan is Architect-approved, task state is `READY_FOR_EXECUTION`, documentation impact is resolved and no material implementation ambiguity remains.

## Independent task review panel

```text
/ai-review <task-id>
```

Runs the two independent reviewers in `TASK_REVIEW` mode against the same validated source/documentation state and then Final Reviewer adjudication.

## Status

```text
/ai-status
```

Reports baseline validation, documentation scope/synchronization, license state, outstanding clarification decisions, task state, reviewer/final status, Git/commit state, push authorization and unresolved external validation.

## Final release

```text
/ai-release
```

The release gate requires a current `BASELINE_VALIDATED` state and an explicit license decision. It validates the production artifact, required project documentation, clean installation/startup, secret safety, data/schema safety, required tests and real external integration validation.

For distributable apps, the maintained installation guide, user manual/wiki, changelog and licensing documentation must match the actual release candidate.

It runs two fresh independent `RELEASE_REVIEW` assessments and sends both reports plus production/documentation evidence to Final Reviewer for adjudication.

Final verdict is exactly one of:

- `READY_FOR_PRODUCTION`
- `NOT_READY_FOR_PRODUCTION`