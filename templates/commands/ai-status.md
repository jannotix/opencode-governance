---
description: Show current governed baseline, task, context, evidence, operational assurance and resume status
agent: architect
subtask: false
---

Read governance state without changing source code or project documentation.

Report concisely:

- current governance/baseline state and validated repository reference;
- baseline audit cycle/latest reviewer/final verdicts and outstanding validated gaps/unknowns;
- `.ai/CONTEXT_INDEX.md`, `.ai/INSTRUCTION_INDEX.md` and `.ai/GOVERNANCE_MEMORY.md` presence/freshness, unresolved instruction/skill conflicts, active/stale/revoked memory counts and any memory entry whose `stale_when` condition is now true;
- documentation root/scope/synchronization/license/deployment exclusion state;
- current TASK ID/stage/plan/version and requirement-provenance consistency;
- `READ_ONLY_DISCOVERY_SWARM` applicability/use: number of Explore/Scout subtasks, target surfaces and whether material summaries were verified against primary evidence; never run discovery merely for status;
- `GOVERNED_SKILL_ROUTING`: selected skill IDs/sources, scope/trust/freshness and any blocked/untrusted skill requiring approval, without loading skill bodies merely for status;
- `CONTEXT_MANIFEST.md` presence, selected surface, applicable instruction/skill sources, active governance-memory references and material expansion count;
- `MINIMUM_CHANGE_ASSESSMENT` presence/status;
- `VERIFICATION_PROFILE.md` presence/version, `TASK_RISK_PROFILE`, authoritative `VALIDATION_PROFILE`, Evidence-Driven gate plan and `OPERATIONAL_ASSURANCE` plan;
- `evidence/VERIFICATION_EVIDENCE.md` status/freshness and exact required gates that are `PASS`, `FAIL`, `UNAVAILABLE`, `STALE` or `BLOCKED`;
- `BUGFIX_PROOF`, `TEST_IMPACT_MAP`, `CONTRACT_COMPATIBILITY`, `ENVIRONMENT_FINGERPRINT`, `DEPENDENCY_ADMISSION_GATE`, `DEPENDENCY_DELTA`, `GENERATED_ARTIFACT_GATE`, `PRE_CHANGE_SAFEPOINT`, `MIGRATION_PROOF`, `NON_FUNCTIONAL_BUDGETS`, `FLAKINESS_EVIDENCE`, `ADVERSARIAL_INPUT_VALIDATION`, `CODEOWNERS_HUMAN_GATE`, `CLOSED_LOOP_LEARNING` applicability/result;
- for `DEPENDENCY_ADMISSION_GATE`, exact admitted/rejected/human-decision package identity/source/version and whether installation occurred only after `ADMIT`, without querying external registries merely for status;
- for `PRE_CHANGE_SAFEPOINT`, whether required pre-change Git/worktree/schema/config/artifact/backup/recovery evidence existed before mutation;
- for `CLOSED_LOOP_LEARNING`, candidate state and latest Final Reviewer `MEMORY_DECISION: NONE|APPROVE|REJECT`, plus whether an approved memory update has been persisted;
- `PREVIEW_ENVIRONMENT_GATE` environment type/source-artifact/isolation/result without exposing secret URLs/credentials;
- `USER_FLOW_VERIFICATION` required flow IDs/results and missing runtime coverage;
- `VISUAL_BEHAVIOR_GATE` affected surfaces/viewports/states/result when applicable;
- `RELEASE_RECOVERY_PROOF` stable reference, rollback-or-forward-recovery classification and result without executing recovery;
- `TOOL_CAPABILITY_PROFILE` and `MCP_CAPABILITY_ASSESSMENT` summary: relevant capability classes, external side effects, privileged/destructive authorization state, never secret values;
- `SAFE_EXPERIMENTATION` isolation method/result and whether canonical workspace/production boundaries remained protected;
- whether a test rerun masked an earlier unresolved failure;
- whether source/docs/contracts/dependency admission/lockfiles/safepoint inputs/generator inputs/migrations/environment/toolchain/validation configuration/selected skill/preview target/tool-MCP configuration/recovery input/isolation target changed after evidence capture and which evidence became stale;
- `RUN_STATE.json` presence, last safe transition, checkpoint repository reference, cycle, resumability and blocker;
- unprocessed `STEERING.md` entries and whether they require provenance update/replanning;
- evidence packet status: execution, implementation review, architecture review and final;
- Executor/reviewer/final status and outstanding validated findings;
- review-freeze state and whether current Git/evidence/operational target still matches it;
- repository delta considered, Git status, last validated local commit and push authorization;
- missing mandatory external/runtime validation and release readiness;
- repository-required human-owner gate state without fabricating approval;
- optional `.ai/TASK_QUEUE.json` summary when present: next eligible task, dependency blockers and queue state.

Never expose secret values. Operational Assurance never broadens configured permissions and status reporting never calls external tools merely to obtain a prettier report.

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