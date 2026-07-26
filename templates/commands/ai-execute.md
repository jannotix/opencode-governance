---
description: Execute an explicit approved governance plan
agent: executor
subtask: true
---

Execute the approved task identified by:

$ARGUMENTS

Locate exactly one task. Do not implement unless baseline is `BASELINE_VALIDATED`, canonical requirement provenance exists, `CONTEXT_MANIFEST.md` exists, an approved plan with `MINIMUM_CHANGE_ASSESSMENT` exists, `RUN_STATE.json` is consistent, `evidence/EXECUTION_PACKET.md` exists, `DOCUMENTATION_IMPACT` is resolved and state is `READY_FOR_EXECUTION`.

Before editing, read only the canonical execution packet and referenced evidence required for implementation. Conversation history is not authoritative. Expand beyond `CONTEXT_MANIFEST.md` only when primary evidence exposes a wider dependency/regression/security/documentation surface; record every material expansion in the manifest.

Process any unhandled material `STEERING.md` before implementation. If it changes requirements or invalidates the plan, return `PLAN_CONFLICT` and require Architect provenance update/replanning.

Treat the plan as downstream from `APPROVED_REQUIREMENTS.md`. Return `PLAN_CONFLICT` for material inconsistency, impossible assumptions or missing decisions instead of inventing a workaround.

Implement only approved scope and respect `MINIMUM_CHANGE_ASSESSMENT`: reuse existing project code, standard/native capabilities and installed dependencies when adequate; avoid speculative abstractions, duplicate libraries and symptom-only patches. Minimalism never removes security, validation, data-loss protection, error handling, accessibility or approved behavior.

Synchronize required canonical documentation in the same task. Never fabricate license terms.

Checkpoint `RUN_STATE.json` at meaningful phase boundaries: entering `IMPLEMENTING`, entering `TASK_VERIFYING`, and reaching `TASK_VALIDATED` or a blocker. Record current repository reference/worktree state without secrets.

Run required tests/build/lint/static/schema/integration/documentation checks. Only when all acceptance criteria pass set `TASK_VALIDATED`. Do not edit source/task documentation during the review freeze and do not create final commit before Final Reviewer `PASS`.

Finish task-related output with `GOVERNANCE_RESULT`. Never push by default.
