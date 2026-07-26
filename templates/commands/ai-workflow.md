---
description: Run the complete governed multi-model development workflow
agent: architect
subtask: false
---

Run the complete governed development lifecycle for:

$ARGUMENTS

Do not edit source code or project documentation yourself.

Lifecycle:

`INTAKE -> BASELINE_DRAFT -> BASELINE_DUAL_AUDIT -> BASELINE_ADJUDICATION -> BASELINE_VALIDATED -> CLARIFICATION -> PLANNING -> TASK_PLANNED -> READY_FOR_EXECUTION -> IMPLEMENTING -> DOCUMENTATION_SYNC -> TASK_VERIFYING -> TASK_VALIDATED -> DUAL_REVIEW -> FINAL_ADJUDICATION -> LOCAL_COMMITTED`

Rules:

1. if project governance is not initialized, establish `.ai/CODEBASE_BASELINE.md`, `.ai/DEPLOYMENT_SCOPE.md`, `.ai/DOCUMENTATION_SCOPE.md`, `.ai/PROJECT_HISTORY.md`, `.ai/STATUS.md` and `.ai/baseline-audits/` first;
2. before the first implementation, create a draft codebase baseline, architecture map, dependency/call-path map and documentation inventory, then run mandatory independent `BASELINE_AUDIT` reviews with `reviewer` and `reviewer-architecture` followed by `final-reviewer` adjudication;
3. no source implementation may begin until the baseline state is `BASELINE_VALIDATED`;
4. if baseline adjudication returns `BASELINE_DEFECT`, apply only validated corrections to `.ai/` and repeat a fresh independent baseline-audit cycle; after three failed baseline adjudications set `BASELINE_BLOCKED` and stop;
5. for later routine tasks, reuse the validated baseline, documentation scope, inspect repository changes since its reference point or the last validated task, and perform targeted search/read analysis around affected modules, callers, callees, dependencies, data flows and canonical documentation;
6. expand beyond the targeted surface only when evidence indicates wider impact;
7. if evidence shows the baseline is materially stale after major structural/architectural/dependency/import changes, set `BASELINE_REVALIDATION_REQUIRED` and run adversarial baseline revalidation before planning continues;
8. identify every material ambiguity in requirements, behaviour, UX, compatibility, data handling, integrations, deployment, packaging, documentation and licensing;
9. when existing approved requirements and primary evidence do not resolve a material decision, use the `question` tool to ask the developer/project owner; continue clarification until the plan no longer relies on invented assumptions and never repeat questions already answered;
10. determine `DOCUMENTATION_IMPACT` as `NONE`, `UPDATE_REQUIRED` or `CREATE_REQUIRED` and identify exact canonical documents/sections;
11. for distributable applications ensure documentation scope normally includes project overview/readme, step-by-step installation, user manual, wiki/index, changelog and explicit licensing documentation, plus applicable admin/configuration/API/architecture/security/upgrade/troubleshooting/release docs;
12. never choose or infer a software license; ask the developer/project owner when no explicit license decision exists, otherwise record `LICENSE_DECISION_REQUIRED` and keep release readiness blocked;
13. create a fresh Architect-approved JIT plan from validated incremental analysis, clarification answers and documentation impact;
14. delegate implementation only when the task is `READY_FOR_EXECUTION` and no unresolved material implementation ambiguity remains;
15. delegate source and project-documentation writes only to `executor`;
16. Executor must synchronize all required documentation before `TASK_VALIDATED`; required docs are part of the task, not deferred cleanup;
17. after Executor reaches `TASK_VALIDATED`, freeze source and task documentation for the current review cycle;
18. invoke `reviewer` and `reviewer-architecture` independently in `TASK_REVIEW` mode against the same requirement, plan, repository state, source diff and documentation diff; never include one reviewer's output in the other reviewer's prompt;
19. request both task reviews before consuming either result and run them concurrently when the runtime supports concurrent Task calls;
20. after both independent reviews complete, delegate adjudication to `final-reviewer` in `TASK_REVIEW` mode with the validated baseline/maps, documentation scope, approved plan, current source/documentation diff, tests, execution evidence and both review artifacts;
21. Final Reviewer must validate code and documentation consistency using targeted primary evidence rather than a new repository-wide scan unless evidence requires broader inspection;
22. only `final-reviewer` may return the controlling task `PASS`, `IMPLEMENTATION_DEFECT`, `PLAN_DEFECT` or `BLOCKED` verdict;
23. required documentation that is missing, stale, contradictory, unsafe or claims unimplemented behaviour prevents `PASS`;
24. when final adjudication returns `IMPLEMENTATION_DEFECT`, send only validated source/documentation corrections to Executor, re-run validation and start a fresh dual-review cycle;
25. when final adjudication returns `PLAN_DEFECT`, re-investigate, clarify newly exposed ambiguities with the developer/project owner, revise the plan, explicitly restore `READY_FOR_EXECUTION`, execute the revised plan, validate code/docs and start a fresh dual-review cycle;
26. when Executor returns `PLAN_CONFLICT`, re-investigate the conflicting assumption, ask the developer/project owner when a material decision is required, and revise or confirm the plan using evidence before execution continues;
27. after `final-reviewer` returns `PASS`, delegate finalization to Executor: inspect Git state/diff, scan staged changes for secrets, stage only task-scoped source, required project documentation plus relevant `.ai/` state/history, create the required local task commit, and set `LOCAL_COMMITTED`;
28. never push unless the user explicitly authorizes that specific push;
29. append material baseline/task/documentation state transitions, clarification decisions and evidence to `.ai/PROJECT_HISTORY.md` without secret values.

Reviewer independence is mandatory in both baseline and task review cycles even if the runtime serializes the two review invocations. Neither reviewer may read the sibling review artifact for the active cycle.

The default project documentation root is top-level `docs/`, outside the production/runtime package. Preserve coherent existing documentation conventions and explicit legal/packaging exceptions instead of creating contradictory duplicates.

Maximum automatic cycles:

- 3 baseline adjudications before `BASELINE_BLOCKED`;
- 3 task final adjudications before `BLOCKED`.

Finish a governed task only with `LOCAL_COMMITTED` or a justified `BLOCKED`/`BASELINE_BLOCKED` state.