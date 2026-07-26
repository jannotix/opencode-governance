---
description: Analyse a task and create a governed implementation plan
agent: architect
subtask: false
---

Analyse this request without implementing source or project-documentation changes:

$ARGUMENTS

Require initialized governance and `BASELINE_VALIDATED`. If baseline/context index is missing or materially stale, complete/re-request adversarial baseline validation before implementation-ready planning.

For a new task create under `.ai/tasks/<TASK-ID>/`:

- `ORIGINAL_USER_REQUEST.md`;
- `CLARIFICATION_TRANSCRIPT.md`;
- `APPROVED_REQUIREMENTS.md`;
- `CONTEXT_MANIFEST.md`;
- `RUN_STATE.json`;
- `STEERING.md` when steering is supplied/needed;
- `evidence/` for role-specific handoff packets.

Preserve the original request separately from Architect interpretation and redact only secret values. Clarifications are chronological; later supersession must be explicit.

Reuse `.ai/CODEBASE_BASELINE.md`, `.ai/CONTEXT_INDEX.md`, documentation/deployment scope and current Git delta. Build `CONTEXT_MANIFEST.md` with selected modules/files, callers/callees, dependency edges, data flows/trust boundaries, tests, docs, exclusions and evidence-triggered expansions. Start bounded and expand only when primary evidence indicates wider impact.

Before final scope, process unhandled `STEERING.md`. Material steering must enter `CLARIFICATION_TRANSCRIPT.md`, update `APPROVED_REQUIREMENTS.md` only when authorized, and force replanning when it changes the controlling requirement/plan.

Resolve every material ambiguity with `question`; do not repeat answered questions. Verify approved requirements preserve all controlling instructions.

Perform impact analysis for scope, dependencies, regressions, tests, schema/data, deployment, integrations, security/secrets, maintainability and documentation. Determine exactly one `DOCUMENTATION_IMPACT`.

Every implementation-ready plan must include `MINIMUM_CHANGE_ASSESSMENT`:

- root cause or explicit evidence-backed hypothesis;
- whether capability/fix already exists in the codebase;
- reusable existing code/pattern;
- standard-library/native-platform option;
- already-installed dependency option;
- justification for any new dependency;
- justification for any new abstraction/layer;
- why the proposed change is the smallest correct, secure and maintainable solution.

Minimalism may never remove required security, trust-boundary validation, data-loss protection, error handling, accessibility or an approved requirement. For bugs, inspect relevant callers and prefer a shared root-cause fix over symptom-only patches.

Write acceptance criteria traceable to approved requirements and update `RUN_STATE.json` at phase boundaries. Create `evidence/EXECUTION_PACKET.md` as a referential packet containing the exact repository/baseline reference, requirement artifacts, approved plan, context manifest, selected changed/affected paths, validation requirements and permitted evidence-triggered expansion rules. Do not copy unrelated conversation history.

Set `PLANNING -> TASK_PLANNED -> READY_FOR_EXECUTION` only when all gates pass. Otherwise return the appropriate blocker.

Finish task-related output with the `GOVERNANCE_RESULT` block documented by the governance policy. Stop after planning.
