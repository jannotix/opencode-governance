---
description: Run the complete governed multi-model development workflow
agent: architect
subtask: false
---

Run the complete governed development lifecycle for:

$ARGUMENTS

Do not edit source code or project documentation yourself.

Lifecycle:

`INTAKE -> BASELINE_DRAFT -> BASELINE_DUAL_AUDIT -> BASELINE_ADJUDICATION -> BASELINE_VALIDATED -> REQUIREMENT_CAPTURE -> CLARIFICATION -> APPROVED_REQUIREMENTS -> PLANNING -> TASK_PLANNED -> READY_FOR_EXECUTION -> IMPLEMENTING -> DOCUMENTATION_SYNC -> TASK_VERIFYING -> TASK_VALIDATED -> DUAL_REVIEW -> FINAL_ADJUDICATION -> LOCAL_COMMITTED`

Rules:

1. if project governance is not initialized, establish `.ai/CODEBASE_BASELINE.md`, `.ai/DEPLOYMENT_SCOPE.md`, `.ai/DOCUMENTATION_SCOPE.md`, `.ai/PROJECT_HISTORY.md`, `.ai/STATUS.md` and `.ai/baseline-audits/` first;
2. before first implementation, create a draft codebase baseline, architecture map, dependency/call-path map and documentation inventory, then run mandatory independent `BASELINE_AUDIT` reviews with `reviewer` and `reviewer-architecture` followed by `final-reviewer` adjudication;
3. no source implementation may begin until baseline state is `BASELINE_VALIDATED`;
4. if baseline adjudication returns `BASELINE_DEFECT`, apply only validated corrections to `.ai/` and repeat a fresh independent baseline-audit cycle; after three failed baseline adjudications set `BASELINE_BLOCKED` and stop;
5. for a new task create `.ai/tasks/<TASK-ID>/ORIGINAL_USER_REQUEST.md` from the user's actual request before interpreting it; preserve wording and intent and redact secret values only;
6. create/append `.ai/tasks/<TASK-ID>/CLARIFICATION_TRANSCRIPT.md` for material questions and authoritative answers; never silently rewrite earlier answers;
7. create `.ai/tasks/<TASK-ID>/APPROVED_REQUIREMENTS.md` from original request + authoritative clarifications + established repository facts, with provenance for material normalized requirements;
8. for later routine tasks, reuse validated baseline/documentation scope, inspect repository changes since its reference point or last validated task, and perform targeted analysis around affected modules, callers, callees, dependencies, data flows and canonical documentation;
9. expand beyond the targeted surface only when evidence indicates wider impact;
10. if evidence shows baseline is materially stale after major structural/architectural/dependency/import changes, set `BASELINE_REVALIDATION_REQUIRED` and run adversarial baseline revalidation before planning continues;
11. identify every material ambiguity in requirements, behaviour, UX, compatibility, data handling, integrations, deployment, packaging, documentation and licensing;
12. when existing approved requirements and primary evidence do not resolve a material decision, use `question` to ask developer/project owner; continue until plan no longer relies on invented assumptions and never repeat questions already answered;
13. append each material clarification to `CLARIFICATION_TRANSCRIPT.md` and update `APPROVED_REQUIREMENTS.md` only from authoritative input;
14. if user instructions conflict, ask which controls rather than choosing silently;
15. verify approved requirements materially preserve every controlling instruction in original request and clarification transcript;
16. determine `DOCUMENTATION_IMPACT` as `NONE`, `UPDATE_REQUIRED` or `CREATE_REQUIRED` and identify exact canonical documents/sections;
17. for distributable applications ensure documentation scope normally includes project overview/readme, step-by-step installation, user manual, wiki/index, changelog and explicit licensing documentation, plus applicable admin/configuration/API/architecture/security/upgrade/troubleshooting/release docs;
18. never choose or infer a software license; ask developer/project owner when no explicit license decision exists, otherwise record `LICENSE_DECISION_REQUIRED` and keep release readiness blocked;
19. create fresh Architect-approved JIT plan from validated baseline, canonical requirement trail, clarification decisions and documentation impact;
20. do not let plan override, weaken, broaden, contradict or omit a controlling requirement from `ORIGINAL_USER_REQUEST.md`, `CLARIFICATION_TRANSCRIPT.md` or `APPROVED_REQUIREMENTS.md`;
21. delegate implementation only when task is `READY_FOR_EXECUTION` and no unresolved material implementation ambiguity remains;
22. delegate source and project-documentation writes only to `executor`;
23. Executor must read the canonical requirement trail and return `PLAN_CONFLICT` if plan materially conflicts with approved requirements;
24. Executor must synchronize all required documentation before `TASK_VALIDATED`; required docs are part of task, not deferred cleanup;
25. after Executor reaches `TASK_VALIDATED`, freeze source and task documentation for current review cycle;
26. invoke `reviewer` and `reviewer-architecture` independently in `TASK_REVIEW` mode against same canonical requirement trail, plan, repository state, source diff and documentation diff; never include one reviewer's output in the other's prompt;
27. request both reviews before consuming either result and run concurrently when runtime supports concurrent Task calls;
28. after both independent reviews complete, invoke `final-reviewer` in `TASK_REVIEW` mode with `ORIGINAL_USER_REQUEST.md`, `CLARIFICATION_TRANSCRIPT.md`, `APPROVED_REQUIREMENTS.md`, validated baseline/maps, documentation scope, approved plan, source/documentation diff, tests, execution evidence and both review artifacts;
29. Final Reviewer must first verify Architect interpretation against original request and clarification transcript, then verify plan, implementation and documentation;
30. if approved requirements or plan materially contradict, weaken, broaden without authorization, or omit a controlling user instruction, Final Reviewer must return `PLAN_DEFECT` even when implementation perfectly follows the plan;
31. only `final-reviewer` may return controlling task `PASS`, `IMPLEMENTATION_DEFECT`, `PLAN_DEFECT` or `BLOCKED`;
32. required documentation that is missing, stale, contradictory, unsafe or claims unimplemented behaviour prevents `PASS`;
33. when final adjudication returns `IMPLEMENTATION_DEFECT`, send only validated source/documentation corrections to Executor, re-run validation and start fresh dual-review cycle;
34. when final adjudication returns `PLAN_DEFECT`, re-open requirement trail, clarify newly exposed ambiguities with developer/project owner when needed, revise approved requirements only from authoritative input, revise plan, restore `READY_FOR_EXECUTION`, execute and re-review;
35. when Executor returns `PLAN_CONFLICT`, re-investigate conflicting assumption against requirement trail and ask developer/project owner when material decision is required;
36. after `final-reviewer` returns `PASS`, delegate finalization to Executor: inspect Git state/diff, scan staged changes for secrets, stage only task-scoped source, required project documentation plus relevant `.ai/` state/history, create required local task commit, and set `LOCAL_COMMITTED`;
37. never push unless user explicitly authorizes that specific push;
38. append material baseline/task/documentation state transitions, clarification decisions and evidence to `.ai/PROJECT_HISTORY.md` without secret values.

Reviewer independence is mandatory in baseline and task review cycles even if runtime serializes the two review invocations. Neither reviewer may read sibling review artifact for active cycle.

Default project documentation root is top-level `docs/`, outside production/runtime package. Preserve coherent existing documentation conventions and explicit legal/packaging exceptions instead of creating contradictory duplicates.

Maximum automatic cycles:

- 3 baseline adjudications before `BASELINE_BLOCKED`;
- 3 task final adjudications before `BLOCKED`.

Finish a governed task only with `LOCAL_COMMITTED` or a justified `BLOCKED`/`BASELINE_BLOCKED` state.