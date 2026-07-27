# Changelog

## 1.7.0 - 2026-07-27

- Added `/ai-metrics` for read-only governance usage telemetry using usage recorded by OpenCode rather than model-generated estimates.
- Added fail-closed task/role/model attribution: unavailable token, cost, reasoning or cache fields remain `UNAVAILABLE`, and model totals are never proportionally split across roles.
- Added sanitized session-export guidance for role attribution without persisting raw transcript data into project governance state.
- Added `ADAPTIVE_OUTPUT_EFFICIENCY` across all seven governance agents: full reasoning with concise, evidence-dense handoffs and automatic expansion when brevity could weaken safety or correctness.
- Added compact structured reviewer findings that preserve severity, evidence, expected/observed behavior, impact, correction and verification method while removing repeated narrative.
- Updated installers, uninstallers, verification and CI for eleven governance commands and mandatory v1.7 output-efficiency/metrics markers.
- Preserved v1.6 context routing/resume, requirement provenance, reviewer independence, three-cycle limits, provider/model agnosticism and explicit push authorization.
- Added no external runtime dependency.

## 1.6.0 - 2026-07-26

- Added reusable `.ai/CONTEXT_INDEX.md` and per-task `CONTEXT_MANIFEST.md` for evidence-driven sparse context routing.
- Added fresh referential role packets under each task `evidence/` directory so agents receive canonical task evidence without inheriting unrelated conversation history.
- Added mandatory `MINIMUM_CHANGE_ASSESSMENT` to implementation-ready plans: reuse existing/native/stdlib/installed capabilities first and prefer the smallest correct, secure and maintainable root-cause change.
- Added stable machine-readable per-task `RUN_STATE.json` checkpoints at governance phase boundaries.
- Added `/ai-resume` for safe recovery after interrupted sessions, crashes, quota exhaustion or restarts; stale review evidence is invalidated when the reviewed target changes.
- Added lazy v1.6 adoption for existing in-progress tasks: missing checkpoint/context artifacts may be reconstructed only from authoritative existing evidence and Git state, never fabricated.
- Added governed `STEERING.md` handling: material mid-task user direction must enter requirement provenance and trigger replanning when it changes the controlling plan.
- Added machine-readable `GOVERNANCE_RESULT` status blocks for task-oriented commands.
- Added optional `.ai/TASK_QUEUE.json` support for dependency-aware milestone task selection without introducing unbounded autonomous loops.
- Preserved reviewer independence, three-cycle limits, provider/model agnosticism, documentation/license governance and explicit push authorization.

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
- Licensed under FSL-1.1-MIT. Each released version becomes available under the MIT License on the second anniversary of its release date.