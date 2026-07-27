# OpenCode Governance

Provider- and model-agnostic governance workflow for OpenCode projects:

**Architect → Executor → Independent Reviewers → Final Reviewer**

The repository does not hardcode model IDs. Exact `provider/model-id` routes and optional variants are selected during installation.

## Governance roles

- `architect` — requirements, baseline/context/instruction analysis, planning, evidence planning and orchestration; no application-source writes.
- `executor` — implements only approved `READY_FOR_EXECUTION` plans, synchronizes required project documentation and produces validation evidence.
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
├── DEPLOYMENT_SCOPE.md
├── DOCUMENTATION_SCOPE.md
├── PROJECT_HISTORY.md
├── STATUS.md
├── baseline-audits/
└── tasks/
```

The baseline, context index and instruction index are drafts until independently audited by both reviewers and adjudicated by Final Reviewer. No source implementation may begin without `BASELINE_VALIDATED`. Baseline adjudication is bounded to three failed cycles, then `BASELINE_BLOCKED`.

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

## Context and instruction routing

`.ai/CONTEXT_INDEX.md` is a compact routing map of material modules, call/dependency edges, data/trust boundaries, security-sensitive surfaces, canonical docs, tests and known risks.

`.ai/INSTRUCTION_INDEX.md` separately maps authoritative repository-local instruction sources to scope/applicable paths and precedence. Material instruction conflicts that repository evidence cannot resolve require authoritative clarification rather than silent precedence invention.

Each task creates `CONTEXT_MANIFEST.md` from validated indexes plus current Git delta. Agents start from the selected task surface and expand only when primary evidence indicates wider impact.

Role handoffs use fresh referential packets rather than unrelated conversation history. Reviewer packets never contain sibling current-cycle findings.

See [Context efficiency and resumable governance](docs/context-efficiency-resume.md).

## Evidence-Driven Verification

v1.8 adds a deterministic evidence layer around the existing multi-model workflow.

Every task creates `VERIFICATION_PROFILE.md` with a `TASK_RISK_PROFILE` using `NONE | LOW | HIGH` for:

- security;
- data migration;
- public contracts;
- dependencies;
- deployment;
- performance;
- generated artifacts;
- destructive actions;
- input validation;
- test reliability;
- human ownership.

Risk classification may add proof requirements but never removes normal acceptance validation, independent dual review or Final Reviewer adjudication.

The profile discovers the repository's existing authoritative `VALIDATION_PROFILE`/CI-equivalent commands and selects applicable gates:

- `BUGFIX_PROOF`;
- `TEST_IMPACT_MAP`;
- `CONTRACT_COMPATIBILITY`;
- `ENVIRONMENT_FINGERPRINT`;
- `DEPENDENCY_DELTA`;
- `GENERATED_ARTIFACT_GATE`;
- `MIGRATION_PROOF`;
- `NON_FUNCTIONAL_BUDGETS`;
- `FLAKINESS_EVIDENCE`;
- `ADVERSARIAL_INPUT_VALIDATION`;
- `CODEOWNERS_HUMAN_GATE`.

Executor records actual results in `evidence/VERIFICATION_EVIDENCE.md` using `PASS | FAIL | UNAVAILABLE | STALE | BLOCKED`.

Governance does **not** hardcode or install external scanners, fuzzers, contract checkers, mutation tools, benchmark tools or code generators. Existing project tooling may be used as evidence. `UNAVAILABLE` never silently becomes `PASS`; required unavailable evidence needs an explicitly sufficient primary-evidence alternative or remains blocking.

A rerun PASS never erases an earlier unexplained FAIL. Scanner output is evidence, not proof. Test-impact selection never overrides authoritative CI/high-risk full-suite requirements. Public breaking changes require explicit authorization. Irreversible migrations require approved backup/forward-recovery evidence. Existing non-functional thresholds are enforced; governance never invents new thresholds.

Evidence freshness is dependency-specific: changes to source/docs, contracts, lockfiles, generator inputs, migrations, environment/toolchain or validation configuration invalidate only the evidence/reviews that depend on those surfaces.

See [Evidence-Driven Verification](docs/evidence-driven-verification.md).

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

Resume validates Git/checkpoint/provenance/instruction/context/evidence state. It also reconciles `ENVIRONMENT_FINGERPRINT` and evidence dependencies. A changed source, contract, lockfile, generator input, migration, environment/toolchain or validation configuration invalidates only dependent evidence/reviews; unrelated completed phases are not restarted.

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

## Project documentation and licensing

`.ai/DOCUMENTATION_SCOPE.md` records canonical project documentation paths, applicability, audience, synchronization state and license state. Every task records `DOCUMENTATION_IMPACT: NONE | UPDATE_REQUIRED | CREATE_REQUIRED`; required documentation is synchronized before validation and reviewed with implementation.

Governance never chooses a software license. Missing explicit owner/legal evidence becomes `LICENSE_DECISION_REQUIRED` and blocks release readiness until resolved.

## Complete task lifecycle

```text
BASELINE_VALIDATED
        ↓
REQUIREMENT_CAPTURE / CLARIFICATION
        ↓
APPROVED_REQUIREMENTS
        ↓
CONTEXT + INSTRUCTION ROUTING
        ↓
PLANNING / MINIMUM_CHANGE_GATE
        ↓
EVIDENCE_PLANNING
        ↓
READY_FOR_EXECUTION
        ↓
EXECUTOR
        ↓
DOCUMENTATION_SYNC / EVIDENCE_VALIDATION
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
          LOCAL_COMMITTED
```

The source/documentation/evidence target is frozen during each review cycle. Only Final Reviewer validated corrections may drive automatic repair. Task final-adjudication failures remain bounded to three cycles. After `PASS`, Executor creates one scoped local commit; `git push` always requires explicit user authorization.

## Large repositories

Validated baseline/context/instruction indexes are reusable. Routine tasks use Git delta plus task-specific routing and test-impact evidence rather than rescanning the complete repository. Full adversarial revalidation remains reserved for materially stale evidence or broad repository changes.

## Release gate

```text
/ai-release
```

Release review requires a current validated baseline, synchronized documentation, explicit license decision, production package correctness, clean installation/startup evidence when applicable and fresh applicable Evidence-Driven Verification, including contract/dependency/generated/migration/non-functional/human-owner gates when authoritative project evidence requires them.

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

Verification checks all seven agents, all eleven commands, provider-qualified model IDs, governed Build/Plan behavior, requirement provenance, context/instruction routing, minimum-change gate, fresh evidence packets, resume/checkpoint markers, Evidence-Driven Verification, adaptive output efficiency, real-usage metrics policy, reviewer modes, documentation/license gates and `default_agent`.

## Documentation

- [Installation](docs/installation.md)
- [Workflow](docs/workflow.md)
- [Requirement provenance](docs/requirement-provenance.md)
- [Context efficiency and resumable governance](docs/context-efficiency-resume.md)
- [Evidence-Driven Verification](docs/evidence-driven-verification.md)
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
