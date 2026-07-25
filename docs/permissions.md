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
- push: denied;
- local add/commit: confirmation required.

## Reviewer

- source edits: denied;
- `.ai/**`: allowed;
- delegation: denied;
- commit/push: denied;
- destructive shell/Git operations: denied.

Permissions are enforced in the generated OpenCode agent configuration in addition to prompt-level rules.
