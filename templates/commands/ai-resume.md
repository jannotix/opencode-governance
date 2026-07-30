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

## WORKFLOW_CONTINUATION_GATE_V1

Resume preserves the original `top_level_command` recorded in `RUN_STATE.json`; an interrupted `/ai-workflow` remains `top_level_command: ai-workflow`. Require `current_phase`, `next_required_phase` and `terminal_reason` and never replace the original authority with `ai-resume`.

Before emitting a final response, execute the installed `workflow-continuation.py` with `--expected-command ai-resume`. Decision `CONTINUE_REQUIRED` resumes the original workflow at `next_required_phase` from authoritative persisted evidence. `TERMINAL_ALLOWED` is valid only for `LOCAL_COMMITTED` or an explicit blocker with a non-empty `terminal_reason`. `INVALID_RUN_STATE` blocks completion. Do not restart from zero, create a second task, or ask the owner to invoke an internal phase command when continuation is safe.
