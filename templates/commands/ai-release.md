---
description: Run final production-readiness governance gates
agent: architect
subtask: false
---

Run the final governed release assessment for:

$ARGUMENTS

Do not modify source code yourself.

Requirements:

1. read `.ai/CODEBASE_BASELINE.md`, latest baseline audit evidence, `.ai/DEPLOYMENT_SCOPE.md`, `.ai/PROJECT_HISTORY.md`, current task artifacts and repository state;
2. require the baseline state to be `BASELINE_VALIDATED`; if it is missing, blocked or materially stale, complete `/ai-audit`-equivalent adversarial baseline revalidation before release review continues;
3. confirm all required tasks are validated and locally committed;
4. verify the production artifact contains only runtime-required production files according to `DEPLOYMENT_SCOPE.md`;
5. exclude `.ai/`, tests, development documentation, review evidence, local tooling, IDE/temp files and secrets unless a specific file is demonstrably required at runtime;
6. verify no plaintext secrets or tracked credential files are present in source or release artifact;
7. verify schema/data-change and data-preservation safety for existing installations where applicable;
8. build the final artifact/package using the project's real release mechanism;
9. extract/copy that final artifact into a clean directory/environment and perform a clean installation/startup/smoke test from the artifact itself;
10. run the strongest relevant test/build/static-analysis checks;
11. execute mandatory real sandbox/test validation for external integrations where applicable; mocks alone are insufficient;
12. invoke `reviewer` and `reviewer-architecture` as fresh independent `RELEASE_REVIEW` assessments of the same production candidate, without sharing either reviewer's output with the other;
13. request both release reviews before consuming either result and run them concurrently when supported;
14. invoke `final-reviewer` in `RELEASE_REVIEW` mode after both reviews complete and require it to independently adjudicate the production evidence and reviewer findings.

Only `final-reviewer` returns the production verdict:

- `READY_FOR_PRODUCTION`
- `NOT_READY_FOR_PRODUCTION`

Any baseline that is not currently validated, unresolved security finding, plaintext/tracked secret, failed clean install, unsafe schema/data-change state, invalid production package, failed required test, or mandatory external validation not executed requires `NOT_READY_FOR_PRODUCTION`.

Append the release assessment and evidence to `.ai/PROJECT_HISTORY.md` without secret values.

Do not push unless the user explicitly authorizes that specific push.