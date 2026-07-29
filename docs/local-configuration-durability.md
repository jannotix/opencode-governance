# Local Configuration Durability

OpenCode Governance 3.3.1 adds Windows-first tooling that preserves the external OpenCode configuration directory when the desktop application is updated through an owner-triggered command.

The tooling does not modify or intercept the vendor updater. It wraps an explicit update executable selected by the owner.

## What is protected

All regular files under the resolved OpenCode configuration directory are protected recursively, including future customization surfaces not known to this repository.

The following top-level directories are excluded:

```text
backups
.durability
```

Reparse points are rejected instead of followed. The durability store must be outside the configuration directory.

## Default paths

Configuration directory resolution:

1. explicit `-ConfigDir`;
2. `OPENCODE_CONFIG_DIR`;
3. `~/.config/opencode`.

Default durability store on Windows:

```text
%LOCALAPPDATA%\OpenCodeGovernance\config-durability
```

The durability store contains local snapshots, non-secret manifests and quarantined post-update state. It must not be committed.

## Enable durability

Run from the Governance repository:

```powershell
.\scripts\config-durability.ps1 `
  -Action Enable `
  -ConfigDir "C:\path\to\opencode-config"
```

`Enable` persists the exact configuration directory as the user-scoped `OPENCODE_CONFIG_DIR` and creates an initial snapshot.

## Snapshot

```powershell
.\scripts\config-durability.ps1 `
  -Action Snapshot `
  -ConfigDir "C:\path\to\opencode-config"
```

The result includes the snapshot identifier. The manifest records only relative paths, lengths and SHA-256 hashes. It never contains configuration file contents.

## Verify

Verify the latest snapshot:

```powershell
.\scripts\config-durability.ps1 `
  -Action Verify `
  -ConfigDir "C:\path\to\opencode-config"
```

Verify a specific snapshot:

```powershell
.\scripts\config-durability.ps1 `
  -Action Verify `
  -ConfigDir "C:\path\to\opencode-config" `
  -SnapshotId "<snapshot-id>"
```

The result reports added, removed and changed relative paths without printing file contents.

## Restore

```powershell
.\scripts\config-durability.ps1 `
  -Action Restore `
  -ConfigDir "C:\path\to\opencode-config" `
  -SnapshotId "<snapshot-id>"
```

Restore is exact for the protected set:

- files added after the snapshot are removed;
- missing files are restored;
- changed files are replaced;
- excluded recovery directories remain untouched;
- post-restore verification must pass.

## Update OpenCode safely

Supply the exact updater executable and arguments that would otherwise be run manually:

```powershell
.\scripts\update-opencode-safely.ps1 `
  -ConfigDir "C:\path\to\opencode-config" `
  -UpdateExecutable "<updater-executable>" `
  -UpdateArguments @("<argument-1>", "<argument-2>")
```

The wrapper:

1. persists the explicit configuration directory unless disabled;
2. refuses to continue while configured OpenCode processes are running unless `-StopRunningOpenCode` is supplied;
3. creates a pre-update snapshot;
4. runs only the supplied executable and argument vector;
5. verifies the complete protected configuration after the updater exits;
6. creates a quarantine snapshot when drift exists;
7. restores the pre-update snapshot by default;
8. verifies the restored state;
9. runs Governance verification scripts when available.

A failed updater does not bypass recovery. Configuration drift is still quarantined and restored before the wrapper reports the updater failure.

## Important boundaries

- Configuration preservation does not prove that an older configuration schema is compatible with a newer OpenCode release.
- Automatic vendor updates are not intercepted. Use the wrapper for updates where byte-for-byte preservation is required.
- `-NoAutomaticRestore` leaves detected drift in place and returns failure after creating quarantine evidence.
- Credentials may exist inside local snapshot files. Keep the durability store private and never upload it.
- No provider, model, credential or private routing profile is stored in this repository.
- No push, merge, deployment or production action is performed by these scripts.
