---
description: Run the independent dual-review and final-adjudication pipeline
agent: architect
subtask: false
---

Review the governed task identified by:

$ARGUMENTS

Require exactly one `TASK_VALIDATED` task, `BASELINE_VALIDATED`, canonical requirement trail, approved plan with `MINIMUM_CHANGE_ASSESSMENT`, `CONTEXT_MANIFEST.md`, execution evidence and consistent `RUN_STATE.json`. Process material steering before freezing review; steering that changes requirements invalidates the current plan/review target and returns to planning.

Freeze source and task documentation. Build two fresh referential packets under `.ai/tasks/<TASK-ID>/evidence/`:

- `REVIEW_IMPLEMENTATION_PACKET.md` for changed implementation paths, relevant callers/callees, tests, requirement/plan references and documentation impact;
- `REVIEW_ARCHITECTURE_PACKET.md` for changed boundaries/modules, dependency edges, trust/security/data/deployment surfaces, requirement/plan references and documentation impact.

Both packets reference the same canonical requirement trail and frozen repository target but may contain role-specific context. Neither packet may include the sibling current-cycle review. Do not include unrelated conversation history.

Invoke `reviewer` and `reviewer-architecture` independently. Each begins from its packet/context manifest and expands only on primary evidence, recording material expansion. Request both before consuming either result and run concurrently when supported.

After both complete, create `FINAL_PACKET.md` referencing canonical provenance, approved plan, context manifest, frozen diff/target, execution/tests/docs evidence and both independent reviews. Then invoke `final-reviewer`.

Final Reviewer must first compare `APPROVED_REQUIREMENTS.md`/plan with `ORIGINAL_USER_REQUEST.md` plus controlling clarifications. Material omission, weakening, contradiction, fabrication or unauthorized broadening/narrowing is `PLAN_DEFECT` even when implementation follows plan and both reviewers pass.

Only Final Reviewer controls `PASS`, `IMPLEMENTATION_DEFECT`, `PLAN_DEFECT` or `BLOCKED`. Update `RUN_STATE.json` at `DUAL_REVIEW`, `FINAL_ADJUDICATION` and final verdict boundaries. Stale reviews must never be reused after the frozen target changes.

`PASS` authorizes task-scoped local commit, never push.

Finish with `GOVERNANCE_RESULT`.
