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

Perform impact analysis for scope, dependencies, regressions, tests, schema/data, public contracts, generated artifacts, deployment, integrations, security/secrets, maintainability, documentation, human-owner policies and available operational capabilities. Determine exactly one `DOCUMENTATION_IMPACT`.

Every implementation-ready plan must include `MINIMUM_CHANGE_ASSESSMENT`: root cause/evidence-backed hypothesis, whether capability/fix already exists, reusable project code/pattern, standard-library/native option, installed dependency option, justification for new dependency/abstraction and why the proposed change is the smallest correct secure maintainable solution. Never simplify away security, trust-boundary validation, data-loss protection, error handling, accessibility or approved behavior. For bugs inspect relevant callers and prefer a shared root-cause fix when appropriate.

Create `VERIFICATION_PROFILE.md` with:

- `TASK_RISK_PROFILE` using `NONE|LOW|HIGH` for `SECURITY`, `DATA_MIGRATION`, `PUBLIC_CONTRACT`, `DEPENDENCY`, `DEPLOYMENT`, `PERFORMANCE`, `GENERATED_ARTIFACT`, `DESTRUCTIVE_ACTION`, `INPUT_VALIDATION`, `TEST_RELIABILITY`, `HUMAN_OWNERSHIP`, `USER_FLOW`, `VISUAL_BEHAVIOR`, `EXTERNAL_TOOLING`, `RECOVERY`, `EXPERIMENTATION`;
- discovered authoritative `VALIDATION_PROFILE`/CI-equivalent commands from repository evidence;
- gate status `REQUIRED|CONDITIONAL|NOT_APPLICABLE` for `BUGFIX_PROOF`, `TEST_IMPACT_MAP`, `CONTRACT_COMPATIBILITY`, `ENVIRONMENT_FINGERPRINT`, `DEPENDENCY_DELTA`, `GENERATED_ARTIFACT_GATE`, `MIGRATION_PROOF`, `NON_FUNCTIONAL_BUDGETS`, `FLAKINESS_EVIDENCE`, `ADVERSARIAL_INPUT_VALIDATION`, `CODEOWNERS_HUMAN_GATE`;
- `OPERATIONAL_ASSURANCE` with gate status `REQUIRED|CONDITIONAL|NOT_APPLICABLE` for `PREVIEW_ENVIRONMENT_GATE`, `USER_FLOW_VERIFICATION`, `VISUAL_BEHAVIOR_GATE`, `RELEASE_RECOVERY_PROOF`, `TOOL_CAPABILITY_PROFILE` including `MCP_CAPABILITY_ASSESSMENT`, and `SAFE_EXPERIMENTATION`;
- acceptance criteria mapped to required evidence.

Operational planning rules:

- preview may use only an existing/approved `LOCAL_PREVIEW|EPHEMERAL|STAGING|SANDBOX|TEST_ENVIRONMENT`; never provision/deploy production infrastructure merely for governance and never use production data/credentials by default without explicit authorization/policy;
- user flows must come from approved requirements/established behavior; visual verification checks objective behavior or explicit visual requirements, not invented aesthetics;
- recovery proof identifies previous stable reference, rollback or forward-recovery mechanism, artifact/config/data compatibility and backup requirements without authorizing automatic production rollback;
- `TOOL_CAPABILITY_PROFILE` classifies relevant tools/MCP `READ_ONLY|WRITE|EXECUTE|PRIVILEGED|DESTRUCTIVE`, network/secret/external-side-effect exposure and permitted task use; tool availability is never authorization and secret values are never persisted;
- safe experimentation uses only isolation permitted by current project/OpenCode policy and never implies automatic branch push, merge or deployment; do not weaken permissions to make the gate available.

Do not install/add tools, browser frameworks, visual tools, preview infrastructure or dependencies merely to satisfy governance. Prefer existing project/CI/operational mechanisms and primary evidence. Never invent thresholds or fabricate scanner/fuzzer/contract/codegen/preview/recovery/tool capabilities. Required unavailable evidence must have a justified equivalent primary-evidence method or remain blocking.

Write acceptance criteria traceable to approved requirements and required Evidence-Driven/Operational Assurance gates.

Initialize/update `RUN_STATE.json` using these canonical top-level fields: `schema_version`, `task_id`, `state`, `baseline_state`, `baseline_reference`, `plan_id`, `plan_version`, `repository_head`, `review_cycle`, `documentation_impact`, `review_frozen`, `execution_complete`, `implementation_review_complete`, `architecture_review_complete`, `final_adjudication_complete`, `last_safe_transition`, `resumable`, `human_input_required`, `blocker`, `updated_at`. Additional fields may be added but these names remain stable within the task.

Create `evidence/EXECUTION_PACKET.md` as a referential packet containing exact repository/baseline reference, requirement artifacts, approved plan, context manifest, verification/operational profile, selected changed/affected paths, validation requirements and permitted evidence-triggered expansion rules. Do not copy unrelated conversation history.

Set `PLANNING -> EVIDENCE_PLANNING -> TASK_PLANNED -> READY_FOR_EXECUTION` only when all gates pass. Otherwise return the appropriate blocker.

Finish with `GOVERNANCE_RESULT` including `EVIDENCE_STATUS`. Stop after planning.
