# Changelog

Dates use `YYYY-MM-DD`. Older micro-releases are summarized; see git history for full detail.

## Unreleased


## 4.0.3 - 2026-08-02

Security patch: pre-side-effect role transactions, Executor containment, and
attestation hardening over 4.0.2.

### 4.0.2 defects corrected

- **S-001**: Handshake was post-execution. `governed-role-attempt.py` validated
  the handshake only after `opencode run` terminated, so model/tool activity
  could occur before a missing handshake was discovered. 4.0.3 introduces a
  same-process pre-side-effect READY gate (`EFFECT_PLUGIN_RUNTIME_READY_GATE_V2`)
  with a host acknowledgement that must be present before any tool effect.
- **S-002**: READY was emitted before policy/hook readiness. The plugin now
  validates launch, plugin self-hash, policy hash/schema, tool registry,
  capability manifest and hook construction before emitting READY; setup
  failures produce a typed NOT_READY record instead.
- **S-003**: Launch single-use was per-tool-call, breaking multi-tool sessions.
  Launch single-use is now session-level (`ROLE_SESSION_CLAIM_CONTRACT_V1`):
  the launch is claimed once per process/session and cached in-process.
- **S-004**: The Executor transaction launch was not consumed. The role launcher
  now accepts `--launch-file`/`--expected-launch-sha256`/`--attempt-manifest`
  and treats the prepared launch as the sole authoritative launch;
  `executor-attempt finalize` revalidates the role-process receipt and the
  consumed launch hash.
- **S-005**: Prompt transport regressed to argv. The prompt is now transported
  over stdin (`GOVERNED_ROLE_STDIN_TRANSPORT_V1`); `argv_prompt_bytes=0`.
- **S-006**: The Executor child ran in the real workspace. Executor cwd and
  `--dir` now equal the isolated execution root; reviewers use immutable
  evidence roots.
- **S-007**: Executor shell effects were not safely classified. The
  `EXECUTOR_COMMAND_BROKER_V1` provides deterministic command classes with an
  explicit deny list (rm, npm/yarn/pnpm, docker/kubectl, interpreters,
  git commit/push/reset/clean) and a read-only git allowlist.
- **S-008**: `apply_patch` had no path extraction. `STRICT_PATCH_PATH_CONTRACT_V1`
  parses every file header and enforces containment for all targets; `multiedit`
  validates every edit destination.
- **S-009**: The review workflow was not wired to process launchers.
  `GOVERNED_REVIEW_ORCHESTRATION_V1` is a host-owned operation that starts the
  two independent reviewers and the final reviewer under governed launchers.
- **S-010**: The real OpenCode self-test could false-pass. The self-test now
  requires a hook-generated ALLOW decision receipt; handshake-only is not
  acceptance.
- **S-011**: Handshake validation was incomplete. READY now binds and the
  launcher validates launch hash, policy hash, route receipt, opencode version
  (derived from the binary), process/session identity, and more.
- **S-012**: The handshake nonce was unrelated to the launch nonce. READY now
  echoes and binds the launch nonce.
- **S-013**: Non-zero exit was reported as completion. A non-zero OpenCode exit
  is now a typed `GOVERNED_ROLE_PROCESS_FAILED`.
- **S-014**: Route receipts were not authoritative. `AUTHORITATIVE_ROUTE_RECEIPT_V1`
  is a strict, hash-bound schema; arbitrary JSON is rejected on the production
  path.
- **S-015**: Review Chain V3 did not revalidate its receipts. Review Chain V4
  live-revalidates ingestion and route receipts and records per-role
  revalidation evidence.
- **S-016**: Report commit was not transactional. `DETERMINISTIC_ROLE_REPORT_TRANSACTION_V1`
  stages body/metadata/receipt with a journal and a single COMMIT marker.
- **S-017**: Reviewer evidence isolation was filename-based. Immutable evidence
  roots with closed manifests are now built by the orchestrator.
- **S-018**: Tool capability manifests were not launch-bound.
  `TOOL_CAPABILITY_MANIFEST_V1` is hash-bound at launch and validated at setup.
- **S-019**: Published runtime commands used incorrect argparse ordering. The
  exact top-level `--config-dir` form is now documented and tested.

### Contracts introduced

`EFFECT_PLUGIN_RUNTIME_READY_GATE_V2`, `GOVERNED_ROLE_LAUNCH_CONTRACT_V3`,
`GOVERNED_ROLE_PROCESS_CONTRACT_V2`, `ROLE_SESSION_CLAIM_CONTRACT_V1`,
`GOVERNED_ROLE_STDIN_TRANSPORT_V1`, `EXECUTOR_COMMAND_BROKER_V1`,
`STRICT_PATCH_PATH_CONTRACT_V1`, `GOVERNED_REVIEW_ORCHESTRATION_V1`,
`AUTHORITATIVE_ROUTE_RECEIPT_V1`, `DETERMINISTIC_ROLE_REPORT_TRANSACTION_V1`,
`REVIEW_CHAIN_ATTESTATION_V4`, `TOOL_CAPABILITY_MANIFEST_V1`.

### Assurance

Until the full hook+process matrix for a version: `LOCAL_INTEGRITY`,
`SEMANTIC_STATE_MACHINE_ENFORCED`, `EFFECT_POLICY_EXPERIMENTAL`. After: may
claim `ROLE_EFFECT_ENFORCEMENT_ACTIVE` (not OS-sandboxed / externally attested).


## 4.0.2 - 2026-08-02

Security patch: end-to-end role runtime enforcement (R-001–R-012 over 4.0.1).

### 4.0.1 residuals corrected

- R-001: Real OpenCode process self-test (plugin load handshake + tool stream when model available); `file://` registration in `opencode.json`.
- R-002: Positive `EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1` required by governed launchers (`governed-role-attempt.py` and Architect `run-governed.*` when effect hashes are bound).
- R-003/R-004/R-005: `GOVERNED_ROLE_PROCESS_CONTRACT_V1` via `governed-role-attempt.py` (dedicated OpenCode child per security role); Executor prepare emits Launch V2 + SHA-256 and names `governed-role-attempt.py` as the required runner (no silent skip when helper missing).
- R-006: `STRICT_TOOL_EFFECT_REGISTRY_V1` — unknown tools fail closed; `allowed_effects` allowlist enforced.
- R-007: Strict Git option denylist + `governance-read-git.py` helper.
- R-008: Removed runner `install --skip-self-test` auto-heal.
- R-009/R-010/R-011: Launch V2 (hash/nonce/expiry/single-use, `OPENCODE_GOVERNANCE_LAUNCH_SHA256`); report V3 requires route receipt (receipt-bound, not envelope-only); chain V3.
- R-012: OpenCode 1.18.9 real process evidence (handshake + optional tool hook).

### Assurance

Until full hook+process matrix for a version: `LOCAL_INTEGRITY`, `SEMANTIC_STATE_MACHINE_ENFORCED`, `EFFECT_POLICY_EXPERIMENTAL`.  
After: may claim `ROLE_EFFECT_ENFORCEMENT_ACTIVE` (not OS-sandboxed / externally attested).

## 4.0.1 - 2026-08-02

Security patch: make 4.0.0 role-effect enforcement **installed, runtime-bound, path-safe and evidence-bound**.

### 4.0.0 activation defect (explicit)

4.0.0 shipped `plugins/opencode-governance-effect-enforcement/index.js` and Node-only `_enforce` unit tests, but:

- the installer did **not** copy/activate the plugin into the OpenCode config plugins directory (D-001);
- runners did **not** authoritatively inject `OPENCODE_GOVERNANCE_*` role context (D-002);
- CommonJS export compatibility with OpenCode was unproven (D-003);
- Architect shell allowlisting used substring `includes()` (D-004);
- governance path checks accepted any string containing `.ai` (D-005–D-006);
- report ingestion allowed unsafe `task_id` path construction and weak chain integrity (D-008–D-009);
- assurance over-claimed semantic effect enforcement without install/load evidence (D-010).

### Fixes (4.0.1)

- `ROLE_EFFECT_ENFORCEMENT_V1_1` ESM plugin (`index.mjs`) with named export + `tool.execute.before` fail-closed hook.
- `EFFECT_PLUGIN_INSTALLATION_CONTRACT_V1`: atomic install into `<ConfigDir>/plugins/`, ownership marker, hash binding, unrelated plugin preservation, rollback on self-test failure.
- `EFFECT_PLUGIN_RUNTIME_SELF_TEST_V1` after install; verifier re-runs non-mutating equivalent.
- `GOVERNED_ROLE_LAUNCH_CONTRACT_V1`: `run-governed.ps1` / `run-governed.sh` inject runner-owned role env (`ACTIVE`, `ROLE`, workspace/repository, policy hashes). Plugin inert when `ACTIVE≠1`.
- `STRICT_SHELL_EFFECT_CLASSIFICATION_V1`: no substring allowlists; control operators / nested interpreters → `SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED`; Architect only exact `git -C <repository> …`.
- `CANONICAL_ROLE_PATH_CONTAINMENT_V1`: exact registered governance / execution roots; reject traversal, symlinks/reparse, external `.ai` string tricks.
- `DETERMINISTIC_ROLE_REPORT_INGESTION_V2` + `REVIEW_CHAIN_ATTESTATION_V2`: strict task_id grammar, atomic no-clobber, post-write rehash, candidate/evidence uniformity, family collision, order checks.
- Managed tool: `install-effect-plugin.py`; inventory binds plugin/policy hashes.
- Assurance until full runtime matrix green: `LOCAL_INTEGRITY`, `SEMANTIC_STATE_MACHINE_ENFORCED`, `EFFECT_POLICY_EXPERIMENTAL`. After install+self-test: may claim `ROLE_EFFECT_ENFORCEMENT_ACTIVE` (still not OS-sandboxed / externally attested).

## 4.0.0 - 2026-08-02

- Breaking security architecture: `ROLE_EFFECT_ENFORCEMENT_V1` OpenCode plugin using documented `tool.execute.before` fail-closed hook.
- Per-role effect policy (`governance-spec/effects/role-effect-policy.json`) for Architect, Executor and all Reviewer roles.
- Reviewer/Final Reviewer templates are technically read-only (`edit`/`bash` deny); reports enter only via `DETERMINISTIC_ROLE_REPORT_INGESTION_V1`.
- Review-chain attestation binds role → route → model family → packet → candidate → report hash → permission policy.
- Shell/path containment negatives and sibling-report isolation tests.
- Managed tool: `role-report-ingest.py`.
- **Known defect (corrected in 4.0.1):** plugin was not installed/activated by the product installer; role context was not runner-bound; tests only invoked Node `_enforce` and did not prove OpenCode load. See 4.0.1.

## 3.8.0 - 2026-08-02

- Semantic governance core: canonical `governance-spec/governance-contract.json` and deterministic generator (`scripts/generate-governance-contract.py`).
- `SEMANTIC_WORKFLOW_STATE_MACHINE_V1` replaces shape-only continuation checks with exact transition validation (command, postcondition, artifacts, receipts, owner decisions, attempt consumption, lifecycle mode).
- Single semantic authority: `workflow-continuation.py` and `governance-authority.py` consume the same generated contract module (no independent handwritten phase/command lists).
- Complete positive transition matrix tests plus required negatives; generator freshness gate.
- Honest twelve-command simulation contract and fixtures; partial fixtures may no longer claim complete coverage.
- OpenCode runtime compatibility probe (`OPENCODE_RUNTIME_COMPATIBILITY_CONTRACT_V1`) with fail-closed missing/unparsable/incompatible classes.
- Windows Executor transaction scenario manifest and hardening parity hook for `tests/test-executor-transaction.ps1`.
- Local opt-in governance tax metrics foundation (no secrets, no external telemetry, never approval authority).
- Assurance level declarations (`LOCAL_INTEGRITY`, `SEMANTICALLY_ENFORCED`; no false external/signed claims).
- Neutral FSL-1.1-MIT adoption note (no automatic relicensing).

## 3.7.7 - 2026-08-02

- Compatibility and evidence-integrity patch: `LEGACY_FORENSIC_BUNDLE_V1_ADAPTER` so evidence-bound recovery can consume the original Windows PowerShell forensic archive format produced before the 3.7.6 canonical schema existed.
- Dual strict parsers: `CANONICAL_RECOVERY_EVIDENCE_V2` and `LEGACY_PROJECT_STATE_FORENSICS_V1` (unknown/ambiguous formats fail closed).
- Legacy V1 MANIFEST contract: recognised headers, required `FILES:`, `path<TAB>size<TAB>sha256`, size+hash verification, ZIP-slip / absolute / drive / `..` / symlink rejection; `MANIFEST.txt` may omit itself.
- Legacy TSV inventory parser for collector inventories; deterministic Governance-only allowlist derivation from ai-before/after, current-task, and live artifacts (optional owner allowlist is an additional hash-bound constraint only).
- Temporary canonical adaptation binds original archive and manifest SHA-256; source archive is never mutated; temps deleted after success or failure.
- `EVIDENCE_BOUND_RECOVERY_RECEIPT_V2` extended with `source_evidence_format`, source bundle/manifest hashes, adapter contract, canonicalization receipt, legacy inventory hash, and allowlist derivation evidence.
- Faithful Windows V1 forensic fixture plus expanded validate/adopt lifecycle and negative tests; existing V2 fixture retained.

## 3.7.6 - 2026-08-02

- Security/reliability patch: `LEGACY_ARCHITECT_ORPHAN_RECOVERY_CONTRACT_V1` for evidence-bound adoption of preserved 3.7.2–3.7.4 Architect transaction journals.
- Do not compare legacy single-root fingerprints with 3.7.5+ multi-root fingerprints; require a forensic evidence bundle with mandatory SHA-256, closed `MANIFEST.txt`, and ZIP-slip/symlink fail-closed extraction.
- Recovery decisions: `validate-governance-only` (non-mutating), `adopt-governance-only`, `rollback`.
- Mandatory evidence fields: transaction hash, evidence bundle path/hash, repository HEAD, PLAN/packet/checkpoint hashes, attempt log hashes, exact Governance path allowlist.
- `EVIDENCE_BOUND_RECOVERY_RECEIPT_V2` is written and revalidated before the transaction is archived; archive failure retains the live orphan and fails closed.
- Composite Governance-only proof: Git HEAD/index/status (managed paths filtered), workspace inventory drift, dependency hashes, and `GOVERNANCE_RESULT` evidence.
- Sanitised 3.7.4 migration fixture and Python regressions (positive validate/adopt + negatives for hash/ZIP/source/unrelated `.ai` tamper).

## 3.7.5 - 2026-08-02

- Reliability and transaction-integrity patch for nested workspace / repository layouts: `WORKSPACE_REPOSITORY_ROOT_CONTRACT_V1` and `MULTI_GOVERNANCE_ROOT_TRANSACTION_V1`.
- Distinguishes workspace root, application repository root, exact managed Governance roots (workspace `.ai` and repository `.ai`), executor worktree roots, and transaction evidence roots.
- `-WorkspaceDir` / `-RepositoryDir` (Unix: `--workspace-dir` / `--repository-dir`); `-ProjectDir` remains a compatibility alias for the workspace root.
- Repository resolution order: explicit repository dir → unique nested Git root → workspace when it is Git or a non-Git application root. Multiple nested Git repositories return `REPOSITORY_ROOT_AMBIGUOUS`; roots outside the workspace return `REPOSITORY_ROOT_OUTSIDE_WORKSPACE`.
- Project fingerprint excludes only `.git/**` metadata and exact registered managed Governance roots (not arbitrary nested `.ai` directories).
- Snapshots and restores every managed Governance root; partial multi-root restore fails closed as `MULTI_ROOT_RESTORE_INCOMPLETE` / orphan transaction.
- `PROJECT_STATE_CHANGESET_DIAGNOSTIC_V1` classifies fingerprint deltas (`GOVERNANCE_ONLY_CHANGE`, `APPLICATION_SOURCE_CHANGE`, `GIT_METADATA_CHANGE`, `DEPENDENCY_CHANGE`, `GENERATED_ARTIFACT_CHANGE`, `UNKNOWN_CHANGE`) without printing file contents.
- Explicit orphan recovery: `-RecoverTransaction` with `-RecoveryDecision adopt-governance-only|rollback`, content-bound recovery receipt, no auto-adoption.
- Headless permission contract accepts path-bound read-only `git -C <repository> …` forms; write/mutating Git and broad shell/PowerShell remain denied.
- `/ai-resume` that reaches `READY_FOR_EXECUTION` emits `ARCHITECT_PHASE_ADVANCED` with `NEXT_COMMAND=/ai-execute` and `ATTEMPT_CONSUMED=false`.
- Windows, Unix, and Python nested-workspace regressions.

## 3.7.4 - 2026-08-02

- Reliability patch: `ARCHITECT_STDIN_PROMPT_TRANSPORT_V1` streams the complete governed Architect handoff over redirected stdin instead of the process command line.
- PowerShell and Unix Architect runners keep control arguments on argv (`run`, `--dir`, `--agent`, `--model`, optional `--variant`, `--command`, `--format json`) and write the full prompt as exact UTF-8 (no BOM) to child stdin, then close stdin.
- Prevents Windows `Process.Start` failures of the form “The filename or extension is too long” when owner handoffs exceed the command-line length limit; also avoids Unix `ARG_MAX` / argv-size exposure of the handoff.
- Transaction journal (`ARCHITECT_TRANSACTION_V2`) binds `prompt_transport=stdin`, `prompt_transport_contract=ARCHITECT_STDIN_PROMPT_TRANSPORT_V1`, `arguments_utf8_bytes`, `argv_prompt_bytes=0` without changing the authoritative `arguments_sha256`.
- New fail-closed transport errors: `ARCHITECT_PROMPT_TRANSPORT_FAILED` and `ARCHITECT_PROMPT_SIZE_LIMIT_EXCEEDED` (ineligible for model fallback; restore `.ai/**` when safe; log size and SHA-256 only, never prompt contents).
- Optional safety ceiling via `OPENCODE_GOVERNANCE_PROMPT_MAX_BYTES` (default 64 MiB, minimum configurable floor 1 MiB); fails before child execution and never truncates.
- Windows and Unix large-handoff regressions (1 KiB–1 MiB), Unicode, empty optional arguments, early stdin close, and size-limit paths.

## 3.7.3 - 2026-08-02

- Headless Architect permission contract `ARCHITECT_HEADLESS_PERMISSION_CONTRACT_V1` for external transactional runners.
- Temporary `OPENCODE_CONFIG_CONTENT` deny-by-default bash overlay (no blanket `--auto`, no permanent Architect profile weakening).
- Native tool preference for discovery (`read`/`list`/`glob`/`grep`/LSP/Explore/Scout before shell).
- Precise `ARCHITECT_PERMISSION_BLOCKED` / `HEADLESS_PERMISSION_CONTRACT_VIOLATION` (no model fallback, rollback `.ai/**`).
- JSONC-safe routing manifest load (source + semantic hashes; never mutates installed routing).
- Hardened launcher resolution (single selection; `.ps1`/`.cmd`/exe; sanitised host/launcher logs).
- Real incident regression: permission auto-reject no longer surfaces as false-success/no-progress only.
- Executor permission surface denies `.ai/**` and `.git/**` (portable path forms after install) and denies `git push`.
- Approval receipts support content-bound issue/validate via `--project-dir` (hashes real artifact files; `RECEIPT_ARTIFACT_MISMATCH` on drift).
- Install remains a staged pipeline (`core 3.3.0 → base 3.4.4 → capabilities product version`) because intermediate `verify-routing` contracts require matching tool sets at each layer.

## 3.7.2 - 2026-08-01

- Reliability patch: transactional `/ai-resume` for pre-side-effect phases (`ai-resume` accepted by Architect runners with `RESUME_MODE_V1`).
- `ARCHITECT_RUNNER_ENTRY_GATE` extended to `/ai-resume` (pre-side-effect only); post-`IMPLEMENTING` resume refused with `RESUME_POST_SIDE_EFFECT` (no automatic full `.ai/**` rollback).
- Durable Architect transaction journals (`ARCHITECT_TRANSACTION_V1`) under the OpenCode config directory with orphan recovery (`ARCHITECT_ORPHAN_RECOVERED` / `ARCHITECT_ORPHAN_RECOVERY_BLOCKED`).
- Explicit `TOOL_EXECUTION_ABORTED` failure class; optional inclusion in `settings.eligible_failures`; `.ai/**` restored on non-successful exits when project fingerprint is unchanged.
- Windows and Unix incident regressions for abort-during-resume, post-side-effect refusal and orphan recovery.
- Preserved candidate identity, approval receipts, typed continuation and evidence binding from 3.7.1.

## 3.7.1 - 2026-07-31

- Aligned authority continuation validation with `WORKFLOW_CONTINUATION_GATE_V1` (phase-aware; forbids `terminal_reason` on non-terminal phases).
- Documented and accepted receipt schema `opencode-governance.approval-receipt/v1` with historical alias `GOVERNANCE_APPROVAL_RECEIPT_V1`.
- Honest single-model install messaging: capability tools require a routing profile.
- Symlink-safe `.ai` snapshot hashing in Architect runners.
- Re-attached context-intelligence and project-state-integrity regressions to CI; narrowed verify triggers to `main`; set `contents: read` on verify workflows.
- Lifecycle docs and command templates use one phase vocabulary.
- Clarified memory store of record (SQLite) vs optional `.ai/GOVERNANCE_MEMORY.md` projection.

## 3.7.0 - 2026-07-31

- Non-terminal `RUN_STATE.json` requires typed `next_action`.
- Executor promote reverses the applied patch if reverse-check fails.
- Capability uninstall is best-effort without a healthy install.
- Portable Unix backup discovery; Windows installer resolves `py` / `python3` / `python`.
- Consolidated CI to verify + hardening + publish-release; removed version-sliced workflows.

## 3.6.0 - 2026-07-30

- Candidate projections (`workspace`, `staged`, `commit`, `base-diff`) and approval receipts (`opencode-governance.approval-receipt/v1`).
- Governed local engineering memory, evidence reuse, optional pre-commit receipt gate, optional simulation harness.
- Unified capability install into the canonical install / verify-routing / uninstall lifecycle with pre-install snapshot rollback.

## 3.4.4 - 2026-07-30

- Added `WORKFLOW_CONTINUATION_GATE_V1`, an installed deterministic helper that rejects `/ai-workflow` completion at intermediate phases such as `AUDIT_PASS`, `TASK_VALIDATED` or `PRODUCT_INCOMPLETE`.
- Extended `RUN_STATE.json` with `top_level_command`, `current_phase`, `next_required_phase` and `terminal_reason`; `/ai-resume` preserves the original `/ai-workflow` authority instead of starting a new lifecycle.
- Kept `ARCHITECT_RUNNER_REQUIRED` fail-closed while adding complete Windows and Unix handoff commands with project, command and original arguments.
- Added cross-platform contract tests for all twelve `/ai-*` commands and executable continuation-gate regressions.
- Preserved providers, models, variants, fallback order, priorities, work classes, reviewer independence, authentication and external-action boundaries.

## 3.4.3 - 2026-07-30

- Preserved literal `/` characters in normalized OpenCode JSONC so schema and provider URLs remain readable while comment markers inside strings stay safe.
- Added Windows and Unix regressions for readable URL serialization in addition to semantic JSONC preservation.
- Cleaned duplicated 3.4.2 entries from routing verification and uninstall compatibility matrices and added explicit 3.4.3 support.
- Added fail-closed release publication checks that verify release metadata and repair the incorrectly moved 3.4.1 tag only after confirming its historical commit.
- Preserved every local provider/model route, variant, fallback priority, work class, reviewer-independence rule, authentication and no-push/no-deploy governance contract.

## 3.4.2 - 2026-07-30

- Enforced the same routing JSON type contract in the PowerShell installer and both Architect runners.
- Rejected scalar strings where `enabled_roles`, `eligible_failures`, `fallbacks`, `only_on` or `work_classes` require arrays.
- Rejected string-encoded cooldowns, priorities and skill token estimates where the schema requires JSON integers.
- Added Windows and Unix negative regressions for routing and skill-manifest schema parity.
- Preserved all provider/model routes, variants, fallback priorities, work classes, reviewer independence, durability and external-action contracts.

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
- Added Windows and Linux regression coverage for same-family fallback, partial-state removal, exact path rendering and local-tool preservation.
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
- Preserved sticky attempts: primary recovery never interrupts a fallback and is reconsidered only on a later runner invocation after cooldown.
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
