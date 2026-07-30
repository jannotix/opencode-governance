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

## Audit contract

Revalidate the exact current repository reference and product artifact versions. Reviewer packets use one frozen target and never include sibling findings. Final Reviewer adjudicates baseline/product allegations against primary evidence. A changed source, contract, dependency, migration, environment, validation, skill, preview, tool, recovery or isolation input invalidates only dependent evidence.

Audit does not declare the codebase defect-free, rewrite historical requirements, install tools, admit dependencies, deploy, push, merge or widen permissions. Maximum three failed baseline correction cycles. `NO_AUTOMATIC_EXTERNAL_ACTION` applies.
