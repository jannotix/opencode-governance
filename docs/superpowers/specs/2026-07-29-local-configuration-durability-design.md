# OpenCode Governance 3.3.1 — Local Configuration Durability

**Status:** Approved for implementation  
**Date:** 2026-07-29  
**Base:** OpenCode Governance 3.3.0  
**Target:** 3.3.1

## Purpose

Protect a user's persistent OpenCode configuration when updating or reinstalling the Windows desktop application. The repository cannot control the OpenCode updater, so the supported protection is an explicit fail-closed wrapper that snapshots the external configuration directory, runs an owner-selected updater command, verifies the configuration byte-for-byte and restores it when drift is detected.

## Scope

Version 3.3.1 adds Windows PowerShell tooling and documentation. It does not modify OpenCode binaries, disable vendor security updates, choose an update channel, hardcode an installation path or store a user's providers, models, credentials or private routing profile in the repository.

The protected configuration defaults to `OPENCODE_CONFIG_DIR` when set and otherwise to the platform-equivalent of `~/.config/opencode`. The durability store defaults to a separate user-local directory outside the configuration tree.

## Components

### `scripts/config-durability.ps1`

Provides five deterministic actions:

- `Enable`: persist `OPENCODE_CONFIG_DIR` at user scope and create an initial snapshot;
- `Snapshot`: create an immutable local snapshot plus a non-secret manifest;
- `Verify`: compare current protected files with a selected snapshot;
- `Restore`: restore the selected snapshot exactly while leaving excluded backup/state directories untouched;
- `Status`: report the persisted directory, durability root and latest snapshot.

The snapshot manifest records only schema/version metadata, timestamps, normalized relative paths, file lengths and SHA-256 hashes. File contents remain in the local snapshot and are never printed.

### `scripts/update-opencode-safely.ps1`

Runs an explicit update executable and argument vector supplied by the owner. It:

1. resolves and optionally persists the configuration directory;
2. refuses overlapping configuration/durability roots and reparse points;
3. refuses to continue while configured OpenCode processes are running unless explicit stop authorization is supplied;
4. creates a pre-update snapshot;
5. runs the updater and captures its exit code;
6. verifies the complete protected configuration;
7. snapshots the drifted post-update state to quarantine when drift exists;
8. restores the pre-update snapshot by default;
9. verifies the restored state;
10. runs repository `verify.ps1` and `verify-routing.ps1` when available;
11. emits a concise machine-readable result.

Updater failure never suppresses configuration verification. A failed updater that changed configuration still triggers quarantine and restore before returning failure.

## Protected state

All regular files below the resolved configuration directory are protected recursively, including unknown future customization surfaces. The following top-level directories are excluded to prevent recursion or preservation of transient recovery material:

- `backups`;
- `.durability`.

Reparse points are rejected instead of followed. The durability root must be outside the configuration directory and the configuration directory must be outside the durability root.

## Restore semantics

Restore is exact for the protected set:

- files absent from the snapshot are removed;
- files present in the snapshot are copied back;
- changed files are replaced;
- excluded directories remain untouched;
- a post-restore verification must pass.

Before automatic restore, the drifted post-update configuration is copied to a quarantine snapshot for diagnosis. Restoration does not imply application-version compatibility; it only proves configuration preservation.

## Security

- No API keys, tokens, cookies or file contents are written to manifests or logs.
- Snapshots remain local and outside the public repository.
- No updater command is downloaded or inferred.
- No update runs without an explicit executable supplied by the owner.
- Paths are canonicalized and checked for overlap.
- Reparse points fail closed.
- The wrapper never pushes, merges, deploys or changes production infrastructure.

## Compatibility

The durability feature is Windows-first because it addresses the OpenCode Windows desktop updater. Existing Windows and Unix installation, routing, failover, review and release behavior remains unchanged.

## Verification

CI must prove on Windows that:

- PowerShell scripts parse;
- enable persists a non-default configuration path;
- snapshots exclude configured recovery directories;
- unchanged verification passes;
- additions, deletions and content changes are detected;
- updater-induced drift is quarantined and restored;
- updater failure still restores drift;
- unrelated external files are untouched;
- overlapping roots and reparse points fail closed;
- manifests do not contain fixture secret values;
- repository whitelabel checks remain green.
