# OpenCode Governance

Provider- and model-agnostic product-lifecycle and engineering governance for OpenCode projects.

> Community project. Not affiliated with or maintained by the OpenCode team.

Current release: **3.4.4 — Deterministic Workflow Continuation**.

Version 3.4.4 prevents `/ai-workflow` and `/ai-resume` from reporting completion at intermediate checkpoints, validates terminal state through an installed fail-closed helper and makes Architect runner handoffs directly executable without changing local model routing.

OpenCode Governance turns an ordinary AI coding session into a controlled engineering workflow. It does not replace OpenCode and it does not provide an AI model. It installs a set of specialized agents, commands, state contracts and deterministic helpers that force planning, implementation, verification and review to use the same approved requirements and current repository evidence.

The project is designed for real repositories, including large and long-lived codebases where a single model conversation is not a sufficient control system for product scope, security, migrations, dependencies, recovery, documentation and release readiness.

## Why governance is needed

A capable coding model can still produce an incorrect result for reasons that are not visible in the final diff:

- it may misunderstand or simplify the user's real requirement;
- it may plan from stale or incomplete repository context;
- it may implement a technically valid patch against the wrong product decision;
- it may silently broaden scope or introduce an unnecessary dependency;
- it may test only the changed function and miss affected call paths or contracts;
- it may treat a scanner result, summary or previous answer as stronger evidence than the current source tree;
- it may review its own work without genuine independence;
- it may continue from partial output after a provider, quota or model failure;
- it may report a task as complete while documentation, recovery, migration or runtime behavior remains unverified;
- it may confuse a completed milestone with a complete product or a passing task with a production-ready release.

OpenCode Governance addresses these failure modes by separating responsibilities, persisting authoritative task state, binding every phase to evidence, restarting failed roles from frozen inputs and failing closed when required proof is unavailable.

## What the governance does

For each governed project it can:

1. establish and adversarially validate a reusable codebase baseline;
2. preserve the original request, material clarifications and approved requirements;
3. classify the work and choose an appropriate discovery depth;
4. challenge unsafe, incomplete or unnecessarily complex proposed solutions;
5. define product scope and required capabilities without defaulting every request to an MVP;
6. route bounded repository context and applicable instructions or skills;
7. produce an implementation-ready plan with risks, validation and recovery requirements;
8. allow only the Executor role to change application source and approved project documentation;
9. verify the result against repository-native tests, contracts and operational evidence;
10. run independent implementation and architecture/security reviews;
11. let a separate Final Reviewer adjudicate findings and control repair cycles;
12. reconcile milestone completion, product completeness and release readiness separately;
13. create a local commit only after approval when the workflow authorizes it;
14. require explicit owner authorization for push, merge, deployment, publication or production rollback.

The governance is evidence-driven rather than assertion-driven. A model saying that something is correct is not proof. Required evidence that is missing or stale is `UNAVAILABLE`, `BLOCKED` or `PARTIAL`; it is never silently converted into `PASS`.

## Problems it solves

| Problem | Governance response |
|---|---|
| Requirements drift | Canonical Requirement Provenance preserves the original request, clarifications and approved requirements. |
| Repeated full-repository scans | A validated baseline, context index and task-specific manifest support incremental, affected-path discovery. |
| Context-window waste | Work-class budgets, bounded retrieval, skill selection and external summary caching reduce repeated loading. |
| AI self-review | Implementation and architecture/security reviews are separate, isolated roles. |
| Plan-following against a bad plan | Final Reviewer checks the plan and implementation against the original requirement trail. |
| Partial output after provider failure | Eligible fallbacks restart the complete role from the same packet and frozen target. |
| Failed Executor leaving source changes | Routed Executor attempts run in isolated Git worktrees and promote only a verified patch. |
| Unsafe dependencies or migrations | Dependency admission, migration proof, safepoints and recovery gates fail closed. |
| “Tests pass” without realistic behavior | Operational Assurance adds runtime, user-flow, visual, recovery and external-tool evidence when applicable. |
| Milestone mistaken for complete product | Product completeness is reconciled independently from task and release verdicts. |
| Uncontrolled external actions | Push, merge, deployment, publication and production rollback are never automatically authorized. |

## Core invariants

These rules are not optional optimizations. They define the trust model:

- There are exactly seven public governance agents.
- `architect` is the default orchestrator.
- Only `executor` writes application source and approved project documentation.
- Architect, Build and Plan may write governance state only under project-root `.ai/**`.
- Implementation Reviewer and Architecture/Security Reviewer are independent siblings and do not consume each other's conclusions.
- Final Reviewer controls baseline, discovery, task, product and release adjudication.
- The original requirement trail and current primary repository evidence outrank summaries, caches, skills, memory and model assertions.
- A frozen packet and frozen target identify what a role actually reviewed or implemented.
- Failed partial role output is never accepted as authoritative evidence.
- A fallback is transport for the same role, not a new governance authority.
- Reviewer independence is evaluated from the model families actually used, not only configured primaries.
- Required unavailable evidence cannot be reported as passing.
- No dependency, verifier, preview environment or external service is installed merely to satisfy governance.
- No automatic push, merge, deployment, publication or production rollback occurs.
- Real provider/model IDs, credentials and personal routing preferences remain local and untracked.

## Governance agents

| Agent | Responsibility | Write authority |
|---|---|---|
| `architect` | Intake, discovery, product decisions, planning, orchestration, task state and adjudication routing. | `.ai/**` only. |
| `build` | Complete governed lifecycle entry point for a requested build or change. | `.ai/**` only; delegates source work to Executor. |
| `plan` | Planning-only entry point. Produces governed scope and evidence requirements without implementation. | `.ai/**` only. |
| `executor` | Implements the approved packet, synchronizes approved project documentation and reports evidence. | Application source and approved project docs; no governance adjudication. |
| `reviewer` | Independent implementation review against requirements, plan, diff and verification evidence. | Review output only. |
| `reviewer-architecture` | Independent architecture, security, data, contract, dependency, recovery and operational review. | Review output only. |
| `final-reviewer` | Adjudicates conflicting findings, accepts or rejects evidence and controls repair/release verdicts. | Final review output only. |

OpenCode built-in read-only workers may be used for bounded discovery when appropriate. They are evidence-gathering workers, not additional governance authorities.

## Complete workflow

The full lifecycle is:

```text
BASELINE_VALIDATED
→ IDEA_INTAKE
→ PRODUCT_CLASSIFICATION
→ ADAPTIVE_PRODUCT_DISCOVERY
→ GOVERNED_DOMAIN_RESEARCH
→ CONSTRUCTIVE_CHALLENGE
→ PRODUCT_DEFINITION
→ DISCOVERY_DUAL_REVIEW
→ DISCOVERY_ADJUDICATION
→ PRODUCT_SCOPE_APPROVAL
→ CONTEXT_ROUTING
→ DELIVERY_ARCHITECTURE
→ VERTICAL_MILESTONE_PLANNING
→ EVIDENCE + OPERATIONAL PLANNING
→ READY_FOR_EXECUTION
→ IMPLEMENTATION
→ DOCUMENTATION_SYNC
→ EVIDENCE + OPERATIONAL VALIDATION
→ TASK_DUAL_REVIEW
→ TASK_FINAL_ADJUDICATION
→ PRODUCT_COMPLETENESS_RECONCILIATION
→ RELEASE_READINESS
→ VALIDATED_LEARNING
→ LOCAL_COMMITTED
```

Every transition is fail-closed. A small patch can use lighter discovery, but it does not bypass requirement provenance, context validation, implementation evidence or independent review.

### 1. Baseline initialization

`/ai-init` inspects the repository and creates the reusable `.ai/**` baseline. The baseline identifies architecture, major modules, entry points, dependencies, data and trust boundaries, documentation/deployment scope and validation capabilities.

Two independent baseline reviews challenge the initial analysis. Final Reviewer must issue `BASELINE_VALIDATED` before implementation can start. Existing repositories are revalidated lazily when material changes make baseline evidence stale; routine tasks do not trigger repeated full scans.

### 2. Request intake and requirement provenance

The workflow preserves:

- the original user request;
- a chronological clarification transcript;
- established repository facts;
- approved requirements;
- later steering that changes scope or decisions.

Architect may normalize requirements but may not silently weaken, omit or broaden them. A material ambiguity blocks `READY_FOR_EXECUTION`. If a user-requested solution is unsafe, incompatible or unnecessarily expensive, Architect must separate the objective from the proposed implementation, explain the trade-offs and record the final decision.

### 3. Work and product classification

Every request receives one work class:

```text
PATCH
BOUNDED_FEATURE
MAJOR_FEATURE
EXISTING_PRODUCT_EVOLUTION
NEW_PRODUCT
HIGH_RISK_CHANGE
```

Discovery depth is always `LIGHT`, `STANDARD` or `DEEP`; `NONE` is not a valid discovery depth. Product-affecting work is mapped to stable capability IDs and a vertical milestone that produces an end-to-end usable result rather than disconnected backend/frontend/test phases.

### 4. Discovery and product definition

Discovery covers only what the task needs, but it expands when primary evidence reveals affected call paths, contracts, trust boundaries, migrations, integrations or operational surfaces.

For product work the governance maintains six canonical product files under `.ai/product/`:

```text
PRODUCT_VISION.md
USER_AND_ROLE_MODEL.md
DOMAIN_AND_PROCESS_MODEL.md
PRODUCT_COMPLETENESS_MATRIX.md
PRODUCT_BLUEPRINT.md
PRODUCT_DECISIONS.md
```

Domain research and competitor practice remain evidence or recommendations until explicitly approved. They never become requirements automatically.

### 5. Context routing

Architect builds a task-specific context manifest from:

- validated baseline indexes;
- the current Git delta and affected call paths;
- applicable repository instructions;
- selected skills and tools;
- active, scoped governance memory;
- current source, tests, contracts and documentation.

Context starts bounded and expands only for an evidence-backed reason. Summaries and cached context route attention; they do not prove correctness or authorize changes.

### 6. Planning and readiness

An implementation-ready plan defines:

- exact scope and explicit exclusions;
- requirement and product-capability traceability;
- affected modules, callers, callees and public contracts;
- data, migration, dependency, deployment and recovery impact;
- documentation impact;
- minimum-change assessment;
- authoritative validation commands and expected evidence;
- task risk profile;
- operational checks when applicable;
- blockers, fallback behavior and human decisions.

`READY_FOR_EXECUTION` is granted only when the baseline, requirement trail, discovery, product scope, approvals and required planning evidence are coherent.

### 7. Implementation

Executor receives a frozen execution packet and target. It must implement the smallest correct root-cause change, respect existing architecture and report every changed path and validation result.

Executor cannot change the approved plan, choose a new product requirement, authorize a dependency or approve its own output. A conflict between the plan and primary repository evidence returns `PLAN_CONFLICT` for Architect re-evaluation.

### 8. Evidence and Operational Assurance

Validation begins with repository-native commands and project-defined thresholds. Depending on risk, evidence may include:

- focused and dependent tests;
- full CI or high-risk suites;
- lint, type checking, formatting and build checks;
- public contract compatibility;
- migration and rollback proof;
- dependency and generated-artifact checks;
- security invariants and adversarial inputs;
- performance budgets defined by the project;
- realistic user flows and visual behavior;
- preview/runtime environment behavior;
- release recovery and external-tool capability evidence.

Governance never invents thresholds or installs missing tools merely to obtain a green result. When an applicable capability does not exist, the evidence remains unavailable and the correct blocker is reported.

### 9. Independent review

Implementation Reviewer and Architecture/Security Reviewer receive the same frozen target and canonical requirement evidence in isolated review contexts.

The Implementation Reviewer concentrates on correctness, scope, tests, regressions, maintainability and documentation synchronization. The Architecture/Security Reviewer concentrates on architecture, authorization, data safety, dependencies, migrations, contracts, deployment, recovery and operational risks.

Neither reviewer consumes the sibling's conclusion. Their outputs are findings, not the final verdict.

### 10. Final adjudication and repair

Final Reviewer independently checks the requirement trail, plan, implementation target, evidence freshness and both review reports. It decides whether each finding is valid and issues the controlling verdict.

When defects are repairable, the workflow may run another bounded implementation/review cycle from an updated frozen target. Automatic repair is limited to three Final Reviewer cycles. Persistent or material unresolved defects become `BLOCKED` and require human input rather than an unbounded AI loop.

### 11. Product completeness and release readiness

A validated task or milestone can still leave required capabilities incomplete. Product completeness reconciliation updates the capability matrix and reports remaining required work.

Release readiness is a separate decision. It considers accepted capabilities, current evidence, documentation, installation/upgrade behavior, migrations, operational recovery and release-specific risks. A task pass is not automatically a release pass.

### 12. Commit and external actions

After approval, the workflow may create a scoped local commit when configured by the governing command. It does not push that commit automatically.

The following always require explicit owner authorization and remain outside a task verdict:

```text
git push
merge or pull-request merge
deployment or publication
production rollback
production credentials or data
permission expansion
```

## Commands

| Command | Purpose |
|---|---|
| `/ai-init` | Create or migrate governance state and establish the adversarially validated baseline. |
| `/ai-audit` | Revalidate the baseline after material changes or on explicit request. |
| `/ai-docs` | Create, repair or synchronize project documentation through the governed pipeline. |
| `/ai-discover` | Run or refresh adaptive product/repository discovery without implementation. |
| `/ai-plan` | Produce an implementation-ready governed plan only. |
| `/ai-execute` | Execute an approved task packet, then validate and review it. |
| `/ai-review` | Review a frozen existing target without starting a new implementation. |
| `/ai-workflow` | Run the complete governed lifecycle for a request. |
| `/ai-status` | Report current baseline, task, product, evidence and blocker state. |
| `/ai-resume` | Resume an interrupted task from authoritative checkpoints and invalidate stale dependent evidence. |
| `/ai-metrics` | Report recorded governance/context usage without fabricating unavailable token or cost data. |
| `/ai-release` | Reconcile product completeness and evaluate release readiness. |

For ordinary governed development, initialize the repository once with `/ai-init`, then use `/ai-workflow <request>`. Use the narrower commands when a plan, audit, review, documentation pass or release assessment is specifically required.

## Project state

Governance state is project-local and lives under `.ai/`; the repository does not track that directory.

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
├── metrics/
└── tasks/
    └── <TASK-ID>/
        ├── ORIGINAL_USER_REQUEST.md
        ├── CLARIFICATION_TRANSCRIPT.md
        ├── APPROVED_REQUIREMENTS.md
        ├── CONTEXT_MANIFEST.md
        ├── VERIFICATION_PROFILE.md
        ├── RUN_STATE.json
        ├── EXECUTION_PACKET.md
        ├── evidence/
        └── reviews/
```

`RUN_STATE.json` is the machine-readable checkpoint for safe resume. Human-readable status files explain the controlling state and next action. Completed historical evidence is not rewritten to pretend that a newer governance feature existed when the task originally ran.

## Context intelligence and skill routing

With routing enabled, the installer adds managed PowerShell, shell and Python Context Intelligence tools. They provide deterministic actions for work-class budgeting, retrieval-cycle recording, skill selection, content-summary cache access, metrics and task validation.

The retrieval lifecycle is bounded:

```text
DISPATCH → EVALUATE → REFINE → CONTEXT_SUFFICIENT | BLOCKED_CONTEXT_GAP
```

A task must end in one of the two terminal states. `BLOCKED_CONTEXT_GAP` cannot pass task validation. Governance-state paths may not traverse symbolic links, junctions or reparse points.

Skill manifests declare identity, trust class, triggers, supported work classes, technologies, required tools, external dependencies, conflicts, overlaps, token estimate and named sections. Selection:

1. rejects inapplicable, stale or dependency-incompatible candidates;
2. rejects candidates missing a required named section;
3. deduplicates overlaps and conflicts;
4. prefers the highest-trust narrow applicable skill;
5. loads only the selected sections within the task budget;
6. records both selection and rejection reasons.

The external content-summary cache is user-local, content-addressed and advisory. It contains derived structured summaries, never source contents or an unhashed absolute project path. A cache hit never replaces inspection of current primary evidence for a material claim.

See [Context Intelligence and Skill Routing](docs/context-intelligence-skill-routing.md) for schemas, budgets and tool actions.

## Model failover

Failover is optional and configured locally. It is not a quality retry mechanism. It is allowed only for classified provider/model availability failures such as provider unavailability, bounded timeout, rate limit, exhausted plan quota, temporary model unavailability or retirement.

Authentication errors, invalid model configuration, malformed packets, safety refusals, tool permission errors, context overflow, validation defects, low-quality output and unclassified failures do not trigger automatic fallback.

A fallback never continues a partial answer. It restarts the complete authoritative role from the same canonical packet and frozen target. The active fallback is sticky; primary recovery does not interrupt it.

### Reviewer and Final Reviewer failover

Configured fallbacks are rendered as hidden OpenCode subagent aliases. They inherit the same authoritative role prompt and cannot delegate. Hidden aliases are routing transports and do not increase the seven public governance authorities.

Actual selected model families must satisfy the configured independence policy before a review set can be accepted.

### Architect failover runner

Top-level Architect failover is safe only before implementation/review side effects, so it is limited to:

```text
ai-init
ai-audit
ai-discover
ai-plan
```

The installer provides deterministic entrypoints:

```text
opencode-governance-tools/architect-attempt.ps1
opencode-governance-tools/architect-attempt.sh
```

Windows invocation:

```powershell
pwsh -NoProfile -File "<config-dir>\opencode-governance-tools\architect-attempt.ps1" `
  -ProjectDir "<project>" `
  -Command ai-plan `
  -Arguments "<request>" `
  -RoutingConfigPath "<config-dir>\opencode-governance-routing.json" `
  -ConfigDir "<config-dir>"
```

Unix invocation:

```bash
"<config-dir>/opencode-governance-tools/architect-attempt.sh" \
  --project-dir "<project>" \
  --command ai-plan \
  --arguments "<request>" \
  --routing-config "<config-dir>/opencode-governance-routing.json" \
  --config-dir "<config-dir>"
```

The runner snapshots `.ai/**`, fingerprints all project content outside `.ai/**`, starts a fresh `opencode run` for each route and restores governance state before an eligible retry. Git projects also bind the fingerprint to HEAD, index and recursive submodule state. Any protected project delta returns `PROJECT_STATE_CHANGED` and blocks fallback.

Direct invocation of a protected slash command without the runner marker stops before governance writes with `ARCHITECT_RUNNER_REQUIRED`. The active OpenCode process never launches a nested runner.

### Executor failover

A routed Executor attempt runs in a detached linked Git worktree at the same frozen target:

```text
select route
→ prepare isolated worktree
→ execute complete packet inside EXECUTION_ROOT
→ finalize a matching binary-safe patch
→ verify real worktree is unchanged and non-overlapping
→ promote the exact patch
```

An eligible failure discards the isolated worktree and restarts the complete Executor from the same packet on the next route. Promotion is not validation; ordinary evidence, dual review and Final Reviewer adjudication still follow.

See [Model Failover](docs/model-failover.md) and [Architect Runner Integration](docs/architect-runner-integration.md).

## Installation

### Requirements

- OpenCode installed and able to resolve the locally selected models.
- Git for routed Executor isolation and Git-aware project fingerprints.
- Windows: PowerShell 7 (`pwsh`) for transactional Architect and Context Intelligence helpers.
- macOS/Linux: Bash and Python 3 standard library for routing-enabled helpers.

No vector database, hosted governance service or mandatory third-party package is introduced.

### Single-model installation

Windows:

```powershell
./scripts/install.ps1
```

macOS/Linux:

```bash
chmod +x scripts/install.sh
./scripts/install.sh
```

The installer asks for the five configurable role models and optional concrete variants, renders seven public agents and twelve commands, sets `architect` as the default agent and creates a timestamped backup.

### Optional failover routing

1. Copy `examples/routing/continuous-coding.template.json` to a local untracked file.
2. Replace synthetic IDs with exact `provider/model` values from the local OpenCode catalog.
3. Resolve `highest_supported` policies to concrete supported variants before installation.
4. Configure model families, priorities, eligible failures and optional Executor work classes.
5. Keep credentials, subscriptions, quotas and personal routing preferences outside the repository.
6. Install the resolved profile.

Windows:

```powershell
./scripts/install.ps1 `
  -NonInteractive `
  -RoutingConfigPath "<local-profile.json>"
```

macOS/Linux:

```bash
./scripts/install.sh --routing-config "<local-profile.json>"
```

Before changing an existing routing installation, version 3.4.1 validates the complete replacement profile. An invalid profile leaves the existing manifest, aliases and managed tools untouched.

Existing JSONC configuration is normalized with a string-aware parser; URL values and strings containing `//` or `/* ... */` are preserved. On installation failure the original configuration is restored byte for byte. The persistent installation backup contains the original configuration and every existing managed tool before replacement.

Restart OpenCode after installation.

## Local configuration durability

OpenCode desktop updates are outside this repository's control. The Windows durability tooling protects the external configuration directory around an owner-triggered update.

Enable persistence and create a baseline snapshot:

```powershell
./scripts/config-durability.ps1 `
  -Action Enable `
  -ConfigDir "<opencode-config-directory>"
```

Run a selected updater through the protective wrapper:

```powershell
./scripts/update-opencode-safely.ps1 `
  -ConfigDir "<opencode-config-directory>" `
  -UpdateExecutable "<updater-executable>" `
  -UpdateArguments @(<argument-list>)
```

The wrapper snapshots protected files outside the configuration tree, runs only the supplied updater, detects added/removed/changed content, quarantines drift and restores the pre-update state by default. Manifests contain normalized paths, lengths and SHA-256 hashes, not credentials or file contents.

Automatic vendor updates are not intercepted. Configuration preservation proves byte-level restoration, not compatibility with a newer OpenCode schema. See [Local Configuration Durability](docs/local-configuration-durability.md).

## Verification and uninstall

Verify the rendered base contract:

```powershell
./scripts/verify.ps1
```

```bash
./scripts/verify.sh
```

Verify optional routing and managed tools:

```powershell
./scripts/verify-routing.ps1
```

```bash
./scripts/verify-routing.sh
```

Uninstall only repository-managed agents, commands, aliases and tools while preserving unrelated local configuration:

```powershell
./scripts/uninstall.ps1
```

```bash
./scripts/uninstall.sh
```

The external Context Intelligence cache and project `.ai/**` evidence are not deleted automatically.

## Repository verification strategy

CI retains subsystem-specific regression suites because they prove different safety contracts:

- base agent/command rendering and permission boundaries;
- Reviewer/Final Reviewer routing and independence;
- isolated Executor failover and patch promotion;
- Local Configuration Durability;
- installed Architect runner and non-recursion behavior;
- PowerShell host and exit-code reliability;
- project-state fingerprints for Git and non-Git workspaces;
- Context Intelligence budgets, cache and skill routing;
- 3.4.1 hardening for JSONC, backups, routing rollback and governance path safety.

Test fixtures and mock providers are intentionally tracked regression evidence, not runtime debug artifacts. Real provider/model identifiers and credentials are prohibited from tracked examples.

## Security and trust boundaries

The governance protects these boundaries:

- user requirement to approved scope;
- repository source and project documentation;
- `.ai/**` governance state;
- model/provider routing and credentials;
- commands and external tools;
- dependencies and generated artifacts;
- data/schema migrations;
- Git worktrees, commits and external actions;
- preview/production environments and recovery state.

The project is a governance framework, not a sandbox or formal proof system. It cannot make an unsafe underlying tool safe, guarantee that a model finds every defect or replace human legal/security decisions. It improves control by making authority, evidence, state transitions and blockers explicit and testable.

## Documentation

Each detailed subject has one canonical guide:

- [Workflow](docs/workflow.md)
- [Product Lifecycle Governance](docs/product-lifecycle-governance.md)
- [Requirement Provenance](docs/requirement-provenance.md)
- [Context Efficiency and Resume](docs/context-efficiency-resume.md)
- [Context Intelligence and Skill Routing](docs/context-intelligence-skill-routing.md)
- [Evidence-Driven Verification](docs/evidence-driven-verification.md)
- [Operational Assurance](docs/operational-assurance.md)
- [Model Failover](docs/model-failover.md)
- [Architect Runner Integration](docs/architect-runner-integration.md)
- [Local Configuration Durability](docs/local-configuration-durability.md)
- [Permissions](docs/permissions.md)
- [Project Documentation](docs/project-documentation.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Complete release history](CHANGELOG.md)

## License

FSL-1.1-MIT. Each released version becomes available under the MIT License on the second anniversary of its release date. See [LICENSE](LICENSE).
