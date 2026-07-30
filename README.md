# OpenCode Governance

Provider- and model-agnostic product-lifecycle and engineering governance for OpenCode projects.

> Community project. Not affiliated with or maintained by the OpenCode team.

Current release: **3.5.0 — Quality Gates & Governed Learning**.

v3 guides an idea through adaptive product discovery, constructive technical challenge, approved product definition, vertical delivery, evidence-driven implementation, independent review, product-completeness reconciliation and production-readiness assessment.

## Core invariants

- Seven public governance agents; `architect` is default and orchestrator.
- Only `executor` writes application source and approved project documentation.
- Implementation and architecture/security reviewers remain independent.
- Final Reviewer controls baseline, discovery, task, product, learning promotion and release adjudication.
- Requirement provenance and evidence outrank summaries, self-checks and assertions.
- No automatic push, merge, deployment, production rollback or Governance Memory promotion.
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

The installer renders seven public agents and twelve commands, preserves unrelated configuration and creates a timestamped backup. With a routing profile it writes the non-secret routing manifest, renders only enabled hidden fallback aliases and installs ten managed Architect, Executor, Context Intelligence and Quality Gate files. No hidden Architect alias is created.

## Local configuration durability

Windows desktop application updates are outside the control of this repository. Version 3.3.1 added a fail-closed wrapper that preserves the external OpenCode configuration directory before an owner-triggered update.

```powershell
./scripts/config-durability.ps1 -Action Enable -ConfigDir <opencode-config-directory>
```

```powershell
./scripts/update-opencode-safely.ps1 `
  -ConfigDir <opencode-config-directory> `
  -UpdateExecutable <updater-executable> `
  -UpdateArguments @(<argument-list>)
```

The wrapper snapshots protected configuration to a separate user-local durability store, executes only the supplied updater and restores the previous state when drift is detected. Configuration preservation does not prove schema compatibility with a newer OpenCode release. See [Local Configuration Durability](docs/local-configuration-durability.md).

## Architect failover runner

Top-level Architect failover is available only for:

```text
ai-init
ai-audit
ai-discover
ai-plan
```

Installed entrypoints:

```text
opencode-governance-tools/architect-attempt.ps1
opencode-governance-tools/architect-attempt.sh
```

Windows requires PowerShell 7:

```powershell
pwsh -NoProfile -File "<config-dir>\opencode-governance-tools\architect-attempt.ps1" `
  -ProjectDir "<project>" `
  -Command ai-plan `
  -Arguments "<request>" `
  -RoutingConfigPath "<config-dir>\opencode-governance-routing.json" `
  -ConfigDir "<config-dir>"
```

Direct invocation inside an existing OpenCode process fails closed with `ARCHITECT_RUNNER_REQUIRED`. The 3.3.4 runner contract remains active: project content outside root `.ai/**` is fingerprinted before and after every attempt, Git and non-Git workspaces are supported, and any protected delta returns `PROJECT_STATE_CHANGED`.

## Context Intelligence and skill routing

3.4.0 Context Intelligence remains active in 3.5.0:

```text
opencode-governance-tools/context-intelligence.ps1
opencode-governance-tools/context-intelligence.sh
opencode-governance-tools/context-intelligence.py
```

It provides deterministic work-class budgets, at most three `DISPATCH -> EVALUATE -> REFINE` retrieval cycles, `SKILL_CAPABILITY_MANIFEST_V1` selection, external content-addressed summary caching and optional context metrics. Cached summaries remain advisory; material claims require current primary evidence.

Task artifacts:

```text
.ai/tasks/<TASK-ID>/CONTEXT_BUDGET.json
.ai/tasks/<TASK-ID>/CONTEXT_RETRIEVAL.jsonl
.ai/tasks/<TASK-ID>/SKILL_SELECTION.json
.ai/tasks/<TASK-ID>/CONTEXT_METRICS.jsonl
.ai/metrics/CONTEXT_METRICS.jsonl
```

See [Context Intelligence and Skill Routing](docs/context-intelligence-skill-routing.md).

## Quality Gates and governed learning

3.5.0 installs:

```text
opencode-governance-tools/quality-gates.ps1
opencode-governance-tools/quality-gates.sh
opencode-governance-tools/quality-gates.py
```

No network service, vector database or third-party package is required. The PowerShell implementation runs on PowerShell 7; the Unix wrapper invokes the managed Python 3 standard-library core.

Each applicable task may maintain:

```text
.ai/tasks/<TASK-ID>/QUALITY_PROFILE.json
.ai/tasks/<TASK-ID>/DEBUG_PROOF.json
.ai/tasks/<TASK-ID>/TDD_PROOF.json
.ai/tasks/<TASK-ID>/EVAL_PLAN.json
.ai/tasks/<TASK-ID>/IMPLEMENTATION_SELF_CHECK.json
.ai/tasks/<TASK-ID>/QUALITY_VALIDATION.json
.ai/learning/CANDIDATES.jsonl
.ai/learning/PROMOTIONS.jsonl
```

`QUALITY_PROFILE_V1` derives required gates from work class, task kind and risk flags. Bug fixes require confirmed reproduction/root cause and a real RED→GREEN→regression sequence. Security, authorization, routing, parser, migration, public-contract and high-risk changes require TDD. AI-system behavior requires an eval plan; governed high-risk AI work uses `PASS_K`, not a single lucky `pass@k` result.

`IMPLEMENTATION_SELF_CHECK_V1` catches cheap defects before review but always records `approval_authority: false`. It is not a reviewer verdict and cannot be substituted for either independent review or Final Reviewer adjudication.

Learning is candidate-first and append-only. Duplicate active `dedup_key` values are rejected. Promotion requires `approved_by: FINAL_REVIEWER`, writes a `LEARNING_PROMOTION_V1` event with `memory_updated: false`, and never edits `GOVERNANCE_MEMORY.md` automatically. Updating reusable memory remains a separate Final Reviewer-controlled action based on current evidence.

See [Quality Gates and Governed Learning](docs/quality-gates-governed-learning.md).

## Executor failover

Executor failover uses isolated worktrees:

```text
select route
→ prepare detached worktree at frozen HEAD
→ run complete Executor inside EXECUTION_ROOT
→ finalize matching complete report into binary patch
→ promote only if the real worktree remains unchanged and non-overlapping
```

Managed helpers:

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
├── learning/
│   ├── CANDIDATES.jsonl
│   └── PROMOTIONS.jsonl
├── metrics/
│   └── CONTEXT_METRICS.jsonl
├── product/
├── baseline-audits/
└── tasks/
```

Discovery remains `LIGHT`, `STANDARD` or `DEEP`. A validated milestone may remain `PRODUCT_INCOMPLETE`; `PRODUCT_COMPLETENESS_VERDICT` is separate from `RELEASE_VERDICT`.

## Documentation

Focused references: [Product Lifecycle Governance](docs/product-lifecycle-governance.md), [Model Failover](docs/model-failover.md), [Architect Runner Integration](docs/architect-runner-integration.md), [Context Intelligence and Skill Routing](docs/context-intelligence-skill-routing.md), [Quality Gates and Governed Learning](docs/quality-gates-governed-learning.md), [Local Configuration Durability](docs/local-configuration-durability.md), [Workflow](docs/workflow.md), [Requirement Provenance](docs/requirement-provenance.md), [Context Efficiency and Resume](docs/context-efficiency-resume.md), [Evidence-Driven Verification](docs/evidence-driven-verification.md), [Operational Assurance](docs/operational-assurance.md), [Permissions](docs/permissions.md), [Project Documentation](docs/project-documentation.md) and [Troubleshooting](docs/troubleshooting.md).

## Verification

- Windows: `./scripts/verify.ps1`
- macOS/Linux: `./scripts/verify.sh`
- Routing Windows: `./scripts/verify-routing.ps1`
- Routing macOS/Linux: `bash ./scripts/verify-routing.sh`
- Durability Windows: `./scripts/config-durability.ps1 -Action Status`

## License

FSL-1.1-MIT. Each released version becomes available under the MIT License on the second anniversary of its release date. See [LICENSE](LICENSE).
