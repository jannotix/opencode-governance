# Architect Runner Integration

OpenCode Governance installs deterministic Architect runners (`architect-attempt.ps1|.sh`) with transactional failover, PowerShell 7 host checks, content-aware project-state integrity, routing validation, durable transaction journals, headless permission contracts and workflow-continuation gates. This document describes the current **3.7.3** surface.

## Scope

The transactional Architect runner applies to:

```text
ai-init
ai-audit
ai-discover
ai-plan
ai-resume   # PRE_SIDE_EFFECT only
```

These commands may safely retry because they are restricted to `.ai/**` governance state and must not modify application source or approved project documentation.

`/ai-resume` is accepted only when authoritative `RUN_STATE.json` classifies the resume as `PRE_SIDE_EFFECT` (phases at or before `READY_FOR_EXECUTION` / `PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED`). After the implementation side-effect boundary (`IMPLEMENTING` or later) the runner refuses with:

```text
RESUME_POST_SIDE_EFFECT
```

Post-side-effect resume continues non-transactionally from persisted evidence and never rolls back the whole `.ai/**` tree automatically.

The runner is not used for `ai-workflow`, `ai-execute`, `ai-review` or `ai-release` after implementation or review side-effect boundaries.

## Installed tools

With routing and 3.7.3 capabilities enabled, the installation records fourteen managed tools, including:

```text
opencode-governance-tools/architect-attempt.ps1
opencode-governance-tools/architect-attempt.sh
opencode-governance-tools/executor-attempt.ps1
opencode-governance-tools/executor-attempt.sh
opencode-governance-tools/context-intelligence.ps1
opencode-governance-tools/context-intelligence.sh
opencode-governance-tools/context-intelligence.py
opencode-governance-tools/workflow-continuation.ps1
opencode-governance-tools/workflow-continuation.py
opencode-governance-tools/governance-authority.py
opencode-governance-tools/governance-memory.py
opencode-governance-tools/governance-evidence.py
opencode-governance-tools/governance-simulation.py
opencode-governance-tools/governance-pre-commit.py
```

The routing manifest records:

```text
governance_version: 3.7.3
architect_runner_version: 3.7.3
context_intelligence_version: 3.7.3
workflow_continuation_version: 3.7.3
```

Before replacing an existing routing installation, the wrapper validates the complete new profile. An invalid profile cannot remove the current manifest, aliases or managed tools. Every existing managed tool is copied into the timestamped installation backup before replacement.

## PowerShell host and routing contract

The PowerShell Architect runner requires PowerShell 7 or newer because its process-isolation implementation relies on modern .NET process APIs. Run it through:

```text
pwsh -NoProfile -File
```

Windows PowerShell 5.1 is rejected before the runner resolves project state, creates temporary snapshots or modifies `.ai/**`. The deterministic error is:

```text
POWERSHELL_7_REQUIRED
```

The Windows and Unix runners validate the same routing properties before the first child process starts:

- schema, settings and Architect role presence;
- fail-closed independence policy;
- supported eligible failures (including optional `TOOL_EXECUTION_ABORTED`);
- concrete model, family and variant policy;
- explicit `only_on` arrays;
- positive, unique fallback priorities;
- cooldown from 60 to 86,400 seconds.

JSON arrays and integers are type-checked consistently across PowerShell and Unix. An absent optional work-class array is empty, while scalar strings are rejected rather than coerced.

## Direct command gate

A direct `/ai-init`, `/ai-audit`, `/ai-discover`, `/ai-plan` or pre-side-effect `/ai-resume` invocation inside an already running OpenCode process must stop before `.ai/**` writes when the runner marker is absent.

The deterministic stop result is:

```text
ARCHITECT_RUNNER_REQUIRED
COMMAND: <ai-init|ai-audit|ai-discover|ai-plan|ai-resume>
WINDOWS_HOST: pwsh -NoProfile -File
WINDOWS_RUNNER: <exact-installed-path>
UNIX_RUNNER: <exact-installed-path>
PROJECT_DIR: <CURRENT_PROJECT_ROOT>
WINDOWS_COMMAND: <complete executable command>
UNIX_COMMAND: <complete executable command>
```

The agent must return both complete commands with the actual project root and original arguments substituted. It must not invent another path or launch a nested runner from inside the active OpenCode process.

## Routed child marker

The external runner starts each fresh OpenCode child with both:

```text
OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1
[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]
```

The environment marker identifies the child process. The argument marker is visible to the governed command gate. A marked child continues normally and never recursively launches another runner.

## Project-state integrity

The runner uses:

```text
PROJECT_STATE_FINGERPRINT_V1
```

Before and after every routed attempt, it creates a canonical fingerprint for every project entry outside root `.ai/**` and Git metadata. Each entry includes, as applicable:

- normalized relative path;
- entry type;
- mode or Windows attributes;
- byte length;
- SHA-256 content digest;
- symlink or reparse-point target.

For Git workspaces the fingerprint also binds:

- current `HEAD`, including an unborn repository state;
- the exact Git index file digest;
- recursive submodule status and checked-out commits.

This detects content changes even when a file was already dirty, staged or untracked and the textual Git status classification remains unchanged.

Non-Git project directories are supported through the same full-tree fingerprint. Git is not required merely to run the supported pre-execution commands. When Git metadata exists but the Git executable is unavailable, the runner fails closed because repository state cannot be verified safely.

Any source or project-documentation delta, including a mutation during a nominally successful child attempt, stops with:

```text
ARCHITECT_FAILOVER_BLOCKED: PROJECT_STATE_CHANGED
HUMAN_RECOVERY_REQUIRED
```

The runner does not restore or overwrite changed source content. It restores `.ai/**` only when the non-governance project fingerprint still matches the frozen state.

## Durable Architect transactions and orphan recovery

Before the first route attempt the runner opens a durable transaction journal under the OpenCode configuration directory:

```text
<OPENCODE_CONFIG_DIR>/opencode-governance-architect-tx/<project-key>/
  meta.json                 # ARCHITECT_TRANSACTION_V1
  ai-snapshot/              # byte-identical .ai/** freeze
```

`meta.json` binds command, project path, owner PID, `ai_hash` and `project_state_fingerprint`.

On the next runner invocation for the same project:

1. if the owner PID is still alive → `ARCHITECT_TRANSACTION_ACTIVE`;
2. if the PID is dead and the project fingerprint still matches → restore `.ai/**` from the durable snapshot (`ARCHITECT_ORPHAN_RECOVERED`) and clear the journal;
3. if the project fingerprint drifted → `ARCHITECT_ORPHAN_RECOVERY_BLOCKED` / `HUMAN_RECOVERY_REQUIRED`.

Successful completion closes the transaction. Non-successful exits restore `.ai/**` when the project fingerprint is unchanged, then close the journal. When restore is impossible the journal is retained as an orphan for the next invocation.

## Transactional retry

Before the first route attempt, the runner freezes:

- the complete `.ai/**` tree and its hash (durable snapshot);
- the complete non-`.ai/**` project content fingerprint;
- Git HEAD, index and recursive submodule state when applicable;
- the routing manifest and route order.

After an eligible provider, quota, rate-limit, retirement, temporary-availability, bounded-timeout or tool-execution-abort failure, it:

1. rejects the partial command result;
2. verifies that the project fingerprint is unchanged;
3. restores `.ai/**` byte-for-byte;
4. verifies the restored hash;
5. starts a fresh OpenCode process on the next eligible route;
6. never continues the failed model's partial output.

Any source/project-documentation change, restoration mismatch, ineligible failure or exhausted route set stops with human recovery required.

## Failure classification

`Classify-Failure` / `classify` maps child output to deterministic classes. New in 3.7.2:

```text
TOOL_EXECUTION_ABORTED
```

Matched from phrases such as `tool execution aborted`, `tool call aborted`, `process killed`, `terminated by signal`, or abnormal exit codes (`< 0` or `>= 128`). Profiles may list `TOOL_EXECUTION_ABORTED` under `settings.eligible_failures` to allow bounded failover after an abort; otherwise the failure is ineligible but `.ai/**` is still restored when the project fingerprint is unchanged.

New in 3.7.3:

```text
ARCHITECT_PERMISSION_BLOCKED
HEADLESS_PERMISSION_CONTRACT_VIOLATION
```

Matched from non-interactive permission auto-rejection (`permission requested`, `auto-rejecting`, `The user rejected permission`). This class is never eligible for model fallback, does not consume implementation/review cycles, rolls back `.ai/**` when safe, and requires a Governance correction. External children always receive temporary `OPENCODE_CONFIG_CONTENT` with `ARCHITECT_HEADLESS_PERMISSION_CONTRACT_V1` (deny-by-default bash, no blanket `--auto`). See [Architect Headless Permission Contract](architect-headless-permission-contract.md).

## Windows example

```powershell
pwsh -NoProfile -File `
  "$env:OPENCODE_CONFIG_DIR\opencode-governance-tools\architect-attempt.ps1" `
  -ProjectDir "C:\path\to\project" `
  -Command ai-resume `
  -Arguments "Resume TASK-001 from READY_FOR_EXECUTION." `
  -RoutingConfigPath "$env:OPENCODE_CONFIG_DIR\opencode-governance-routing.json" `
  -ConfigDir "$env:OPENCODE_CONFIG_DIR"
```

## Verification

```powershell
./scripts/verify.ps1 -ConfigDir <config-dir>
./scripts/verify-routing.ps1 -ConfigDir <config-dir>
```

```bash
./scripts/verify.sh <config-dir>
bash ./scripts/verify-routing.sh <config-dir>
```

The routing verifier checks exact managed tool paths, installed files, Architect/Build/Plan policy markers, command entry gates (including pre-side-effect `/ai-resume` on 3.7.2+), headless permission markers on 3.7.3, project-state fingerprint markers, cooldown validation, Context Intelligence hardening, workflow-continuation helpers, hidden-route consistency and the preserved Executor routing contract. PowerShell wrappers rely on terminating errors from PowerShell child scripts and never infer their outcome from a pre-existing native `$LASTEXITCODE` value.

## Distinguishing workspace errors

`ARCHITECT_RUNNER_UNAVAILABLE`, `ARCHITECT_RUNNER_REQUIRED` or `POWERSHELL_7_REQUIRED` concern Architect runner installation or invocation.

`PROJECT_STATE_CHANGED` means a child attempt changed source or project documentation outside root `.ai/**`; this is a hard integrity block, not an eligible provider/model fallback condition.

`RESUME_POST_SIDE_EFFECT` means `/ai-resume` was routed transactionally after implementation began; use non-transactional evidence reconciliation instead.

`ARCHITECT_ORPHAN_RECOVERED` / `ARCHITECT_ORPHAN_RECOVERY_BLOCKED` concern durable transaction journals left by a previous incomplete run.

`DISCOVERY_BLOCKED_WRONG_WORKSPACE` is a different, correct fail-closed condition: a prompt intended for the Governance repository was executed inside an application repository, or vice versa.

The installation includes `workflow-continuation.ps1` and `workflow-continuation.py`; `/ai-workflow` and `/ai-resume` must obtain `TERMINAL_ALLOWED` before reporting completion. `CONTINUE_REQUIRED` preserves the current lifecycle and `INVALID_RUN_STATE` fails closed.
