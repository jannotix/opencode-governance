# Workflow

This document defines phase ordering and ownership. Detailed gate semantics live in the dedicated references linked below.

## 1. Repository baseline

Initialize once per repository:

```text
/ai-init
```

The baseline is drafted by Architect, independently audited by both reviewers, then adjudicated by Final Reviewer.

```text
BASELINE_DRAFT
→ BASELINE_DUAL_AUDIT
   ├─ reviewer / BASELINE_AUDIT
   └─ reviewer-architecture / BASELINE_AUDIT
→ final-reviewer / BASELINE_AUDIT
→ BASELINE_VALIDATED
```

Maximum failed baseline adjudications: three. Then `BASELINE_BLOCKED`.

## 2. Requirement provenance

Every task starts with:

```text
ORIGINAL_USER_REQUEST.md
CLARIFICATION_TRANSCRIPT.md
APPROVED_REQUIREMENTS.md
```

The plan is downstream from these artifacts. Material ambiguity or instruction conflict must be resolved before `READY_FOR_EXECUTION`.

See [Requirement provenance](requirement-provenance.md).

## 3. Context routing

Architect builds task context from:

- validated `CONTEXT_INDEX.md`;
- `INSTRUCTION_INDEX.md` and applicable skills;
- active scoped `GOVERNANCE_MEMORY.md` entries;
- current Git delta;
- optional bounded `READ_ONLY_DISCOVERY_SWARM` results;
- primary repository evidence.

The task-specific result is `CONTEXT_MANIFEST.md`.

See [Context efficiency and resumable governance](context-efficiency-resume.md).

## 4. Planning

An implementation-ready plan must include:

- acceptance criteria and requirement traceability;
- `MINIMUM_CHANGE_ASSESSMENT`;
- `TASK_RISK_PROFILE`;
- `VALIDATION_PROFILE`;
- Evidence-Driven gate applicability;
- `OPERATIONAL_ASSURANCE` applicability;
- documentation impact;
- dependency admission and pre-change safepoint requirements when applicable.

Planning states for verification gates:

```text
REQUIRED | CONDITIONAL | NOT_APPLICABLE
```

See [Evidence-Driven Verification](evidence-driven-verification.md) and [Operational Assurance](operational-assurance.md).

## 5. Execution

Only `executor` may edit application source or approved project documentation.

Execution requires:

```text
BASELINE_VALIDATED
READY_FOR_EXECUTION
CONTEXT_MANIFEST.md
VERIFICATION_PROFILE.md
RUN_STATE.json
EXECUTION_PACKET.md
```

Before a new direct dependency is installed, `DEPENDENCY_ADMISSION_GATE` must resolve appropriately. Before a required high-risk mutation, `PRE_CHANGE_SAFEPOINT` must exist.

Executor records validation in:

```text
evidence/VERIFICATION_EVIDENCE.md
```

Required unavailable evidence without a sufficient approved equivalent cannot produce `TASK_VALIDATED`.

## 6. Review

At `TASK_VALIDATED`, the reviewed target is frozen.

Architect creates independent packets for:

```text
reviewer
reviewer-architecture
```

Both reviewers inspect the same frozen source/documentation/evidence target and do not receive sibling current-cycle findings.

Only after both reviews complete is `FINAL_PACKET.md` built.

Final Reviewer independently verifies requirement provenance, plan authorization, evidence freshness and reviewer allegations before returning:

```text
PASS
IMPLEMENTATION_DEFECT
PLAN_DEFECT
BLOCKED
```

A materially incorrect plan remains `PLAN_DEFECT` even when implementation follows it exactly.

Maximum failed final-adjudication repair cycles: three. Then `BLOCKED`.

## 7. Validated learning

When `CLOSED_LOOP_LEARNING` applies, reviewers challenge the candidate independently and Final Reviewer records:

```text
MEMORY_DECISION: NONE | APPROVE | REJECT
```

Only an approved candidate may be persisted by Architect to `.ai/GOVERNANCE_MEMORY.md`.

## 8. Finalization

After Final Reviewer `PASS`, Executor creates one scoped local commit. `git push` requires explicit authorization for that push.

## Lifecycle

```text
BASELINE_VALIDATED
→ REQUIREMENT_CAPTURE / CLARIFICATION
→ GOVERNED_DISCOVERY / SKILL_ROUTING
→ CONTEXT_ROUTING
→ PLANNING
→ EVIDENCE + OPERATIONAL PLANNING
→ READY_FOR_EXECUTION
→ PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED
→ IMPLEMENTING
→ DOCUMENTATION_SYNC
→ EVIDENCE_VALIDATION
→ OPERATIONAL_VALIDATION
→ TASK_VALIDATED
→ DUAL_REVIEW
→ FINAL_ADJUDICATION
→ VALIDATED_LEARNING
→ LOCAL_COMMITTED
```

## Resume

```text
/ai-resume <TASK-ID>
```

Resume reconstructs state from Git and persisted `.ai/**` evidence, never from chat history. It invalidates only evidence that depends on changed inputs.

See [Context efficiency and resumable governance](context-efficiency-resume.md).

## Release

```text
/ai-release
```

Release review revalidates the production candidate, required evidence, Operational Assurance, documentation, licensing, packaging and independent release reviews. It is an assessment gate; it does not automatically deploy, rollback, merge or push.

## Other commands

```text
/ai-plan <task>
/ai-execute <task-id-or-plan-id>
/ai-review <task-id>
/ai-audit
/ai-docs
/ai-status
/ai-metrics [scope]
/ai-release
```
