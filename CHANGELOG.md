# Changelog

## 1.5.0 - 2026-07-26

- Added canonical per-task requirement provenance under `.ai/tasks/<TASK-ID>/`.
- Added `ORIGINAL_USER_REQUEST.md` to preserve the user's actual request independently from Architect interpretation.
- Added append-only `CLARIFICATION_TRANSCRIPT.md` for material Architect questions, authoritative answers and explicit superseding decisions.
- Added `APPROVED_REQUIREMENTS.md` as the normalized executable requirement set derived from original request, clarifications and established repository facts, with provenance.
- Blocked `READY_FOR_EXECUTION` when the canonical requirement trail is missing, materially inconsistent or still ambiguous.
- Required Executor to detect plan conflicts against approved requirements instead of blindly following an inconsistent plan.
- Required both task reviewers to receive the same canonical requirement trail.
- Required Final Reviewer to independently compare Architect requirements/plan against the original user request and clarification transcript before judging implementation.
- Added mandatory `PLAN_DEFECT` when Architect materially omits, weakens, contradicts or unauthorizedly broadens a controlling user requirement, even when implementation perfectly follows the plan.
- Added requirement-trail integrity reporting to `/ai-status` and verification checks to Windows/Unix installers.
- Added secret redaction rules for persisted requirement evidence without changing requirement semantics.

## 1.4.0 - 2026-07-26

- Added project documentation governance through `.ai/DOCUMENTATION_SCOPE.md`.
- Added `/ai-docs` to generate, repair or synchronize project documentation through the governed Executor/review pipeline.
- Added default out-of-runtime `docs/` layout for projects without an established documentation convention.
- Added distributable-application documentation baseline: overview/readme, step-by-step installation, user manual, wiki/index, changelog and licensing documentation, with additional docs when applicable.
- Added per-task `DOCUMENTATION_IMPACT`: `NONE`, `UPDATE_REQUIRED` or `CREATE_REQUIRED`.
- Required Executor to synchronize applicable documentation before `TASK_VALIDATED`.
- Added documentation consistency checks to Implementation, Architecture/Security and Final Reviewers for task, baseline and release reviews.
- Added release blocking for missing/stale/contradictory required documentation.
- Added explicit software-license decision handling with `LICENSE_DECISION_REQUIRED`; governance never chooses or invents a project license.
- Kept `docs/**` and `.ai/**` outside the production/runtime artifact by default, with explicit legal/packaging/runtime exceptions only.
- Added explicit OpenCode `question` permission for Architect, governed Build and governed Plan.
- Added mandatory clarification of material project decisions instead of silent assumptions; `READY_FOR_EXECUTION` is blocked while relevant ambiguity remains.
- Updated workflow, status, audit, release, installer, verification, uninstall and public documentation for clarification/documentation governance.

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