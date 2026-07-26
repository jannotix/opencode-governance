---
description: Analyse a task and create a governed implementation plan
agent: architect
subtask: false
---

Analyse this request without implementing source or project-documentation changes:

$ARGUMENTS

Ensure project-local governance has been initialized, including `.ai/DOCUMENTATION_SCOPE.md`.

If `.ai/CODEBASE_BASELINE.md` is missing or the baseline is not `BASELINE_VALIDATED`, complete the mandatory adversarial baseline flow before task planning:

Architect draft baseline/documentation inventory
→ independent `reviewer` + `reviewer-architecture` `BASELINE_AUDIT`
→ `final-reviewer` `BASELINE_AUDIT`
→ `BASELINE_VALIDATED`

Do not create a task implementation plan from an unvalidated baseline.

If an existing validated baseline is materially stale, set `BASELINE_REVALIDATION_REQUIRED` and revalidate it before planning continues.

For routine tasks, reuse the validated baseline, architecture map, dependency/call-path map and documentation scope. Reconcile them with repository changes since the recorded reference point or last validated task using targeted Git history/diff/status inspection, then inspect only the affected modules, callers, callees, dependencies, data flows and canonical documentation required to establish task impact. Expand analysis only when evidence indicates a wider surface.

Before finalizing scope, identify every material ambiguity in behaviour, UX, compatibility, data handling, integrations, deployment, packaging, documentation or licensing. When existing requirements and primary evidence do not resolve a decision, use the `question` tool to ask the developer/project owner. Continue clarification until the plan no longer depends on invented assumptions. Do not repeat questions already answered.

Perform an adversarial impact analysis covering scope, affected components, dependencies, regression surface, tests, database/schema and data-change impact, deployment impact, external validation, security/secrets, maintainability and project documentation.

Determine exactly one documentation impact state:

- `DOCUMENTATION_IMPACT: NONE` with evidence why canonical docs remain correct;
- `DOCUMENTATION_IMPACT: UPDATE_REQUIRED` with exact canonical documents/sections;
- `DOCUMENTATION_IMPACT: CREATE_REQUIRED` with exact missing applicable documents.

For distributable applications, ensure `.ai/DOCUMENTATION_SCOPE.md` normally requires a project overview/readme, step-by-step installation guide, user manual, wiki/index, changelog and explicit licensing documentation, plus admin/configuration/API/architecture/security/upgrade/troubleshooting/release docs when applicable.

Never choose or infer a software license. If no authoritative license decision exists, ask the developer/project owner when required. Otherwise record `LICENSE_DECISION_REQUIRED`; release readiness must remain blocked until resolved.

Create or update the task records under `.ai/tasks/<TASK-ID>/` with:

- specification;
- clarification questions and authoritative answers;
- accepted unresolved constraints/unknowns that do not block execution;
- architecture analysis;
- exact implementation plan;
- documentation impact and canonical docs/sections;
- acceptance criteria;
- validation strategy;
- evidence.

Set the task state:

`PLANNING -> TASK_PLANNED -> READY_FOR_EXECUTION`

Only set `READY_FOR_EXECUTION` when the task is fully planned, evidence-backed, executable, based on a currently validated baseline and free of unresolved material implementation ambiguity. Otherwise return `BLOCKED` or `BASELINE_BLOCKED` with the missing decision, evidence or prerequisite.

Stop after planning is complete. Do not implement source or project-documentation changes.