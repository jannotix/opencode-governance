---
description: Run the complete governed multi-model development workflow
agent: architect
subtask: false
---

Run the complete governed development lifecycle for:

$ARGUMENTS

Do not edit source code or project documentation yourself.

Lifecycle:

`INTAKE -> BASELINE_DRAFT -> BASELINE_DUAL_AUDIT -> BASELINE_ADJUDICATION -> BASELINE_VALIDATED -> REQUIREMENT_CAPTURE -> CLARIFICATION -> APPROVED_REQUIREMENTS -> CONTEXT_ROUTING -> PLANNING -> MINIMUM_CHANGE_GATE -> TASK_PLANNED -> READY_FOR_EXECUTION -> IMPLEMENTING -> DOCUMENTATION_SYNC -> TASK_VERIFYING -> TASK_VALIDATED -> DUAL_REVIEW -> FINAL_ADJUDICATION -> LOCAL_COMMITTED`

Rules:

1. initialize `.ai/CODEBASE_BASELINE.md`, `.ai/CONTEXT_INDEX.md`, `.ai/DEPLOYMENT_SCOPE.md`, `.ai/DOCUMENTATION_SCOPE.md`, `.ai/PROJECT_HISTORY.md`, `.ai/STATUS.md`, tasks and baseline-audits when required;
2. baseline draft is independently audited by both reviewers and adjudicated by Final Reviewer; no implementation before `BASELINE_VALIDATED`; maximum three failed baseline adjudications;
3. capture `ORIGINAL_USER_REQUEST.md`, append-only `CLARIFICATION_TRANSCRIPT.md` and provenance-backed `APPROVED_REQUIREMENTS.md`; use `question` for unresolved material decisions and never silently choose between conflicting instructions;
4. for each task create `CONTEXT_MANIFEST.md`, `RUN_STATE.json`, optional `STEERING.md` and `evidence/`; reuse validated baseline/context index plus Git delta and expand context only on evidence of wider impact;
5. material steering must enter requirement provenance before action and force replanning when it invalidates the current plan;
6. plan must include `DOCUMENTATION_IMPACT`, traceable acceptance criteria and `MINIMUM_CHANGE_ASSESSMENT`; prefer the smallest correct, secure, maintainable root-cause change, reuse existing/native/stdlib/installed capabilities, and never simplify away security/validation/data-loss protection/accessibility/approved requirements;
7. create fresh referential `EXECUTION_PACKET.md`; Executor reads canonical evidence, implements only approved scope, records evidence-triggered context expansions, synchronizes required docs and checkpoints `RUN_STATE.json` at phase boundaries;
8. after `TASK_VALIDATED`, freeze source/task docs and create independent role-specific review packets; reviewer packets must never contain sibling current-cycle review output;
9. after both reviews complete, create `FINAL_PACKET.md` and invoke Final Reviewer with canonical provenance, frozen target, evidence/tests/docs and both independent reviews;
10. Final Reviewer independently challenges Architect interpretation; a perfectly implemented materially wrong plan is `PLAN_DEFECT`;
11. only validated Final Reviewer corrections return to Executor/Architect; maximum three failed task final-adjudication cycles;
12. after `PASS`, Executor creates one scoped local commit after secret/Git-state checks; never push without explicit authorization;
13. append material transitions to history and keep `RUN_STATE.json`/`.ai/STATUS.md` synchronized;
14. when `.ai/TASK_QUEUE.json` exists, an orchestrated milestone may select the highest-priority eligible task whose dependencies are complete, but each task still passes every normal gate and no unbounded loop is allowed.

Reviewer independence is mandatory. Conversation history is never authoritative evidence. Required project documentation is part of task correctness. Governance never chooses a software license.

Finish task-related output with:

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
