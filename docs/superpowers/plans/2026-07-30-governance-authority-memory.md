# Governance Authority and Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the complete 3.4.5 → 3.5.0 → 3.6.0 roadmap as a tested 3.6.0 runtime overlay for OpenCode Governance 3.4.4.

**Architecture:** Keep the established routing and seven public authorities unchanged. Add four standard-library Python tools with a separate exact managed-tool manifest, then inject idempotent policy sections into installed agents and commands through cross-platform wrappers.

**Tech Stack:** Python 3 standard library, SQLite, Git CLI, Bash, PowerShell 7, GitHub Actions.

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

### Task 4: Deterministic simulation contracts

**Files:**
- Create: `scripts/governance-simulation.py`
- Test: `tests/test-governance-authority-memory.py`

**Interfaces:**
- Produces scenario validation with twelve-command coverage and external-action refusal.

- [x] Write failing command-coverage and forbidden-action tests.
- [x] Implement deterministic scenario validation.
- [x] Reject automatic push, merge, deployment and production rollback.
- [x] Run focused tests to green.

### Task 5: Runtime overlay installation

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
- [x] Implement conservative uninstall that preserves unrelated local tools.
- [x] Add canonical Windows and Unix wrappers around the existing base installer.
- [x] Add integrity verification.

### Task 6: Cross-platform CI and release documentation

**Files:**
- Create: `.github/workflows/verify-v360.yml`
- Create: `docs/governance-authority-memory.md`
- Modify: `VERSION`
- Modify: `CHANGELOG.md`
- Modify: `README.md`

**Interfaces:**
- Produces Linux and Windows release-blocking verification and final 3.6.0 documentation.

- [x] Add Python compile, shell parse and PowerShell parse gates.
- [x] Run authority, memory, evidence, simulation and installer tests on both platforms.
- [ ] Add user-facing installation and architecture documentation.
- [ ] Update final version and changelog.
- [ ] Validate all repository workflows and merge only after green status.
