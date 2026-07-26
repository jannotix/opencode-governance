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
2. require `.ai/tasks/<TASK-ID>/RUN_STATE.json`, the canonical requirement trail, approved plan when planning has completed, and `.ai/CONTEXT_MANIFEST.md`/task context artifacts required by the recorded phase;
3. read current `.ai/STATUS.md`, validated baseline/reference, `.ai/CONTEXT_INDEX.md`, task `CONTEXT_MANIFEST.md`, `STEERING.md` when present, and the checkpoint;
4. inspect current Git HEAD/status/diff and compare them with the checkpointed repository reference and recorded review-freeze state;
5. process any unprocessed material steering through `CLARIFICATION_TRANSCRIPT.md` and `APPROVED_REQUIREMENTS.md` before resuming; if steering invalidates the plan, return to `PLANNING` and create a revised plan rather than continuing execution;
6. if the baseline is missing/materially stale, return `BASELINE_AUDIT_REQUIRED` or set `BASELINE_REVALIDATION_REQUIRED` as appropriate;
7. if source/documentation changed after `TASK_VALIDATED` or during a recorded review freeze, invalidate stale current-cycle reviews and resume from validation/review as required;
8. if Git state contains unrelated or ambiguous changes that cannot be reconciled safely with the checkpoint, return `BLOCKED` instead of guessing;
9. resume from the last safe persisted phase; do not repeat completed phases whose evidence still matches, and never fabricate missing review/provenance history;
10. preserve the three-cycle baseline/task adjudication limits;
11. update `RUN_STATE.json`, `.ai/STATUS.md` and `.ai/PROJECT_HISTORY.md` at the next phase boundary without secret values.

Valid examples of resume routing:

- `READY_FOR_EXECUTION` -> Executor with a fresh `EXECUTION_PACKET.md`;
- interrupted `IMPLEMENTING` -> reconcile worktree, then continue Executor only when the plan/checkpoint still match;
- `TASK_VALIDATED` -> fresh independent dual review;
- one/both reviews complete with unchanged frozen target -> complete missing review(s), then final adjudication;
- `FINAL_ADJUDICATION` interrupted -> rebuild `FINAL_PACKET.md` from canonical evidence and completed independent reviews;
- `PASS` without local commit -> Executor finalization only;
- `LOCAL_COMMITTED` -> nothing to resume;
- `BLOCKED`/`BASELINE_BLOCKED` -> remain blocked until the recorded blocker is authoritatively resolved.

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
