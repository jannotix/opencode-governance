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

## RESUME_MODE_V1

Before any `.ai/**` write, classify resume mode from authoritative `RUN_STATE.json` (`current_phase`, `next_required_phase`, and when needed `state` / `last_safe_transition`):

- `PRE_SIDE_EFFECT` — at or before `READY_FOR_EXECUTION` / `PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED`. Must run through the transactional Architect runner (`ARCHITECT_RUNNER_ENTRY_GATE`). Partial governance writes are never authoritative; failed exits restore `.ai/**`.
- `POST_SIDE_EFFECT` — `IMPLEMENTING` or later (implementation/review/release boundary already crossed). Do **not** invoke the transactional runner and do **not** roll back the whole `.ai/**` tree automatically. Reconcile evidence, invalidate only dependent artifacts, and continue the original `top_level_command`.

Unknown or unprovable phase → `RESUME_PHASE_UNKNOWN` / `HUMAN_INPUT_REQUIRED`. Never guess.

Orphan Architect transactions (`ARCHITECT_TRANSACTION_V1` under the OpenCode config directory) are recovered only for pre-side-effect resumes when project content fingerprint still matches the frozen transaction.

## Resume integrity contract

Verify current Git target and every evidence dependency before selecting the next phase. Do not recreate historical safepoints, approvals, failure reproduction, reviewer independence or validation evidence after the fact. If a review target changed, discard affected review results and create a fresh cycle. If steering changed requirements or product scope, return to discovery/planning before execution.

Resume never installs tools, broadens permissions or performs external actions merely to recover progress. `NO_AUTOMATIC_EXTERNAL_ACTION` applies.

When the frozen target changed, `REVIEW_FREEZE` evidence is stale and a new review cycle is required.

## LEGACY_RUN_STATE_MIGRATION_V1

Before applying the continuation gate to a task created before Governance 3.4.4, inspect the existing `RUN_STATE.json`, `.ai/STATUS.md`, `.ai/PROJECT_HISTORY.md`, the latest controlling `GOVERNANCE_RESULT`, Final Reviewer verdicts and frozen packet/target evidence. Create only the missing `top_level_command`, `current_phase`, `next_required_phase` and `terminal_reason` fields.

Use only authoritative persisted evidence. Never infer completion from file presence, timestamps alone, conversation history or a model summary. Preserve every existing state field and append a migration record to `.ai/PROJECT_HISTORY.md` with the source evidence and Governance version. An original `/ai-workflow` remains `top_level_command: ai-workflow`; do not rewrite it as `ai-resume`. Map the highest proven checkpoint to `current_phase` and its required successor or validated repair route to `next_required_phase`. A proven blocker uses its exact reason and no next phase. If the original command or next required phase cannot be proven, set `current_phase: HUMAN_INPUT_REQUIRED`, `next_required_phase: null` and a precise `terminal_reason`; do not guess or restart the task.

Run the continuation helper only after this migration is complete. Migration changes governance state only and never recreates stale evidence, changes source/docs or authorizes external actions.

## WORKFLOW_CONTINUATION_GATE_V1

Resume preserves the original `top_level_command` recorded in `RUN_STATE.json`; an interrupted `/ai-workflow` remains `top_level_command: ai-workflow`. Require `current_phase`, `next_required_phase` and `terminal_reason` and never replace the original authority with `ai-resume`.

Before emitting a final response, execute the installed `workflow-continuation.py` with `--expected-command ai-resume`. Decision `CONTINUE_REQUIRED` resumes the original workflow at `next_required_phase` from authoritative persisted evidence. `TERMINAL_ALLOWED` is valid only for `LOCAL_COMMITTED` or an explicit blocker with a non-empty `terminal_reason`. `INVALID_RUN_STATE` blocks completion. Do not restart from zero, create a second task, or ask the owner to invoke an internal phase command when continuation is safe.

`NO_AUTOMATIC_EXTERNAL_ACTION` applies on resume: never push, merge, deploy, publish, production rollback or widen permissions merely to recover progress.
