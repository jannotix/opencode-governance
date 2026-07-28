---
description: Execute an approved product-aware governance plan
agent: architect
subtask: false
---

Execute `$ARGUMENTS` only through Executor after `READY_FOR_EXECUTION`. Require task provenance, product references, `PRODUCT_BLUEPRINT_VERSION`, `PRODUCT_CAPABILITY_TRACEABILITY`, `CONTEXT_MANIFEST.md`, `VERIFICATION_PROFILE.md`, `RUN_STATE.json`, execution packet and all approvals.

Product artifacts:
- `.ai/product/PRODUCT_VISION.md`
- `.ai/product/USER_AND_ROLE_MODEL.md`
- `.ai/product/DOMAIN_AND_PROCESS_MODEL.md`
- `.ai/product/PRODUCT_COMPLETENESS_MATRIX.md`
- `.ai/product/PRODUCT_BLUEPRINT.md`
- `.ai/product/PRODUCT_DECISIONS.md`

Executor implements only approved capability/milestone scope, records verification evidence, synchronizes docs and reports `MILESTONE_VALIDATED` plus `PRODUCT_INCOMPLETE` and remaining required capabilities when partial. Preserve `DEPENDENCY_ADMISSION_GATE`, `PRE_CHANGE_SAFEPOINT`, `OPERATIONAL_ASSURANCE`; no automatic push/deploy.

## Execution handoff contract

Create a fresh referential `EXECUTION_PACKET.md` with exact baseline/repository/product/plan versions, requirements, selected context, capability IDs, validation and permitted evidence-triggered expansion. Executor returns `PLAN_CONFLICT` rather than improvising when evidence contradicts plan or product state.

Required evidence is recorded in `VERIFICATION_EVIDENCE.md` with exact commands, targets, results and freshness. Changes to dependent source/docs/contracts/lockfiles/generators/migrations/environment/validation/preview/tools/recovery/isolation stale affected proof. Freeze only after every acceptance criterion, required capability and applicable gate is satisfied. `NO_AUTOMATIC_EXTERNAL_ACTION` applies.
