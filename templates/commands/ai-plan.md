---
description: Analyse a task and create a governed implementation plan
agent: architect
subtask: false
---

Analyse this request without implementing source or project-documentation changes:

$ARGUMENTS

Require initialized governance and `BASELINE_VALIDATED`. If baseline/context/instruction index is missing or materially stale, complete/re-request adversarial baseline validation before implementation-ready planning.

For a new task create under `.ai/tasks/<TASK-ID>/`:

- `ORIGINAL_USER_REQUEST.md`;
- `CLARIFICATION_TRANSCRIPT.md`;
- `APPROVED_REQUIREMENTS.md`;
- `CONTEXT_MANIFEST.md`;
- `VERIFICATION_PROFILE.md`;
- `RUN_STATE.json`;
- `STEERING.md` when steering is supplied/needed;
- `evidence/` for role-specific handoff packets and `VERIFICATION_EVIDENCE.md`.

Preserve original request separately from Architect interpretation and redact only secret values. Clarifications are chronological; later supersession must be explicit.

Reuse `.ai/CODEBASE_BASELINE.md`, `.ai/CONTEXT_INDEX.md`, `.ai/INSTRUCTION_INDEX.md`, documentation/deployment scope and current Git delta. Build `CONTEXT_MANIFEST.md` with selected modules/files, callers/callees, dependency edges, data flows/trust boundaries, applicable scoped instructions, tests, docs, exclusions and evidence-triggered expansions. Start bounded and expand only when primary evidence indicates wider impact.

Before final scope, process unhandled `STEERING.md`. Material steering must enter `CLARIFICATION_TRANSCRIPT.md`, update `APPROVED_REQUIREMENTS.md` only when authorized, and force replanning when it changes the controlling requirement/plan.

Resolve every material ambiguity with `question`; do not repeat answered questions. Verify approved requirements preserve all controlling instructions.

Perform impact analysis for scope, dependencies, regressions, tests, schema/data, public contracts, generated artifacts, deployment, integrations, security/secrets, maintainability, documentation and human-owner policies. Determine exactly one `DOCUMENTATION_IMPACT`.

Every implementation-ready plan must include `MINIMUM_CHANGE_ASSESSMENT`: root cause/evidence-backed hypothesis, whether capability/fix already exists, reusable project code/pattern, standard-library/native option, installed dependency option, justification for new dependency/abstraction and why the proposed change is the smallest correct secure maintainable solution. Never simplify away security, trust-boundary validation, data-loss protection, error handling, accessibility or approved behavior. For bugs inspect relevant callers and prefer a shared root-cause fix when appropriate.

Create `VERIFICATION_PROFILE.md` with:

- `TASK_RISK_PROFILE` using `NONE|LOW|HIGH` for `SECURITY`, `DATA_MIGRATION`, `PUBLIC_CONTRACT`, `DEPENDENCY`, `DEPLOYMENT`, `PERFORMANCE`, `GENERATED_ARTIFACT`, `DESTRUCTIVE_ACTION`, `INPUT_VALIDATION`, `TEST_RELIABILITY`, `HUMAN_OWNERSHIP`;
- discovered authoritative `VALIDATION_PROFILE`/CI-equivalent commands from repository evidence;
- gate status `REQUIRED|CONDITIONAL|NOT_APPLICABLE` for `BUGFIX_PROOF`, `TEST_IMPACT_MAP`, `CONTRACT_COMPATIBILITY`, `ENVIRONMENT_FINGERPRINT`, `DEPENDENCY_DELTA`, `GENERATED_ARTIFACT_GATE`, `MIGRATION_PROOF`, `NON_FUNCTIONAL_BUDGETS`, `FLAKINESS_EVIDENCE`, `ADVERSARIAL_INPUT_VALIDATION`, `CODEOWNERS_HUMAN_GATE`;
- acceptance criteria mapped to the required evidence.

Do not install or add tools/dependencies merely to satisfy governance. Prefer existing project/CI tooling and primary evidence. Never invent performance/security thresholds or fabricate scanner/fuzzer/contract/codegen capabilities. Required unavailable evidence must have a justified equivalent primary-evidence method or remain blocking.

Write acceptance criteria traceable to approved requirements and evidence gates.

Initialize/update `RUN_STATE.json` using these canonical top-level fields: `schema_version`, `task_id`, `state`, `baseline_state`, `baseline_reference`, `plan_id`, `plan_version`, `repository_head`, `review_cycle`, `documentation_impact`, `review_frozen`, `execution_complete`, `implementation_review_complete`, `architecture_review_complete`, `final_adjudication_complete`, `last_safe_transition`, `resumable`, `human_input_required`, `blocker`, `updated_at`. Additional fields may be added but these names remain stable within the task.

Create `evidence/EXECUTION_PACKET.md` as a referential packet containing exact repository/baseline reference, requirement artifacts, approved plan, context manifest, verification profile, selected changed/affected paths, validation requirements and permitted evidence-triggered expansion rules. Do not copy unrelated conversation history.

Set `PLANNING -> EVIDENCE_PLANNING -> TASK_PLANNED -> READY_FOR_EXECUTION` only when all gates pass. Otherwise return the appropriate blocker.

Finish with `GOVERNANCE_RESULT` including `EVIDENCE_STATUS`. Stop after planning.
