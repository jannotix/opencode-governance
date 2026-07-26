# Permissions

## Architect

- source edits: denied;
- `.ai/**`: allowed;
- delegation: Executor, Implementation Reviewer, Architecture/Security Reviewer and Final Reviewer only;
- destructive shell/Git operations: denied or require confirmation;
- push: denied.

## Executor

- source edits: allowed;
- subagent delegation: denied;
- destructive shell/Git operations: denied;
- local add/commit: confirmation required;
- push: confirmation required and allowed only after explicit user authorization for that specific push.

## Independent Reviewers

Both `reviewer` and `reviewer-architecture` use the same safety boundary:

- source edits: denied;
- `.ai/**`: allowed only for their own review evidence;
- delegation: denied;
- commit/push: denied;
- destructive shell/Git operations: denied;
- current-cycle sibling review output must not be used as evidence.

## Final Reviewer

- source edits: denied;
- `.ai/**`: allowed for final adjudication evidence;
- delegation: denied;
- commit/push: denied;
- destructive shell/Git operations: denied;
- reviewer findings are advisory until independently validated against primary repository evidence.

Prompt-level policy is stricter than permission availability:

- Executor may implement only `READY_FOR_EXECUTION` tasks;
- source edits are frozen during each dual-review/adjudication cycle;
- raw reviewer findings never authorize automatic code changes;
- local task commit is required only after Final Reviewer `PASS`;
- commit permission never implies push permission;
- staged changes must be scoped to the validated task and scanned for plaintext secrets;
- unrelated user changes must not be included.

Permissions are enforced in the generated OpenCode agent configuration in addition to prompt-level rules.