# OpenCode Governance

Provider- and model-agnostic governance workflow for OpenCode projects:

**Architect → Executor → Independent Reviewers → Final Reviewer**

The repository does not hardcode model IDs. Exact `provider/model-id` routes and optional variants are selected during installation.

## Governance roles

- `architect` — requirements, validated baseline/context/instruction/memory routing, governed discovery, planning, evidence planning and orchestration; no application-source writes.
- `executor` — single application-source/project-documentation writer; implements only approved `READY_FOR_EXECUTION` plans and produces validation/operational evidence.
- `reviewer` — independent implementation/runtime/regression/documentation/evidence review.
- `reviewer-architecture` — independent architecture/security/data/dependency/deployment/maintainability/evidence review.
- `final-reviewer` — independent controlling adjudicator for baseline, task and release reviews.

OpenCode primary overrides:

- `Build` — complete governed lifecycle using the configured Architect model.
- `Plan` — governed planning-only mode using the Architect model; source editing and subagent delegation are denied.

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

Connect the required providers and list exact model IDs with `/models` or `opencode models`, then run:

Windows PowerShell:

```powershell
./scripts/install.ps1
```

macOS/Linux:

```bash
chmod +x scripts/install.sh
./scripts/install.sh
```

Build and Plan inherit the Architect model/variant. Installation preserves unrelated OpenCode configuration, creates timestamped backups and verifies the rendered configuration. Restart OpenCode Desktop/TUI after installation.

## First repository use

```text
/ai-init
```

Initial governance creates/reuses:

```text
.ai/
├── CODEBASE_BASELINE.md
├── CONTEXT_INDEX.md
├── INSTRUCTION_INDEX.md
├── GOVERNANCE_MEMORY.md
├── DEPLOYMENT_SCOPE.md
├── DOCUMENTATION_SCOPE.md
├── PROJECT_HISTORY.md
├── STATUS.md
├── baseline-audits/
└── tasks/
```

The baseline, context index, instruction/skill index and governance memory are drafts/reusable evidence until independently audited by both reviewers and adjudicated by Final Reviewer. No source implementation may begin without `BASELINE_VALIDATED`. Baseline adjudication is bounded to three failed cycles, then `BASELINE_BLOCKED`.

`GOVERNANCE_MEMORY.md` starts empty when no validated reusable lesson exists. Governance never fabricates historical memory.

## Canonical requirement provenance

Every governed task keeps the user's request separate from Architect interpretation:

```text
.ai/tasks/<TASK-ID>/
├── ORIGINAL_USER_REQUEST.md
├── CLARIFICATION_TRANSCRIPT.md
├── APPROVED_REQUIREMENTS.md
├── CONTEXT_MANIFEST.md
├── VERIFICATION_PROFILE.md
├── RUN_STATE.json
├── STEERING.md                  # when used
└── evidence/
    ├── EXECUTION_PACKET.md
    ├── VERIFICATION_EVIDENCE.md
    ├── REVIEW_IMPLEMENTATION_PACKET.md
    ├── REVIEW_ARCHITECTURE_PACKET.md
    └── FINAL_PACKET.md
```

`ORIGINAL_USER_REQUEST.md` preserves actual user intent. Clarifications are chronological and explicit supersession is preserved. The Architect plan is downstream evidence and cannot override the canonical requirement trail. A materially wrong plan remains `PLAN_DEFECT` even when implemented perfectly.

## Context, instructions, skills and governed memory

`.ai/CONTEXT_INDEX.md` is a compact routing map of material modules, call/dependency edges, data/trust boundaries, security-sensitive surfaces, canonical docs, tests and known risks.

`.ai/INSTRUCTION_INDEX.md` separately maps authoritative repository-local instruction sources and project/OpenCode skills. Skills are indexed by ID/source, scope/trigger, freshness and trust:

```text
PROJECT_AUTHORITATIVE
PROJECT_ADVISORY
WORKSPACE_ADVISORY
EXTERNAL_UNTRUSTED
```

Skills never outrank canonical user requirements and are loaded only when task-relevant.

`.ai/GOVERNANCE_MEMORY.md` stores only Final Reviewer-validated reusable lessons with scope, evidence, `stale_when` and `ACTIVE | STALE | REVOKED`. Memory is advisory routing evidence, never a waiver or substitute for current primary evidence.

Each task creates `CONTEXT_MANIFEST.md` from validated indexes, relevant active memory and current Git delta.

### Read-only discovery swarm

For materially multi-surface tasks, Architect/Build may use a bounded `READ_ONLY_DISCOVERY_SWARM` of 2–4 OpenCode built-in read-only workers:

- `Explore` — local codebase discovery;
- `Scout` — external dependency/upstream/documentation research.

Writable `General` is not enabled for governance discovery. Discovery workers do not edit files, do not make product decisions and do not see sibling discovery conclusions. Their summaries are routing hypotheses; material claims are verified against primary evidence before planning.

See [Context efficiency and resumable governance](docs/context-efficiency-resume.md).

## Evidence-Driven Verification

Every task creates `VERIFICATION_PROFILE.md` with `TASK_RISK_PROFILE` and project-authoritative validation mechanisms. Evidence results are written to `evidence/VERIFICATION_EVIDENCE.md`.

Core gates include:

- `VALIDATION_PROFILE`;
- `BUGFIX_PROOF`;
- `TEST_IMPACT_MAP`;
- `CONTRACT_COMPATIBILITY`;
- `ENVIRONMENT_FINGERPRINT`;
- `DEPENDENCY_ADMISSION_GATE`;
- `DEPENDENCY_DELTA`;
- `GENERATED_ARTIFACT_GATE`;
- `PRE_CHANGE_SAFEPOINT`;
- `MIGRATION_PROOF`;
- `NON_FUNCTIONAL_BUDGETS`;
- `FLAKINESS_EVIDENCE`;
- `ADVERSARIAL_INPUT_VALIDATION`;
- `CODEOWNERS_HUMAN_GATE`;
- `CLOSED_LOOP_LEARNING`.

Planning states are `REQUIRED | CONDITIONAL | NOT_APPLICABLE`. Evidence states are `PASS | FAIL | UNAVAILABLE | STALE | BLOCKED`.

`UNAVAILABLE` never silently becomes `PASS`.

### Dependency admission before installation

A new direct dependency is not installed until `DEPENDENCY_ADMISSION_GATE` resolves:

```text
ADMIT
REJECT
HUMAN_DECISION
NOT_APPLICABLE
```

Admission is exact package/source/version scoped and checks whether existing/native capabilities are sufficient, package identity/existence when externally sourced, and available compatibility/maintenance/security/license evidence. Suspected typo/slopsquat or unverifiable identity is never silently admitted.

### Pre-change safepoint

Before approved high-risk destructive, migration or deployment-state mutations, `PRE_CHANGE_SAFEPOINT` may require a recoverable pre-change reference: Git/worktree, relevant schema/migration state, config/lockfile/artifact fingerprints, existing required backup/snapshot reference and authoritative rollback/forward-recovery path. Governance does not fabricate or silently create privileged production backups.

### Closed-loop learning

When an escaped/repeated defect, validation gap, stable false-positive rationale, recovery lesson or tooling constraint is proven, `CLOSED_LOOP_LEARNING` records:

```text
WHAT_ESCAPED
WHY_NOT_DETECTED
WHICH_GATE_SHOULD_HAVE_CAUGHT_IT
WHAT_REUSABLE_RULE_CHANGES
```

Final Reviewer records `MEMORY_DECISION: NONE | APPROVE | REJECT`. Only an approved candidate may be persisted by Architect to `GOVERNANCE_MEMORY.md`.

See [Evidence-Driven Verification](docs/evidence-driven-verification.md).

## Operational Assurance

v2.0 extends the same evidence model from code correctness to realistic operation and external side effects:

- `PREVIEW_ENVIRONMENT_GATE`;
- `USER_FLOW_VERIFICATION`;
- `VISUAL_BEHAVIOR_GATE`;
- `RELEASE_RECOVERY_PROOF`;
- `TOOL_CAPABILITY_PROFILE` with `MCP_CAPABILITY_ASSESSMENT`;
- `SAFE_EXPERIMENTATION`.

Operational Assurance may require more proof but may never grant more privilege. It never silently provisions production infrastructure, uses production credentials/data, widens OpenCode permissions, deploys, rolls back, pushes or merges merely to satisfy governance.

See [Operational Assurance](docs/operational-assurance.md).

## Adaptive output efficiency and usage telemetry

All seven governance agents use `ADAPTIVE_OUTPUT_EFFICIENCY`: reasoning depth is preserved while output defaults to concise, evidence-dense communication.

```text
/ai-metrics [scope]
```

`/ai-metrics` reads usage already recorded by OpenCode and never estimates missing token counts or proportionally splits model totals across roles. Missing fields remain `UNAVAILABLE`.

See [Token efficiency and usage telemetry](docs/token-efficiency.md).

## Minimum necessary change

Every implementation-ready plan contains `MINIMUM_CHANGE_ASSESSMENT`: root cause/evidence-backed hypothesis, existing capability/pattern reuse, standard/native option, installed dependency option, justification for new dependencies/abstractions and why the proposed diff is the smallest correct, secure and maintainable change.

Minimalism never removes required security, trust-boundary validation, data-loss protection, error handling, accessibility or approved behavior.

## Checkpoint and resume

Each active task maintains machine-readable `.ai/tasks/<TASK-ID>/RUN_STATE.json` at phase boundaries.

```text
/ai-resume <TASK-ID>
```

Resume validates Git/checkpoint/provenance/context/instruction/skill/memory/evidence state and invalidates only dependent stale evidence. It never fabricates historical dependency admission, pre-change safepoints, Operational Assurance execution or Governance Memory.

Task-oriented commands expose:

```text
GOVERNANCE_RESULT
TASK_ID: <id or NONE>
STATE: <state>
NEXT_ACTION: <action or NONE>
CYCLE: <n/3 or N/A>
HUMAN_INPUT_REQUIRED: YES|NO
RESUMABLE: YES|NO
CHECKPOINT: <RUN_STATE path or NONE>
EVIDENCE_STATUS: COMPLETE|PARTIAL|BLOCKED|N/A
```

## Governed steering and task queue

Material mid-task `STEERING.md` direction must enter requirement provenance and force replanning when it invalidates the current plan.

Large milestones may use optional `.ai/TASK_QUEUE.json` with priority, dependencies and state. Each task still passes the complete governance lifecycle; no unbounded autonomous loop is introduced.

## Complete task lifecycle

```text
BASELINE_VALIDATED
        ↓
REQUIREMENT_CAPTURE / CLARIFICATION
        ↓
APPROVED_REQUIREMENTS
        ↓
GOVERNED_DISCOVERY / SKILL_ROUTING
        ↓
CONTEXT ROUTING
        ↓
PLANNING / MINIMUM_CHANGE_GATE
        ↓
EVIDENCE + OPERATIONAL PLANNING
        ↓
READY_FOR_EXECUTION
        ↓
PRE_CHANGE_SAFEPOINT (when required)
        ↓
EXECUTOR
        ↓
DOCUMENTATION_SYNC / EVIDENCE + OPERATIONAL VALIDATION
        ↓
TASK_VALIDATED
        ↓
┌────────────────────────────────┐
│ Implementation Reviewer        │
│ Architecture/Security Reviewer │
└───────────────┬────────────────┘
                ↓
          Final Reviewer
                ↓
PASS / IMPLEMENTATION_DEFECT / PLAN_DEFECT / BLOCKED
                ↓
VALIDATED LEARNING (when applicable)
                ↓
          LOCAL_COMMITTED
```

The source/documentation/evidence target is frozen during each review cycle. Only Final Reviewer-validated corrections may drive automatic repair. Task final-adjudication failures remain bounded to three cycles. After `PASS`, Executor creates one scoped local commit; `git push` always requires explicit user authorization.

## Project documentation and licensing

`.ai/DOCUMENTATION_SCOPE.md` records canonical project documentation paths, applicability, audience, synchronization state and license state. Every task records `DOCUMENTATION_IMPACT: NONE | UPDATE_REQUIRED | CREATE_REQUIRED`; required documentation is synchronized before validation and reviewed with implementation.

Governance never chooses a software license. Missing explicit owner/legal evidence becomes `LICENSE_DECISION_REQUIRED` and blocks release readiness until resolved.

## Large repositories

Validated baseline/context/instruction/memory evidence is reusable. Routine tasks use Git delta, task-specific routing, optional read-only discovery, relevant skills/memory and test-impact evidence rather than rescanning the complete repository. Full adversarial revalidation remains reserved for materially stale evidence or broad repository changes.

## Release gate

```text
/ai-release
```

Release review requires a current validated baseline, synchronized documentation, explicit license decision, production package correctness, clean installation/startup evidence when applicable, admitted new direct dependencies, required safepoints/recovery evidence and fresh applicable Evidence-Driven Verification/Operational Assurance.

Final release verdict:

```text
READY_FOR_PRODUCTION
NOT_READY_FOR_PRODUCTION
```

## Verification

Windows:

```powershell
./scripts/verify.ps1
```

macOS/Linux:

```bash
./scripts/verify.sh
```

Verification checks all seven agents, all eleven commands, provider-qualified model IDs, governed Build/Plan behavior, requirement provenance, context/instruction/skill/memory routing, bounded read-only discovery, minimum-change, dependency admission, pre-change safepoints, Evidence-Driven Verification, Operational Assurance, fresh evidence packets, resume/checkpoint markers, adaptive output efficiency, usage telemetry, reviewer modes, documentation/license gates and `default_agent`.

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