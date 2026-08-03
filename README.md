# OpenCode Governance

**Deterministic product-lifecycle governance for [OpenCode](https://github.com/anomalyco/opencode).**
Provider- and model-agnostic. Fail-closed by design.

> Community project. Not affiliated with the OpenCode team.

---

## Why

AI coding agents are fast, but they operate without guardrails: they write source
without independent review, lose track of approved requirements, drift from the
frozen target, and skip verification when it is inconvenient. **OpenCode
Governance** turns an unconstrained agent into a governed engineering process
where every side effect is bound to approved evidence.

| Without governance | With OpenCode Governance |
|---|---|
| Agent writes source directly | Only `executor` writes source, inside an isolated worktree |
| No independent review | Two independent reviewers + Final Reviewer adjudication |
| Requirements drift silently | Requirement Provenance blocks execution when the trail is broken |
| Failed partial output becomes authoritative | Failed output is rejected; the role restarts from the same packet |
| Model claims outrank evidence | Primary repository evidence always wins |
| No external-action boundary | Push, merge, deploy and publish require explicit owner authorization |
| Handoff leaks on the command line | Prompt transported over stdin (`argv_prompt_bytes=0`) |

## What it gives you

- **Seven specialized agents** — Architect, Build, Plan, Executor, Implementation
  Reviewer, Architecture Reviewer, Final Reviewer — each with a strict write
  authority and an effect policy that denies tools and paths outside its scope.
- **Twelve `/ai-*` commands** that enforce a deterministic lifecycle from
  baseline validation through release.
- **Pre-side-effect READY gate** — no tool runs before the plugin has proven it
  loaded correctly and the host has acknowledged it.
- **Executor command brokerage** — explicit allow/deny classification of every
  shell command; destructive operations (rm, git push, npm install, interpreters)
  fail closed.
- **Transactional report commit** — staged journal with a single COMMIT marker;
  a crash never leaves a partial authoritative state.
- **Review Chain V4 attestation** — live-revalidates every receipt (ingestion,
  route, launch, process, handshake) before the chain passes.
- **Model failover** with reviewer independence — implementation and
  architecture reviewers must use distinct model families.

## Quickstart

```bash
git clone https://github.com/jannotix/opencode-governance.git
cd opencode-governance
export OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

bash ./scripts/install.sh \
  --config-dir "$OPENCODE_CONFIG_DIR" \
  --routing-config "examples/routing/continuous-coding.template.json"
```

Windows:

```powershell
$env:OPENCODE_CONFIG_DIR = "$env:USERPROFILE\.config\opencode"

pwsh -NoProfile -File .\scripts\install.ps1 `
  -ConfigDir $env:OPENCODE_CONFIG_DIR `
  -RoutingConfigPath "examples\routing\continuous-coding.template.json" `
  -NonInteractive
```

Verify:

```bash
bash ./scripts/verify.sh "$OPENCODE_CONFIG_DIR"
bash ./scripts/verify-routing.sh "$OPENCODE_CONFIG_DIR"
```

Provider IDs, credentials and personal routing preferences stay local and
untracked. The installer takes a full pre-install snapshot and rolls back on
failure.

## Requirements

- OpenCode
- Git
- Python 3.9+
- PowerShell 7+ on Windows

## Agents

| Agent | Responsibility | Write authority |
|---|---|---|
| `architect` | Intake, discovery, planning, orchestration | `.ai/**` only |
| `build` | Full governed lifecycle entry | `.ai/**` only |
| `plan` | Planning only | `.ai/**` only |
| `executor` | Implements the approved packet | Application source (isolated worktree) |
| `reviewer` | Independent implementation review | Review output only |
| `reviewer-architecture` | Architecture/security review | Review output only |
| `final-reviewer` | Adjudication, memory, release verdict | Final review output only |

Only `executor` writes application source. Reviewers are read-only by policy.
Every role runs in its own dedicated OpenCode process.

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

```
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

Small patches may use lighter discovery but still require requirement
provenance, frozen-target evidence, independent review and explicit owner
authorization for push, merge, deploy or publication.

## Trust model

- Exactly seven public governance agents.
- Only `executor` writes application source.
- Independent reviewers; Final Reviewer adjudicates.
- Original requirements and primary repository evidence outrank summaries,
  cache, skills and model claims.
- Failed partial output is never authoritative.
- Fallbacks restart the full role from the same packet and frozen target.
- Required unavailable evidence cannot become `PASS`.

## Effect plugin

The effect-enforcement plugin is the runtime guard. It hooks
`tool.execute.before`, classifies every tool call against the role's effect
policy, and throws to fail closed when a tool, path or command is outside scope.

```bash
# standalone install / self-test (the umbrella installer does this automatically)
python ./scripts/install-effect-plugin.py --config-dir "$OPENCODE_CONFIG_DIR" install
python ./scripts/install-effect-plugin.py --config-dir "$OPENCODE_CONFIG_DIR" self-test --non-mutating
```

> **Scope.** Enforcement is logical (path containment, hash binding, effect
> policy, semantic state machine), not an OS-level sandbox or external
> attestation. See the `LOCAL_INTEGRITY` / `SEMANTIC_STATE_MACHINE_ENFORCED` /
> `EFFECT_POLICY_EXPERIMENTAL` declarations in `role-effect-policy.json` for the
> authoritative statement.

## Capabilities (routing profile required)

With a local routing profile the installer adds:

- Candidate projections (`workspace`, `staged`, `commit`, `base-diff`) and
  approval receipts
- Typed actionable continuation on non-terminal `RUN_STATE.json`
- Risk-focused review lenses
- Final-Reviewer-governed local engineering memory (advisory SQLite store)
- Exact dependency-bound evidence reuse
- Optional staged pre-commit receipt gate
- Optional loopback simulation harness

Without a routing profile only the base agents and commands install.

## Configuration durability (Windows)

`config-durability.ps1` and `update-opencode-safely.ps1` snapshot and restore
the OpenCode config directory across owner-triggered app updates. Credentials
are never copied into diagnostic output.

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

## Update

```bash
git pull --ff-only
```

Rerun the installer with the same local routing profile. Routing is preserved
when the profile remains valid.

## Uninstall

```bash
bash ./scripts/uninstall.sh --config-dir "$OPENCODE_CONFIG_DIR"
```

```powershell
pwsh -NoProfile -File .\scripts\uninstall.ps1 -ConfigDir $env:OPENCODE_CONFIG_DIR
```

Removes only manifest-owned agents, commands, aliases and tools. Provider auth,
project `.ai/**`, backups and memory stay intact.

## Documentation

| Doc | Topic |
|---|---|
| [`docs/workflow.md`](docs/workflow.md) | Lifecycle transitions |
| [`docs/model-configuration.md`](docs/model-configuration.md) | Local models |
| [`docs/model-failover.md`](docs/model-failover.md) | Bounded fallbacks |
| [`docs/governance-authority-memory.md`](docs/governance-authority-memory.md) | Receipts, memory, evidence, simulation |
| [`docs/context-intelligence-skill-routing.md`](docs/context-intelligence-skill-routing.md) | Context and skills |
| [`docs/permissions.md`](docs/permissions.md) | Write and external-action boundaries |
| [`docs/architect-headless-permission-contract.md`](docs/architect-headless-permission-contract.md) | Headless Architect permission contract |
| [`docs/architect-stdin-prompt-transport.md`](docs/architect-stdin-prompt-transport.md) | Architect stdin prompt transport |
| [`docs/workspace-repository-root-contract.md`](docs/workspace-repository-root-contract.md) | Nested workspace / multi-root transactions |
| [`docs/legacy-orphan-recovery.md`](docs/legacy-orphan-recovery.md) | Evidence-bound legacy orphan recovery |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | Recovery |
| [`CHANGELOG.md`](CHANGELOG.md) | Release history |

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Security reports: [`SECURITY.md`](SECURITY.md).

## License

See [`LICENSE`](LICENSE).
