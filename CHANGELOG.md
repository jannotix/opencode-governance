# Changelog

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

## Earlier releases

The complete changelog from 1.0.0 through 3.3.2 is preserved at [CHANGELOG-ARCHIVE-1.0.0-3.3.2.md](CHANGELOG-ARCHIVE-1.0.0-3.3.2.md).
