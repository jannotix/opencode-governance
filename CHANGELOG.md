# Changelog

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

The complete changelog from 1.0.0 through 3.3.2 is preserved at [docs/releases/CHANGELOG-1.0.0-3.3.2.md](docs/releases/CHANGELOG-1.0.0-3.3.2.md).
