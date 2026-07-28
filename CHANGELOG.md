# Changelog

## 3.1.0 - 2026-07-28

- Added optional automatic failover for Implementation Reviewer, Architecture/Security Reviewer and Final Reviewer using hidden native OpenCode subagent aliases while preserving exactly seven public governance authorities.
- Added complete-role restart semantics: failed partial output is rejected and the fallback reruns from the byte-identical packet and frozen target.
- Added sticky fallback attempts and bounded primary re-entry: a recovered primary never interrupts an active fallback and is reconsidered only on a later invocation after cooldown.
- Added provider-aware routing that prefers the same model family for provider, rate-limit or quota failures and skips a retired or globally unavailable model family.
- Added actual selected-family independence checks, fail-closed `MODEL_INDEPENDENCE_CONFLICT` and explicit role rebalance for conflicting Final Reviewer fallback routes.
- Added validated routing profiles, concrete variant resolution, non-secret routing manifests, exact alias-to-manifest verification and conservative managed-alias uninstall.
- Preserved legacy single-model installation, seven public agents, twelve commands, provider/model agnosticism, reviewer isolation, frozen-target evidence, single-writer execution and all v2/v3 governance contracts.
- Executor and Architect/Build/Plan failover remain intentionally disabled pending their dedicated safe-restart releases.

## 3.0.2 - 2026-07-28

- Fixed Windows project-local `.ai/**` writes when OpenCode evaluates edit targets as normalized absolute paths.
- Preserved deny-by-default editing outside `.ai/**` by rendering portable relative/absolute path patterns instead of enabling broad external-directory access.
- Added `/ai-init` `PERMISSION_BOOTSTRAP_PROBE` with create, read-back and delete verification before any other governance write.
- Added `PRODUCT_ARTIFACT_SET_VERIFIED` so v2-to-v3 migration cannot report success unless all six canonical product artifacts exist, are readable and contain required schema metadata.
- Strengthened Windows and Unix verifiers with positive and negative portable-path cases while preserving seven agents, twelve commands, provider/model agnosticism and all v2/v3 governance contracts.
- No application-source permission, provider routing, dependency, automatic external action or public command surface changed.

## 3.0.1 - 2026-07-28

- Removed the redundant `docs/installation.md` file and made the README installation section canonical.
- Narrowed `docs/workflow.md` to lifecycle and state-transition semantics instead of repeating command and role documentation.
- Added CI repository-hygiene checks for stale documentation references and tracked temporary, log or diagnostic files.
- Preserved all executable verification scripts, seven-agent/twelve-command contracts, provider/model agnosticism and public Git history.
- No governance behavior, model routing, permissions, runtime dependency or external-action policy changed.

## 3.0.0 - 2026-07-28

- Added adaptive product discovery with `LIGHT|STANDARD|DEEP` depth for every governed request.
- Added `/ai-discover` for explicit discovery, refresh and audit workflows.
- Added the six-file `.ai/product/` definition, decision and completeness layer.
- Added governed domain research, constructive challenge, guided decisions and safe user override.
- Added independent `DISCOVERY_REVIEW` and Final Reviewer discovery adjudication.
- Added vertical milestone and required-capability traceability without reducing complete-product requests to a default MVP.
- Added separate `PRODUCT_COMPLETENESS_VERDICT` and `RELEASE_VERDICT`.
- Added backward-compatible lazy migration from v2 project state without rewriting history or fabricating requirements.
- Preserved seven agents, single-writer execution, reviewer independence, provider/model agnosticism, Evidence-Driven Verification, Operational Assurance, explicit external-action authorization and no new mandatory runtime dependency.

## 2.0.1 - 2026-07-27

- Fixed the v2.0.0 template/verifier contract mismatch for the canonical `EXTERNAL_TOOLING` risk dimension in Executor, Implementation Reviewer, Architecture/Security Reviewer and Final Reviewer.
- Kept `scripts/verify.ps1` and `scripts/verify.sh` strict; the fix makes the agent contracts explicit instead of weakening verification.
- Consolidated public documentation so README and workflow remain concise while context/resume, Evidence-Driven Verification, Operational Assurance and permissions each have a single clear responsibility.
- Added the OpenCode community-project non-affiliation notice to README.
- Simplified GitHub Actions by removing assertions already enforced by the canonical verifiers and added direct shell/PowerShell syntax validation.
- No provider/model routing, authentication, command/agent count, governance semantics or mandatory dependency requirements changed.

## 2.0.0 - 2026-07-27

- Added **Operational Assurance** as the v2 governance layer, extending Evidence-Driven Verification from code/test evidence to realistic runtime behavior, recovery and external side-effect boundaries without adding a new governance agent, slash command or mandatory runtime dependency.
- Added conditional `PREVIEW_ENVIRONMENT_GATE`, `USER_FLOW_VERIFICATION`, `VISUAL_BEHAVIOR_GATE`, `RELEASE_RECOVERY_PROOF`, `TOOL_CAPABILITY_PROFILE` with `MCP_CAPABILITY_ASSESSMENT`, and `SAFE_EXPERIMENTATION`; these gates reuse existing/approved project mechanisms and never silently provision production infrastructure, use production data/credentials, widen permissions, deploy, rollback, push or merge.
- Added bounded `READ_ONLY_DISCOVERY_SWARM` for materially multi-surface tasks using OpenCode read-only `Explore` and `Scout`; writable `General` is intentionally excluded from governance discovery, workers are isolated from sibling conclusions and their summaries remain non-authoritative routing evidence until verified against primary sources.
- Added `GOVERNED_SKILL_ROUTING` using task-relevant OpenCode/project skills indexed in `.ai/INSTRUCTION_INDEX.md` with source/ID, scope/trigger, freshness and trust classification `PROJECT_AUTHORITATIVE|PROJECT_ADVISORY|WORKSPACE_ADVISORY|EXTERNAL_UNTRUSTED`; skill content never outranks canonical Requirement Provenance or silently authorizes side effects.
- Added `.ai/GOVERNANCE_MEMORY.md` for narrowly scoped, evidence-backed reusable lessons with `stale_when` and `ACTIVE|STALE|REVOKED`; memory is advisory routing evidence, never a waiver, and completed historical tasks are not retroactively given fabricated memory.
- Added `CLOSED_LOOP_LEARNING` for proven escaped/repeated defects, validation gaps, scoped false-positive rationales, recovery lessons and tooling constraints. Reviewers challenge candidate learning independently and only Final Reviewer `MEMORY_DECISION: APPROVE` permits Architect to persist the exact validated lesson.
- Added `DEPENDENCY_ADMISSION_GATE` before new direct dependency installation with exact package/source/version, existing-capability necessity, identity/existence and available maintenance/compatibility/security/license evidence; suspected typo/slopsquat, unverifiable identity, `REJECT` or unresolved `HUMAN_DECISION` cannot be silently installed.
- Added `PRE_CHANGE_SAFEPOINT` before required high-risk destructive/migration/deployment-state mutations, capturing non-secret recoverable Git/worktree/schema/config/artifact plus required existing backup/recovery references before mutation; resume/release never fabricate a historical safepoint.
- Extended evidence freshness, `/ai-resume`, independent dual review and `/ai-release` across selected skills, governance memory, dependency admission, safepoints, preview/runtime targets, tool/MCP capabilities, recovery inputs and experimentation boundaries while invalidating only dependent evidence.
- Updated all seven agent templates, the existing eleven commands, Windows/Unix installers, strict verifiers and public documentation while preserving Requirement Provenance, validated baseline/context routing, single-writer Executor, reviewer independence, Final Reviewer control, Evidence-Driven Verification, adaptive output efficiency, real-usage metrics, three-cycle limits, provider/model agnosticism and explicit push authorization.

## 1.8.1 - 2026-07-27

- Fixed the canonical v1.8 Executor/verifier mismatch that caused `scripts/verify.ps1` and `scripts/verify.sh` to fail because `TASK_RISK_PROFILE` was required by the verifier but not explicitly referenced by `templates/agents/executor.md`.
- Executor now explicitly reads `TASK_RISK_PROFILE` from `VERIFICATION_PROFILE.md` before implementation and treats its `NONE|LOW|HIGH` classifications as controlling inputs for required/conditional evidence gates.
- Executor may not silently downgrade or reinterpret Architect risk classifications; contradictory primary evidence must return `PLAN_CONFLICT` or an evidence blocker for Architect re-evaluation.
- Kept the verifier strict rather than weakening the v1.8 Evidence-Driven Verification contract.
- No provider/model routing, command surface, authentication, Evidence-Driven gate semantics or external dependency requirements changed.

## 1.8.0 - 2026-07-27

- Added a single **Evidence-Driven Verification** layer around the existing governance workflow; no new governance agent or external runtime dependency was introduced.
- Added reusable `.ai/INSTRUCTION_INDEX.md` to map repository-local instruction sources, path scope, precedence/specificity and unresolved instruction conflicts separately from code/context routing.
- Added per-task `VERIFICATION_PROFILE.md` with `TASK_RISK_PROFILE` (`NONE|LOW|HIGH`) for security, data migration, public contract, dependency, deployment, performance, generated artifact, destructive action, input validation, test reliability and human ownership risk.
- Added per-task `evidence/VERIFICATION_EVIDENCE.md` as the single compact result surface for deterministic validation evidence instead of creating one governance artifact per gate.
- Added authoritative `VALIDATION_PROFILE`/CI-parity discovery from existing repository commands/tooling; governance never installs a verifier or invents thresholds merely to satisfy a gate.
- Added `BUGFIX_PROOF` with reproducible pre-fix failure/post-fix pass when technically possible, optional bounded negative control for critical fixes and honest characterization when reproduction is unavailable.
- Added `TEST_IMPACT_MAP` for changed-path to direct/dependent/integration-test mapping while preserving authoritative CI/high-risk full-suite requirements.
- Added `CONTRACT_COMPATIBILITY` for affected public API/schema/library/CLI/config/event contracts, including explicit authorization requirement for breaking changes.
- Added non-secret `ENVIRONMENT_FINGERPRINT` and dependency-specific evidence freshness so source, contract, lockfile, generator, migration, environment/toolchain or validation-config changes invalidate only dependent evidence/reviews.
- Added `DEPENDENCY_DELTA`, `GENERATED_ARTIFACT_GATE` and `MIGRATION_PROOF`; scanners remain evidence rather than proof, dependencies are never auto-fixed, and irreversible migrations require approved backup/forward-recovery evidence.
- Added conditional `NON_FUNCTIONAL_BUDGETS`, `FLAKINESS_EVIDENCE`, `ADVERSARIAL_INPUT_VALIDATION` and `CODEOWNERS_HUMAN_GATE` using only authoritative project capabilities/policies when applicable.
- Added stable `EVIDENCE_STATUS: COMPLETE|PARTIAL|BLOCKED|N/A` to task-oriented governance results.
- Extended `/ai-resume`, dual review and `/ai-release` to invalidate stale dependent evidence and prevent PASS/production readiness from relying on unavailable, stale or failed required proof.
- Updated installers, verification scripts and public documentation for v1.8 while preserving context routing/resume, requirement provenance, adaptive output efficiency, usage telemetry, reviewer independence, three-cycle limits, provider/model agnosticism and explicit push authorization.

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
- Licensed under FSL-1.1-MIT. Each released version becomes available under the MIT License on the second anniversary of its release date. See [LICENSE](LICENSE).
