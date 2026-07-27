---
description: Show current governed baseline, task, context, evidence and resume status
agent: architect
subtask: false
---

Read governance state without changing source code or project documentation.

Report concisely:

- current governance/baseline state and validated repository reference;
- baseline audit cycle/latest reviewer/final verdicts and outstanding validated gaps/unknowns;
- `.ai/CONTEXT_INDEX.md` and `.ai/INSTRUCTION_INDEX.md` presence/freshness plus unresolved instruction conflicts;
- documentation root/scope/synchronization/license/deployment exclusion state;
- current TASK ID/stage/plan/version and requirement-provenance consistency;
- `CONTEXT_MANIFEST.md` presence, selected surface, applicable instruction sources and material expansion count;
- `MINIMUM_CHANGE_ASSESSMENT` presence/status;
- `VERIFICATION_PROFILE.md` presence/version, `TASK_RISK_PROFILE`, authoritative `VALIDATION_PROFILE` and gate plan;
- `evidence/VERIFICATION_EVIDENCE.md` status/freshness and exact required gates that are `PASS`, `FAIL`, `UNAVAILABLE`, `STALE` or `BLOCKED`;
- `BUGFIX_PROOF`, `TEST_IMPACT_MAP`, `CONTRACT_COMPATIBILITY`, `ENVIRONMENT_FINGERPRINT`, `DEPENDENCY_DELTA`, `GENERATED_ARTIFACT_GATE`, `MIGRATION_PROOF`, `NON_FUNCTIONAL_BUDGETS`, `FLAKINESS_EVIDENCE`, `ADVERSARIAL_INPUT_VALIDATION`, `CODEOWNERS_HUMAN_GATE` applicability/result;
- whether a test rerun masked an earlier unresolved failure;
- whether source/docs/contracts/lockfiles/generator inputs/migrations/environment/toolchain/validation configuration changed after evidence capture and which evidence became stale;
- `RUN_STATE.json` presence, last safe transition, checkpoint repository reference, cycle, resumability and blocker;
- unprocessed `STEERING.md` entries and whether they require provenance update/replanning;
- evidence packet status: execution, implementation review, architecture review and final;
- Executor/reviewer/final status and outstanding validated findings;
- review-freeze state and whether current Git/evidence target still matches it;
- repository delta considered, Git status, last validated local commit and push authorization;
- missing mandatory external validation and release readiness;
- repository-required human-owner gate state without fabricating approval;
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
EVIDENCE_STATUS: COMPLETE|PARTIAL|BLOCKED|N/A
```
