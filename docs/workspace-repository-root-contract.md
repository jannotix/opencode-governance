# Workspace / repository root contract (3.7.6)

Contract names:

```text
WORKSPACE_REPOSITORY_ROOT_CONTRACT_V1
MULTI_GOVERNANCE_ROOT_TRANSACTION_V1
PROJECT_STATE_CHANGESET_DIAGNOSTIC_V1
```

## Problem

Governance 3.7.4 fingerprint excluded only `<workspace>/.ai/**`. When the Architect ran with a non-Git outer workspace and a nested application repository (for example `Source_Code/`), legitimate writes under `<repository>/.ai/**` changed the project fingerprint and produced a false `PROJECT_STATE_CHANGED` orphan.

## Root model

| Concept | Description |
|---------|-------------|
| Workspace root | Directory passed to the runner (`-WorkspaceDir` / `-ProjectDir`) |
| Repository root | Application Git root (may equal workspace or be nested) |
| Managed Governance roots | Exact bound paths: `workspace/.ai`, `repository/.ai` when distinct |
| Executor worktree roots | Isolated worktrees registered by the Executor contract |
| Transaction / evidence roots | Durable journal under the OpenCode config directory |

## Resolution order

1. Explicit `-RepositoryDir` / `--repository-dir`
2. Unique nested Git worktree under the workspace
3. Workspace itself when it is a Git worktree
4. Workspace itself when no Git repository exists (`NON_GIT_PROJECT_SUPPORTED`)

Typed blockers:

```text
REPOSITORY_ROOT_AMBIGUOUS
REPOSITORY_ROOT_NOT_FOUND
REPOSITORY_ROOT_OUTSIDE_WORKSPACE
REPOSITORY_ROOT_CONTRACT_MISMATCH
```

## Fingerprint exclusions

Exclude only:

- `.git/**` metadata for the integrity contract
- exact registered managed Governance roots
- exact registered Executor worktree roots when applicable

Do **not** exclude arbitrary nested `.ai` directories.

## Multi-root transaction

Before the child starts, every managed Governance root is snapshotted with:

```text
canonical_path
existed_before
tree_hash_before
snapshot_path
role
```

On eligible failure or restore paths, all managed roots are restored and hash-verified. Partial restore fails closed (`MULTI_ROOT_RESTORE_INCOMPLETE`) and retains the orphan journal.

Schema remains compatible with `ARCHITECT_TRANSACTION_V2` via:

```text
extensions.workspace_repository_root_contract
extensions.multi_governance_root_transaction
managed_governance_roots
workspace_root
repository_root
```

## Explicit recovery

```text
-RecoverTransaction
-RecoveryDecision adopt-governance-only|rollback
-ExpectedTransactionHash <sha256 of meta.json>
-TaskId <task>
-WorkspaceDir / -RepositoryDir
```

`adopt-governance-only` requires dead PID, matching roots, matching fingerprint (application unchanged), valid checkpoint, and writes a content-bound recovery receipt. It does not re-run planning.

## Phase continuation

When `/ai-resume` advances to `READY_FOR_EXECUTION`:

```text
ARCHITECT_PHASE_ADVANCED
STATE=READY_FOR_EXECUTION
NEXT_COMMAND=/ai-execute
ATTEMPT_CONSUMED=false
```

## Incident recovery (sanitised)

For a preserved orphan after Governance-only planning on a nested repository layout:

```text
pwsh -NoProfile -File <installed>/architect-attempt.ps1 `
  -RecoverTransaction `
  -WorkspaceDir <workspace> `
  -RepositoryDir <workspace>/Source_Code `
  -Command ai-resume `
  -TaskId <TASK-ID> `
  -RecoveryDecision adopt-governance-only `
  -ExpectedTransactionHash <meta.json sha256> `
  -RoutingConfigPath <routing> `
  -ConfigDir <opencode-config>
```

After adoption, continue with the exact next lifecycle command for the task (for example `/ai-execute` with the verified plan and packet identifiers). Do not embed private absolute paths in shared fixtures.
