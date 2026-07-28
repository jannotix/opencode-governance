---
description: Assess product completeness and production readiness
agent: architect
subtask: false
---

Assess the frozen release candidate from primary evidence. Read:
- `.ai/product/PRODUCT_VISION.md`
- `.ai/product/USER_AND_ROLE_MODEL.md`
- `.ai/product/DOMAIN_AND_PROCESS_MODEL.md`
- `.ai/product/PRODUCT_COMPLETENESS_MATRIX.md`
- `.ai/product/PRODUCT_BLUEPRINT.md`
- `.ai/product/PRODUCT_DECISIONS.md`

Run `PRODUCT_COMPLETENESS_RECONCILIATION` across request, clarifications, approved requirements, decisions, blueprint, matrix, milestones/tasks, implementation, verification evidence, `OPERATIONAL_ASSURANCE`, documentation and candidate.

Output `PRODUCT_BLUEPRINT_VERSION`, `COMPLETENESS_MATRIX_STATUS`, `REMAINING_REQUIRED_CAPABILITIES`, `PRODUCT_COMPLETENESS_VERDICT: PRODUCT_COMPLETE|PRODUCT_DEFECT|PRODUCT_BLOCKED`, `RELEASE_VERDICT: READY_FOR_PRODUCTION|NOT_READY_FOR_PRODUCTION`, human input and `EVIDENCE_STATUS`.

`READY_FOR_PRODUCTION` requires `PRODUCT_COMPLETE` plus all existing test/build/security/dependency/migration/packaging/license/human-owner/recovery/release gates. A complete product may still be not ready. Never deploy, rollback, push or merge automatically. Preserve `DEPENDENCY_ADMISSION_GATE`, `PRE_CHANGE_SAFEPOINT`, `CLOSED_LOOP_LEARNING`, `MEMORY_DECISION`.
