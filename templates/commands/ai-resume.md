---
description: Resume interrupted product governance from persisted evidence
agent: architect
subtask: false
---

Resume `$ARGUMENTS` from Git, `RUN_STATE.json`, `STEERING.md`, canonical task/product artifacts and evidence, never conversation history.

Read:
- `.ai/product/PRODUCT_VISION.md`
- `.ai/product/USER_AND_ROLE_MODEL.md`
- `.ai/product/DOMAIN_AND_PROCESS_MODEL.md`
- `.ai/product/PRODUCT_COMPLETENESS_MATRIX.md`
- `.ai/product/PRODUCT_BLUEPRINT.md`
- `.ai/product/PRODUCT_DECISIONS.md`

Reconstruct `WORK_CLASS`, `DISCOVERY_DEPTH`, `DISCOVERY_STATUS`, `PRODUCT_SCOPE_STATUS`, `PRODUCT_BLUEPRINT_VERSION`, `MATERIAL_UNKNOWN_COUNT`, approval and milestone state. Invalidate only evidence dependent on changed product/source/contract/dependency/environment/tool/recovery inputs. Preserve `GOVERNANCE_RESULT`, `ENVIRONMENT_FINGERPRINT`, `STALE`, `GOVERNANCE_MEMORY`, `DEPENDENCY_ADMISSION_GATE`, `PRE_CHANGE_SAFEPOINT`, `MEMORY_DECISION`, `OPERATIONAL_ASSURANCE`.

## Resume integrity contract

Verify current Git target and every evidence dependency before selecting the next phase. Do not recreate historical safepoints, approvals, failure reproduction, reviewer independence or validation evidence after the fact. If a review target changed, discard affected review results and create a fresh cycle. If steering changed requirements or product scope, return to discovery/planning before execution.

Resume never installs tools, broadens permissions or performs external actions merely to recover progress.

When the frozen target changed, `REVIEW_FREEZE` evidence is stale and a new review cycle is required.
