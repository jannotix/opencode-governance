---
description: Run final production-readiness governance gates
agent: architect
subtask: false
---

Run the final governed release assessment for:

$ARGUMENTS

Do not modify source code yourself.

Requirements:

1. read `.ai/CODEBASE_BASELINE.md`, `.ai/DEPLOYMENT_SCOPE.md`, `.ai/PROJECT_HISTORY.md`, current task artifacts and repository state;
2. confirm all required tasks are validated and locally committed;
3. verify the production artifact contains only runtime-required production files according to `DEPLOYMENT_SCOPE.md`;
4. exclude `.ai/`, tests, development documentation, review evidence, local tooling, IDE/temp files and secrets unless a specific file is demonstrably required at runtime;
5. verify no plaintext secrets or tracked credential files are present in source or release artifact;
6. verify schema/data-change and data-preservation safety for existing installations where applicable;
7. build the final artifact/package using the project's real release mechanism;
8. extract/copy that final artifact into a clean directory/environment and perform a clean installation/startup/smoke test from the artifact itself;
9. run the strongest relevant test/build/static-analysis checks;
10. execute mandatory real sandbox/test validation for external integrations where applicable; mocks alone are insufficient;
11. invoke `reviewer` and `reviewer-architecture` as fresh independent release reviews of the same production candidate, without sharing either reviewer's output with the other;
12. request both release reviews before consuming either result and run them concurrently when supported;
13. invoke `final-reviewer` after both reviews complete and require it to independently adjudicate the production evidence and reviewer findings.

Only `final-reviewer` returns the production verdict:

- `READY_FOR_PRODUCTION`
- `NOT_READY_FOR_PRODUCTION`

Any unresolved security finding, plaintext/tracked secret, failed clean install, unsafe schema/data-change state, invalid production package, failed required test, or mandatory external validation not executed requires `NOT_READY_FOR_PRODUCTION`.

Append the release assessment and evidence to `.ai/PROJECT_HISTORY.md` without secret values.

Do not push unless the user explicitly authorizes that specific push.