---
description: Safely resume an interrupted governed task from persisted evidence
agent: architect
subtask: false
---

Resume the governed task identified by:

$ARGUMENTS

Do not infer progress from chat history. Reconstruct state only from repository evidence, `.ai/**` artifacts and Git.

Required flow:

1. locate exactly one matching task under `.ai/tasks/`;
2. require canonical requirement provenance and inspect `.ai/STATUS.md`, validated baseline/reference, `.ai/CONTEXT_INDEX.md`, `.ai/INSTRUCTION_INDEX.md`, `.ai/GOVERNANCE_MEMORY.md`, task `STEERING.md` when present and current Git state;
3. read `RUN_STATE.json` when present and validate canonical fields: `schema_version`, `task_id`, `state`, `baseline_state`, `baseline_reference`, `plan_id`, `plan_version`, `repository_head`, `review_cycle`, `documentation_impact`, `review_frozen`, execution/reviewer/final completion flags, `last_safe_transition`, `resumable`, `human_input_required`, `blocker`, `updated_at`;
4. require `VERIFICATION_PROFILE.md` for a v1.8+ in-progress task and inspect `evidence/VERIFICATION_EVIDENCE.md` when execution/validation has begun; for v2.0 tasks also reconcile `OPERATIONAL_ASSURANCE`, `DEPENDENCY_ADMISSION_GATE`, `PRE_CHANGE_SAFEPOINT`, governed skill/memory routing and closed-loop evidence when applicable;
5. for a pre-v1.8 in-progress task missing `RUN_STATE.json`, `CONTEXT_MANIFEST.md`, `VERIFICATION_PROFILE.md` or evidence packets, reconstruct only what authoritative existing `.ai/**` evidence plus current Git state prove; never fabricate historical phase/review/evidence completion; when safe reconstruction is impossible return `BLOCKED` or require authoritative clarification/revalidation;
6. for an in-progress v1.8/v1.x task resumed under v2.0, add current governed discovery/skill/memory/Operational Assurance planning only from authoritative current evidence when remaining work depends on it. Never fabricate historical discovery, skill use, dependency admission, safepoint, preview/user-flow/visual/recovery/tool/experiment execution or memory decisions;
7. completed historical tasks do not need synthetic v1.8/v2.0 artifacts or memory entries;
8. compare current Git HEAD/status/diff and changed paths with the checkpoint and relevant evidence packet; `repository_head` alone is insufficient for a dirty worktree;
9. process unhandled material steering through `CLARIFICATION_TRANSCRIPT.md` and `APPROVED_REQUIREMENTS.md`; if steering invalidates the plan, return to `PLANNING` rather than continuing execution;
10. if baseline/context/instruction index/governance memory is missing/materially stale, return `BASELINE_AUDIT_REQUIRED` or set `BASELINE_REVALIDATION_REQUIRED` as appropriate; a newly true `stale_when` marks only affected memory entries stale, not necessarily the full baseline;
11. validate applicable scoped instructions and selected skills from `.ai/INSTRUCTION_INDEX.md`; changed/overridden skill source/ID/scope/trust/freshness affecting the task requires plan/evidence re-evaluation. Do not reload all skills merely to resume;
12. validate selected active governance-memory entries against current scope/evidence/`stale_when`; stale/revoked entries must be removed from task routing and cannot justify continuing a prior assumption;
13. reconcile `ENVIRONMENT_FINGERPRINT` and Evidence-Driven dependencies: source/docs, public contracts, dependency manifests/lockfiles, generator inputs, migrations, runtime/compiler/package-manager/test-tool versions, container/dev-environment digest and validation configuration;
14. reconcile `DEPENDENCY_ADMISSION_GATE`: if a new dependency was already installed, require evidence that the exact package/source/version was admitted before installation. Never retroactively mark an unproven package `ADMIT`; if historical admission cannot be established, stop before further dependency-dependent work and require re-evaluation/human decision as appropriate;
15. reconcile `PRE_CHANGE_SAFEPOINT`: if the risky mutation has not occurred, require the safepoint before it. If it already occurred and no authoritative pre-change evidence exists, never fabricate a historical safepoint; classify the recovery evidence honestly and return to the earliest safe recoverable phase or `BLOCKED` when required;
16. reconcile Operational Assurance dependencies: preview source/artifact/environment and required services; user-flow/visual runtime target; tool/MCP configuration, capabilities and permissions; recovery stable/artifact/config/schema/data inputs; safe-experiment isolation target and canonical-workspace cleanliness;
17. when any dependency changed materially, mark only dependent `VERIFICATION_EVIDENCE.md` sections `STALE`, invalidate downstream reviews/final adjudication that relied on them, and rerun the minimal sufficient validation before PASS; do not restart unrelated completed phases;
18. a changed environment/toolchain can stale runtime/build/test/preview/user-flow/visual evidence even when source is unchanged;
19. a changed tool/MCP capability or permission can stale `TOOL_CAPABILITY_PROFILE`/`MCP_CAPABILITY_ASSESSMENT`; never assume previous authorization remains valid;
20. preserve prior `FLAKINESS_EVIDENCE`: never discard an earlier FAIL because a resumed rerun passes;
21. reconcile `CLOSED_LOOP_LEARNING`/Governance Memory: a prior candidate without Final Reviewer `MEMORY_DECISION: APPROVE` is not memory. An approved-but-not-persisted candidate may be written only by Architect from the exact final evidence. Never recreate memory from chat summaries;
22. do not automatically recreate preview infrastructure, restart privileged external tools, execute rollback, install packages, or rebuild an external worktree/temp clone merely to resume; use current permitted project mechanisms or return `UNAVAILABLE`/`BLOCKED`;
23. if source/documentation changed after `TASK_VALIDATED` or during review freeze, invalidate stale current-cycle reviews and resume from validation/review as required;
24. if unrelated/ambiguous Git changes cannot be reconciled with the checkpoint, return `BLOCKED` instead of guessing;
25. resume from the last safe persisted phase; do not repeat completed phases whose evidence still matches;
26. preserve three-cycle baseline/task adjudication limits;
27. update `RUN_STATE.json`, `.ai/STATUS.md`, `.ai/GOVERNANCE_MEMORY.md` only when an already-approved memory transition is due, and `.ai/PROJECT_HISTORY.md` at the next phase boundary without secrets.

Resume routing examples:

- `READY_FOR_EXECUTION` -> refresh selected skill/memory refs and `EXECUTION_PACKET.md`; if required safepoint is pending, route there before Executor mutation;
- interrupted `PRE_CHANGE_SAFEPOINT` -> complete/validate safepoint before any high-risk mutation;
- interrupted `IMPLEMENTING` -> reconcile worktree, dependency admission, safepoint and evidence dependencies and continue only when plan/checkpoint still match;
- interrupted `EVIDENCE_VALIDATION`/`OPERATIONAL_VALIDATION`/`TASK_VERIFYING` -> rerun only required missing/stale gates, preserving historical failures;
- `TASK_VALIDATED` -> confirm Evidence-Driven and Operational Assurance freshness, then fresh independent dual review;
- one/both reviews complete with unchanged frozen target/evidence -> complete missing review(s), then final adjudication;
- interrupted `FINAL_ADJUDICATION` -> rebuild `FINAL_PACKET.md` from canonical fresh evidence and completed independent reviews;
- `PASS` with `MEMORY_DECISION: APPROVE` but memory not persisted -> Architect persists only the exact validated memory entry, then Executor finalization;
- `PASS` without local commit -> Executor finalization only, while authoritative human merge/release gates remain recorded;
- `LOCAL_COMMITTED` -> nothing to resume;
- `BLOCKED`/`BASELINE_BLOCKED` -> remain blocked until recorded blocker is authoritatively resolved.

Governed discovery, skills, memory and Operational Assurance never grant new permissions during resume. Never expose secret values. Never push by default.

Finish with:

```text
GOVERNANCE_RESULT
TASK_ID: <TASK-ID>
STATE: <current state>
NEXT_ACTION: <next governed action or NONE>
CYCLE: <n/3 or N/A>
HUMAN_INPUT_REQUIRED: YES|NO
RESUMABLE: YES|NO
CHECKPOINT: .ai/tasks/<TASK-ID>/RUN_STATE.json
EVIDENCE_STATUS: COMPLETE|PARTIAL|BLOCKED|N/A
```