# Permissions

## Architect

- source edits: denied;
- `.ai/**`: allowed;
- delegation: Executor and Reviewer only;
- destructive shell/Git operations: denied or require confirmation;
- push: denied.

## Executor

- source edits: allowed;
- subagent delegation: denied;
- destructive shell/Git operations: denied;
- local add/commit: confirmation required;
- push: confirmation required and allowed only after explicit user authorization for that specific push.

## Reviewer

- source edits: denied;
- `.ai/**`: allowed;
- delegation: denied;
- commit/push: denied;
- destructive shell/Git operations: denied.

Prompt-level policy is stricter than permission availability:

- Executor may implement only `READY_FOR_EXECUTION` tasks;
- local task commit is required only after Reviewer `PASS`;
- commit permission never implies push permission;
- staged changes must be scoped to the validated task and scanned for plaintext secrets;
- unrelated user changes must not be included.

Permissions are enforced in the generated OpenCode agent configuration in addition to prompt-level rules.
