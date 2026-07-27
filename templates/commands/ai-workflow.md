---
description: Run the complete governed multi-model development workflow
agent: architect
subtask: false
---

Run the complete governed development lifecycle for:

$ARGUMENTS

Do not edit source code or project documentation yourself.

Lifecycle:

`INTAKE -> BASELINE_DRAFT -> BASELINE_DUAL_AUDIT -> BASELINE_ADJUDICATION -> BASELINE_VALIDATED -> REQUIREMENT_CAPTURE -> CLARIFICATION -> APPROVED_REQUIREMENTS -> CONTEXT_ROUTING -> PLANNING -> MINIMUM_CHANGE_GATE -> EVIDENCE_PLANNING -> TASK_PLANNED -> READY_FOR_EXECUTION -> IMPLEMENTING -> DOCUMENTATION_SYNC -> EVIDENCE_VALIDATION -> TASK_VERIFYING -> TASK_VALIDATED -> DUAL_REVIEW -> FINAL_ADJUDICATION -> LOCAL_COMMITTED`

Rules:

1. initialize `.ai/CODEBASE_BASELINE.md`, `.ai/CONTEXT_INDEX.md`, `.ai/INSTRUCTION_INDEX.md`, `.ai/DEPLOYMENT_SCOPE.md`, `.ai/DOCUMENTATION_SCOPE.md`, `.ai/PROJECT_HISTORY.md`, `.ai/STATUS.md`, tasks and baseline-audits when required;
2. baseline draft is independently audited by both reviewers and adjudicated by Final Reviewer; no implementation before `BASELINE_VALIDATED`; maximum three failed baseline adjudications;
3. capture `ORIGINAL_USER_REQUEST.md`, append-only `CLARIFICATION_TRANSCRIPT.md` and provenance-backed `APPROVED_REQUIREMENTS.md`; use `question` for unresolved material decisions/instruction conflicts and never silently choose between conflicting instructions;
4. for each task create `CONTEXT_MANIFEST.md`, `VERIFICATION_PROFILE.md`, `RUN_STATE.json`, optional `STEERING.md` and `evidence/`; reuse validated baseline/context/instruction indexes plus Git delta and expand context only on evidence of wider impact;
5. material steering must enter requirement provenance before action and force replanning when it invalidates the current plan;
6. plan must include `DOCUMENTATION_IMPACT`, traceable acceptance criteria and `MINIMUM_CHANGE_ASSESSMENT`; prefer the smallest correct, secure, maintainable root-cause change, reuse existing/native/stdlib/installed capabilities, and never simplify away security/validation/data-loss protection/accessibility/approved requirements;
7. `VERIFICATION_PROFILE.md` must define `TASK_RISK_PROFILE`, authoritative `VALIDATION_PROFILE`/CI parity and `REQUIRED|CONDITIONAL|NOT_APPLICABLE` evidence gates for bug proof, test impact, contract compatibility, environment fingerprint, dependency delta, generated artifacts, migrations, existing non-functional budgets, flakiness, adversarial input and repository-required human ownership;
8. risk classification may add proof requirements but never remove normal validation, dual review or Final Reviewer adjudication;
9. never install/add an external tool or dependency merely to satisfy evidence governance and never invent thresholds; use existing project mechanisms and primary evidence. Required unavailable evidence needs an explicitly sufficient equivalent method or remains blocking;
10. create fresh referential `EXECUTION_PACKET.md`; Executor reads canonical evidence, implements only approved scope, records evidence-triggered context expansions, synchronizes required docs and writes/updates `evidence/VERIFICATION_EVIDENCE.md` with exact validation/gate results;
11. `BUGFIX_PROOF` must preserve pre-fix failure when reproducible and post-fix pass; a rerun pass never erases an earlier unexplained failure; test-impact selection never bypasses authoritative CI/full-suite requirements;
12. public contract, dependency/lockfile, generated-artifact, migration, environment/toolchain, validation-config and non-functional evidence are checked when applicable; scanner/tool output is evidence, not proof;
13. after all required acceptance/evidence gates are fresh and sufficient, Executor reaches `TASK_VALIDATED`;
14. freeze the reviewed source/documentation target and evidence dependencies; create independent role-specific review packets referencing the same `VERIFICATION_PROFILE.md`/`VERIFICATION_EVIDENCE.md`; reviewer packets must never contain sibling current-cycle review output;
15. invoke both reviewers independently, requesting both before consuming either result and running concurrently when supported;
16. after both reviews complete, create `FINAL_PACKET.md` with canonical provenance, frozen target, verification profile/evidence, tests/docs and both independent reviews;
17. Final Reviewer independently challenges Architect interpretation and evidence sufficiency; a perfectly implemented materially wrong plan is `PLAN_DEFECT`, and required stale/insufficient evidence cannot support `PASS`;
18. only validated Final Reviewer corrections return to Executor/Architect; changes to source/docs/contracts/lockfiles/generator inputs/migrations/environment/toolchain/validation config invalidate dependent evidence/reviews;
19. maximum three failed task final-adjudication cycles;
20. authoritative `CODEOWNERS_HUMAN_GATE`/human approval requirements block merge/release/push at the boundary specified by repository policy; never fabricate approval;
21. after `PASS`, Executor creates one scoped local commit after secret/Git-state checks; never push without explicit authorization;
22. append material transitions to history and keep `RUN_STATE.json`/`.ai/STATUS.md` synchronized;
23. when `.ai/TASK_QUEUE.json` exists, an orchestrated milestone may select the highest-priority eligible task whose dependencies are complete, but each task still passes every normal gate and no unbounded loop is allowed.

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
EVIDENCE_STATUS: COMPLETE|PARTIAL|BLOCKED|N/A
```
