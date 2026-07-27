---
description: Run the complete governed multi-model development workflow
agent: architect
subtask: false
---

Run the complete governed development lifecycle for:

$ARGUMENTS

Do not edit source code or project documentation yourself.

Lifecycle:

`INTAKE -> BASELINE_DRAFT -> BASELINE_DUAL_AUDIT -> BASELINE_ADJUDICATION -> BASELINE_VALIDATED -> REQUIREMENT_CAPTURE -> CLARIFICATION -> APPROVED_REQUIREMENTS -> GOVERNED_DISCOVERY -> SKILL_ROUTING -> CONTEXT_ROUTING -> PLANNING -> MINIMUM_CHANGE_GATE -> EVIDENCE_PLANNING -> OPERATIONAL_PLANNING -> TASK_PLANNED -> READY_FOR_EXECUTION -> PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED -> IMPLEMENTING -> DOCUMENTATION_SYNC -> EVIDENCE_VALIDATION -> OPERATIONAL_VALIDATION -> TASK_VERIFYING -> TASK_VALIDATED -> DUAL_REVIEW -> FINAL_ADJUDICATION -> VALIDATED_LEARNING -> LOCAL_COMMITTED`

Rules:

1. initialize `.ai/CODEBASE_BASELINE.md`, `.ai/CONTEXT_INDEX.md`, `.ai/INSTRUCTION_INDEX.md`, `.ai/GOVERNANCE_MEMORY.md`, `.ai/DEPLOYMENT_SCOPE.md`, `.ai/DOCUMENTATION_SCOPE.md`, `.ai/PROJECT_HISTORY.md`, `.ai/STATUS.md`, tasks and baseline-audits when required;
2. baseline draft/indexes/memory are independently audited by both reviewers and adjudicated by Final Reviewer; no implementation before `BASELINE_VALIDATED`; maximum three failed baseline adjudications;
3. capture `ORIGINAL_USER_REQUEST.md`, append-only `CLARIFICATION_TRANSCRIPT.md` and provenance-backed `APPROVED_REQUIREMENTS.md`; use `question` for unresolved material decisions/instruction conflicts and never silently choose between conflicting instructions;
4. when task discovery has multiple independent surfaces, `READ_ONLY_DISCOVERY_SWARM` may issue 2-4 independent read-only OpenCode `Explore`/`Scout` subtasks; never use writable `General`, never expose sibling discovery conclusions, and verify material summaries against primary evidence before planning;
5. `GOVERNED_SKILL_ROUTING` uses only task-relevant skills indexed in `.ai/INSTRUCTION_INDEX.md` with verified source/ID/scope/freshness/trust `PROJECT_AUTHORITATIVE|PROJECT_ADVISORY|WORKSPACE_ADVISORY|EXTERNAL_UNTRUSTED`; skills never override requirement provenance or authorize side effects;
6. for each task create `CONTEXT_MANIFEST.md`, `VERIFICATION_PROFILE.md`, `RUN_STATE.json`, optional `STEERING.md` and `evidence/`; reuse validated baseline/context/instruction indexes, applicable active governance-memory entries and Git delta and expand context only on primary evidence of wider impact;
7. material steering must enter requirement provenance before action and force replanning when it invalidates the current plan;
8. plan must include `DOCUMENTATION_IMPACT`, traceable acceptance criteria and `MINIMUM_CHANGE_ASSESSMENT`; prefer the smallest correct, secure, maintainable root-cause change, reuse existing/native/stdlib/installed capabilities, and never simplify away security/validation/data-loss protection/accessibility/approved requirements;
9. `VERIFICATION_PROFILE.md` must define `TASK_RISK_PROFILE`, authoritative `VALIDATION_PROFILE`/CI parity and `REQUIRED|CONDITIONAL|NOT_APPLICABLE` Evidence-Driven gates for `BUGFIX_PROOF`, `TEST_IMPACT_MAP`, `CONTRACT_COMPATIBILITY`, `ENVIRONMENT_FINGERPRINT`, `DEPENDENCY_ADMISSION_GATE`, `DEPENDENCY_DELTA`, `GENERATED_ARTIFACT_GATE`, `PRE_CHANGE_SAFEPOINT`, `MIGRATION_PROOF`, `NON_FUNCTIONAL_BUDGETS`, `FLAKINESS_EVIDENCE`, `ADVERSARIAL_INPUT_VALIDATION`, `CODEOWNERS_HUMAN_GATE`, `CLOSED_LOOP_LEARNING`;
10. any new direct dependency requires `DEPENDENCY_ADMISSION_GATE = ADMIT` before installation, with exact package/source/version, evidence existing stack is insufficient, identity/existence where externally sourced and available maintenance/compatibility/security/license evidence; suspected typo/slopsquat, unverifiable identity, `REJECT` or unresolved `HUMAN_DECISION` blocks installation;
11. when required, `PRE_CHANGE_SAFEPOINT` captures recoverable non-secret pre-change Git/worktree/schema/config/lockfile/artifact plus existing required backup/recovery references before the first high-risk destructive/migration/deployment-state mutation; do not fabricate or silently create privileged production backups;
12. v2.0 `OPERATIONAL_ASSURANCE` in the same profile plans `PREVIEW_ENVIRONMENT_GATE`, `USER_FLOW_VERIFICATION`, `VISUAL_BEHAVIOR_GATE`, `RELEASE_RECOVERY_PROOF`, `TOOL_CAPABILITY_PROFILE` with `MCP_CAPABILITY_ASSESSMENT`, and `SAFE_EXPERIMENTATION`;
13. `TASK_RISK_PROFILE` includes `USER_FLOW`, `VISUAL_BEHAVIOR`, `EXTERNAL_TOOLING`, `RECOVERY` and `EXPERIMENTATION` in addition to existing risk dimensions; risk may add proof but never remove normal validation, dual review or Final Reviewer adjudication;
14. never install/add an external verification/browser/visual tool, provision preview infrastructure or add a dependency merely to satisfy governance and never invent thresholds; use existing approved project mechanisms and primary evidence. Required unavailable evidence needs an explicitly sufficient equivalent method or remains blocking;
15. preview/staging evidence must identify the frozen source/artifact and production-isolation boundary; production deployment/data/credentials are not used merely to satisfy governance without explicit authorization/policy;
16. user flows derive from approved requirements/established product behavior; visual checks are objective or requirement-backed, not invented aesthetic judgments;
17. recovery proof records stable reference, rollback or forward-recovery mechanism and artifact/config/data/backup compatibility but never authorizes automatic production rollback;
18. relevant external tools/MCP are governed by `TOOL_CAPABILITY_PROFILE`: `READ_ONLY|WRITE|EXECUTE|PRIVILEGED|DESTRUCTIVE`, network/secret/external-side-effect exposure and authorized use. Tool availability is not authorization; never persist secret values;
19. `SAFE_EXPERIMENTATION` may use only an existing permitted isolation mechanism and never weakens OpenCode permissions, uses production data by default, or implies automatic push/merge/deploy;
20. create fresh referential `EXECUTION_PACKET.md`; Executor reads canonical evidence, selected skills/memory refs, implements only approved scope, records evidence-triggered context expansions, synchronizes required docs and writes/updates `evidence/VERIFICATION_EVIDENCE.md` with exact Evidence-Driven and Operational Assurance results;
21. `BUGFIX_PROOF` preserves pre-fix failure when reproducible and post-fix pass; a rerun pass never erases an earlier unexplained failure; test-impact selection never bypasses authoritative CI/full-suite requirements;
22. public contract, dependency admission/lockfile, safepoint, generated-artifact, migration, environment/toolchain, validation-config, selected skill, preview/runtime, tool/MCP, recovery and isolation evidence are checked when applicable; scanner/tool output is evidence, not proof;
23. after all required acceptance/evidence/operational gates are fresh and sufficient, Executor reaches `TASK_VALIDATED`;
24. freeze the reviewed source/documentation target and evidence dependencies; create independent role-specific review packets referencing the same `VERIFICATION_PROFILE.md`/`VERIFICATION_EVIDENCE.md`; reviewer packets must never contain sibling current-cycle review output;
25. invoke both reviewers independently, requesting both before consuming either result and running concurrently when supported;
26. after both reviews complete, create `FINAL_PACKET.md` with canonical provenance, frozen target, verification/operational profile/evidence, selected skill/memory refs, tests/docs and both independent reviews;
27. Final Reviewer independently challenges Architect interpretation, skill/memory relevance, dependency admission, safepoint and Evidence-Driven/Operational Assurance sufficiency; a perfectly implemented materially wrong plan is `PLAN_DEFECT`, and required stale/insufficient evidence cannot support `PASS`;
28. only validated Final Reviewer corrections return to Executor/Architect; changes to source/docs/contracts/dependency-admission/lockfiles/safepoint/generator inputs/migrations/environment/toolchain/validation config/selected skill/preview target/tool capability/recovery input/isolation target invalidate dependent evidence/reviews;
29. `CLOSED_LOOP_LEARNING` runs only when authoritative evidence shows a reusable escaped/repeated defect, validation gap, stable false-positive rationale, recovery lesson or tooling constraint. Final Reviewer records `MEMORY_DECISION: NONE|APPROVE|REJECT`; only an approved candidate may be written by Architect to `.ai/GOVERNANCE_MEMORY.md` with exact scope/evidence/`stale_when` and `ACTIVE|STALE|REVOKED` lifecycle;
30. maximum three failed task final-adjudication cycles;
31. authoritative `CODEOWNERS_HUMAN_GATE`/human approval requirements block merge/release/push at the boundary specified by repository policy; never fabricate approval;
32. after any approved memory update and final `PASS`, Executor creates one scoped local commit after secret/Git-state checks; never push without explicit authorization;
33. append material transitions to history and keep `RUN_STATE.json`/`.ai/STATUS.md`/governance memory synchronized;
34. when `.ai/TASK_QUEUE.json` exists, an orchestrated milestone may select the highest-priority eligible task whose dependencies are complete, but each task still passes every normal gate and no unbounded loop is allowed.

Reviewer independence is mandatory. Conversation history, discovery summaries, skill bodies and governance memory are never substitutes for current primary evidence. Required project documentation is part of task correctness. Governance never chooses a software license. Operational Assurance never broadens configured permissions.

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