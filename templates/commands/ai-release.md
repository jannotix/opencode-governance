---
description: Run final production-readiness governance gates
agent: architect
subtask: false
---

Run the final governed release assessment for:

$ARGUMENTS

Do not modify source code or project documentation yourself.

Requirements:

1. read `.ai/CODEBASE_BASELINE.md`, latest baseline audit evidence, `.ai/DOCUMENTATION_SCOPE.md`, `.ai/DEPLOYMENT_SCOPE.md`, `.ai/PROJECT_HISTORY.md`, current task artifacts, canonical project documentation and repository state;
2. require the baseline state to be `BASELINE_VALIDATED`; if it is missing, blocked or materially stale, complete `/ai-audit`-equivalent adversarial baseline revalidation before release review continues;
3. confirm all required tasks are validated and locally committed;
4. identify unresolved material release ambiguities; when product/project decisions cannot be resolved from authoritative evidence, use the `question` tool to ask the developer/project owner rather than inventing an answer;
5. require an explicit project software-license decision; if `.ai/DOCUMENTATION_SCOPE.md` contains `LICENSE_DECISION_REQUIRED` or legal files conflict with the explicit license decision, return `NOT_READY_FOR_PRODUCTION` until resolved;
6. require applicable project documentation to be complete and synchronized with the production candidate;
7. for distributable applications, verify at minimum the applicable project overview/readme, complete step-by-step installation guide, user manual, wiki/index, changelog and licensing documentation; also verify admin, upgrade, architecture, configuration, API, security, troubleshooting and release notes when marked required;
8. verify installation/manual/wiki instructions, commands, paths, configuration examples and stated behaviour against the actual release artifact and runtime evidence;
9. verify the production artifact contains only runtime-required production files according to `DEPLOYMENT_SCOPE.md`;
10. exclude `docs/**`, `.ai/**`, tests, development/review evidence, local tooling, IDE/temp files and secrets from the production artifact by default;
11. allow a specific license/notice or documentation file inside the production artifact only when `.ai/DEPLOYMENT_SCOPE.md` records an explicit legal, packaging or runtime requirement;
12. verify no plaintext secrets or tracked credential files are present in source, documentation or release artifact;
13. verify schema/data-change and data-preservation safety for existing installations where applicable;
14. build the final artifact/package using the project's real release mechanism;
15. extract/copy that final artifact into a clean directory/environment and perform a clean installation/startup/smoke test from the artifact itself, following the maintained installation documentation where applicable;
16. run the strongest relevant test/build/static-analysis checks;
17. execute mandatory real sandbox/test validation for external integrations where applicable; mocks alone are insufficient;
18. invoke `reviewer` and `reviewer-architecture` as fresh independent `RELEASE_REVIEW` assessments of the same production candidate and canonical documentation, without sharing either reviewer's output with the other;
19. request both release reviews before consuming either result and run them concurrently when supported;
20. invoke `final-reviewer` in `RELEASE_REVIEW` mode after both reviews complete and require it to independently adjudicate production, documentation, licensing and reviewer evidence.

Only `final-reviewer` returns the production verdict:

- `READY_FOR_PRODUCTION`
- `NOT_READY_FOR_PRODUCTION`

Any baseline that is not currently validated, unresolved material release decision, `LICENSE_DECISION_REQUIRED`, missing/incorrect legal files, materially stale/missing required documentation, documentation contradicted by the shipped app, unresolved security finding, plaintext/tracked secret, failed clean install, unsafe schema/data-change state, invalid production package, failed required test, or mandatory external validation not executed requires `NOT_READY_FOR_PRODUCTION`.

Append the release assessment and evidence to `.ai/PROJECT_HISTORY.md` without secret values.

Do not push unless the user explicitly authorizes that specific push.