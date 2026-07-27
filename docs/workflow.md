# Workflow

## Initial repository validation

```text
/ai-init
```

Creates/reuses baseline, context index, documentation/deployment scope, history/status, audit and task directories. Architect performs broad structural/risk-based intake, then two independent baseline audits and Final Reviewer adjudication:

```text
BASELINE_DRAFT
→ BASELINE_DUAL_AUDIT
   ├── reviewer / BASELINE_AUDIT
   └── reviewer-architecture / BASELINE_AUDIT
→ final-reviewer / BASELINE_AUDIT
→ BASELINE_VALIDATED
```

The reviewers do not receive sibling current-cycle findings. `BASELINE_PASS` means the baseline, `.ai/CONTEXT_INDEX.md`, documentation inventory, material risks/unknowns and exclusions are trustworthy reusable context; it does not mean the codebase is defect-free.

Maximum failed baseline adjudications: three, then `BASELINE_BLOCKED`.

## Requirement and clarification gate

Every task begins with:

```text
ORIGINAL_USER_REQUEST.md
CLARIFICATION_TRANSCRIPT.md
APPROVED_REQUIREMENTS.md
```

Original user intent remains distinct from Architect interpretation. Material unanswered product/project decisions are resolved with OpenCode `question`; answered questions are not repeated. Explicit later supersession is recorded chronologically.

A plan cannot override the canonical requirement trail.

## Context routing

A validated repository maintains `.ai/CONTEXT_INDEX.md` with material module/path, call/dependency, data/trust, security, documentation, validation and risk routing metadata.

Each task builds `.ai/tasks/<TASK-ID>/CONTEXT_MANIFEST.md` from that index plus current Git delta. It records selected context, safe exclusions and every material evidence-triggered expansion.

Agents start from the manifest and relevant packet. Full repository rescans are not the default for routine work.

## Minimum-change planning

Implementation-ready plans contain `MINIMUM_CHANGE_ASSESSMENT`:

- root cause/evidence-backed hypothesis;
- existing capability/pattern reuse;
- stdlib/native-platform option;
- installed dependency option;
- new dependency/abstraction justification;
- smallest correct, secure and maintainable proposed change.

For bugs, inspect relevant callers and prefer the correct shared root-cause fix. Minimalism never removes security, trust-boundary validation, data-loss protection, required error handling, accessibility or approved behavior.

## Checkpoint state

Each active task maintains `.ai/tasks/<TASK-ID>/RUN_STATE.json` at governance phase boundaries. It records current state, baseline/reference, plan version, repository target, review cycle/freeze, completion flags, last safe transition, resumability and blocker.

Task commands emit a parseable `GOVERNANCE_RESULT` block with state, next action, cycle, human-input requirement and checkpoint path.

## Fresh evidence packets

Role handoffs are built under `.ai/tasks/<TASK-ID>/evidence/`:

```text
EXECUTION_PACKET.md
REVIEW_IMPLEMENTATION_PACKET.md
REVIEW_ARCHITECTURE_PACKET.md
FINAL_PACKET.md
```

Packets reference canonical evidence instead of copying chat history. Implementation and Architecture/Security packets target the same frozen task state but contain role-specific selected context. Neither contains the sibling current-cycle review. Final packet is built only after both independent reviews complete.

## Adaptive output efficiency

All governance agents use `ADAPTIVE_OUTPUT_EFFICIENCY`: reasoning depth is not reduced, but handoffs and reports default to concise, evidence-dense output. Agents reference canonical artifacts rather than duplicating them, omit filler/repeated conclusions and preserve exact technical evidence.

Compression stops when it could create ambiguity or weaken correctness, especially for security, destructive/irreversible actions, schema/data changes, unresolved requirements, architectural disagreements, blockers and recovery instructions.

Reviewer findings keep all required evidence in a compact structured form so Final Reviewer can adjudicate without consuming repeated narrative.

## Usage telemetry

```text
/ai-metrics [scope]
```

`/ai-metrics` is observational. It reads usage already recorded by OpenCode through supported stats/session/export capabilities. It never estimates missing token counts, never proportionally assigns model totals to roles and never changes governance state.

When runtime evidence allows it, usage is aggregated by governance role/model. Missing fields or attribution are reported as `UNAVAILABLE`/`PARTIAL`. Sanitized session export is used when supported and needed for attribution; raw transcript content is not persisted as governance evidence.

See [Token efficiency and usage telemetry](token-efficiency.md).

## Complete workflow

```text
/ai-workflow <task>
```

Lifecycle:

```text
BASELINE_VALIDATED
→ REQUIREMENT_CAPTURE
→ CLARIFICATION
→ APPROVED_REQUIREMENTS
→ CONTEXT_ROUTING
→ PLANNING
→ MINIMUM_CHANGE_GATE
→ TASK_PLANNED
→ READY_FOR_EXECUTION
→ IMPLEMENTING
→ DOCUMENTATION_SYNC
→ TASK_VERIFYING
→ TASK_VALIDATED
→ DUAL_REVIEW
→ FINAL_ADJUDICATION
→ LOCAL_COMMITTED
```

Executor implements only an approved plan and synchronizes required project documentation before `TASK_VALIDATED`.

At `TASK_VALIDATED`, source/task documentation are frozen for the current review cycle. Architect creates the two fresh independent reviewer packets and requests both reviewers before consuming either result.

After both reviews complete, Architect creates `FINAL_PACKET.md`. Final Reviewer validates requirement provenance and Architect interpretation before implementation correctness, then validates reviewer allegations against primary evidence rather than counting votes.

Final task verdicts:

- `PASS`;
- `IMPLEMENTATION_DEFECT`;
- `PLAN_DEFECT`;
- `BLOCKED`.

A perfect implementation of a materially wrong plan is `PLAN_DEFECT`. Review evidence becomes stale when the frozen source/documentation target changes. Repair returns only Final Reviewer validated corrections through the appropriate Architect/Executor route.

Maximum failed task final-adjudication cycles: three, then `BLOCKED`.

After `PASS`, Executor creates one scoped local task commit. Push requires explicit user authorization.

## Governed steering

`.ai/tasks/<TASK-ID>/STEERING.md` may carry authoritative mid-task direction. Before it can change implementation:

1. record material direction chronologically in `CLARIFICATION_TRANSCRIPT.md`;
2. identify add/narrow/supersede semantics;
3. update `APPROVED_REQUIREMENTS.md` only from authoritative input;
4. reassess the plan;
5. return to `PLANNING` when the plan became stale.

Operational prioritization that does not change requirements may be recorded/applied without rewriting the plan.

## Resume after interruption

```text
/ai-resume <TASK-ID>
```

Resume reads `RUN_STATE.json`, `.ai/STATUS.md`, requirement provenance, context manifest/index, steering and Git state. It validates the checkpointed repository target before routing to the last safe unfinished phase.

Examples:

- `READY_FOR_EXECUTION` → fresh execution packet/Executor;
- interrupted `IMPLEMENTING` → reconcile worktree and continue only if plan/checkpoint still match;
- `TASK_VALIDATED` → fresh dual review;
- one review complete with unchanged frozen target → complete the missing independent review;
- interrupted `FINAL_ADJUDICATION` → rebuild final packet and adjudicate;
- `PASS` without commit → scoped Executor finalization;
- `LOCAL_COMMITTED` → nothing to resume;
- `BLOCKED`/`BASELINE_BLOCKED` → remain blocked until authoritative resolution.

Resume never fabricates missing provenance/review history and never reuses stale review output after the target changes.

## Optional task queue

Large milestones may add `.ai/TASK_QUEUE.json` containing task IDs, priorities, dependencies and state. The orchestrator may select the highest-priority eligible task whose dependencies are complete.

This is scheduling only: every task still runs the complete governance lifecycle, three-cycle limits remain, and human decisions still block. There is no unbounded autonomous loop.

## Other commands

Planning only:

```text
/ai-plan <task>
```

Execute an approved plan:

```text
/ai-execute <task-id-or-plan-id>
```

Independent dual review + final adjudication:

```text
/ai-review <task-id>
```

Explicit baseline/context-index audit:

```text
/ai-audit
```

Governed project documentation task:

```text
/ai-docs
```

Status/checkpoint report:

```text
/ai-status
```

Recorded usage telemetry:

```text
/ai-metrics [scope]
```

Production gate:

```text
/ai-release
```

## Documentation and license

`.ai/DOCUMENTATION_SCOPE.md` maps canonical documentation and applicability. Required task documentation is synchronized before validation and reviewed with code. `docs/**` and `.ai/**` are outside the runtime artifact by default except explicitly justified legal/packaging/runtime exceptions.

Governance never chooses/invents software licenses. Missing explicit license state becomes `LICENSE_DECISION_REQUIRED` and blocks release readiness until resolved.

## Large repositories

Initial baseline validation is broad and risk-based. Routine tasks reuse validated baseline/context index and inspect Git delta plus targeted affected paths. Full revalidation is reserved for material architectural/dependency/import changes, broad milestones, large merges/rebases, evidence of stale/incomplete context or explicit `/ai-audit`.