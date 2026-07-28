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
