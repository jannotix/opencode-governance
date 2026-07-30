# Changelog

All released versions are recorded in this single file. Dates use `YYYY-MM-DD`.

## 3.4.1 - 2026-07-30

- Hardened Context Intelligence governance-state writes against symbolic-link, junction and reparse-point traversal outside the project.
- Required an explicit terminal retrieval state, `CONTEXT_SUFFICIENT` or `BLOCKED_CONTEXT_GAP`, before context validation can pass.
- Rejected skills that declare sections but do not contain every requested section instead of silently selecting an empty section set.
- Added string-safe JSONC normalization so OpenCode configuration values containing URLs, `//` or `/* ... */` remain semantically unchanged during installation.
- Made routing installation fail-safe by validating the complete replacement profile before changing an existing manifest, aliases or managed tools.
- Extended installation backups to all seven managed Architect, Executor and Context Intelligence tools and preserved the original OpenCode configuration byte-for-byte in the persistent backup.
- Aligned PowerShell Architect cooldown validation with Unix and ensured retained attempt logs never retain the private `.ai/**` snapshot.
- Removed superseded internal design/implementation documents and consolidated the previously split changelog into this canonical file.
- Added Windows and Linux regressions for JSONC preservation, invalid-reinstall rollback, complete tool backup, context path safety, section routing and terminal-state validation.
- Preserved every provider/model route, variant, fallback priority, `only_on`, hidden alias, Executor work class, reviewer-independence rule, Local Configuration Durability and no-push/no-deploy contract.

## 3.4.0 - 2026-07-30

- Added bounded iterative context retrieval with deterministic `CONTEXT_BUDGET_V1`, a maximum of three `DISPATCH -> EVALUATE -> REFINE` cycles and explicit `CONTEXT_SUFFICIENT|BLOCKED_CONTEXT_GAP` terminal states.
- Added normalized `SKILL_CAPABILITY_MANIFEST_V1` selection with trust precedence, work-class and technology applicability, overlap/conflict deduplication, section-level loading and exact rejection reasons.
- Added an external user-local content-addressed summary cache keyed by project identity, relative-path hash, source SHA-256, schema, parser and skill context; cache output remains advisory and never replaces current primary evidence.
- Added context-efficiency metrics for considered/admitted/rejected files, retrieval cycles, selected skills, estimated skill tokens, cache results, repeated reads, packet references and runtime token data when available.
- Added managed PowerShell, Unix and Python Context Intelligence tools with path-escape, invalid-task, cache-overlap and malformed-schema fail-closed validation.
- Added Windows and Linux regression coverage for budgets, cycle limits, skill deduplication, cache invalidation, source-content secrecy, installation, verification and conservative uninstall.
- Preserved every provider/model route, variant, fallback priority, `only_on`, hidden alias, Executor work class, reviewer-independence rule, Local Configuration Durability and no-push/no-deploy contract.

## 3.3.4 - 2026-07-30

- Replaced Architect runner `git status --porcelain` equality with `PROJECT_STATE_FINGERPRINT_V1`, a content-aware project manifest that detects changes to files that were already dirty, staged or untracked.
- Added path, entry type, mode/attributes, length, SHA-256 and symlink-target fingerprinting for every project entry outside root `.ai/**`; Git projects additionally bind the state to HEAD, the index and recursive submodule state.
- Added fail-closed `PROJECT_STATE_CHANGED` handling before accepting either failed or successful routed attempts, preventing source or project-documentation mutations from escaping through unchanged Git status classifications.
- Added Architect failover support for non-Git directories while preserving the same `.ai/**` rollback and project-content immutability contract.
- Added Windows and Linux regression coverage for dirty tracked content, existing untracked content, staged replacement, safe non-Git retry and non-Git source mutation.
- Preserved every provider/model route, variant, hidden alias, Executor work class, reviewer-independence rule, Local Configuration Durability and no-push/no-deploy contract.

## 3.3.3 - 2026-07-29

- Added an explicit PowerShell 7+ host contract for `architect-attempt.ps1`; Windows PowerShell 5.1 now stops before project inspection or `.ai/**` mutation with `POWERSHELL_7_REQUIRED`.
- Updated rendered Architect, Build, Plan and command-entry guidance to use `pwsh -NoProfile -File` on Windows.
- Removed stale `$LASTEXITCODE` coupling between PowerShell child scripts in installation, routing verification and uninstall wrappers; terminating errors now propagate directly.
- Added regression coverage with pre-seeded non-zero native exit codes for v3.3.0 compatibility verification, v3.3.3 verification, installation and uninstall.
- Preserved Unix Architect failover, all model/provider routes, hidden aliases, Executor work classes, Local Configuration Durability and no-push/no-deploy contracts.

## 3.3.2 - 2026-07-29

- Fixed `ARCHITECT_RUNNER_UNAVAILABLE` by installing deterministic `architect-attempt.ps1` and `architect-attempt.sh` entrypoints under the active OpenCode configuration directory.
- Added exact managed-tool registration and verification for both Architect transactional runners while preserving all existing Executor helpers and hidden routes.
- Added `ARCHITECT_RUNNER_ENTRY_GATE` to `ai-init`, `ai-audit`, `ai-discover` and `ai-plan`, preventing direct in-process invocation from writing `.ai/**` without the external runner.
- Added the explicit `[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]` child marker and environment marker to prevent recursive runner invocation.
- Preserved complete `.ai/**` rollback before eligible Architect retries and blocked continuation when source/project documentation changes, restoration fails or the error is ineligible.
- Added conservative uninstall support that removes only the four manifest-managed Architect/Executor tools and preserves unrelated local tools.
- Added Windows and Linux regression coverage reproducing the WHMCS failure, verifying same-family fallback, partial-state removal, exact path rendering and local-tool preservation.
- Preserved Local Configuration Durability, Executor isolation, reviewer independence, whitelabel routing and all no-push/no-deploy contracts.

## 3.3.1 - 2026-07-29

- Added Windows-first local configuration durability tooling for owner-triggered OpenCode desktop application updates.
- Added external configuration snapshots with non-secret manifests containing normalized relative paths, file lengths and SHA-256 hashes only.
- Added exact drift detection for added, removed and changed files across the complete protected configuration tree.
- Added fail-closed path validation that rejects overlapping configuration/durability roots and reparse points.
- Added an explicit safe-update wrapper that gates running OpenCode processes, executes only an owner-supplied updater command and verifies configuration after the updater exits.
- Added quarantine snapshots and automatic pre-update restoration when an updater changes configuration, including after updater failure.
- Added user-scoped `OPENCODE_CONFIG_DIR` persistence without hardcoding personal paths in the repository.
- Added Windows CI coverage for snapshot, verification, restore, excluded recovery directories, secret-safe manifests, update drift recovery and failed-updater recovery.
- Preserved all v3.3 Executor isolation, routing, review, commit and external-action contracts; no provider/model configuration or credential is tracked.

## 3.3.0 - 2026-07-29

- Added optional work-class-aware Executor failover with hidden, locally configured routing aliases while preserving exactly seven public governance agents.
- Added isolated Executor attempts in detached linked Git worktrees rooted at the same frozen target and governed by the same canonical execution packet.
- Added deterministic `select`, `prepare`, `finalize`, `promote` and `discard` helpers for Windows and Unix, installed and removed conservatively from the local OpenCode configuration.
- Added complete-role restart after eligible provider/model failures; failed partial output and source changes never enter the real worktree.
- Added binary-safe patch finalization, matching complete-report validation, frozen-target checks, dirty-path fingerprinting and fail-closed overlap or concurrent-change detection before promotion.
- Added Executor fallback filtering by all six governance work classes.
- Preserved Evidence-Driven Verification, Operational Assurance, independent dual review, Final Reviewer adjudication, commit authorization and no automatic push, merge or deployment.
- Kept the repository fully whitelabel: tracked templates, examples and fixtures use synthetic identifiers only; real providers, models, variants, subscriptions and routing preferences remain local untracked configuration.
- Added Windows and Linux CI coverage for installation, uninstall, routing selection, isolated discard, binary promotion, forbidden-path rejection, overlap blocking and same-status dirty-file drift detection.

## 3.2.0 - 2026-07-28

- Added real top-level Architect failover for `/ai-init`, `/ai-audit`, `/ai-discover` and `/ai-plan` through cross-platform transactional runners.
- Added fresh-process route attempts with concrete model/variant selection, bounded cooldown state and same-family provider preference before different-family fallback.
- Added complete `.ai/**` snapshots outside the repository and byte-for-byte restoration before every eligible retry.
- Added fail-closed protection when source or project-documentation state changes, governance restoration fails, the error is ineligible, or no valid route remains.
- Preserved sticky attempts: primary recovery never interrupts an active fallback and is reconsidered only on a later runner invocation after cooldown.
- Explicitly blocked top-level automatic restart of workflow, execution, review and release commands after the implementation/review side-effect boundary.
- Preserved reviewer/final hidden-route failover, legacy single-model installation, seven public agents, twelve commands and all v2/v3 governance contracts.

## 3.1.0 - 2026-07-28

- Added optional automatic failover for Implementation Reviewer, Architecture/Security Reviewer and Final Reviewer using hidden native OpenCode subagent aliases while preserving exactly seven public governance authorities.
- Added complete-role restart semantics: failed partial output is rejected and the fallback reruns from the byte-identical packet and frozen target.
- Added sticky fallback attempts and bounded primary re-entry.
- Added provider-aware routing that prefers the same model family for provider, rate-limit or quota failures and skips a retired or globally unavailable model family.
- Added actual selected-family independence checks, fail-closed `MODEL_INDEPENDENCE_CONFLICT` and explicit role rebalance for conflicting Final Reviewer fallback routes.
- Added validated routing profiles, concrete variant resolution, non-secret routing manifests, exact alias-to-manifest verification and conservative managed-alias uninstall.
- Preserved legacy single-model installation, provider/model agnosticism, reviewer isolation, frozen-target evidence, single-writer execution and all v2/v3 governance contracts.

## 3.0.2 - 2026-07-28

- Fixed Windows project-local `.ai/**` writes when OpenCode evaluates edit targets as normalized absolute paths.
- Preserved deny-by-default editing outside `.ai/**` by rendering portable relative/absolute path patterns instead of enabling broad external-directory access.
- Added `/ai-init` `PERMISSION_BOOTSTRAP_PROBE` with create, read-back and delete verification before any other governance write.
- Added `PRODUCT_ARTIFACT_SET_VERIFIED` so v2-to-v3 migration cannot report success unless all six canonical product artifacts exist, are readable and contain required schema metadata.
- Strengthened Windows and Unix verifiers with positive and negative portable-path cases while preserving all established contracts.

## 3.0.1 - 2026-07-28

- Removed the redundant `docs/installation.md` file and made the README installation section canonical.
- Narrowed `docs/workflow.md` to lifecycle and state-transition semantics instead of repeating command and role documentation.
- Added CI repository-hygiene checks for stale documentation references and tracked temporary, log or diagnostic files.
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
- Kept strict verifiers; the fix makes the agent contracts explicit instead of weakening verification.
- Consolidated public documentation so each guide has one clear responsibility.
- Added the OpenCode community-project non-affiliation notice to README.
- Simplified GitHub Actions by removing assertions already enforced by canonical verifiers and added direct shell/PowerShell syntax validation.

## 2.0.0 - 2026-07-27

- Added Operational Assurance, extending Evidence-Driven Verification from code/test evidence to realistic runtime behavior, recovery and external side-effect boundaries.
- Added conditional preview, user-flow, visual-behavior, release-recovery, tool/MCP capability and safe-experimentation gates without authorizing production side effects.
- Added bounded read-only discovery workers for materially multi-surface tasks.
- Added governed skill routing and `.ai/GOVERNANCE_MEMORY.md` with scoped, evidence-backed, revocable lessons.
- Added closed-loop learning, dependency admission and pre-change safepoint contracts.
- Extended evidence freshness, resume, independent dual review and release checks across these capabilities.
- Preserved Requirement Provenance, validated baseline/context routing, single-writer Executor, reviewer independence, Final Reviewer control, adaptive output efficiency and explicit push authorization.

## 1.8.1 - 2026-07-27

- Fixed the canonical Executor/verifier mismatch for `TASK_RISK_PROFILE`.
- Required Executor to read the authoritative risk profile before implementation and prohibited silent risk downgrades.
- Kept the verifier strict rather than weakening Evidence-Driven Verification.

## 1.8.0 - 2026-07-27

- Added Evidence-Driven Verification around the existing workflow without a new governance agent or mandatory external dependency.
- Added `.ai/INSTRUCTION_INDEX.md`, per-task `VERIFICATION_PROFILE.md`, `TASK_RISK_PROFILE` and compact verification evidence.
- Added authoritative validation-profile discovery, bugfix proof, test-impact mapping, contract compatibility, environment fingerprints and dependency-specific evidence freshness.
- Added dependency delta, generated-artifact, migration, non-functional, flakiness, adversarial-input and human-ownership gates.
- Extended resume, dual review and release to invalidate stale dependent evidence.

## 1.7.0 - 2026-07-27

- Added `/ai-metrics` using usage recorded by OpenCode rather than model-generated estimates.
- Added fail-closed task/role/model attribution and sanitized session-export guidance.
- Added adaptive output efficiency and compact structured reviewer findings.
- Preserved context routing/resume, requirement provenance, reviewer independence, three-cycle limits, provider/model agnosticism and explicit push authorization.

## 1.6.0 - 2026-07-26

- Added reusable `.ai/CONTEXT_INDEX.md`, per-task `CONTEXT_MANIFEST.md` and referential role packets for sparse context routing.
- Added `MINIMUM_CHANGE_ASSESSMENT`, machine-readable `RUN_STATE.json`, `/ai-resume`, lazy adoption for existing tasks and governed `STEERING.md` handling.
- Added machine-readable `GOVERNANCE_RESULT` blocks and optional dependency-aware task queues.
- Preserved reviewer independence, three-cycle limits, provider/model agnosticism and explicit push authorization.

## 1.5.0 - 2026-07-26

- Added canonical per-task Requirement Provenance with original request, append-only clarification transcript and approved requirements.
- Blocked execution when the requirement trail is missing, inconsistent or ambiguous.
- Required Executor, both reviewers and Final Reviewer to use the same canonical requirement trail.
- Added mandatory `PLAN_DEFECT` when Architect materially misrepresents controlling requirements.

## 1.4.0 - 2026-07-26

- Added project documentation governance and `/ai-docs`.
- Added documentation scope, distributable-application documentation baseline and per-task documentation impact.
- Required documentation consistency checks throughout implementation, review and release.
- Added explicit license-decision handling; governance never chooses a project license.
- Added mandatory clarification of material project decisions.

## 1.3.0 - 2026-07-26

- Added mandatory adversarial validation of the reusable codebase baseline.
- Added independent baseline audits, Final Reviewer adjudication and bounded correction cycles.
- Blocked implementation until `BASELINE_VALIDATED` and added `/ai-audit` plus lazy revalidation.
- Preserved incremental analysis for large repositories.

## 1.2.0 - 2026-07-26

- Added five configurable governance roles, independent dual review and final finding adjudication.
- Added reusable architecture/dependency maps, incremental planning and targeted verification for large repositories.
- Overrode OpenCode Build and Plan with governed behavior.
- Required full provider/model IDs and limited automatic repair to three final-review cycles.

## 1.1.0 - 2026-07-25

- Added repository baseline and just-in-time task planning.
- Added `READY_FOR_EXECUTION`, dependency/deployment/history governance, scoped local commits and explicit push authorization.
- Added `/ai-init` and `/ai-release`.

## 1.0.0 - 2026-07-25

- Initial release with Architect, Executor and Reviewer roles.
- Added Windows and Unix installers, verification and uninstall scripts.
- Licensed under FSL-1.1-MIT; each released version becomes available under the MIT License on the second anniversary of its release date.
