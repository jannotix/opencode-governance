# OpenCode Governance

Provider- and model-agnostic product-lifecycle governance for [OpenCode](https://github.com/anomalyco/opencode) projects.

> Community project. Not affiliated with the OpenCode team.

Current release: **3.7.4 — Architect stdin prompt transport**.

Installs seven specialized agents, twelve `/ai-*` commands, deterministic tooling and fail-closed contracts so planning, implementation, validation and review stay bound to approved requirements and current repository evidence.

## Requirements

- OpenCode
- Git
- Python 3
- PowerShell 7+ on Windows

Provider IDs, credentials and personal routing preferences stay local and untracked.

## Install

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

The installer takes a full pre-install snapshot and rolls back on failure. See `examples/routing/continuous-coding.template.json` for a valid profile shape (resolve `highest_supported` variants locally before install).

## Verify

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

## Agents

| Agent | Responsibility | Write authority |
|---|---|---|
| `architect` | Intake, discovery, planning, orchestration | `.ai/**` only |
| `build` | Full governed lifecycle entry | `.ai/**` only |
| `plan` | Planning only | `.ai/**` only |
| `executor` | Implements the approved packet | Application source and approved docs |
| `reviewer` | Independent implementation review | Review output only |
| `reviewer-architecture` | Architecture/security review | Review output only |
| `final-reviewer` | Adjudication, memory, release verdict | Final review output only |

## Commands

| Command | Purpose |
|---|---|
| `/ai-init` | Initialize or refresh the governance baseline |
| `/ai-audit` | Adversarially validate the baseline |
| `/ai-docs` | Govern project documentation changes |
| `/ai-discover` | Product or repository discovery |
| `/ai-plan` | Implementation-ready governed plan |
| `/ai-execute` | Execute an approved packet |
| `/ai-review` | Review a frozen candidate and evidence |
| `/ai-workflow` | Full governed lifecycle |
| `/ai-status` | Current task and governance state |
| `/ai-resume` | Resume an interrupted lifecycle |
| `/ai-metrics` | Usage and governance metrics |
| `/ai-release` | Release readiness assessment |

## Lifecycle

```text
BASELINE_VALIDATED
→ IDEA_INTAKE → PRODUCT_CLASSIFICATION → ADAPTIVE_PRODUCT_DISCOVERY
→ GOVERNED_DOMAIN_RESEARCH → CONSTRUCTIVE_CHALLENGE → PRODUCT_DEFINITION
→ DISCOVERY_DUAL_REVIEW → DISCOVERY_ADJUDICATION → PRODUCT_SCOPE_APPROVAL
→ CONTEXT_ROUTING → DELIVERY_ARCHITECTURE → VERTICAL_MILESTONE_PLANNING
→ EVIDENCE_PLANNING → OPERATIONAL_PLANNING → READY_FOR_EXECUTION
→ PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED → IMPLEMENTING → DOCUMENTATION_SYNC
→ EVIDENCE_VALIDATION → OPERATIONAL_VALIDATION → TASK_VALIDATED
→ DUAL_REVIEW → FINAL_ADJUDICATION
→ PRODUCT_COMPLETENESS_RECONCILIATION → RELEASE_READINESS
→ VALIDATED_LEARNING → LOCAL_COMMITTED
```

Small patches may use lighter discovery. They still require requirement provenance, frozen-target evidence, independent review and explicit owner authorization for push, merge, deploy or publication.

## Trust model

- Exactly seven public governance agents.
- Only `executor` writes application source.
- Independent reviewers; Final Reviewer adjudicates.
- Original requirements and primary repository evidence outrank summaries, cache, skills and model claims.
- Failed partial output is never authoritative.
- Fallbacks restart the full role from the same packet and frozen target.
- Required unavailable evidence cannot become `PASS`.

## Capabilities (routing profile required)

With a local routing profile the installer adds:

- Candidate projections (`workspace`, `staged`, `commit`, `base-diff`) and approval receipts (`opencode-governance.approval-receipt/v1`)
- Typed actionable continuation on non-terminal `RUN_STATE.json`
- Risk-focused review lenses (both independent reviewers retained)
- Final-Reviewer-governed local engineering memory (advisory SQLite store)
- Exact dependency-bound evidence reuse
- Optional staged pre-commit receipt gate (never auto-installed)
- Optional loopback simulation harness (orchestration fixture, not model QA)

Without a routing profile only the base agents and commands install. Details: [`docs/governance-authority-memory.md`](docs/governance-authority-memory.md).

## Configuration durability (Windows)

`config-durability.ps1` and `update-opencode-safely.ps1` snapshot and restore the OpenCode config directory across owner-triggered app updates. Credentials are never copied into diagnostic output. Durability does not authorize updates by itself.

## Pre-commit receipt gate

Optional, project-scoped, explicit install:

```bash
python3 "$OPENCODE_CONFIG_DIR/opencode-governance-tools/governance-pre-commit.py" install \
  --project-dir "/path/to/project"

python3 "$OPENCODE_CONFIG_DIR/opencode-governance-tools/governance-pre-commit.py" arm \
  --project-dir "/path/to/project" \
  --receipt ".ai/tasks/<TASK-ID>/approval-receipt.json" \
  --authority-tool "$OPENCODE_CONFIG_DIR/opencode-governance-tools/governance-authority.py"
```

Remove the project hook before uninstalling the referenced tools.

## Uninstall

### Windows

```powershell
pwsh -NoProfile -File .\scripts\uninstall.ps1 -ConfigDir $env:OPENCODE_CONFIG_DIR
```

### Linux and macOS

```bash
bash ./scripts/uninstall.sh --config-dir "$OPENCODE_CONFIG_DIR"
```

Removes only manifest-owned agents, commands, aliases and tools. Provider auth, project `.ai/**`, backups and memory stay intact.

## Update

```bash
git pull --ff-only
```

Rerun the installer with the same local routing profile. Routing is preserved when the profile remains valid.

## Documentation

| Doc | Topic |
|---|---|
| [`docs/workflow.md`](docs/workflow.md) | Lifecycle transitions |
| [`docs/model-configuration.md`](docs/model-configuration.md) | Local models |
| [`docs/model-failover.md`](docs/model-failover.md) | Bounded fallbacks |
| [`docs/governance-authority-memory.md`](docs/governance-authority-memory.md) | Receipts, memory, evidence, simulation |
| [`docs/context-intelligence-skill-routing.md`](docs/context-intelligence-skill-routing.md) | Context and skills |
| [`docs/permissions.md`](docs/permissions.md) | Write and external-action boundaries |
| [`docs/architect-headless-permission-contract.md`](docs/architect-headless-permission-contract.md) | Headless Architect permission contract (3.7.3+) |
| [`docs/architect-stdin-prompt-transport.md`](docs/architect-stdin-prompt-transport.md) | Architect stdin prompt transport (3.7.4) |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | Recovery |
| [`CHANGELOG.md`](CHANGELOG.md) | Release history |

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Security reports: [`SECURITY.md`](SECURITY.md).

## License

See [`LICENSE`](LICENSE).
