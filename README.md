# OpenCode Governance

Provider- and model-agnostic product-lifecycle and engineering governance for OpenCode projects.

> Community project. Not affiliated with or maintained by the OpenCode team.

Current release: **3.6.0 — Governed Authority, Memory & Evidence**.

OpenCode Governance turns an ordinary AI coding session into a controlled engineering workflow. It installs seven specialized agents, twelve commands, state contracts and deterministic tools that bind planning, implementation, validation and review to the same approved requirements and current repository evidence.

Version 3.6.0 adds immutable candidate projections, content-bound approval receipts, executable continuation, risk-focused review lenses, Final-Reviewer-governed engineering memory, exact evidence reuse, a staged pre-commit receipt gate and deterministic OpenCode simulation. These capabilities are part of the canonical installer, routing manifest, verifier and uninstaller; there is no separate runtime overlay.

## Why governance is needed

A capable coding model can still produce the wrong result because it may:

- misunderstand or silently simplify the real requirement;
- plan from stale or incomplete repository context;
- implement a valid patch against the wrong product decision;
- broaden scope or add an unnecessary dependency;
- test only the changed function and miss affected call paths or contracts;
- treat an old summary or scanner result as stronger than current source evidence;
- review its own work without genuine independence;
- continue from partial output after a provider or quota failure;
- report completion while documentation, migration, recovery or runtime behavior remains unverified;
- confuse a passing task with a complete product or production-ready release.

OpenCode Governance addresses these failure modes by separating authority, persisting canonical task state, freezing reviewed targets, requiring evidence, restarting failed roles from identical inputs and failing closed when required proof is missing or stale.

## Core trust model

- Exactly seven public governance agents are installed.
- `architect` is the default orchestrator.
- Only `executor` writes application source and approved project documentation.
- Architect, Build and Plan may write governance state only under project-root `.ai/**`.
- Implementation Reviewer and Architecture/Security Reviewer are independent siblings.
- Final Reviewer adjudicates findings, evidence, memory and release readiness.
- Original requirements and current primary repository evidence outrank summaries, cache, skills, memory and model assertions.
- Failed partial output is never accepted as authoritative evidence.
- Fallbacks restart the complete role from the same packet and frozen target.
- Required unavailable evidence cannot become `PASS`.
- No dependency or external service is installed merely to make governance green.
- Push, merge, deployment, publication and production rollback require explicit owner authorization.
- Provider IDs, model IDs, variants, credentials and personal routing preferences remain local and untracked.

## Governance agents

| Agent | Responsibility | Write authority |
|---|---|---|
| `architect` | Intake, discovery, product decisions, planning, orchestration and task state. | `.ai/**` only. |
| `build` | Complete governed lifecycle entry point for a requested build or change. | `.ai/**` only; delegates source work. |
| `plan` | Planning-only entry point. | `.ai/**` only. |
| `executor` | Implements the approved packet and reports evidence. | Application source and approved project docs. |
| `reviewer` | Independent implementation review. | Review output only. |
| `reviewer-architecture` | Independent architecture, security, data, dependency and recovery review. | Review output only. |
| `final-reviewer` | Adjudicates findings, evidence, repair cycles, memory and release verdicts. | Final review output only. |

## Public commands

| Command | Purpose |
|---|---|
| `/ai-init` | Initialize or refresh the reusable governance baseline. |
| `/ai-audit` | Adversarially validate the current baseline. |
| `/ai-docs` | Govern project documentation changes. |
| `/ai-discover` | Run explicit product or repository discovery. |
| `/ai-plan` | Produce an implementation-ready governed plan. |
| `/ai-execute` | Execute an already approved packet. |
| `/ai-review` | Review a frozen candidate and its evidence. |
| `/ai-workflow` | Run the complete governed lifecycle. |
| `/ai-status` | Report current task and governance state. |
| `/ai-resume` | Continue the authoritative interrupted lifecycle. |
| `/ai-metrics` | Report recorded usage and governance metrics. |
| `/ai-release` | Assess product completeness and release readiness. |

## Complete lifecycle

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

A small patch may use lighter discovery, but it does not bypass requirement provenance, frozen-target evidence, independent review or external-action boundaries.

## 3.6.0 capabilities

### Candidate authority and approval receipts

The governance can freeze four projections:

- `workspace`: current project files outside root `.git/**` and `.ai/**`;
- `staged`: exact Git index blob and mode set;
- `commit`: complete tree of one resolved commit;
- `base-diff`: resolved candidate, resolved base and immutable merge base.

`GOVERNANCE_APPROVAL_RECEIPT_V1` binds the candidate to approved requirements, execution packet, verification profile, evidence manifest, both independent reviews, Final Reviewer adjudication and the model families actually used. Any live projection mismatch invalidates delivery.

### Actionable continuation

A non-terminal `RUN_STATE.json` must contain either an executable `/ai-*` action with exact arguments and expected postcondition, or a concrete human decision. Narrative instructions such as “retry” or “continue” are not executable authority.

### Focused review lenses

Both reviewers remain mandatory. The task risk profile adds relevant lenses such as authorization, public contracts, migrations, dependency supply chain, performance, accessibility, deployment, observability and recovery without weakening reviewer independence.

### Governed engineering memory

Lessons are stored in a local SQLite database outside the repository. Executor and reviewers may propose memory candidates, but only Final Reviewer may activate or reject them. Memory is retrieved progressively and remains advisory. Promotion into a project policy requires recurring validated occurrences and explicit owner authorization.

### Exact evidence reuse

Prior evidence is reusable only when its previous outcome was `PASS` and every declared dependency hash is identical, including candidate bytes, affected contracts, validation command, environment, toolchain, policies and selected skills. A changed dependency returns `EVIDENCE_STALE`.

### Staged pre-commit gate

The installed tool can add an explicit project-scoped Git hook that validates a staged approval receipt without making a model call. Hook installation is never automatic.

### Deterministic simulation

The simulation harness can run a real OpenCode process against a loopback OpenAI-compatible scripted model. It tests orchestration, tool calls and terminal contracts without commercial API calls. It supplements rather than replaces repository-native verification.

## Installation

### Requirements

- OpenCode already installed;
- Git;
- Python 3;
- PowerShell 7+ on Windows;
- a local routing profile for routed failover and the complete 3.6.0 capability set.

The repository never contains real provider IDs, credentials, subscriptions or personal routing preferences.

### Windows

```powershell
$env:OPENCODE_CONFIG_DIR = "$env:USERPROFILE\.config\opencode"

pwsh -NoProfile -File .\scripts\install.ps1 `
  -ConfigDir $env:OPENCODE_CONFIG_DIR `
  -RoutingConfigPath "C:\path\to\local-routing-profile.json" `
  -NonInteractive
```

### Linux and macOS

```bash
export OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

bash ./scripts/install.sh \
  --config-dir "$OPENCODE_CONFIG_DIR" \
  --routing-config "/path/to/local-routing-profile.json"
```

Installation creates a complete pre-install snapshot before changing the configuration. If any canonical stage fails, the previous managed installation is restored.

## Verification

### Windows

```powershell
pwsh -NoProfile -File .\scripts\verify.ps1 -ConfigDir $env:OPENCODE_CONFIG_DIR
pwsh -NoProfile -File .\scripts\verify-routing.ps1 -ConfigDir $env:OPENCODE_CONFIG_DIR
python .\scripts\governance-capabilities.py verify --config-dir $env:OPENCODE_CONFIG_DIR
```

### Linux and macOS

```bash
bash ./scripts/verify.sh "$OPENCODE_CONFIG_DIR"
bash ./scripts/verify-routing.sh "$OPENCODE_CONFIG_DIR"
python3 ./scripts/governance-capabilities.py verify --config-dir "$OPENCODE_CONFIG_DIR"
```

The canonical routing manifest is `opencode-governance-routing.json`. Version 3.6.0 records all 14 managed tools, component versions, capability tool hashes and managed prompt-section hashes in that single manifest.

## Local configuration durability

OpenCode Desktop and CLI use the same authoritative configuration directory. Local Configuration Durability protects that directory across owner-triggered application updates:

- `config-durability.ps1` creates an external snapshot with a non-secret manifest of paths, lengths and SHA-256 hashes;
- verification detects added, removed or changed protected files;
- `update-opencode-safely.ps1` refuses unsafe overlapping paths and active OpenCode processes;
- updater drift is quarantined and the pre-update configuration is restored byte-for-byte, including when the updater itself fails;
- backups, quarantine data and recovery directories remain outside the protected source tree;
- provider credentials and secret values are never copied into diagnostic output.

Durability does not change provider/model routing and does not authorize an OpenCode update by itself. The owner supplies the updater command explicitly.

## Updating an existing installation

```bash
git pull --ff-only
```

Then rerun the canonical installer with the same local routing profile. The installer preserves provider/model routing semantically and fails closed if the profile is invalid.

## Project pre-commit receipt gate

Install and arm explicitly:

```bash
python3 "$OPENCODE_CONFIG_DIR/opencode-governance-tools/governance-pre-commit.py" install \
  --project-dir "/path/to/project"

python3 "$OPENCODE_CONFIG_DIR/opencode-governance-tools/governance-pre-commit.py" arm \
  --project-dir "/path/to/project" \
  --receipt ".ai/tasks/<TASK-ID>/approval-receipt.json" \
  --authority-tool "$OPENCODE_CONFIG_DIR/opencode-governance-tools/governance-authority.py"
```

Remove the project hook explicitly before uninstalling the referenced governance tool.

## Uninstallation

### Windows

```powershell
pwsh -NoProfile -File .\scripts\uninstall.ps1 -ConfigDir $env:OPENCODE_CONFIG_DIR
```

### Linux and macOS

```bash
bash ./scripts/uninstall.sh --config-dir "$OPENCODE_CONFIG_DIR"
```

Uninstallation removes only manifest-owned agents, commands, aliases and tools. Provider authentication, project `.ai/**` state, project documentation, backups, governed memory and unrelated local files are preserved.

## Repository documentation

- `docs/workflow.md`: lifecycle and transition semantics;
- `docs/model-configuration.md`: local model setup;
- `docs/model-failover.md`: bounded fallback behavior;
- `docs/governance-authority-memory.md`: candidate receipts, memory, evidence and simulation;
- `docs/context-efficiency-resume.md`: context routing and resume;
- `docs/permissions.md`: write and external-action boundaries;
- `docs/troubleshooting.md`: installation and recovery guidance;
- `CHANGELOG.md`: single canonical release history.

## License

See `LICENSE` for the repository’s license terms.
