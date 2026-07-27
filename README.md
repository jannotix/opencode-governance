# OpenCode Governance

Provider- and model-agnostic governance workflow for OpenCode projects.

> Community project. Not affiliated with or maintained by the OpenCode team.

The workflow separates planning, implementation and review, preserves requirement provenance, uses deterministic evidence where available, and keeps external side effects behind explicit policy gates.

## Core invariants

| Invariant | Rule |
|---|---|
| Single writer | Only `executor` edits application source and approved project documentation. |
| Independent review | Implementation and architecture/security reviewers inspect the same frozen target without seeing sibling findings. |
| Final adjudication | `final-reviewer` validates requirements, evidence and reviewer allegations before task or release approval. |
| Requirement provenance | User intent is stored separately from Architect interpretation. |
| Evidence over assertion | Required unavailable or stale evidence cannot silently become `PASS`. |
| Bounded repair | Baseline and task correction loops stop after three failed adjudications. |
| No automatic push/deploy | Push, merge, deployment and rollback require separate authorization. |
| Provider agnostic | Model IDs and variants are supplied during installation. |

## Roles

| Agent | Responsibility |
|---|---|
| `architect` | Intake, baseline/context routing, planning, evidence planning and orchestration. |
| `build` | Governed full-workflow entry point using the Architect model. |
| `plan` | Governed planning-only entry point using the Architect model. |
| `executor` | Approved implementation, documentation sync and validation evidence. |
| `reviewer` | Independent implementation/runtime/regression review. |
| `reviewer-architecture` | Independent architecture/security/data/dependency/deployment review. |
| `final-reviewer` | Controlling baseline, task and release adjudication. |

`architect` is installed as `default_agent`.

## Commands

```text
/ai-init
/ai-audit
/ai-docs
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

Connect the required providers and obtain exact OpenCode `provider/model-id` values first.

Windows PowerShell:

```powershell
./scripts/install.ps1
```

macOS/Linux:

```bash
chmod +x scripts/install.sh
./scripts/install.sh
```

The installer renders the seven agent templates, installs the eleven commands, preserves unrelated OpenCode configuration, creates a timestamped backup and sets `default_agent` to `architect`.

Restart OpenCode Desktop/TUI after installation.

## Repository initialization

Run once per repository:

```text
/ai-init
```

Reusable governance state is stored under `.ai/`:

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
├── baseline-audits/
└── tasks/
```

No implementation begins until the reusable baseline reaches `BASELINE_VALIDATED`.

## Task lifecycle

```text
REQUIREMENT PROVENANCE
        ↓
GOVERNED DISCOVERY / SKILL ROUTING
        ↓
CONTEXT + RISK PLANNING
        ↓
READY_FOR_EXECUTION
        ↓
EXECUTOR
        ↓
EVIDENCE + OPERATIONAL VALIDATION
        ↓
TASK_VALIDATED
        ↓
INDEPENDENT DUAL REVIEW
        ↓
FINAL ADJUDICATION
        ↓
VALIDATED LEARNING (when applicable)
        ↓
LOCAL_COMMITTED
```

Each task keeps canonical requirement and evidence artifacts under `.ai/tasks/<TASK-ID>/`, including:

- `ORIGINAL_USER_REQUEST.md`
- `CLARIFICATION_TRANSCRIPT.md`
- `APPROVED_REQUIREMENTS.md`
- `CONTEXT_MANIFEST.md`
- `VERIFICATION_PROFILE.md`
- `RUN_STATE.json`
- `evidence/VERIFICATION_EVIDENCE.md`
- independent reviewer packets
- `FINAL_PACKET.md`

A correct implementation of a materially incorrect plan is `PLAN_DEFECT`, not `PASS`.

## Context and discovery

Routine work reuses validated repository indexes plus the current Git delta instead of rescanning the complete repository.

For materially multi-surface tasks, Architect/Build may use a bounded `READ_ONLY_DISCOVERY_SWARM` with OpenCode `Explore` and `Scout`. Writable `General` is not used as a governance discovery worker.

`GOVERNED_SKILL_ROUTING` loads only task-relevant skills. Skill authority is scoped and classified as:

```text
PROJECT_AUTHORITATIVE
PROJECT_ADVISORY
WORKSPACE_ADVISORY
EXTERNAL_UNTRUSTED
```

`.ai/GOVERNANCE_MEMORY.md` contains only Final Reviewer-approved reusable lessons with explicit scope, evidence and staleness conditions.

See [Context efficiency and resumable governance](docs/context-efficiency-resume.md).

## Evidence-Driven Verification

`VERIFICATION_PROFILE.md` defines `TASK_RISK_PROFILE` and the required validation gates. Results are recorded in `evidence/VERIFICATION_EVIDENCE.md`.

Core controls include CI-parity validation, bugfix proof, test-impact mapping, contract compatibility, environment fingerprints, dependency admission/delta, generated artifacts, pre-change safepoints, migrations, non-functional budgets, flakiness handling, adversarial input validation, human-owner gates and closed-loop learning.

Planning states:

```text
REQUIRED | CONDITIONAL | NOT_APPLICABLE
```

Evidence states:

```text
PASS | FAIL | UNAVAILABLE | STALE | BLOCKED
```

`UNAVAILABLE` is never treated as `PASS` without sufficient equivalent primary evidence.

See [Evidence-Driven Verification](docs/evidence-driven-verification.md).

## Operational Assurance

Operational Assurance extends verification to runtime behavior and external side effects:

- `PREVIEW_ENVIRONMENT_GATE`
- `USER_FLOW_VERIFICATION`
- `VISUAL_BEHAVIOR_GATE`
- `RELEASE_RECOVERY_PROOF`
- `TOOL_CAPABILITY_PROFILE` with `MCP_CAPABILITY_ASSESSMENT`
- `SAFE_EXPERIMENTATION`

The governing rule is simple: **verification may require more proof, but it may not grant more privilege**.

See [Operational Assurance](docs/operational-assurance.md).

## Resume and metrics

Interrupted tasks resume from persisted evidence rather than chat history:

```text
/ai-resume <TASK-ID>
```

Usage telemetry is read-only and uses OpenCode-recorded data:

```text
/ai-metrics [scope]
```

Missing attribution remains `UNAVAILABLE`; token usage is not estimated.

## Verification

Windows:

```powershell
./scripts/verify.ps1
```

macOS/Linux:

```bash
./scripts/verify.sh
```

The verifier is the executable contract for the rendered governance configuration. GitHub Actions runs the canonical render/verification path on Windows and Linux.

## Documentation

- [Installation](docs/installation.md)
- [Workflow](docs/workflow.md)
- [Requirement provenance](docs/requirement-provenance.md)
- [Context efficiency and resumable governance](docs/context-efficiency-resume.md)
- [Evidence-Driven Verification](docs/evidence-driven-verification.md)
- [Operational Assurance](docs/operational-assurance.md)
- [Token efficiency and usage telemetry](docs/token-efficiency.md)
- [Model configuration](docs/model-configuration.md)
- [Project documentation governance](docs/project-documentation.md)
- [Permissions](docs/permissions.md)
- [Troubleshooting](docs/troubleshooting.md)

## Uninstall

```powershell
./scripts/uninstall.ps1
```

or:

```bash
./scripts/uninstall.sh
```

Provider authentication, project `.ai/` state, project documentation and backups are left untouched.

## License

FSL-1.1-MIT. Each released version becomes available under the MIT License on the second anniversary of its release date. See [LICENSE](LICENSE).
