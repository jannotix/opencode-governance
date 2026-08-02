---
description: Run independent discovery task baseline or release review
agent: architect
subtask: false
---

Review `$ARGUMENTS`. Supported modes: `DISCOVERY_REVIEW|TASK_REVIEW|BASELINE_AUDIT|RELEASE_REVIEW`.

Use existing `REVIEW_IMPLEMENTATION_PACKET.md`, `REVIEW_ARCHITECTURE_PACKET.md`, `FINAL_PACKET.md`; never include sibling current-cycle findings. Product evidence includes:
- `.ai/product/PRODUCT_VISION.md`
- `.ai/product/USER_AND_ROLE_MODEL.md`
- `.ai/product/DOMAIN_AND_PROCESS_MODEL.md`
- `.ai/product/PRODUCT_COMPLETENESS_MATRIX.md`
- `.ai/product/PRODUCT_BLUEPRINT.md`
- `.ai/product/PRODUCT_DECISIONS.md`

For discovery, Final Reviewer returns `DISCOVERY_PASS|DISCOVERY_DEFECT|DISCOVERY_BLOCKED`. For task review it controls `PASS|IMPLEMENTATION_DEFECT|PLAN_DEFECT|BLOCKED` and `MEMORY_DECISION`. For release it records `PRODUCT_COMPLETENESS_VERDICT` and `RELEASE_VERDICT`. Preserve verification and `OPERATIONAL_ASSURANCE` evidence freshness.

## Independent review contract

Both reviewers inspect the same frozen target and canonical evidence without sibling current-cycle findings. Discovery summaries, skills, memory and conversation history are not proof. Final Reviewer classifies each allegation, rejects false positives, preserves unique valid findings and verifies provenance before plan and implementation.

Task repair follows `IMPLEMENTATION_DEFECT|PLAN_DEFECT|BLOCKED` semantics with fresh dependent evidence and maximum three cycles. Release review assesses the current candidate, not accumulated PASS history. `REVIEW_FREEZE`, `EVIDENCE_FRESHNESS`, `BOUNDED_REPAIR` and `NO_AUTOMATIC_EXTERNAL_ACTION` are mandatory.

## Deterministic review orchestration (GOVERNED_REVIEW_ORCHESTRATION_V1, 4.0.3)

The dual-review flow is a host-owned deterministic operation, not narrative
prompt instructions. When installed, invoke `scripts/review-orchestration.py`
to start Implementation Reviewer and Architecture Reviewer against separate
IMMUTABLE evidence roots, ingest both reports deterministically, build the
Final Reviewer evidence root, start Final Reviewer, and attest the Review Chain
V4:

```
python scripts/review-orchestration.py \
  --config-dir "$OPENCODE_CONFIG_DIR" \
  --workspace "$PWD" \
  --task-id <TASK-ID> \
  --packet-sha256 <64-hex> \
  --candidate-identity <commit-sha> \
  --packet-path .ai/tasks/<TASK-ID>/FINAL_PACKET.md \
  --implementation-source .ai/tasks/<TASK-ID>/implementation-evidence \
  --architecture-source .ai/tasks/<TASK-ID>/architecture-evidence \
  --model <routed-model>
```

Implementation Reviewer never receives Architecture output and vice-versa.
Neither reviewer receives `RUN_STATE.json`, `FINAL_ADJUDICATION.md`, sibling
temp files, logs or ingestion metadata. The Architect model needs no generic
shell or `task`; this operation is part of the deterministic Governance host.
A `GOVERNED_ROLE_PROCESS_COMPLETE` receipt for each reviewer and a
`REVIEW_CHAIN_ATTESTED` V4 attestation are required before the workflow may
proceed past `FINAL_ADJUDICATION`.
