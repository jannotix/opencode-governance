# Local Configuration Durability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Windows-first, fail-closed protection that preserves a user's complete OpenCode configuration across desktop application updates.

**Architecture:** A reusable PowerShell snapshot engine owns path validation, hashing, verification and exact restore. A separate safe-update wrapper owns process gating, updater execution, drift quarantine, automatic restore and governance verification. Recovery data stays outside the configuration directory and outside the repository.

**Tech Stack:** PowerShell 7/Windows PowerShell-compatible syntax where possible, SHA-256, JSON manifests, GitHub Actions `windows-latest`.

## Global Constraints

- Release version is `3.3.1 — Local Configuration Durability`.
- No provider, model, credential, token or personal path is tracked.
- No updater executable or update channel is inferred.
- The durability root must not overlap the OpenCode configuration directory.
- Reparse points fail closed.
- Existing Governance 3.3.0 routing and failover behavior remains unchanged.
- No automatic push, merge, deployment or production action is introduced.

---

### Task 1: Snapshot engine

**Files:**
- Create: `scripts/config-durability.ps1`
- Test: `.github/workflows/verify-v331.yml`

**Interfaces:**
- Consumes: `ConfigDir`, optional `DurabilityRoot`, action and optional `SnapshotId`.
- Produces: result object with `action`, `config_dir`, `durability_root`, `snapshot_id`, `match`, `added`, `removed`, `changed`.

- [ ] **Step 1: Add failing CI cases**

Create fixture configuration with nested files, a secret marker, excluded `backups` content and an external unrelated file. Assert snapshot, unchanged verification, drift detection, secret-free manifest, overlap rejection and reparse-point rejection.

- [ ] **Step 2: Validate expected failure**

Run the new Windows workflow before the script exists. Expected: PowerShell parse/execution failure because `scripts/config-durability.ps1` is missing.

- [ ] **Step 3: Implement minimal snapshot engine**

Implement `Enable`, `Snapshot`, `Verify`, `Restore` and `Status`; canonicalize paths; reject overlap/reparse points; hash all protected regular files; exclude top-level `backups` and `.durability`; store content only in local snapshots; output JSON by default and objects with `-PassThru`.

- [ ] **Step 4: Run CI**

Expected: all snapshot-engine cases pass on `windows-latest`.

- [ ] **Step 5: Commit**

```bash
git add scripts/config-durability.ps1 .github/workflows/verify-v331.yml
git commit -m "feat: add local configuration snapshots"
```

### Task 2: Safe updater wrapper

**Files:**
- Create: `scripts/update-opencode-safely.ps1`
- Modify: `.github/workflows/verify-v331.yml`

**Interfaces:**
- Consumes: explicit `UpdateExecutable`, `UpdateArguments`, optional process names and restore policy.
- Produces: result object with update exit code, snapshot/quarantine IDs, drift state, restore state and governance verification state.

- [ ] **Step 1: Add failing updater tests**

Use mock PowerShell updater scripts that mutate configuration and either return `0` or non-zero. Assert both paths quarantine and restore drift, updater failure remains failure, and an unchanged successful updater leaves the configuration untouched.

- [ ] **Step 2: Validate expected failure**

Expected: workflow fails because `scripts/update-opencode-safely.ps1` is missing.

- [ ] **Step 3: Implement safe wrapper**

Call the snapshot engine with `-PassThru`, gate running OpenCode processes, create pre-update snapshot, execute the exact owner-supplied executable/arguments, verify, quarantine drift, restore by default, re-verify, run governance verifiers when present, and return failure for a failed updater after recovery.

- [ ] **Step 4: Run CI**

Expected: success, drift recovery and failed-updater recovery cases pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/update-opencode-safely.ps1 .github/workflows/verify-v331.yml
git commit -m "feat: add safe OpenCode update wrapper"
```

### Task 3: Release documentation

**Files:**
- Create: `docs/local-configuration-durability.md`
- Create: `VERSION`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `.github/workflows/verify-v331.yml`

**Interfaces:**
- Consumes: implemented command syntax.
- Produces: canonical user instructions and release identity.

- [ ] **Step 1: Add documentation assertions**

Assert `VERSION` equals `3.3.1`, README identifies the current release, changelog starts with 3.3.1 and no commercial provider/model identifiers appear in the new files.

- [ ] **Step 2: Write documentation**

Document enable, snapshot, verify, restore and safe-update commands; distinguish configuration preservation from application compatibility; state that automatic vendor updates are not intercepted.

- [ ] **Step 3: Run all workflows**

Expected: existing Governance and Executor workflows plus the new 3.3.1 workflow pass.

- [ ] **Step 4: Commit**

```bash
git add VERSION README.md CHANGELOG.md docs/local-configuration-durability.md .github/workflows/verify-v331.yml
git commit -m "release: OpenCode Governance 3.3.1"
```

### Task 4: Integration

**Files:**
- Review all changed files.

- [ ] **Step 1: Open pull request**

Target `main`; summarize scope, fail-closed behavior, security boundaries and verification.

- [ ] **Step 2: Verify final head**

Require `Verify governance`, `Verify Executor failover v3.3` and `Verify Local Configuration Durability v3.3.1` to complete successfully.

- [ ] **Step 3: Squash merge**

Merge only with the expected final head SHA.

- [ ] **Step 4: Verify published main**

Confirm PR merged, `VERSION`, README and changelog show 3.3.1, and the two new PowerShell scripts exist on `main`.
