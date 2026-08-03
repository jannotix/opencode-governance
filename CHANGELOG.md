# Changelog

Dates use `YYYY-MM-DD`.

## Unreleased


## 4.1.0 - 2026-08-03

Security and reliability hardening of the governed role runtime, review
orchestration and Executor command brokerage.

### Executor command broker

- Reject command heads that contain a path separator (`/bin/rm`, `/usr/bin/git`)
  before classification; a path-like head previously bypassed the deny list and
  git allowlist entirely.
- Deny wrapper and privilege-escalation heads (`env`, `sudo`, `xargs`, `nohup`,
  `time`, `strace`, …) that re-execute an arbitrary child.
- Reject absolute interpreter invocations (`/usr/bin/python`, `/bin/bash -c`)
  through the same separator guard.
- Require an explicit git subcommand; a bare `git` no longer falls through to
  allow.

### Review orchestration

- Reviewer output is harvested from the role-process stdout and written through
  the deterministic ingest channel. Reviewer roles are read-only by policy and
  cannot author report files directly.
- Per-role model routing (`--implementation-model`, `--architecture-model`,
  `--final-model`) with an early rejection when the implementation and
  architecture reviewers resolve to the same model family, so Review Chain V4
  independence cannot fail mid-attestation.

### Role runtime

- Route agents of the form `executor-fallback-N` are accepted as matching the
  `executor` role; failover no longer disables every tool call.
- Idempotent re-ingest of an identical report body returns the existing receipt
  instead of failing on divergent metadata timestamps.
- The launcher detects child exit before READY is emitted and fails immediately
  with the real exit code, instead of waiting for the full timeout.
- Child stdout/stderr are redirected to log files, removing a pipe-buffer
  deadlock window when the child emits verbose output before READY.

### Scope

Evidence-root "immutability" is logical (path containment, hash indexing,
effect-policy enforcement), not an OS-level sandbox or external attestation. The
README and module docstrings state this explicitly. The
`LOCAL_INTEGRITY` / `SEMANTIC_STATE_MACHINE_ENFORCED` / `EFFECT_POLICY_EXPERIMENTAL`
assurance declarations remain authoritative.


## 4.0.4 - 2026-08-03

Clean re-cut of 4.0.3 with no behavioural change.


## 4.0.3 - 2026-08-02

Pre-side-effect role transactions, Executor containment and attestation
hardening over 4.0.2.

### Pre-side-effect READY gate

- The plugin emits READY only after validating the launch, plugin and policy
  hashes, tool registry, capability manifest and hook construction; setup
  failures produce a typed NOT_READY record.
- The launcher monitors READY while the child runs and writes a host
  acknowledgement bound to it; no tool effect is permitted before
  acknowledgement.
- Launch single-use is session-scoped: the launch is claimed once per
  process/session and cached in-process; replay from another process or session
  is rejected.
- READY echoes and binds the launch nonce.

### Executor and transport

- The prepared Executor launch is the sole authoritative launch; `finalize`
  revalidates the role-process receipt and consumed launch hash.
- Prompt transport is stdin (`argv_prompt_bytes=0`).
- Executor cwd equals the isolated execution root; reviewers use isolated
  evidence roots.
- Deterministic command classification with an explicit deny list and a
  read-only git allowlist.
- `apply_patch` and `multiedit` path extraction enforces containment for every
  parsed target.

### Attestation

- Hook-generated decision receipts; the real-binary self-test requires a
  positive ALLOW receipt.
- Full READY field validation (launch hash, policy hash, route receipt, OpenCode
  version derived from the binary, process/session identity).
- Non-zero OpenCode exit is a typed `GOVERNED_ROLE_PROCESS_FAILED`.
- `AUTHORITATIVE_ROUTE_RECEIPT_V1` strict schema; arbitrary JSON is rejected on
  the production path.
- Review Chain V4 live-revalidates ingestion and route receipts.
- Transactional report commit with a journal and a single COMMIT marker;
  rollback restores prior committed artifacts.
- Tool capability manifest hash-bound at launch and validated at setup.

### Contracts

`EFFECT_PLUGIN_RUNTIME_READY_GATE_V2`, `GOVERNED_ROLE_LAUNCH_CONTRACT_V3`,
`GOVERNED_ROLE_PROCESS_CONTRACT_V2`, `ROLE_SESSION_CLAIM_CONTRACT_V1`,
`GOVERNED_ROLE_STDIN_TRANSPORT_V1`, `EXECUTOR_COMMAND_BROKER_V1`,
`STRICT_PATCH_PATH_CONTRACT_V1`, `GOVERNED_REVIEW_ORCHESTRATION_V1`,
`AUTHORITATIVE_ROUTE_RECEIPT_V1`, `DETERMINISTIC_ROLE_REPORT_TRANSACTION_V1`,
`REVIEW_CHAIN_ATTESTATION_V4`, `TOOL_CAPABILITY_MANIFEST_V1`.

### Assurance

`LOCAL_INTEGRITY`, `SEMANTIC_STATE_MACHINE_ENFORCED`, `EFFECT_POLICY_EXPERIMENTAL`
until the full hook+process matrix for a version is green; then
`ROLE_EFFECT_ENFORCEMENT_ACTIVE` (still not OS-sandboxed or externally attested).


## 4.0.2 - 2026-08-02

End-to-end role runtime enforcement over 4.0.1.

- Real OpenCode process self-test (plugin-load handshake + tool stream when a
  model is available); `file://` plugin registration in `opencode.json`.
- Positive `EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1` required by governed launchers.
- Dedicated OpenCode child per security role (`GOVERNED_ROLE_PROCESS_CONTRACT_V1`);
  Executor prepare emits Launch V2 with SHA-256 and names the required runner.
- Unknown tools fail closed; `allowed_effects` allowlist enforced.
- Strict git option denylist and `governance-read-git.py` read-only helper.
- Removed runner `install --skip-self-test` auto-heal.
- Launch V2 (hash, nonce, expiry, single-use); report V3 requires a route
  receipt; Review Chain V3.
- OpenCode 1.18.9 real-process evidence.


## 4.0.1 - 2026-08-02

Make 4.0.0 role-effect enforcement installed, runtime-bound, path-safe and
evidence-bound.

- ESM plugin (`index.mjs`) with named export and `tool.execute.before`
  fail-closed hook.
- Atomic install into the config plugins directory with ownership marker, hash
  binding and rollback on self-test failure.
- Runner-owned role context injection (`ACTIVE`, `ROLE`, workspace/repository,
  policy hashes); plugin inert when `ACTIVE≠1`.
- Strict shell classification (no substring allowlists; control operators and
  nested interpreters rejected; Architect allows only exact
  `git -C <repository> …`).
- Canonical path containment (exact registered roots; reject traversal,
  symlinks/reparse, external `.ai`).
- Deterministic report ingestion V2 and Review Chain V2 (strict task_id grammar,
  atomic no-clobber, post-write rehash, candidate/evidence uniformity, family
  collision, chronology checks).


## 4.0.0 - 2026-08-02

Breaking security architecture: role-effect enforcement via an OpenCode plugin.

- `ROLE_EFFECT_ENFORCEMENT_V1` plugin using the documented
  `tool.execute.before` fail-closed hook.
- Per-role effect policy for Architect, Executor and all Reviewer roles.
- Reviewer roles technically read-only; reports enter only via deterministic
  ingestion.
- Review-chain attestation binds role, route, model family, packet, candidate,
  report hash and permission policy.


## 3.8.0 - 2026-08-02

Semantic governance core.

- Canonical `governance-contract.json` and deterministic generator.
- `SEMANTIC_WORKFLOW_STATE_MACHINE_V1` with exact transition validation
  (command, postcondition, artifacts, receipts, owner decisions, attempt
  consumption, lifecycle mode).
- Single semantic authority: `workflow-continuation.py` and
  `governance-authority.py` consume the same generated contract module.
- Complete positive transition matrix tests plus required negatives; generator
  freshness gate.
- OpenCode runtime compatibility probe with fail-closed
  missing/unparsable/incompatible classes.
- Windows Executor transaction scenario manifest and hardening parity hook.
- Local opt-in governance tax metrics (no secrets, no external telemetry).


## 3.7.7 - 2026-08-02

Compatibility and evidence-integrity patch.

- `LEGACY_FORENSIC_BUNDLE_V1_ADAPTER` so evidence-bound recovery can consume the
  original Windows PowerShell forensic archive format.
- Dual strict parsers: canonical V2 and legacy V1 (unknown/ambiguous formats
  fail closed).
- Legacy V1 MANIFEST contract: required `FILES:`, `path<TAB>size<TAB>sha256`,
  size+hash verification, ZIP-slip/symlink rejection.
- Deterministic Governance-only allowlist derivation from ai-before/after,
  current-task and live artifacts.
- Source archive never mutated; temporary canonical adaptation binds original
  archive and manifest SHA-256.


## 3.7.6 - 2026-08-02

Evidence-bound Architect orphan recovery.

- `LEGACY_ARCHITECT_ORPHAN_RECOVERY_CONTRACT_V1` for evidence-bound adoption of
  preserved 3.7.2–3.7.4 transaction journals.
- Recovery decisions: `validate-governance-only`, `adopt-governance-only`,
  `rollback`.
- Forensic evidence bundle with mandatory SHA-256, closed `MANIFEST.txt` and
  ZIP-slip/symlink fail-closed extraction.
- Composite Governance-only proof: Git HEAD/index/status (managed paths
  filtered), workspace inventory drift, dependency hashes and
  `GOVERNANCE_RESULT` evidence.
- `EVIDENCE_BOUND_RECOVERY_RECEIPT_V2` revalidated before the transaction is
  archived.


## 3.7.5 - 2026-08-02

Nested workspace and repository root support.

- `WORKSPACE_REPOSITORY_ROOT_CONTRACT_V1`: distinct workspace root, application
  repository root, exact managed Governance roots and executor worktree roots.
- Repository resolution: explicit dir, unique nested Git root or workspace;
  ambiguous or outside-workspace roots fail closed.
- Project fingerprint excludes only `.git/**` and exact registered Governance
  roots.
- Snapshot and restore of every managed Governance root; partial multi-root
  restore fails closed.
- `PROJECT_STATE_CHANGESETS_DIAGNOSTIC_V1` classifies fingerprint deltas.
- Explicit orphan recovery with content-bound receipt (no auto-adoption).
- Headless permission contract accepts path-bound read-only `git -C` forms.


## 3.7.4 - 2026-08-02

Stdin prompt transport for the Architect runner.

- `ARCHITECT_STDIN_PROMPT_TRANSPORT_V1`: full governed handoff streamed over
  redirected stdin instead of the command line.
- Control arguments stay on argv; the prompt is written as exact UTF-8 (no BOM)
  to stdin then closed.
- Prevents Windows command-line length failures and Unix `ARG_MAX` exposure.
- Transaction journal binds `prompt_transport=stdin`, `argv_prompt_bytes=0`.
- Optional size ceiling via `OPENCODE_GOVERNANCE_PROMPT_MAX_BYTES` (default
  64 MiB).
- Windows and Unix large-handoff regressions (1 KiB–1 MiB), Unicode, early stdin
  close and size-limit paths.


## 3.7.3 - 2026-08-02

Headless Architect permission contract.

- `ARCHITECT_HEADLESS_PERMISSION_CONTRACT_V1` for external transactional
  runners.
- Temporary `OPENCODE_CONFIG_CONTENT` deny-by-default bash overlay (no blanket
  `--auto`, no permanent profile weakening).
- Native tool preference for discovery before shell.
- Precise permission-blocked failure classes (no model fallback; rollback
  `.ai/**`).
- JSONC-safe routing manifest load (source + semantic hashes; never mutates
  installed routing).
- Hardened launcher resolution (single selection; sanitised host/launcher logs).
- Executor permission surface denies `.ai/**` and `.git/**`.
- Approval receipts support content-bound issue/validate via `--project-dir`.


## 3.7.2 - 2026-08-01

Transactional `/ai-resume` for pre-side-effect phases.

- Entry gate extended to `/ai-resume` (pre-side-effect only); post-`IMPLEMENTING`
  resume refused.
- Durable Architect transaction journals with orphan recovery.
- Explicit `TOOL_EXECUTION_ABORTED` failure class; optional inclusion in
  `settings.eligible_failures`; `.ai/**` restored on non-successful exits when
  the project fingerprint is unchanged.
- Windows and Unix abort-during-resume, post-side-effect refusal and orphan
  recovery regressions.


## 3.7.1 - 2026-07-31

- Authority continuation validation aligned with `WORKFLOW_CONTINUATION_GATE_V1`
  (phase-aware; forbids `terminal_reason` on non-terminal phases).
- Accepted receipt schema `opencode-governance.approval-receipt/v1`.
- Single-model install messaging: capability tools require a routing profile.
- Symlink-safe `.ai` snapshot hashing.
- CI narrow to `main`; `contents: read` on verify workflows.
- Memory store of record (SQLite) vs optional `.ai/GOVERNANCE_MEMORY.md`
  projection.


## 3.7.0 - 2026-07-31

- Non-terminal `RUN_STATE.json` requires typed `next_action`.
- Executor promote reverses the applied patch if reverse-check fails.
- Capability uninstall is best-effort without a healthy install.
- Portable Unix backup discovery; Windows installer resolves
  `py` / `python3` / `python`.
- Consolidated CI to verify + hardening + publish-release.


## 3.6.0 - 2026-07-30

- Candidate projections (`workspace`, `staged`, `commit`, `base-diff`) and
  approval receipts.
- Governed local engineering memory, evidence reuse, optional pre-commit receipt
  gate, optional simulation harness.
- Unified capability install into the canonical install / verify-routing /
  uninstall lifecycle with pre-install snapshot rollback.


## 3.4.4 - 2026-07-30

- `WORKFLOW_CONTINUATION_GATE_V1`: deterministic helper that rejects
  `/ai-workflow` completion at intermediate phases.
- `RUN_STATE.json` extended with `top_level_command`, `current_phase`,
  `next_required_phase` and `terminal_reason`.
- `/ai-resume` preserves the original `/ai-workflow` authority instead of
  starting a new lifecycle.
- `ARCHITECT_RUNNER_REQUIRED` fail-closed with complete Windows and Unix handoff
  commands.
- Cross-platform contract tests for all twelve `/ai-*` commands.


## 3.4.3 - 2026-07-30

- Preserved literal `/` characters in normalised OpenCode JSONC so schema and
  provider URLs remain readable.
- Windows and Unix readable-URL serialization regressions.
- Fail-closed release publication checks that verify release metadata.
- Routing verification and uninstall compatibility matrices cleaned and updated.


## 3.4.2 - 2026-07-30

- Enforced the routing JSON type contract in the PowerShell installer and both
  Architect runners.
- Rejected scalar strings where the schema requires arrays.
- Rejected string-encoded integers where the schema requires JSON integers.
- Windows and Unix negative regressions for routing and skill-manifest schema
  parity.


## 3.4.1 - 2026-07-30

- Hardened Context Intelligence governance-state writes against symlink, junction
  and reparse-point traversal.
- Required an explicit terminal retrieval state before context validation passes.
- Rejected skills that declare sections but omit requested sections.
- String-safe JSONC normalisation (URLs and comment markers inside strings
  preserved).
- Routing installation validates the complete replacement profile before
  changing an existing manifest.
- Extended backups to all seven managed tools; original OpenCode configuration
  preserved byte-for-byte.
- Consolidated the previously split changelog into a canonical file.


## 3.4.0 - 2026-07-30

- Bounded iterative context retrieval (`CONTEXT_BUDGET_V1`): max three
  `DISPATCH -> EVALUATE -> REFINE` cycles with explicit terminal states.
- Normalised `SKILL_CAPABILITY_MANIFEST_V1` selection with trust precedence,
  work-class applicability, overlap deduplication and section-level loading.
- External user-local content-addressed summary cache (advisory; never replaces
  primary evidence).
- Context-efficiency metrics (considered/admitted/rejected files, retrieval
  cycles, selected skills, cache results, runtime token data).
- Managed PowerShell, Unix and Python Context Intelligence tools with path-escape
  and malformed-schema fail-closed validation.


## 3.3.4 - 2026-07-30

- `PROJECT_STATE_FINGERPRINT_V1`: content-aware project manifest replacing
  `git status --porcelain` equality.
- Path, entry type, mode/attributes, length, SHA-256 and symlink-target
  fingerprinting for every project entry outside `.ai/**`.
- Fail-closed `PROJECT_STATE_CHANGED` before accepting routed attempts.
- Architect failover support for non-Git directories.
- Windows and Linux regression coverage for dirty tracked, untracked, staged and
  non-Git mutation paths.


## 3.3.3 - 2026-07-29

- Explicit PowerShell 7+ host contract for the Architect runner; Windows
  PowerShell 5.1 stops before project inspection or `.ai/**` mutation.
- Rendered guidance uses `pwsh -NoProfile -File` on Windows.
- Removed stale `$LASTEXITCODE` coupling between child scripts; terminating
  errors propagate directly.


## 3.3.2 - 2026-07-29

- Installed deterministic `architect-attempt.ps1` and `architect-attempt.sh`
  entrypoints.
- `ARCHITECT_RUNNER_ENTRY_GATE` on `ai-init`, `ai-audit`, `ai-discover` and
  `ai-plan`, preventing direct in-process `.ai/**` writes.
- Explicit child and environment markers to prevent recursive runner invocation.
- Conservative uninstall that removes only manifest-managed Architect/Executor
  tools.


## 3.3.1 - 2026-07-29

Windows-first local configuration durability.

- External configuration snapshots with non-secret manifests (relative paths,
  lengths, SHA-256).
- Exact drift detection for added, removed and changed files.
- Fail-closed path validation (overlapping roots and reparse points rejected).
- Safe-update wrapper that gates running processes, executes the updater and
  verifies configuration after exit.
- Quarantine snapshots and automatic pre-update restoration.
- User-scoped `OPENCODE_CONFIG_DIR` persistence without hardcoded personal paths.


## 3.3.0 - 2026-07-29

Executor failover with isolated worktrees.

- Optional work-class-aware Executor failover with hidden, locally configured
  routing aliases (seven public agents preserved).
- Isolated Executor attempts in detached linked Git worktrees.
- Deterministic `select`, `prepare`, `finalize`, `promote` and `discard`
  helpers for Windows and Unix.
- Complete-role restart after eligible failures; failed partial output never
  enters the real worktree.
- Binary-safe patch finalization, frozen-target checks and fail-closed overlap
  detection before promotion.


## 3.2.0 - 2026-07-28

Architect failover.

- Real top-level failover for `/ai-init`, `/ai-audit`, `/ai-discover` and
  `/ai-plan` through cross-platform transactional runners.
- Fresh-process route attempts with model/variant selection, bounded cooldown
  and same-family preference before cross-family fallback.
- Complete `.ai/**` snapshots outside the repository and byte-for-byte
  restoration before every eligible retry.
- Fail-closed protection when source/documentation state changes or restoration
  fails.
- Sticky attempts: primary recovery never interrupts a fallback.


## 3.1.0 - 2026-07-28

Reviewer failover.

- Optional automatic failover for Implementation, Architecture/Security and
  Final Reviewer using hidden native OpenCode subagent aliases.
- Complete-role restart: failed partial output rejected; the fallback reruns
  from the byte-identical packet and frozen target.
- Provider-aware routing that prefers the same model family for provider or
  rate-limit failures.
- Selected-family independence checks with fail-closed
  `MODEL_INDEPENDENCE_CONFLICT`.


## 3.0.2 - 2026-07-28

- Fixed Windows project-local `.ai/**` writes when OpenCode evaluates edit
  targets as normalised absolute paths.
- `/ai-init` `PERMISSION_BOOTSTRAP_PROBE` with create, read-back and delete
  verification before any other governance write.
- `PRODUCT_ARTIFACT_SET_VERIFIED` so v2-to-v3 migration cannot report success
  unless all six canonical product artifacts exist and contain required schema.


## 3.0.1 - 2026-07-28

- Removed the redundant `docs/installation.md`; made the README installation
  section canonical.
- Narrowed `docs/workflow.md` to lifecycle and state-transition semantics.
- CI repository-hygiene checks for stale documentation references and tracked
  temporary/log/diagnostic files.


## 3.0.0 - 2026-07-28

Adaptive product discovery.

- `LIGHT|STANDARD|DEEP` discovery depth for every governed request.
- `/ai-discover` for explicit discovery, refresh and audit workflows.
- Six-file `.ai/product/` definition, decision and completeness layer.
- Governed domain research, constructive challenge and safe user override.
- Independent `DISCOVERY_REVIEW` and Final Reviewer discovery adjudication.
- Vertical milestone and required-capability traceability.
- Separate `PRODUCT_COMPLETENESS_VERDICT` and `RELEASE_VERDICT`.
- Backward-compatible lazy migration from v2 project state.


## 2.0.1 - 2026-07-27

- Fixed the v2.0.0 template/verifier contract mismatch for the canonical
  `EXTERNAL_TOOLING` risk dimension.
- Consolidated public documentation so each guide has one clear responsibility.
- Added the OpenCode community-project non-affiliation notice to README.
- Simplified GitHub Actions by removing assertions already enforced by canonical
  verifiers.


## 2.0.0 - 2026-07-27

Operational Assurance layer.

- Extended Evidence-Driven Verification to runtime behavior, recovery and
  external side-effect boundaries.
- Conditional preview, user-flow, visual-behavior, release-recovery,
  tool/MCP capability and safe-experimentation gates (no production side
  effects).
- Bounded read-only discovery workers for multi-surface tasks.
- Governed skill routing with source, scope, freshness and trust classification.
- `.ai/GOVERNANCE_MEMORY.md` for scoped, evidence-backed, revocable lessons.
- Closed-loop learning, dependency admission and pre-change safepoint contracts.


## 1.8.1 - 2026-07-27

- Fixed the canonical Executor/verifier mismatch for `TASK_RISK_PROFILE`.
- Required Executor to read the authoritative risk profile before
  implementation; prohibited silent risk downgrades.


## 1.8.0 - 2026-07-27

Evidence-Driven Verification.

- `.ai/INSTRUCTION_INDEX.md`, per-task `VERIFICATION_PROFILE.md`,
  `TASK_RISK_PROFILE` and compact verification evidence.
- Authoritative validation-profile discovery, bugfix proof, test-impact mapping,
  contract compatibility, environment fingerprints and dependency-specific
  evidence freshness.
- Dependency delta, generated-artifact, migration, non-functional, flakiness,
  adversarial-input and human-ownership gates.
- Extended resume, dual review and release to invalidate stale dependent
  evidence.


## 1.7.0 - 2026-07-27

- `/ai-metrics` using usage recorded by OpenCode rather than model-generated
  estimates.
- Fail-closed task/role/model attribution and sanitised session-export guidance.
- Adaptive output efficiency and compact structured reviewer findings.


## 1.6.0 - 2026-07-26

Context routing and resume.

- Reusable `.ai/CONTEXT_INDEX.md`, per-task `CONTEXT_MANIFEST.md` and
  referential role packets for sparse context routing.
- `MINIMUM_CHANGE_ASSESSMENT`, machine-readable `RUN_STATE.json`, `/ai-resume`
  and lazy adoption for existing tasks.
- Machine-readable `GOVERNANCE_RESULT` blocks and optional dependency-aware task
  queues.


## 1.5.0 - 2026-07-26

Requirement Provenance.

- Canonical per-task provenance with original request, append-only clarification
  transcript and approved requirements.
- Blocked execution when the requirement trail is missing, inconsistent or
  ambiguous.
- Required Executor, both reviewers and Final Reviewer to use the same canonical
  requirement trail.
- Mandatory `PLAN_DEFECT` when Architect materially misrepresents controlling
  requirements.


## 1.4.0 - 2026-07-26

Project documentation governance.

- `/ai-docs` with documentation scope, distributable-application baseline and
  per-task documentation impact.
- Documentation consistency checks throughout implementation, review and release.
- Explicit license-decision handling; governance never chooses a project license.
- Mandatory clarification of material project decisions.


## 1.3.0 - 2026-07-26

Baseline validation.

- Mandatory adversarial validation of the reusable codebase baseline.
- Independent baseline audits, Final Reviewer adjudication and bounded correction
  cycles.
- Blocked implementation until `BASELINE_VALIDATED`; added `/ai-audit` and lazy
  revalidation.


## 1.2.0 - 2026-07-26

Governance roles and dual review.

- Five configurable governance roles, independent dual review and final finding
  adjudication.
- Reusable architecture/dependency maps, incremental planning and targeted
  verification for large repositories.
- OpenCode Build and Plan overridden with governed behavior.
- Full provider/model IDs required; automatic repair limited to three final-review
  cycles.


## 1.1.0 - 2026-07-25

- Repository baseline and just-in-time task planning.
- `READY_FOR_EXECUTION`, dependency/deployment/history governance, scoped local
  commits and explicit push authorization.
- `/ai-init` and `/ai-release`.


## 1.0.0 - 2026-07-25

Initial release.

- Architect, Executor and Reviewer roles.
- Windows and Unix installers, verification and uninstall scripts.
- FSL-1.1-MIT license; each released version becomes available under the MIT
  License on the second anniversary of its release date.
