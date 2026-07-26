# Permissions

## Architect

- source edits: denied;
- `.ai/**`: allowed;
- delegation: Executor, Implementation Reviewer, Architecture/Security Reviewer and Final Reviewer only;
- may update baseline/governance evidence only after validated baseline-adjudication findings;
- destructive shell/Git operations: denied or require confirmation;
- push: denied.

## Governed Build

`build` is a primary entry point using the Architect model and the complete governance lifecycle.

- source edits: denied;
- `.ai/**`: allowed;
- delegation: Executor, both independent Reviewers and Final Reviewer only;
- may coordinate `BASELINE_AUDIT` and `TASK_REVIEW` modes;
- implementation must be delegated to Executor;
- destructive shell/Git operations: denied or require confirmation;
- push: denied.

## Governed Plan

`plan` is a primary planning-only entry point using the Architect model.

- source edits: denied;
- `.ai/**`: allowed;
- delegation: denied;
- implementation/review execution: denied by prompt policy;
- requires an already `BASELINE_VALIDATED` baseline;
- cannot self-certify a draft/stale baseline and must return `BASELINE_AUDIT_REQUIRED` when revalidation is needed;
- destructive shell/Git operations: denied or require confirmation;
- push: denied.

## Executor

- source edits: allowed;
- subagent delegation: denied;
- execution requires both `BASELINE_VALIDATED` and `READY_FOR_EXECUTION`;
- destructive shell/Git operations: denied;
- local add/commit: confirmation required;
- push: confirmation required and allowed only after explicit user authorization for that specific push.

## Independent Reviewers

Both `reviewer` and `reviewer-architecture` use the same safety boundary:

- source edits: denied;
- `.ai/**`: allowed only for their own review/audit evidence;
- delegation: denied;
- commit/push: denied;
- destructive shell/Git operations: denied;
- current-cycle sibling review output must not be used as evidence;
- `BASELINE_AUDIT` must independently inspect primary repository evidence rather than treating the Architect draft as authoritative;
- `TASK_REVIEW` must independently inspect task evidence rather than treating the Architect plan, Executor report or passing tests as authoritative.

## Final Reviewer

- source edits: denied;
- `.ai/**`: allowed for final baseline/task/release adjudication evidence;
- delegation: denied;
- commit/push: denied;
- destructive shell/Git operations: denied;
- reviewer findings are advisory until independently validated against primary repository evidence;
- only Final Reviewer may return `BASELINE_PASS` / `BASELINE_DEFECT` for baseline validation or the controlling task/release verdicts.

Prompt-level policy is stricter than permission availability:

- source implementation is prohibited before `BASELINE_VALIDATED`;
- Executor may implement only `READY_FOR_EXECUTION` tasks;
- source edits are frozen during each task dual-review/adjudication cycle;
- raw reviewer findings never authorize automatic code changes;
- baseline findings never authorize source edits during `/ai-init` or `/ai-audit`;
- local task commit is required only after Final Reviewer `PASS`;
- commit permission never implies push permission;
- staged changes must be scoped to the validated task and scanned for plaintext secrets;
- unrelated user changes must not be included.

Permissions are enforced in the generated OpenCode agent configuration in addition to prompt-level rules.