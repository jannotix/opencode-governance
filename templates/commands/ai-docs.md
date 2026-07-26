---
description: Generate or synchronize governed project documentation
agent: architect
subtask: false
---

Generate, repair or synchronize the current project's user/developer documentation without bypassing governance.

Optional focus/request:

$ARGUMENTS

Do not edit project documentation yourself. Architect plans and coordinates; Executor performs documentation writes.

## Preconditions

1. ensure project governance is initialized;
2. require a currently `BASELINE_VALIDATED` codebase baseline;
3. read `.ai/DOCUMENTATION_SCOPE.md`, `.ai/DEPLOYMENT_SCOPE.md`, existing canonical documentation and relevant source/configuration evidence;
4. if the baseline is missing or materially stale, complete adversarial baseline validation first;
5. if documentation scope is missing or materially inaccurate, update it under `.ai/` from evidence before planning documentation work.

Never invent product behaviour, installation requirements, supported environments, configuration values, API semantics, user workflows or license terms.

If any material documentation fact cannot be determined from repository evidence or existing approved requirements, use the `question` tool to ask the developer/project owner. Continue clarification until the documentation can be written accurately. Do not repeat questions already answered.

## Default documentation for distributable applications

When no coherent existing documentation convention exists, use top-level `docs/` outside the production/runtime code boundary.

Ensure the following minimum set is present and useful unless genuinely not applicable:

- `docs/README.md` — product overview, supported runtime/platforms, main capabilities, quick start and documentation index;
- `docs/INSTALLATION.md` — complete step-by-step prerequisites, installation, configuration required for first start, launch/startup and initial verification;
- `docs/USER_MANUAL.md` — task-oriented instructions explaining how users operate the shipped application;
- `docs/wiki/README.md` — wiki/index linking task-oriented operational pages under `docs/wiki/`;
- `docs/CHANGELOG.md` — maintained version/change history based on validated project history/releases;
- licensing documentation backed by an explicit project license decision.

Create other documents when applicable:

- `docs/ADMIN_MANUAL.md`;
- `docs/UPGRADE.md`;
- `docs/ARCHITECTURE.md`;
- `docs/CONFIGURATION.md`;
- `docs/API.md`;
- `docs/SECURITY.md`;
- `docs/TROUBLESHOOTING.md`;
- `docs/RELEASE_NOTES.md`;
- additional `docs/wiki/*.md` task/topic pages.

Do not create empty/filler documents merely to satisfy a filename list. Mark non-applicable items in `.ai/DOCUMENTATION_SCOPE.md`.

Preserve coherent existing project conventions. If root-level `README.md`, `LICENSE`, `NOTICE` or `CHANGELOG.md` are required by the project ecosystem/legal distribution model, preserve them and record their relationship to canonical `docs/` documentation rather than creating contradictory copies.

## License rule

Never choose, infer or fabricate a software license.

Use only:

- an explicit license choice supplied by the developer/project owner; or
- authoritative existing project legal files/metadata that unambiguously establish the license.

If no explicit license decision exists:

1. ask the developer/project owner using `question`;
2. if still unresolved, set `LICENSE_DECISION_REQUIRED` in `.ai/DOCUMENTATION_SCOPE.md`;
3. do not fabricate `LICENSE.md` terms;
4. allow unrelated development only when safe, but keep release readiness blocked.

## Governed documentation task

Create a dedicated task under `.ai/tasks/<TASK-ID>/` with:

- current documentation inventory;
- source/configuration evidence used;
- clarification questions/answers;
- exact documents/sections to create/update/remove from canonical scope;
- installation/manual/wiki verification strategy;
- license state;
- deployment exclusion checks;
- acceptance criteria.

Set the task `READY_FOR_EXECUTION` only when the documentation work is evidence-backed and free of unresolved material ambiguity.

Delegate writes only to `executor`.

Executor must:

- create/update only the approved canonical documentation;
- verify commands, paths, configuration examples and installation steps against the actual project where locally possible;
- use safe placeholders rather than real secrets;
- ensure `docs/**` remains excluded from production/runtime packaging by default;
- update `.ai/DOCUMENTATION_SCOPE.md` synchronization references through the governed `.ai/` state where applicable;
- set `TASK_VALIDATED` only after documentation acceptance checks pass.

After `TASK_VALIDATED`, freeze the documentation target and run fresh independent `TASK_REVIEW` assessments with `reviewer` and `reviewer-architecture`, followed by `final-reviewer` `TASK_REVIEW` adjudication.

Final Reviewer controls the result. Required inaccurate, incomplete or contradictory documentation prevents `PASS`.

After `PASS`, require Executor to create one scoped local commit containing only the governed documentation task plus relevant `.ai/` evidence.

Never push unless the user explicitly authorizes that specific push.