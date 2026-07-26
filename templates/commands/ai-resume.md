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
2. require canonical requirement provenance and inspect `.ai/STATUS.md`, validated baseline/reference, `.ai/CONTEXT_INDEX.md`, task `STEERING.md` when present and current Git state;
3. read `RUN_STATE.json` when present and validate canonical fields: `schema_version`, `task_id`, `state`, `baseline_state`, `baseline_reference`, `plan_id`, `plan_version`, `repository_head`, `review_cycle`, `documentation_impact`, `review_frozen`, execution/reviewer/final completion flags, `last_safe_transition`, `resumable`, `human_input_required`, `blocker`, `updated_at`;
4. for a pre-v1.6 in-progress task missing `RUN_STATE.json`, `CONTEXT_MANIFEST.md` or evidence packets, reconstruct only what authoritative existing `.ai/**` evidence plus current Git state prove; never fabricate historical phase/review completion; when safe reconstruction is impossible return `BLOCKED` or require authoritative clarification/revalidation;
5. completed historical tasks do not need synthetic v1.6 artifacts;
6. compare current Git HEAD/status/diff and changed paths with the checkpoint and relevant evidence packet; `repository_head` alone is insufficient for a dirty worktree;
7. process unhandled material steering through `CLARIFICATION_TRANSCRIPT.md` and `APPROVED_REQUIREMENTS.md`; if steering invalidates the plan, return to `PLANNING` rather than continuing execution;
8. if baseline/context index is missing/materially stale, return `BASELINE_AUDIT_REQUIRED` or set `BASELINE_REVALIDATION_REQUIRED`;
9. if source/documentation changed after `TASK_VALIDATED` or during review freeze, invalidate stale current-cycle reviews and resume from validation/review as required;
10. if unrelated/ambiguous Git changes cannot be reconciled with the checkpoint, return `BLOCKED` instead of guessing;
11. resume from the last safe persisted phase; do not repeat completed phases whose evidence still matches;
12. preserve three-cycle baseline/task adjudication limits;
13. update `RUN_STATE.json`, `.ai/STATUS.md` and `.ai/PROJECT_HISTORY.md` at the next phase boundary without secrets.

Resume routing examples:

- `READY_FOR_EXECUTION` -> fresh `EXECUTION_PACKET.md`/Executor;
- interrupted `IMPLEMENTING` -> reconcile worktree and continue only when plan/checkpoint still match;
- `TASK_VALIDATED` -> fresh independent dual review;
- one/both reviews complete with unchanged frozen target -> complete missing review(s), then final adjudication;
- interrupted `FINAL_ADJUDICATION` -> rebuild `FINAL_PACKET.md` from canonical evidence and completed independent reviews;
- `PASS` without local commit -> Executor finalization only;
- `LOCAL_COMMITTED` -> nothing to resume;
- `BLOCKED`/`BASELINE_BLOCKED` -> remain blocked until recorded blocker is authoritatively resolved.

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
```

Never expose secret values. Never push by default.
