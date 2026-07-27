# OpenCode Governance

Provider- and model-agnostic governance workflow for OpenCode projects:

**Architect → Executor → Independent Reviewers → Final Reviewer**

The repository does not hardcode model IDs. Exact `provider/model-id` routes and optional variants are selected during installation.

## Governance roles

- `architect` — requirements, baseline/context analysis, planning and orchestration; no application-source writes.
- `executor` — implements only approved `READY_FOR_EXECUTION` plans, synchronizes required project documentation and validates the task.
- `reviewer` — independent implementation/runtime/regression/documentation review.
- `reviewer-architecture` — independent architecture/security/data/dependency/deployment/maintainability review.
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

Connect the required providers in OpenCode and list exact model IDs:

```text
/connect
/models
```

or:

```bash
opencode models
```

Always select the full `provider/model-id`; the provider prefix determines the subscription/API route.

Windows PowerShell:

```powershell
./scripts/install.ps1
```

macOS/Linux:

```bash
chmod +x scripts/install.sh
./scripts/install.sh
```

The installer asks for the model and optional variant/reasoning level for the five governance roles. Build and Plan inherit the Architect model/variant. It preserves unrelated OpenCode configuration, creates timestamped backups and verifies the rendered configuration.

Restart OpenCode Desktop/TUI after installation.

## First repository use

```text
/ai-init
```

Initial governance creates/reuses:

```text
.ai/
├── CODEBASE_BASELINE.md
├── CONTEXT_INDEX.md
├── DEPLOYMENT_SCOPE.md
├── DOCUMENTATION_SCOPE.md
├── PROJECT_HISTORY.md
├── STATUS.md
├── baseline-audits/
└── tasks/
```

The initial baseline and context index are drafts until independently audited:

```text
Architect draft baseline + context index
            ↓
┌────────────────────────────────┐
│ Implementation Reviewer        │
│ Architecture/Security Reviewer │
└───────────────┬────────────────┘
                ↓
          Final Reviewer
                ↓
       BASELINE_VALIDATED
```

The reviewers inspect primary repository evidence independently and do not receive each other's current audit output. Final Reviewer validates allegations rather than counting votes.

No source implementation may begin without `BASELINE_VALIDATED`. Baseline adjudication is bounded to three failed cycles, then `BASELINE_BLOCKED`.

## Canonical requirement provenance

Every governed task keeps the user's request separate from Architect interpretation:

```text
.ai/tasks/<TASK-ID>/
├── ORIGINAL_USER_REQUEST.md
├── CLARIFICATION_TRANSCRIPT.md
├── APPROVED_REQUIREMENTS.md
├── CONTEXT_MANIFEST.md
├── RUN_STATE.json
├── STEERING.md                  # when used
└── evidence/
```

`ORIGINAL_USER_REQUEST.md` preserves the actual request. `CLARIFICATION_TRANSCRIPT.md` is chronological and records explicit superseding decisions. `APPROVED_REQUIREMENTS.md` contains normalized executable requirements with provenance.

The implementation plan is downstream evidence. A plan that materially omits, weakens, contradicts, fabricates or unauthorizedly broadens/narrows a controlling requirement is defective even when implemented perfectly.

Architect, Build and Plan explicitly allow OpenCode's `question` tool for unresolved material decisions. Questions already answered by the user or primary evidence must not be repeated.

See [Requirement provenance](docs/requirement-provenance.md).

## Context-efficient governance

Validated repositories maintain `.ai/CONTEXT_INDEX.md`, a compact routing map of material modules, call/dependency edges, data/trust boundaries, security-sensitive surfaces, canonical docs, tests and known risks.

Each task creates `CONTEXT_MANIFEST.md` from the validated index plus current Git delta. Agents start from the selected task surface and expand only when primary evidence indicates wider dependency, regression, security, documentation or architectural impact.

Role handoffs use fresh referential packets:

```text
.ai/tasks/<TASK-ID>/evidence/
├── EXECUTION_PACKET.md
├── REVIEW_IMPLEMENTATION_PACKET.md
├── REVIEW_ARCHITECTURE_PACKET.md
└── FINAL_PACKET.md
```

Packets reference canonical artifacts instead of copying unrelated conversation history. The two reviewer packets never contain the sibling current-cycle review. Final packet is built only after both independent reviews complete.

See [Context efficiency and resumable governance](docs/context-efficiency-resume.md).

## Adaptive output efficiency and usage telemetry

All seven governance agents use `ADAPTIVE_OUTPUT_EFFICIENCY`: reasoning depth is preserved while output defaults to concise, evidence-dense communication. Agents omit filler, repeated canonical evidence and obvious tool narration, while preserving exact technical evidence and expanding whenever brevity could create safety or correctness ambiguity.

```text
/ai-metrics [scope]
```

`/ai-metrics` reads usage already recorded by the installed OpenCode runtime. It may use model stats and sanitized session data for proven task/role attribution, but never estimates missing token counts or proportionally splits model totals across roles. Missing fields remain `UNAVAILABLE`.

See [Token efficiency and usage telemetry](docs/token-efficiency.md).

## Minimum necessary change

Every implementation-ready plan contains `MINIMUM_CHANGE_ASSESSMENT`:

- root cause or evidence-backed hypothesis;
- existing code/pattern reuse;
- standard-library/native-platform option;
- already-installed dependency option;
- justification for new dependencies or abstractions;
- why the proposed diff is the smallest correct, secure and maintainable change.

Minimalism never removes required security, trust-boundary validation, data-loss protection, error handling, accessibility or approved behavior. Bug fixes should address the shared root cause when relevant callers demonstrate it, rather than only patching the reported symptom.

## Checkpoint and resume

Each active task maintains machine-readable `.ai/tasks/<TASK-ID>/RUN_STATE.json` at phase boundaries.

After an interrupted session, restart, crash or provider quota exhaustion:

```text
/ai-resume <TASK-ID>
```

Resume validates the checkpoint against Git state, baseline freshness, requirement provenance, steering and the frozen review target. It resumes only from a safe persisted phase. Missing history is never invented, and review evidence is invalidated when the reviewed target has changed.

Task-oriented commands expose a parseable block:

```text
GOVERNANCE_RESULT
TASK_ID: <id or NONE>
STATE: <state>
NEXT_ACTION: <action or NONE>
CYCLE: <n/3 or N/A>
HUMAN_INPUT_REQUIRED: YES|NO
RESUMABLE: YES|NO
CHECKPOINT: <RUN_STATE path or NONE>
```

## Governed steering

Mid-task authoritative direction may be recorded in `STEERING.md`. Material steering cannot silently mutate the task after planning: it must enter `CLARIFICATION_TRANSCRIPT.md`, update approved requirements only when authorized, and force replanning when the current plan is no longer valid.

## Optional task queue

Large milestones may use `.ai/TASK_QUEUE.json` with task priority, dependencies and state. Governance may select the highest-priority eligible task, but every task still passes the normal baseline, provenance, planning, execution and review gates. No unbounded autonomous loop is introduced.

## Project documentation governance

`.ai/DOCUMENTATION_SCOPE.md` records canonical project documentation paths, applicability, audience, synchronization state and license state.

Without an existing coherent convention, top-level `docs/` is the default documentation root outside the production/runtime package. For distributable applications, the normal minimum applicable set is overview/readme, step-by-step installation, user manual, wiki/index, changelog and licensing documentation, plus other admin/upgrade/architecture/configuration/API/security/troubleshooting/release documentation when applicable.

Every task records `DOCUMENTATION_IMPACT: NONE | UPDATE_REQUIRED | CREATE_REQUIRED`. Required documentation is synchronized by Executor before `TASK_VALIDATED` and reviewed with the implementation.

Governance never chooses a software license. Missing explicit owner/legal evidence becomes `LICENSE_DECISION_REQUIRED` and blocks release readiness until resolved.

## Complete task lifecycle

```text
BASELINE_VALIDATED
        ↓
REQUIREMENT_CAPTURE
        ↓
CLARIFICATION / APPROVED_REQUIREMENTS
        ↓
CONTEXT_ROUTING
        ↓
PLANNING / MINIMUM_CHANGE_GATE
        ↓
READY_FOR_EXECUTION
        ↓
EXECUTOR
        ↓
DOCUMENTATION_SYNC / TASK_VERIFYING
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

The source/documentation target is frozen during each review cycle. Only Final Reviewer validated corrections may drive automatic repair. Task final-adjudication failures are bounded to three cycles, then `BLOCKED`.

After `PASS`, Executor creates one scoped local task commit. `git push` always requires explicit user authorization.

## Large repositories

A validated baseline/context index is reusable. Routine tasks use Git delta plus task-specific routing rather than rescanning the complete repository. Full adversarial revalidation is reserved for material architecture changes, broad milestones, large merge/rebase events, major dependency upgrades, substantial imported code, materially stale evidence or explicit `/ai-audit`.

## Release gate

```text
/ai-release
```

Release review requires a current validated baseline, synchronized required documentation, explicit license decision, production package correctness, clean installation/startup evidence when applicable, required tests/build/static checks, secret safety, schema/data preservation and mandatory real integration validation.

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

Verification checks all seven agents, all eleven commands, provider-qualified model IDs, governed Build/Plan behavior, requirement provenance, context routing, minimum-change gate, fresh evidence packets, resume/checkpoint markers, adaptive output efficiency, real-usage metrics policy, reviewer modes, documentation/license gates and `default_agent`.

## Uninstall

```powershell
./scripts/uninstall.ps1
```

or:

```bash
./scripts/uninstall.sh
```

Provider authentication, project `.ai/` state, project documentation and backups are left untouched.

## Documentation

- [Installation](docs/installation.md)
- [Workflow](docs/workflow.md)
- [Requirement provenance](docs/requirement-provenance.md)
- [Context efficiency and resumable governance](docs/context-efficiency-resume.md)
- [Token efficiency and usage telemetry](docs/token-efficiency.md)
- [Model configuration](docs/model-configuration.md)
- [Project documentation governance](docs/project-documentation.md)
- [Permissions](docs/permissions.md)
- [Troubleshooting](docs/troubleshooting.md)

## License

FSL-1.1-MIT. Each released version becomes available under the MIT License on the second anniversary of its release date. See [LICENSE](LICENSE).