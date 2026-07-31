# Workflow

## Canonical lifecycle

Phase names used in `RUN_STATE.json` and `WORKFLOW_CONTINUATION_GATE_V1`:

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
→ EVIDENCE_PLANNING
→ OPERATIONAL_PLANNING
→ READY_FOR_EXECUTION
→ PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED
→ IMPLEMENTING
→ DOCUMENTATION_SYNC
→ EVIDENCE_VALIDATION
→ OPERATIONAL_VALIDATION
→ TASK_VALIDATED
→ DUAL_REVIEW
→ FINAL_ADJUDICATION
→ PRODUCT_COMPLETENESS_RECONCILIATION
→ RELEASE_READINESS
→ VALIDATED_LEARNING
→ LOCAL_COMMITTED
```

Aliases accepted by the continuation gate for compatibility: `IMPLEMENTATION` / `IMPLEMENTING`, `TASK_DUAL_REVIEW` / `DUAL_REVIEW`, `TASK_FINAL_ADJUDICATION` / `FINAL_ADJUDICATION`.

## Rules

- Transitions are fail-closed.
- Small tasks may use `LIGHT` discovery; discovery is never `NONE`.
- Product-specific phases may be `NOT_REQUIRED` only when primary evidence proves no product-scope effect.
- Non-terminal `RUN_STATE.json` requires typed `next_action` (`execute` with a real `/ai-*` command, or `human_decision`).
- `terminal_reason` is forbidden on non-terminal phases.
- Only `LOCAL_COMMITTED` or an explicit blocker with `terminal_reason` is terminal.
- Failed or stale evidence returns the workflow to the earliest affected phase.
- A validated milestone may remain `PRODUCT_INCOMPLETE` until every required capability is accepted.

See also: [governance authority & memory](governance-authority-memory.md), [permissions](permissions.md).
