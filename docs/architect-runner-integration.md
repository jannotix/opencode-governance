# Architect Runner Integration

OpenCode Governance 3.3.2 fixed the `ARCHITECT_RUNNER_UNAVAILABLE` installation defect for Architect pre-execution failover. Version 3.3.3 added an explicit PowerShell host contract and reliable PowerShell child-script result propagation. Version 3.3.4 adds content-aware project-state integrity and non-Git workspace support.

## Scope

The transactional Architect runner applies only to:

```text
ai-init
ai-audit
ai-discover
ai-plan
```

These commands may safely retry because they are restricted to `.ai/**` governance state and must not modify application source or approved project documentation.

The runner is not used for `ai-workflow`, `ai-execute`, `ai-review` or `ai-release` after implementation or review side-effect boundaries.

## Installed tools

With Architect failover enabled, the installer creates and records these managed tools under the active OpenCode configuration directory:

```text
opencode-governance-tools/architect-attempt.ps1
opencode-governance-tools/architect-attempt.sh
opencode-governance-tools/executor-attempt.ps1
opencode-governance-tools/executor-attempt.sh
```

The routing manifest records `governance_version: 3.3.4`, `architect_runner_version: 3.3.4` and the exact four managed tool paths.

## PowerShell host contract

The PowerShell Architect runner requires PowerShell 7 or newer because its process-isolation implementation relies on modern .NET process APIs. Run it through:

```text
pwsh -NoProfile -File
```

Windows PowerShell 5.1 is rejected before the runner resolves project state, creates temporary snapshots or modifies `.ai/**`. The deterministic error is:

```text
POWERSHELL_7_REQUIRED
```

The Unix runner remains available independently through `architect-attempt.sh`.

## Direct command gate

A direct `/ai-init`, `/ai-audit`, `/ai-discover` or `/ai-plan` invocation inside an already running OpenCode process must stop before `.ai/**` writes when the runner marker is absent.

The deterministic stop result is:

```text
ARCHITECT_RUNNER_REQUIRED
COMMAND: <ai-init|ai-audit|ai-discover|ai-plan>
WINDOWS_HOST: pwsh -NoProfile -File
WINDOWS_RUNNER: <exact-installed-path>
UNIX_RUNNER: <exact-installed-path>
PROJECT_DIR: <CURRENT_PROJECT_ROOT>
```

The agent must not invent another path and must not launch a nested runner from inside the active OpenCode process.

## Routed child marker

The external runner starts each fresh OpenCode child with both:

```text
OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1
[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]
```

The environment marker identifies the child process. The argument marker is visible to the governed command gate. A marked child continues normally and never recursively launches another runner.

## Project-state integrity

Version 3.3.4 replaces classification-only `git status --porcelain` comparison with:

```text
PROJECT_STATE_FINGERPRINT_V1
```

Before and after every routed attempt, the runner creates a canonical fingerprint for every project entry outside root `.ai/**` and Git metadata. Each entry includes, as applicable:

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

Non-Git project directories are supported through the same full-tree fingerprint. Git is not required merely to run `/ai-init`, `/ai-audit`, `/ai-discover` or `/ai-plan`. When Git metadata exists but the Git executable is unavailable, the runner fails closed because repository state cannot be verified safely.

Any source or project-documentation delta, including a mutation during a nominally successful child attempt, stops with:

```text
ARCHITECT_FAILOVER_BLOCKED: PROJECT_STATE_CHANGED
HUMAN_RECOVERY_REQUIRED
```

The runner does not restore or overwrite changed source content. It restores `.ai/**` only when the non-governance project fingerprint still matches the frozen state.

Full content hashing intentionally adds pre/post attempt work, especially on large repositories. This cost is required to provide an immutability guarantee that status classification alone cannot provide.

## Transactional retry

Before the first route attempt, the runner freezes:

- the complete `.ai/**` tree and its hash;
- the complete non-`.ai/**` project content fingerprint;
- Git HEAD, index and recursive submodule state when applicable;
- the routing manifest and route order.

After an eligible provider, quota, rate-limit, retirement, temporary-availability or bounded-timeout failure, it:

1. rejects the partial command result;
2. verifies that the project fingerprint is unchanged;
3. restores `.ai/**` byte-for-byte;
4. verifies the restored hash;
5. starts a fresh OpenCode process on the next eligible route;
6. never continues the failed model's partial output.

Any source/project-documentation change, restoration mismatch, ineligible failure or exhausted route set stops with human recovery required.

## Windows example

```powershell
pwsh -NoProfile -File `
  "$env:OPENCODE_CONFIG_DIR\opencode-governance-tools\architect-attempt.ps1" `
  -ProjectDir "C:\path\to\project" `
  -Command ai-init `
  -Arguments "Initialize and validate the project baseline." `
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

The routing verifier checks exact managed tool paths, installed files, Architect/Build/Plan policy markers, command entry gates, project-state fingerprint markers, hidden-route consistency and the preserved Executor routing contract. PowerShell wrappers rely on terminating errors from PowerShell child scripts and never infer their outcome from a pre-existing native `$LASTEXITCODE` value.

## Distinguishing workspace errors

`ARCHITECT_RUNNER_UNAVAILABLE`, `ARCHITECT_RUNNER_REQUIRED` or `POWERSHELL_7_REQUIRED` concern Architect runner installation or invocation.

`PROJECT_STATE_CHANGED` means a child attempt changed source or project documentation outside root `.ai/**`; this is a hard integrity block, not an eligible provider/model fallback condition.

`DISCOVERY_BLOCKED_WRONG_WORKSPACE` is a different, correct fail-closed condition: a prompt intended for the Governance repository was executed inside an application repository, or vice versa. Version 3.3.4 does not weaken workspace validation.
