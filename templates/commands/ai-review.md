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
