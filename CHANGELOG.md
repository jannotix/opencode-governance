# Changelog

## 1.3.0 - 2026-07-26

- Added mandatory adversarial validation of the initial reusable codebase baseline.
- Added independent `BASELINE_AUDIT` modes for Implementation and Architecture/Security Reviewers.
- Added Final Reviewer baseline adjudication with `BASELINE_PASS`, `BASELINE_DEFECT` and `BLOCKED` verdicts.
- Blocked source implementation until the repository reaches `BASELINE_VALIDATED`.
- Added bounded baseline correction/review cycles with `BASELINE_BLOCKED` after three failed adjudications.
- Added `/ai-audit` for explicit full baseline revalidation after material repository changes or on demand.
- Added lazy revalidation for existing repositories instead of rescanning all projects during governance updates.
- Added baseline-audit evidence under `.ai/baseline-audits/`.
- Updated Build, Plan, task execution, task review, release gates, status reporting, installers, verification, uninstall and documentation for baseline validation.
- Preserved incremental/JIT analysis for routine tasks so validated large-repository baselines are reused instead of repeatedly rescanned.

## 1.2.0 - 2026-07-26

- Added five configurable governance roles.
- Added independent implementation and architecture/security reviews.
- Added final finding adjudication before approval or repair.
- Added reviewer isolation for each review cycle.
- Added concurrent dual-review support when available.
- Added reusable architecture and dependency/call-path maps to the codebase baseline.
- Added incremental task planning from repository deltas instead of repeated full scans.
- Added targeted reviewer and final-adjudication verification for large repositories.
- Overrode OpenCode `Build` with the complete governed lifecycle and `Plan` with governed planning-only behavior.
- Required full `provider/model-id` values so duplicate models exposed by different providers route deterministically.
- Limited automatic repair to three final-review cycles.
- Updated release review, installers, verification and uninstall scripts.
- Kept provider and model configuration fully user-defined.
- Added OpenCode Desktop configuration guidance.

## 1.1.0 - 2026-07-25

- Added repository baseline and just-in-time task planning.
- Added `READY_FOR_EXECUTION` task gating.
- Added dependency, deployment-scope and project-history governance.
- Added data/schema and external-integration validation rules.
- Added scoped local commits after review approval.
- Added explicit authorization requirement for `git push`.
- Added `/ai-init` and `/ai-release`.

## 1.0.0 - 2026-07-25

- Initial release.
- Added Architect, Executor and Reviewer roles.
- Added Windows and Unix installers.
- Added verification and uninstall scripts.
- Added OpenCode commands and project-local `.ai/` state.
- Licensed under FSL-1.1-MIT.