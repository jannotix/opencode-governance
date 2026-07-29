# OpenCode Governance

Provider- and model-agnostic product-lifecycle and engineering governance for OpenCode projects.

> Community project. Not affiliated with or maintained by the OpenCode team.

Current release: **3.3.4 — Project State Integrity**.

v3 guides an idea through adaptive product discovery, constructive technical challenge, approved product definition, vertical delivery, evidence-driven implementation, independent review, product-completeness reconciliation and production-readiness assessment.

## Core invariants

- Seven public governance agents; `architect` is default and orchestrator.
- Only `executor` writes application source and approved project documentation.
- Implementation and architecture/security reviewers remain independent.
- Final Reviewer controls baseline, discovery, task, product and release adjudication.
- Requirement provenance and evidence outrank summaries and assertions.
- No automatic push, merge, deployment or production rollback.
- Provider/model IDs and concrete variants are supplied only during local setup.
- Tracked examples use synthetic identifiers; personal routing profiles remain untracked.
- Optional fallback aliases and deterministic helpers are transports, not additional governance authorities.

## Commands

```text
/ai-init
/ai-audit
/ai-docs
/ai-discover
/ai-plan
/ai-execute
/ai-review
/ai-workflow
/ai-status
/ai-resume
/ai-metrics
/ai-release
```

## Installation

Legacy single-model routing:

- Windows: `./scripts/install.ps1`
- macOS/Linux: `chmod +x scripts/install.sh && ./scripts/install.sh`

Optional failover routing:

1. copy `examples/routing/continuous-coding.template.json` to a local untracked file;
2. replace every synthetic provider/model ID with an exact value from the local OpenCode catalog;
3. resolve every `variant_policy: highest_supported` to a concrete supported local `variant`;
4. keep credentials, subscriptions, quotas and personal routing preferences outside the repository;
5. install the resolved local profile:
   - Windows: `./scripts/install.ps1 -NonInteractive -RoutingConfigPath <profile.json>`
   - macOS/Linux: `./scripts/install.sh --routing-config <profile.json>`

The installer renders seven public agents and twelve commands, preserves unrelated configuration and creates a timestamped backup. With a routing profile it writes the non-secret `opencode-governance-routing.json` manifest, renders only enabled hidden fallback aliases and installs managed Architect and Executor transactional helpers. No hidden Architect alias is created.

## Local configuration durability

Windows desktop application updates are outside the control of this repository. Version 3.3.1 added an explicit fail-closed wrapper that preserves the external OpenCode configuration directory before an owner-triggered update.

Enable persistence and create a baseline snapshot:

```powershell
./scripts/config-durability.ps1 `
  -Action Enable `
  -ConfigDir <opencode-config-directory>
```

Run an update through the protective wrapper:

```powershell
./scripts/update-opencode-safely.ps1 `
  -ConfigDir <opencode-config-directory> `
  -UpdateExecutable <updater-executable> `
  -UpdateArguments @(<argument-list>)
```

The wrapper snapshots all protected configuration files to a separate user-local durability store, runs only the supplied updater command, detects additions/removals/content drift, quarantines changed post-update state and restores the pre-update snapshot by default. Manifests contain paths, lengths and SHA-256 hashes only; configuration contents and credentials remain local.

Automatic vendor updates are not intercepted. Use the wrapper when byte-for-byte configuration preservation is required. Configuration preservation does not prove schema compatibility with a newer OpenCode release. See [Local Configuration Durability](docs/local-configuration-durability.md).

## Architect failover runner

Top-level Architect failover is available only for pre-execution commands:

```text
ai-init
ai-audit
ai-discover
ai-plan
```

With Architect failover enabled, version 3.3.4 installs deterministic entrypoints inside the active OpenCode configuration directory:

```text
opencode-governance-tools/architect-attempt.ps1
opencode-governance-tools/architect-attempt.sh
```

Windows requires PowerShell 7 or newer. Invoke the PowerShell runner explicitly through `pwsh`; Windows PowerShell 5.1 fails before reading or modifying project state with `POWERSHELL_7_REQUIRED`.

```powershell
pwsh -NoProfile -File "<config-dir>\opencode-governance-tools\architect-attempt.ps1" `
  -ProjectDir "<project>" `
  -Command ai-plan `
  -Arguments "<request>" `
  -RoutingConfigPath "<config-dir>\opencode-governance-routing.json" `
  -ConfigDir "<config-dir>"
```

macOS/Linux:

```bash
"<config-dir>/opencode-governance-tools/architect-attempt.sh" \
  --project-dir "<project>" \
  --command ai-plan \
  --arguments "<request>" \
  --routing-config "<config-dir>/opencode-governance-routing.json" \
  --config-dir "<config-dir>"
```

Direct `/ai-init`, `/ai-audit`, `/ai-discover` or `/ai-plan` invocation inside an existing OpenCode process fails closed before `.ai/**` writes with `ARCHITECT_RUNNER_REQUIRED`, the exact installed runner path and the required Windows host command. The external runner marks child attempts with `[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]`; marked children continue normally and never recursively launch another runner.

The runner starts a fresh `opencode run` process for each route, snapshots the complete `.ai/**` tree and restores it before an eligible retry. A fallback never continues partial output and a recovered primary never interrupts an active fallback.

Version 3.3.4 fingerprints every project entry outside root `.ai/**` before and after each routed attempt using path, entry type, mode/attributes, length, SHA-256 and symlink target. Git workspaces additionally bind the fingerprint to HEAD, the index and recursive submodule state. Non-Git directories are supported with the same content-integrity contract. Any source or project-documentation delta returns `PROJECT_STATE_CHANGED` and blocks fallback, including changes to files that were already dirty, staged or untracked.

Content fingerprinting scans the complete project tree outside `.ai/**`; very large workspaces may incur additional pre/post attempt latency. This cost is intentional because classification-only Git status cannot prove immutability.

Top-level automatic restart remains unavailable for `ai-workflow`, `ai-execute`, `ai-review` and `ai-release`, because those flows may already have crossed an implementation or review side-effect boundary.

## Executor failover

When enabled in the local routing profile, `/ai-execute` and the implementation phase of `/ai-workflow` use isolated Executor attempts:

```text
select route
→ prepare detached worktree at frozen HEAD
→ run complete Executor inside EXECUTION_ROOT
→ finalize matching complete report into binary patch
→ promote only if real worktree state is unchanged and non-overlapping
```

Eligible route failure discards the isolated worktree and restarts the complete Executor from the same packet and frozen target on the next eligible route. Failed partial changes never enter the real worktree.

Managed helpers are installed under the local OpenCode configuration directory:

```text
opencode-governance-tools/executor-attempt.ps1
opencode-governance-tools/executor-attempt.sh
```

Promotion is not validation. Evidence-Driven Verification, Operational Assurance, independent dual review, Final Reviewer adjudication and explicit commit/push authorization remain unchanged.

## Project state

```text
.ai/
├── CODEBASE_BASELINE.md
├── CONTEXT_INDEX.md
├── INSTRUCTION_INDEX.md
├── GOVERNANCE_MEMORY.md
├── DOCUMENTATION_SCOPE.md
├── DEPLOYMENT_SCOPE.md
├── PROJECT_HISTORY.md
├── STATUS.md
├── product/
│   ├── PRODUCT_VISION.md
│   ├── USER_AND_ROLE_MODEL.md
│   ├── DOMAIN_AND_PROCESS_MODEL.md
│   ├── PRODUCT_COMPLETENESS_MATRIX.md
│   ├── PRODUCT_BLUEPRINT.md
│   └── PRODUCT_DECISIONS.md
├── baseline-audits/
└── tasks/
```

Discovery is always `LIGHT`, `STANDARD` or `DEEP`. Domain evidence and recommendations do not become requirements automatically. A validated milestone may remain `PRODUCT_INCOMPLETE`. `PRODUCT_COMPLETENESS_VERDICT` is separate from `RELEASE_VERDICT`.

## Documentation

Focused references: [Product Lifecycle Governance](docs/product-lifecycle-governance.md), [Model Failover](docs/model-failover.md), [Architect Runner Integration](docs/architect-runner-integration.md), [Local Configuration Durability](docs/local-configuration-durability.md), [Workflow](docs/workflow.md), [Requirement Provenance](docs/requirement-provenance.md), [Context Efficiency and Resume](docs/context-efficiency-resume.md), [Evidence-Driven Verification](docs/evidence-driven-verification.md), [Operational Assurance](docs/operational-assurance.md), [Permissions](docs/permissions.md), [Project Documentation](docs/project-documentation.md) and [Troubleshooting](docs/troubleshooting.md).

## Verification

Base rendered contract:

- Windows: `./scripts/verify.ps1`
- macOS/Linux: `./scripts/verify.sh`

Optional routing contract:

- Windows: `./scripts/verify-routing.ps1`
- macOS/Linux: `bash ./scripts/verify-routing.sh`

Local configuration durability:

- Windows: `./scripts/config-durability.ps1 -Action Status`

## License

FSL-1.1-MIT. Each released version becomes available under the MIT License on the second anniversary of its release date. See [LICENSE](LICENSE).
