---
description: Analyse a request and create a governed product-aware implementation plan
agent: architect
subtask: false
---

Plan `$ARGUMENTS` without implementation. Require `BASELINE_VALIDATED`.

Read product artifacts:
- `.ai/product/PRODUCT_VISION.md`
- `.ai/product/USER_AND_ROLE_MODEL.md`
- `.ai/product/DOMAIN_AND_PROCESS_MODEL.md`
- `.ai/product/PRODUCT_COMPLETENESS_MATRIX.md`
- `.ai/product/PRODUCT_BLUEPRINT.md`
- `.ai/product/PRODUCT_DECISIONS.md`

Set `WORK_CLASS`, `DISCOVERY_DEPTH`, `ASSISTANCE_MODE`, `DISCOVERY_STATUS`, `PRODUCT_SCOPE_STATUS`, `MATERIAL_UNKNOWN_COUNT`, `USER_APPROVAL_REQUIRED`, `USER_APPROVAL_STATUS`, `PRODUCT_BLUEPRINT_VERSION`. Run or require `ADAPTIVE_PRODUCT_DISCOVERY`, `CONSTRUCTIVE_CHALLENGE`, `GUIDED_DECISION_POLICY` and `DISCOVERY_REVIEW` as applicable.

Create task provenance, `CONTEXT_MANIFEST.md`, `MINIMUM_CHANGE_ASSESSMENT`, `VERIFICATION_PROFILE.md`, `RUN_STATE.json`, `EXECUTION_PACKET.md`. Product-affecting plans include `PRODUCT_CAPABILITY_TRACEABILITY`, exact capability IDs, `VERTICAL_MILESTONE`, milestone acceptance and completeness impact.

`READY_FOR_EXECUTION` requires `DISCOVERY_PASS`, `MATERIAL_UNKNOWN_COUNT: 0`, product scope `APPROVED|NOT_REQUIRED`, approval `APPROVED|NOT_REQUIRED`, and all v2 Evidence-Driven/Operational Assurance prerequisites. Stop after planning.

## Planning completeness contract

Read original request and chronological clarification directly before normalizing requirements. Reconcile with approved product version and decision register; any contradiction or unapproved scope change requires authoritative clarification. Build sparse verified context from validated indexes, applicable instructions/skills/memory and Git delta.

The plan defines exact in/out scope, affected paths/call paths and trust/data/contract/integration/deployment/documentation impact; product capability IDs; vertical milestone outcome; acceptance criteria; minimum-change assessment; risk profile; validation commands; Evidence-Driven and Operational Assurance applicability; dependency admission; safepoint/migration/recovery behavior; evidence freshness and blockers.

Do not invent thresholds, tools, infrastructure, recoverability, legal conclusions or human approvals. A technically correct implementation of an incorrect plan remains `PLAN_DEFECT`. `NO_AUTOMATIC_EXTERNAL_ACTION` applies.
