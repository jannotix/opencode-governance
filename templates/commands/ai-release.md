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

## Release evidence contract

Request independent implementation and architecture release reviews against the same candidate, then Final Reviewer adjudication. Product completeness requires current evidence for every required capability, user/admin/negative flows, role/permission behavior, data lifecycle, applicable installation/update/recovery and documentation. A test suite alone is insufficient.

Production readiness separately requires baseline validity, artifact/package identity, clean install/startup/smoke where applicable, authoritative validation, security/secrets, admitted dependencies and delta, contract/codegen/migration/data evidence, non-functional budgets, operational/recovery/tool evidence, legal/license state and required human-owner gates. Any required stale/failed/unavailable proof prevents readiness. `NO_AUTOMATIC_EXTERNAL_ACTION` applies.
