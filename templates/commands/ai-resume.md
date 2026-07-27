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
2. require canonical requirement provenance and inspect `.ai/STATUS.md`, validated baseline/reference, `.ai/CONTEXT_INDEX.md`, `.ai/INSTRUCTION_INDEX.md`, task `STEERING.md` when present and current Git state;
3. read `RUN_STATE.json` when present and validate canonical fields: `schema_version`, `task_id`, `state`, `baseline_state`, `baseline_reference`, `plan_id`, `plan_version`, `repository_head`, `review_cycle`, `documentation_impact`, `review_frozen`, execution/reviewer/final completion flags, `last_safe_transition`, `resumable`, `human_input_required`, `blocker`, `updated_at`;
4. require `VERIFICATION_PROFILE.md` for a v1.8+ in-progress task and inspect `evidence/VERIFICATION_EVIDENCE.md` when execution/validation has begun; for v2.0 tasks also reconcile `OPERATIONAL_ASSURANCE`;
5. for a pre-v1.8 in-progress task missing `RUN_STATE.json`, `CONTEXT_MANIFEST.md`, `VERIFICATION_PROFILE.md` or evidence packets, reconstruct only what authoritative existing `.ai/**` evidence plus current Git state prove; never fabricate historical phase/review/evidence completion; when safe reconstruction is impossible return `BLOCKED` or require authoritative clarification/revalidation;
6. for an in-progress v1.8 task resumed under v2.0, add Operational Assurance planning/evidence only from current authoritative evidence when the remaining work actually depends on it; never fabricate historical preview/user-flow/visual/recovery/tool/experiment execution;
7. completed historical tasks do not need synthetic v1.8/v2.0 artifacts;
8. compare current Git HEAD/status/diff and changed paths with the checkpoint and relevant evidence packet; `repository_head` alone is insufficient for a dirty worktree;
9. process unhandled material steering through `CLARIFICATION_TRANSCRIPT.md` and `APPROVED_REQUIREMENTS.md`; if steering invalidates the plan, return to `PLANNING` rather than continuing execution;
10. if baseline/context/instruction index is missing/materially stale, return `BASELINE_AUDIT_REQUIRED` or set `BASELINE_REVALIDATION_REQUIRED`;
11. validate applicable scoped instructions from `.ai/INSTRUCTION_INDEX.md`; new/changed instruction files affecting task paths require plan/evidence re-evaluation;
12. reconcile `ENVIRONMENT_FINGERPRINT` and Evidence-Driven dependencies: source/docs, public contracts, dependency manifests/lockfiles, generator inputs, migrations, runtime/compiler/package-manager/test-tool versions, container/dev-environment digest and validation configuration;
13. reconcile Operational Assurance dependencies: preview source/artifact/environment and required services; user-flow/visual runtime target; tool/MCP configuration, capabilities and permissions; recovery stable/artifact/config/schema/data inputs; safe-experiment isolation target and canonical-workspace cleanliness;
14. when any dependency changed materially, mark only dependent `VERIFICATION_EVIDENCE.md` sections `STALE`, invalidate downstream reviews/final adjudication that relied on them, and rerun the minimal sufficient validation before PASS; do not restart unrelated completed phases;
15. a changed environment/toolchain can stale runtime/build/test/preview/user-flow/visual evidence even when source is unchanged;
16. a changed tool/MCP capability or permission can stale `TOOL_CAPABILITY_PROFILE`/`MCP_CAPABILITY_ASSESSMENT`; never assume previous authorization remains valid;
17. preserve prior `FLAKINESS_EVIDENCE`: never discard an earlier FAIL because a resumed rerun passes;
18. do not automatically recreate preview infrastructure, restart privileged external tools, execute rollback, or rebuild an external worktree/temp clone merely to resume; use current permitted project mechanisms or return `UNAVAILABLE`/`BLOCKED`;
19. if source/documentation changed after `TASK_VALIDATED` or during review freeze, invalidate stale current-cycle reviews and resume from validation/review as required;
20. if unrelated/ambiguous Git changes cannot be reconciled with the checkpoint, return `BLOCKED` instead of guessing;
21. resume from the last safe persisted phase; do not repeat completed phases whose evidence still matches;
22. preserve three-cycle baseline/task adjudication limits;
23. update `RUN_STATE.json`, `.ai/STATUS.md` and `.ai/PROJECT_HISTORY.md` at the next phase boundary without secrets.

Resume routing examples:

- `READY_FOR_EXECUTION` -> fresh `EXECUTION_PACKET.md`/Executor with verification/operational profile;
- interrupted `IMPLEMENTING` -> reconcile worktree/evidence dependencies and continue only when plan/checkpoint still match;
- interrupted `EVIDENCE_VALIDATION`/`OPERATIONAL_VALIDATION`/`TASK_VERIFYING` -> rerun only required missing/stale gates, preserving historical failures;
- `TASK_VALIDATED` -> confirm Evidence-Driven and Operational Assurance freshness, then fresh independent dual review;
- one/both reviews complete with unchanged frozen target/evidence -> complete missing review(s), then final adjudication;
- interrupted `FINAL_ADJUDICATION` -> rebuild `FINAL_PACKET.md` from canonical fresh evidence and completed independent reviews;
- `PASS` without local commit -> Executor finalization only, while authoritative human merge/release gates remain recorded;
- `LOCAL_COMMITTED` -> nothing to resume;
- `BLOCKED`/`BASELINE_BLOCKED` -> remain blocked until recorded blocker is authoritatively resolved.

Operational Assurance never grants new permissions during resume. Never expose secret values. Never push by default.

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
