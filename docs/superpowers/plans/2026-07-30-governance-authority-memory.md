# Governance Authority and Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the complete 3.4.5 → 3.5.0 → 3.6.0 roadmap as a tested 3.6.0 runtime overlay for OpenCode Governance 3.4.4.

**Architecture:** Keep the established routing and seven public authorities unchanged. Add five standard-library Python tools with a separate exact managed-tool and managed-section manifest, then inject idempotent policy sections into installed agents and commands through cross-platform wrappers.

**Tech Stack:** Python 3 standard library, SQLite, Git CLI, loopback HTTP, Bash, PowerShell 7, GitHub Actions.

## Global Constraints

- Preserve local providers, models, variants, fallbacks, work classes and reviewer independence.
- Do not add public governance agents.
- Do not install dependencies or external services.
- Do not authorize push, merge, deployment, publication or production rollback from a task receipt.
- Primary repository evidence and requirement provenance always outrank cache, memory and summaries.

---

### Task 1: Deterministic authority and continuation

**Files:**
- Create: `scripts/governance-authority.py`
- Test: `tests/test-governance-authority-memory.py`

**Interfaces:**
- Produces candidate `freeze`, receipt `issue|validate`, continuation `validate` and lens `derive` commands.

- [x] Write failing projection, receipt-drift, model-family and continuation tests.
- [x] Verify tests fail while the command is absent.
- [x] Implement exact workspace, staged, commit and base-diff identities.
- [x] Implement content-bound approval receipts and live-gate validation.
- [x] Implement typed actionable continuation and risk-derived lens matrices.
- [x] Run the focused tests to green.

### Task 2: Governed engineering memory

**Files:**
- Create: `scripts/governance-memory.py`
- Test: `tests/test-governance-authority-memory.py`

**Interfaces:**
- Produces `init`, `propose`, `adjudicate`, `search`, `get`, `review-due` and `promote-policy` commands.

- [x] Write failing authority, progressive-disclosure, supersession and promotion tests.
- [x] Implement local SQLite WAL storage.
- [x] Keep new lessons non-authoritative until Final Reviewer adjudication.
- [x] Add topic revision, supersession and review lifecycle.
- [x] Require recurring validated tasks and owner authorization for policy promotion.
- [x] Run focused tests to green.

### Task 3: Exact evidence reuse

**Files:**
- Create: `scripts/governance-evidence.py`
- Test: `tests/test-governance-authority-memory.py`

**Interfaces:**
- Produces evidence `record` and `validate` commands keyed by complete dependency maps.

- [x] Write failing reuse and stale-dependency tests.
- [x] Implement immutable record hashes and exact dependency matching.
- [x] Reject non-PASS evidence and any dependency delta.
- [x] Run focused tests to green.

### Task 4: Deterministic simulation contracts and loopback runner

**Files:**
- Create: `scripts/governance-simulation.py`
- Test: `tests/test-governance-authority-memory.py`
- Test: `tests/test-governance-simulation-fixture.py`
- Test: `tests/test-governance-simulation-run.py`

**Interfaces:**
- Produces scenario `validate` and OpenCode process `run` commands.

- [x] Write failing command-coverage and forbidden-action tests.
- [x] Implement deterministic scenario validation and terminal-marker contracts.
- [x] Implement loopback OpenAI-compatible scripted model hosting.
- [x] Launch an isolated supplied OpenCode binary with a generated fixture provider configuration.
- [x] Reject automatic push, merge, deployment and production rollback.
- [x] Exercise the complete hosting protocol without API keys or paid tokens on Linux and Windows.

### Task 5: Staged pre-commit receipt gate

**Files:**
- Create: `scripts/governance-pre-commit.py`
- Test: `tests/test-governance-pre-commit.py`

**Interfaces:**
- Produces project-scoped `install`, `arm`, `validate` and `uninstall` commands.

- [x] Preserve existing Git hook content and make repeated installation idempotent.
- [x] Accept only receipts under project-root `.ai/**` with the `staged` projection.
- [x] Revalidate the exact index without invoking a model.
- [x] Block commit after any staged-byte change.
- [x] Remove only the managed hook block and pointer.

### Task 6: Transactional runtime overlay installation

**Files:**
- Create: `scripts/governance-runtime-install.py`
- Create: `scripts/install-v360.sh`
- Create: `scripts/install-v360.ps1`
- Create: `scripts/uninstall-v360.sh`
- Create: `scripts/uninstall-v360.ps1`
- Test: `tests/test-governance-runtime-install.py`

**Interfaces:**
- Produces overlay `install|verify|uninstall` lifecycle and `opencode-governance-runtime.json`.

- [x] Write failing installer lifecycle tests.
- [x] Implement backups, exact tool hashing and idempotent prompt injection.
- [x] Bind every managed prompt section by exact SHA-256.
- [x] Roll back all post-mutation failures byte-for-byte.
- [x] Project the exact external memory database path into installed agents.
- [x] Implement conservative uninstall that preserves unrelated local tools and content.
- [x] Add canonical Windows and Unix wrappers around the existing base installer.

### Task 7: Cross-platform CI and release documentation

**Files:**
- Create: `.github/workflows/verify-v360.yml`
- Create: `docs/governance-authority-memory.md`
- Create: `docs/releases/3.6.0.md`
- Create: `docs/testing-v360.md`

**Interfaces:**
- Produces Linux and Windows release-blocking verification and final 3.6.0 overlay documentation while preserving base `VERSION=3.4.4`.

- [x] Add Python compile, shell parse and PowerShell parse gates.
- [x] Run authority, memory, evidence, pre-commit, simulation and installer tests on both platforms.
- [x] Rerun every established 3.3/3.4 repository workflow.
- [x] Add user-facing installation, architecture, staged-gate and simulation documentation.
- [x] Preserve routing-compatible base version metadata and publish overlay release notes separately.
- [x] Require all repository workflows to pass before merge.
