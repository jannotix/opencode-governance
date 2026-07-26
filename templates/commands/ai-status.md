---
description: Show current governed baseline, task, context and resume status
agent: architect
subtask: false
---

Read governance state without changing source code or project documentation.

Report concisely:

- current governance/baseline state and validated repository reference;
- baseline audit cycle/latest reviewer/final verdicts and outstanding validated gaps/unknowns;
- `.ai/CONTEXT_INDEX.md` presence/freshness;
- documentation root/scope/synchronization/license/deployment exclusion state;
- current TASK ID/stage/plan/version and requirement-provenance consistency;
- `CONTEXT_MANIFEST.md` presence, selected surface and material expansion count;
- `MINIMUM_CHANGE_ASSESSMENT` presence/status;
- `RUN_STATE.json` presence, last safe transition, checkpoint repository reference, cycle, resumability and blocker;
- unprocessed `STEERING.md` entries and whether they require provenance update/replanning;
- evidence packet status: execution, implementation review, architecture review and final;
- Executor/reviewer/final status and outstanding validated findings;
- review-freeze state and whether current Git target still matches it;
- repository delta considered, Git status, last validated local commit and push authorization;
- missing mandatory external validation and release readiness;
- optional `.ai/TASK_QUEUE.json` summary when present: next eligible task, dependency blockers and queue state.

Never expose secret values.

Finish with:

```text
GOVERNANCE_RESULT
TASK_ID: <id or NONE>
STATE: <state>
NEXT_ACTION: <action or NONE>
CYCLE: <n/3 or N/A>
HUMAN_INPUT_REQUIRED: YES|NO
RESUMABLE: YES|NO
CHECKPOINT: <RUN_STATE path or NONE>
```
