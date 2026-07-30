# Context Intelligence & Skill Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic bounded retrieval, skill capability routing, content-addressed summary caching and context metrics without external services or routing changes.

**Architecture:** Install one PowerShell and one Unix context-intelligence helper. The helpers share the same JSON contracts, write task controls under `.ai/tasks/<TASK-ID>/`, keep summaries in an external user-local cache and expose deterministic actions for budget initialization, cycle recording, skill selection, cache get/put and metrics recording. Agent and command templates require those contracts but retain primary-evidence authority.

**Tech Stack:** PowerShell 7, Python 3 standard library, Bash wrappers, JSON, Markdown governance templates, GitHub Actions.

## Global Constraints

- Release version is exactly `3.4.0`.
- No network service, vector database or new package dependency.
- Preserve every provider/model route, variant, priority, `only_on`, hidden alias and Executor work class.
- Existing routing manifests `3.3.0`, `3.3.2`, `3.3.3` and `3.3.4` remain verifiable.
- Maximum retrieval cycles is three.
- Cache content remains outside the project and never becomes primary evidence.
- Existing projects are not mass-edited.
- No automatic push, deployment, external publication or cache deletion.

---

### Task 1: Context helper contracts and red tests

**Files:**
- Create: `tests/test-context-intelligence.ps1`
- Create: `tests/test-context-intelligence.py`
- Create: `.github/workflows/verify-v340.yml`
- Create: `scripts/context-intelligence.ps1`
- Create: `scripts/context-intelligence.py`
- Create: `scripts/context-intelligence.sh`

**Interfaces:**
- Produces PowerShell actions: `InitializeBudget`, `RecordCycle`, `SelectSkills`, `CacheGet`, `CachePut`, `RecordMetrics`, `ValidateTask`.
- Produces Python subcommands: `initialize-budget`, `record-cycle`, `select-skills`, `cache-get`, `cache-put`, `record-metrics`, `validate-task`.
- JSON budget schema: `CONTEXT_BUDGET_V1`.
- JSON skill schema: `SKILL_CAPABILITY_MANIFEST_V1`.

- [ ] Write failing Windows and Linux tests for all work-class budgets, invalid task IDs, fourth-cycle rejection, cache hit/miss, skill trust precedence, overlap deduplication and secret/source-content exclusion.
- [ ] Run only the new workflow and confirm failures are caused by missing helpers.
- [ ] Implement the minimum helpers with stdlib-only canonical JSON and SHA-256 keys.
- [ ] Run the new workflow and require Windows and Linux success.

### Task 2: Installer, verifier and uninstall integration

**Files:**
- Modify: `scripts/install.ps1`
- Modify: `scripts/install.sh`
- Modify: `scripts/uninstall.ps1`
- Modify: `scripts/uninstall.sh`
- Modify: `scripts/verify-routing.ps1`
- Modify: `scripts/verify-routing.sh`
- Modify: `.github/workflows/verify-v332.yml`
- Modify: `.github/workflows/verify-v333.yml`

**Interfaces:**
- Installed tools add `context-intelligence.ps1` and `context-intelligence.sh` to `managed_tools`.
- Routing manifest gains `context_intelligence_version: 3.4.0`.
- Current managed tool count becomes six.

- [ ] Extend tests to require six exact managed tools and preserve unrelated local tools.
- [ ] Verify tests fail against the current 3.3.4 installer.
- [ ] Install the two helpers, render exact paths and update manifest version fields without changing routing values.
- [ ] Extend verifiers for 3.4.0 while retaining 3.3.x compatibility.
- [ ] Extend uninstall to remove only the six manifest-managed tools and preserve the external cache.
- [ ] Run installer, verifier and uninstall tests on Windows and Linux.

### Task 3: Governance context and skill-routing contracts

**Files:**
- Modify: `templates/agents/architect.md`
- Modify: `templates/agents/build.md`
- Modify: `templates/agents/plan.md`
- Modify: `templates/agents/executor.md`
- Modify: `templates/commands/ai-init.md`
- Modify: `templates/commands/ai-plan.md`
- Modify: `templates/commands/ai-workflow.md`
- Modify: `templates/commands/ai-resume.md`
- Modify: `templates/commands/ai-metrics.md`
- Modify: `docs/context-efficiency-resume.md`
- Create: `docs/context-intelligence-skill-routing.md`

**Interfaces:**
- Task artifacts: `CONTEXT_BUDGET.json`, `CONTEXT_RETRIEVAL.jsonl`, `SKILL_SELECTION.json`, `CONTEXT_METRICS.jsonl`.
- Terminal states: `CONTEXT_SUFFICIENT`, `BLOCKED_CONTEXT_GAP`.
- Selection records contain accepted and rejected skills with reasons.

- [ ] Add verifier assertions for required 3.4 markers and artifacts.
- [ ] Run verifier tests and confirm marker failures.
- [ ] Add concise native contracts to the relevant templates.
- [ ] Document budgets, cache authority, lazy loading, metrics and migration.
- [ ] Run governance and routing verification.

### Task 4: Release metadata and full regression

**Files:**
- Modify: `VERSION`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `.github/workflows/verify.yml` as required for release markers only.

**Interfaces:**
- Release marker: `3.4.0 — Context Intelligence & Skill Routing`.

- [ ] Update version and changelog with exact preserved contracts.
- [ ] Run the v3.4.0 workflow.
- [ ] Run all existing governance, Durability, Architect runner, PowerShell reliability and Executor failover workflows.
- [ ] Compare the branch with `main` and confirm no routing fixture or model template value changed.
- [ ] Make the PR ready only when every workflow on the final SHA succeeds.
