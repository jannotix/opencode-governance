# Permissions

## Architect

- source/project-documentation edits: denied;
- `.ai/**`: allowed;
- `question`: explicitly allowed for clarification of material project decisions;
- delegation: Executor, Implementation Reviewer, Architecture/Security Reviewer and Final Reviewer only;
- may update baseline/governance evidence only after validated baseline-adjudication findings;
- destructive shell/Git operations: denied or require confirmation;
- push: denied.

Architect must ask the developer/project owner rather than invent a material product, behaviour, compatibility, data, integration, deployment, packaging, documentation or licensing decision that cannot be established from approved requirements or primary evidence.

## Governed Build

`build` is a primary entry point using the Architect model and the complete governance lifecycle.

- source/project-documentation edits: denied;
- `.ai/**`: allowed;
- `question`: explicitly allowed;
- delegation: Executor, both independent Reviewers and Final Reviewer only;
- may coordinate `BASELINE_AUDIT` and `TASK_REVIEW` modes;
- implementation/documentation writes must be delegated to Executor;
- destructive shell/Git operations: denied or require confirmation;
- push: denied.

## Governed Plan

`plan` is a primary planning-only entry point using the Architect model.

- source/project-documentation edits: denied;
- `.ai/**`: allowed;
- `question`: explicitly allowed;
- delegation: denied;
- implementation/review execution: denied by prompt policy;
- requires an already `BASELINE_VALIDATED` baseline;
- cannot self-certify a draft/stale baseline and must return `BASELINE_AUDIT_REQUIRED` when revalidation is needed;
- may clarify material ambiguity before producing a plan;
- destructive shell/Git operations: denied or require confirmation;
- push: denied.

## Executor

- source and approved project-documentation edits: allowed;
- subagent delegation: denied;
- execution requires `BASELINE_VALIDATED`, `READY_FOR_EXECUTION` and resolved `DOCUMENTATION_IMPACT`;
- must not invent an unresolved project/license decision; returns `PLAN_CONFLICT`/`BLOCKED` instead;
- synchronizes required canonical project docs before `TASK_VALIDATED`;
- destructive shell/Git operations: denied;
- local add/commit: confirmation required;
- push: confirmation required and allowed only after explicit user authorization for that specific push.

## Independent Reviewers

Both `reviewer` and `reviewer-architecture` use the same safety boundary:

- source/project-documentation edits: denied;
- `.ai/**`: allowed only for their own review/audit evidence;
- delegation: denied;
- commit/push: denied;
- destructive shell/Git operations: denied;
- current-cycle sibling review output must not be used as evidence;
- `BASELINE_AUDIT` independently inspects primary repository and documentation evidence rather than treating Architect's draft as authoritative;
- `TASK_REVIEW` independently checks implementation plus required project documentation rather than treating Architect's plan, Executor report or passing tests as authoritative;
- `RELEASE_REVIEW` checks the production candidate, maintained documentation and licensing state.

## Final Reviewer

- source/project-documentation edits: denied;
- `.ai/**`: allowed for final baseline/task/release adjudication evidence;
- delegation: denied;
- commit/push: denied;
- destructive shell/Git operations: denied;
- reviewer findings are advisory until independently validated against primary repository/documentation evidence;
- only Final Reviewer may return `BASELINE_PASS` / `BASELINE_DEFECT` for baseline validation or controlling task/release verdicts;
- required stale/missing/contradictory documentation prevents task `PASS`;
- `LICENSE_DECISION_REQUIRED` prevents `READY_FOR_PRODUCTION`.

Prompt-level policy is stricter than permission availability:

- source implementation is prohibited before `BASELINE_VALIDATED`;
- unresolved material implementation ambiguity prevents `READY_FOR_EXECUTION`;
- Executor may implement only `READY_FOR_EXECUTION` tasks;
- every task must resolve `DOCUMENTATION_IMPACT`;
- required project documentation must be synchronized before `TASK_VALIDATED`;
- source and task-documentation edits are frozen during each dual-review/adjudication cycle;
- raw reviewer findings never authorize automatic code/documentation changes;
- baseline findings never authorize source/project-documentation edits during `/ai-init` or `/ai-audit`;
- `/ai-docs` delegates documentation writes only through Executor and the standard review pipeline;
- local task commit is required only after Final Reviewer `PASS`;
- commit permission never implies push permission;
- staged changes must be scoped to the validated task and scanned for plaintext secrets;
- unrelated user changes must not be included;
- `docs/**` and `.ai/**` are excluded from production/runtime artifacts by default unless an explicit legal/packaging/runtime exception is recorded.

Permissions are enforced in the generated OpenCode agent configuration in addition to prompt-level rules.