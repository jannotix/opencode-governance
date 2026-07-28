---
description: Adversarially revalidate governance product and repository state
agent: architect
subtask: false
---

Audit current baseline/index/memory/documentation and product state. Check stale sources, contradictions between task provenance and product artifacts, missing `PRODUCT_COMPLETENESS_MATRIX.md` coverage, unsupported approvals, silent MVP reduction and migration assumptions.

Product artifacts:
- `.ai/product/PRODUCT_VISION.md`
- `.ai/product/USER_AND_ROLE_MODEL.md`
- `.ai/product/DOMAIN_AND_PROCESS_MODEL.md`
- `.ai/product/PRODUCT_COMPLETENESS_MATRIX.md`
- `.ai/product/PRODUCT_BLUEPRINT.md`
- `.ai/product/PRODUCT_DECISIONS.md`

Use independent reviewer audits and Final Reviewer control. Do not implement or invent corrections beyond validated `.ai/**` changes. Preserve `VERIFICATION_PROFILE`, `TASK_RISK_PROFILE`, `DEPENDENCY_ADMISSION_GATE`, `PRE_CHANGE_SAFEPOINT`, `CLOSED_LOOP_LEARNING` and `OPERATIONAL_ASSURANCE` semantics.
