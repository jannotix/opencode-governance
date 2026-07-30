# Quality Gates & Governed Learning Implementation Plan

> **For agentic workers:** Use superpowers:test-driven-development and verification-before-completion for every task below.

**Goal:** Add deterministic Debug-First, risk-adaptive TDD, AI eval, pre-review self-check and governed learning candidate contracts without weakening independent review or adding external dependencies.

**Architecture:** Install PowerShell, Unix and Python Quality Gate helpers. Helpers create task-scoped JSON proof artifacts and append-only learning events. They validate evidence shape and gate status but never approve implementation, edit Governance Memory or change routing.

**Tech Stack:** PowerShell 7, Python 3 standard library, Bash, JSONL, Markdown templates, GitHub Actions.

## Constraints

- Release exactly `3.5.0`.
- Preserve Architect runner `3.3.4` and Context Intelligence `3.4.0` component versions.
- Ten exact managed tools with routing enabled.
- No network service, database or third-party package.
- No automatic memory promotion, role/model changes, push, deployment or permission expansion.

### Task 1 — Red tests and helper contracts

- [ ] Create `tests/test-quality-gates.py`, `tests/test-quality-gates.ps1` and `.github/workflows/verify-v350.yml`.
- [ ] Cover quality profiles, Debug-First pass/block/escalation, TDD RED/GREEN/regression, eval PASS_K, self-check readiness, learning deduplication and Final Reviewer-only promotion.
- [ ] Confirm Windows and Linux fail because helpers are absent.
- [ ] Implement `scripts/quality-gates.py`, `.ps1`, `.sh` with stdlib-only deterministic schemas.
- [ ] Require both platform jobs green.

### Task 2 — Installation, verification and uninstall

- [ ] Extend installer manifest to Governance `3.5.0`, Quality Gates `3.5.0` and ten exact managed tools.
- [ ] Preserve Architect runner `3.3.4` and Context Intelligence `3.4.0` hashes and routing values.
- [ ] Render exact Quality Gate paths and policies.
- [ ] Extend verifiers while retaining 3.3.x and 3.4.0 compatibility.
- [ ] Remove only exact managed Quality Gate tools during uninstall; preserve learning evidence and unrelated tools.

### Task 3 — Native governance contracts

- [ ] Add concise `QUALITY_GATES_V1` rules to Architect, Build, Plan and Executor rendered agents.
- [ ] Add command entry rules to `ai-plan`, `ai-execute`, `ai-workflow`, `ai-review`, `ai-resume`, `ai-audit` and `ai-metrics`.
- [ ] Document task artifacts, exceptions, eval reliability and candidate promotion.
- [ ] Keep self-check output outside reviewer conclusions and sibling review packets.

### Task 4 — Release and full regression

- [ ] Set `VERSION`, README and changelog to `3.5.0 — Quality Gates & Governed Learning`.
- [ ] Update current-version expectations in v3.3/v3.4 workflows without removing their regression coverage.
- [ ] Run v3.5, v3.4, Architect, PowerShell, Project State, Executor, Durability and governance workflows.
- [ ] Confirm no provider/model route, variant, priority, `only_on`, alias, work class or reviewer independence change.
- [ ] Merge only the final green SHA through a squash PR.
