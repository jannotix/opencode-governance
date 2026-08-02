# Architect Headless Permission Contract (3.7.3)

Contract name: `ARCHITECT_HEADLESS_PERMISSION_CONTRACT_V1`

## Why interactive Architect permissions cannot be reused headlessly

The interactive Architect profile uses:

```yaml
bash:
  "*": ask
```

with a small set of allow/deny overrides. That works in OpenCode Desktop, where a human can approve `ask` prompts. A headless `opencode run` child automatically rejects unanswered permission prompts:

```text
permission requested: bash (...); auto-rejecting
The user rejected permission to use this specific tool call.
```

The child may still exit zero without advancing the task checkpoint. That is a Governance permission-contract defect, not a provider or model failure.

## Selected architecture

External Architect runners (`architect-attempt.ps1|.sh`, installed from `run-governed.*`) inject a **temporary runtime-only** overlay through:

```text
OPENCODE_CONFIG_CONTENT
```

OpenCode config precedence places `OPENCODE_CONFIG_CONTENT` after project config, so managed denials remain effective against local project weakening. The overlay:

- keeps `--agent architect` (installed instructions and routing remain authoritative);
- overrides Architect permissions for the child process only;
- preserves the selected model and variant from the routing decision;
- never rewrites the user's persistent `opencode.json(c)`;
- never enables blanket `--auto`;
- is bound into the transaction journal as `runtime_policy_sha256`;
- is discarded when the child exits (environment-scoped).

Interactive Desktop sessions continue to use the interactive Architect frontmatter (`bash: "*": ask`). The headless contract does **not** permanently weaken that profile.

### Why blanket `--auto` was rejected

`--auto` auto-approves every non-denied `ask`. Combined with residual `ask` defaults or project overrides it can grant unintended shell authority. The headless contract uses **deny-by-default** bash rules (`"*": deny` first, explicit read-only allows later, hard denials last) so residual asks fail closed instead of auto-approving.

## Native tool preference

Architect instructions require ordinary discovery to prefer native OpenCode tools before shell:

1. `read`
2. `list` / directory tools
3. `glob`
4. `grep`
5. LSP
6. approved read-only Explore / Scout tasks

Shell is reserved for operations that genuinely require a process (for example exact Git probes).

## Allowed shell classes (headless)

Deny-by-default. Explicit allows cover only:

**Git (read-only):** `status`, `diff`, `log`, `show`, `grep`, `rev-parse`, `ls-files`, `rev-list`, `submodule status`, `worktree list`, `branch --show-current`, `remote -v` (metadata only). Direct forms and `git -C <path> <subcommand>` forms are allowed when the path token has no shell metacharacters. Mutating Git (`add`, `commit`, `push`, `reset`, …) is denied even with `-C`. This is **not** a broad shell grant; nested interpreters remain denied. The OpenCode permission matcher does not re-validate that `<path>` equals the resolved repository root—Governance runners still invoke Git only against the contract-resolved repository.

**Windows (minimum forms):** `Test-Path`, `Get-ChildItem`, `Get-Content`, `Get-Item`, `Get-FileHash`, `Resolve-Path`, `Select-String`, `Get-Command`, `ConvertFrom-Json`, `Select-Object`, `Where-Object`, `ForEach-Object`, `Sort-Object`, `Measure-Object`, `Format-List`, `Format-Table`.

**Unix (minimum forms):** `pwd`, `ls`, `cat`, `head`, `tail`, `grep`, `rg`, `stat`, `sha256sum`, `realpath`, read-only `sed -n`, limited `find` print/type/name/maxdepth.

Pipelines and compound commands must evaluate component-by-component. An allowed leading command never authorizes a later denied command.

## Denied shell classes (headless)

Including but not limited to:

- `git push`, `fetch`/`pull` that mutate remote-tracking state, remote create/modify, merge, rebase, cherry-pick, revert, destructive reset, checkout/switch of the real project, `git clean`, index writes;
- application-source writes, deletion, move, arbitrary copy;
- `Set-Content`, `Add-Content`, `Out-File`, shell redirection;
- nested interpreters (`pwsh -Command`, `powershell -EncodedCommand`, `cmd /c`, `bash -c`, `sh -c`, Python/Node/PHP/Ruby/Perl as mutation interpreters);
- package install/update, provider authentication, credential access, deployment, publication, production rollback;
- unrestricted network tools (`curl`/`wget`/`ssh`/`scp` via bash);
- arbitrary scripts and `Invoke-Expression`.

Only Architect may write authorised Governance state under `.ai/**`. Only Executor may edit application source through the isolated Executor contract.

## External directory policy

Narrow, canonicalised, read-oriented roots may be allowed for the active OpenCode config directory, installed Governance tools, and the handoff file directory. Broad home-directory access is denied via `external_directory: "*": deny` plus explicit root allows. Credential paths (`.env`, SSH keys, cloud credentials, browser profiles, `.netrc`, kubeconfig) are denied at the `read` layer, with additional bash hard-denies for common secret path forms.

**Residual risk (honest):** OpenCode enforces path-aware tools and many bash path touches through `external_directory`, but shell is not a perfect sandbox. Prefer native OpenCode tools for filesystem discovery. The trusted runner should verify installation metadata itself and pass only sanitised non-secret results to the Architect.

Runtime external grants are environment-scoped and disappear when the child ends.

## JSONC routing handling

Runners load the routing manifest with the official JSONC normalisation contract (comment strip + trailing-comma removal) **in memory only**. The installed file is never rewritten merely to read it. Logs record `source_sha256` and `semantic_sha256`.

## Launcher resolution

Exactly one launcher is selected. Supported: direct executables, npm `.ps1`/`.cmd`, WinGet, Scoop, Chocolatey, Unix PATH/bin locations, explicit `OpenCodeCommand` and prefix arguments. Logs distinguish host executable, launcher type, launcher path and prefix count without printing handoffs or secrets.

## Typed permission failure

When structured OpenCode output indicates permission auto-reject, runners return:

```text
ARCHITECT_PERMISSION_BLOCKED
```

with `HEADLESS_PERMISSION_CONTRACT_VIOLATION` detail containing only:

- denied tool;
- sanitised command class;
- route;
- attempt number;
- permission-contract version;
- logs path.

Effects:

- ineligible for model fallback;
- does not consume implementation or review cycles;
- rolls back `.ai/**` when the project fingerprint is unchanged;
- preserves application source and diagnostic logs;
- requires a Governance correction or explicit typed owner decision.

`ARCHITECT_NO_PROGRESS` remains only for genuine zero-exit/no-progress cases with no more precise blocker.

## Transaction semantics

Exit code zero is transport evidence only. Success still requires persisted progress / `GOVERNANCE_RESULT` postconditions. Transactions bind `permission_contract` and `runtime_policy_sha256`.

## Troubleshooting

1. Upgrade/reinstall Governance 3.7.3 into the active `OPENCODE_CONFIG_DIR`.
2. Run `verify` and `verify-routing`.
3. Re-run the external Architect attempt.
4. If `ARCHITECT_PERMISSION_BLOCKED` persists, inspect attempt logs for the denied tool class and correct the Governance contract—do not enable blanket shell allow or `--auto`.
5. Prefer native OpenCode tools for filesystem discovery.

## Local verification

```powershell
pwsh -NoProfile -File .\scripts\verify.ps1 -ConfigDir $env:OPENCODE_CONFIG_DIR
pwsh -NoProfile -File .\scripts\verify-routing.ps1 -ConfigDir $env:OPENCODE_CONFIG_DIR
pwsh -NoProfile -File .\tests\test-architect-headless-permissions.ps1
```

```bash
bash ./scripts/verify.sh "$OPENCODE_CONFIG_DIR"
bash ./scripts/verify-routing.sh "$OPENCODE_CONFIG_DIR"
bash ./tests/test-architect-headless-permissions.sh
```
