---
description: Run the independent dual-review and final-adjudication pipeline
agent: architect
subtask: false
---

Review the governed task identified by:

$ARGUMENTS

Require exactly one `TASK_VALIDATED` task, `BASELINE_VALIDATED`, canonical requirement trail, approved plan with `MINIMUM_CHANGE_ASSESSMENT`, `CONTEXT_MANIFEST.md`, `VERIFICATION_PROFILE.md` including `OPERATIONAL_ASSURANCE`, fresh `evidence/VERIFICATION_EVIDENCE.md`, execution evidence and consistent `RUN_STATE.json`. Process material steering before freezing review; steering that changes requirements invalidates the current plan/review target and returns to planning.

Before review, validate evidence freshness against source/docs, public contracts, lockfiles/dependency manifests, generator inputs, migrations, environment/toolchain, validation configuration, preview source/artifact/environment, tool/MCP configuration/permissions, recovery inputs and safe-experiment isolation target. Required stale/failed/unavailable-without-sufficient-equivalent evidence prevents a clean review PASS.

Freeze source and task documentation. Build two fresh referential packets under `.ai/tasks/<TASK-ID>/evidence/`:

- `REVIEW_IMPLEMENTATION_PACKET.md` for changed implementation paths, relevant callers/callees, tests, requirement/plan references, verification/operational profile/evidence, user-flow/visual surfaces and documentation impact;
- `REVIEW_ARCHITECTURE_PACKET.md` for changed boundaries/modules, dependency edges, trust/security/data/deployment surfaces, public contracts, generator/migration surfaces, preview/recovery/tool/MCP/isolation boundaries, verification profile/evidence, applicable instruction sources and documentation impact.

Both packets reference the same canonical requirement trail and frozen repository target but may contain role-specific context. Neither packet may include the sibling current-cycle review. Do not include unrelated conversation history.

Invoke `reviewer` and `reviewer-architecture` independently. Each begins from its packet/context manifest and independently challenges `TASK_RISK_PROFILE`, Evidence-Driven gates, all applicable `OPERATIONAL_ASSURANCE` gates and evidence sufficiency/freshness. Request both before consuming either result and run concurrently when supported.

Operational Assurance includes `PREVIEW_ENVIRONMENT_GATE`, `USER_FLOW_VERIFICATION`, `VISUAL_BEHAVIOR_GATE`, `RELEASE_RECOVERY_PROOF`, `TOOL_CAPABILITY_PROFILE`/`MCP_CAPABILITY_ASSESSMENT` and `SAFE_EXPERIMENTATION`. Reviewers must verify that none of these gates broadened permissions, used production data/credentials merely for governance, fabricated tool/human authorization, or implied automatic production deploy/rollback/push/merge.

After both complete, create `FINAL_PACKET.md` referencing canonical provenance, approved plan, context manifest, verification/operational profile/evidence, frozen diff/target, execution/tests/docs evidence and both independent reviews. Then invoke `final-reviewer`.

Final Reviewer must first compare `APPROVED_REQUIREMENTS.md`/plan with `ORIGINAL_USER_REQUEST.md` plus controlling clarifications, then independently validate risk classification and required Evidence-Driven/Operational Assurance evidence. Material omission, weakening, contradiction, fabrication or unauthorized broadening/narrowing is `PLAN_DEFECT` even when implementation follows plan and both reviewers pass. Required insufficient/stale evidence cannot support `PASS`.

Only Final Reviewer controls `PASS`, `IMPLEMENTATION_DEFECT`, `PLAN_DEFECT` or `BLOCKED`. Update `RUN_STATE.json` at `DUAL_REVIEW`, `FINAL_ADJUDICATION` and final verdict boundaries. Stale reviews/evidence must never be reused after their dependent target changes.

`PASS` authorizes task-scoped local commit, never push. Any authoritative `CODEOWNERS_HUMAN_GATE` remains enforced at the merge/release/push boundary specified by repository policy and is never fabricated.

Finish with `GOVERNANCE_RESULT` including `EVIDENCE_STATUS`.
