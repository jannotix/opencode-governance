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

Executor implements only approved capability/milestone scope, returns verification evidence, synchronizes approved docs and reports `MILESTONE_VALIDATED` plus `PRODUCT_INCOMPLETE` and remaining required capabilities when partial. Preserve `DEPENDENCY_ADMISSION_GATE`, `PRE_CHANGE_SAFEPOINT`, `OPERATIONAL_ASSURANCE`; no automatic push/deploy.

## Execution handoff contract

Create a fresh referential `EXECUTION_PACKET.md` with exact baseline/repository/product/plan versions, requirements, selected context, capability IDs, validation and permitted evidence-triggered expansion. Freeze its exact bytes and SHA-256 before the first Executor attempt. Executor returns `PLAN_CONFLICT` rather than improvising when evidence contradicts plan or product state.

## Optional isolated Executor failover

Read the installed `ROLE_FAILOVER_POLICY`. When Executor failover is disabled or no routing manifest exists, preserve the legacy direct Executor handoff.

When Executor failover is enabled, perform this bounded deterministic lifecycle:

1. Record the real project root, frozen `HEAD`, canonical packet SHA-256, `WORK_CLASS`, task ID and an empty attempted-route set.
2. Invoke the installed Executor helper operation `select` for the current `WORK_CLASS`.
3. Invoke `prepare` with a fresh attempt ID, selected route, frozen target and packet SHA-256. Do not create or reuse an attempt worktree manually.
4. Launch a **dedicated** Executor OpenCode process via `governed-role-attempt.py --role executor` (or `governed-role-attempt` wrapper) with the V2 launch receipt, exact `EXECUTION_ROOT`, packet hash, candidate and route receipt. Do **not** delegate Executor as an in-process subagent under Architect authority (4.0.2 `GOVERNED_ROLE_PROCESS_CONTRACT_V1`). Include `EXECUTION_MODE: ISOLATED_FAILOVER`, `EXECUTION_ROOT`, `EXECUTOR_ATTEMPT_ID`, selected route/model/variant/family, `WORK_CLASS`, `PACKET_SHA256`, `FROZEN_TARGET_SHA`. Require all writes and mutating commands to stay inside `EXECUTION_ROOT`.
5. Accept only a complete `EXECUTOR_ATTEMPT_REPORT` whose attempt, packet and frozen-target identifiers match. Persist that exact accepted report as JSON under the real task evidence tree.
6. Invoke `finalize` against the accepted report, then invoke `promote`. Promotion copies only the verified binary patch; it is not validation or approval.
7. After promotion, persist returned evidence in real `.ai/**`, rerun required fresh validation against the real worktree, then continue ordinary dual review and Final Reviewer adjudication.

On an eligible classified route failure only, invoke `discard` with that failure class, add the route to the attempted set, select the next eligible route and restart the complete Executor from the same packet and frozen target. Never continue partial output, reuse a failed worktree, retry the same route, or let recovered primary preempt an active fallback.

A `PLAN_CONFLICT`, invalid packet, permission or safety refusal, malformed/incomplete report, context overflow, validation defect, unclassified error, changed real state, patch mismatch, overlap or promotion failure is ineligible for model fallback. Discard temporary state without cooldown when safe, return `EXECUTOR_FAILOVER_BLOCKED` or the controlling governance blocker, and require human recovery. The number of attempts is bounded by configured eligible routes; no autonomous loop is allowed.

Required evidence is recorded in `VERIFICATION_EVIDENCE.md` with exact commands, targets, results and freshness after accepted promotion. Changes to dependent source/docs/contracts/lockfiles/generators/migrations/environment/validation/preview/tools/recovery/isolation stale affected proof. Freeze only after every acceptance criterion, required capability and applicable gate is satisfied. `NO_AUTOMATIC_EXTERNAL_ACTION` applies.
