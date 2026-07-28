---
description: Discover refresh or audit the governed product definition
agent: architect
subtask: false
---

Run `ADAPTIVE_PRODUCT_DISCOVERY` for `$ARGUMENTS`.

Modes: `/ai-discover` starts or continues; `/ai-discover refresh` updates after an approved change; `/ai-discover audit` finds omissions, contradictions, stale decisions and incomplete coverage.

Always set `WORK_CLASS`, `DISCOVERY_DEPTH: LIGHT|STANDARD|DEEP`, `ASSISTANCE_MODE` and `MATERIAL_UNKNOWN_COUNT`. Apply `GOVERNED_DOMAIN_RESEARCH`, `CONSTRUCTIVE_CHALLENGE`, `GUIDED_DECISION_POLICY` and approval rules. Never implement source/docs or turn research into requirements automatically.

Create/update only:
- `.ai/product/PRODUCT_VISION.md`
- `.ai/product/USER_AND_ROLE_MODEL.md`
- `.ai/product/DOMAIN_AND_PROCESS_MODEL.md`
- `.ai/product/PRODUCT_COMPLETENESS_MATRIX.md`
- `.ai/product/PRODUCT_BLUEPRINT.md`
- `.ai/product/PRODUCT_DECISIONS.md`

For required independent review reuse existing reviewer packet/report names with `REVIEW_MODE: DISCOVERY_REVIEW`. Only Final Reviewer controls `DISCOVERY_PASS|DISCOVERY_DEFECT|DISCOVERY_BLOCKED`. Stop after discovery/review/approval and emit `GOVERNANCE_RESULT` with `EVIDENCE_STATUS`.
