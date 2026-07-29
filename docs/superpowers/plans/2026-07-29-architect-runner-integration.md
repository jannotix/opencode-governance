# Architect Runner Integration Fix Implementation Plan

> **For agentic workers:** implement task-by-task with tests first and verify every platform contract before merge.

**Goal:** Publish OpenCode Governance 3.3.2 with deterministic installed Architect failover entrypoints and a non-recursive direct-command gate.

**Architecture:** Repository `run-governed` scripts remain canonical. Routing installers copy them to stable `architect-attempt` names under the local tools directory, render those exact paths into role policy and record all four failover helpers in the routing manifest. Supported Architect commands require a runner marker before any governance write.

**Tech Stack:** PowerShell 7, Bash, Python 3 installer helper, Markdown command/agent templates, GitHub Actions.

## Global Constraints

- Preserve routing schema version `1.0`.
- Preserve seven public agents and twelve commands.
- Preserve personal provider/model configuration and credentials outside the repository.
- No automatic push, merge, deployment or production rollback.
- Direct supported commands must not mutate `.ai/**` before the runner gate passes.
- Routed child processes must not recursively invoke the runner.

---

### Task 1: Add failing cross-platform regression tests

**Files:**
- Create: `.github/workflows/verify-v332.yml`

- [ ] Assert `VERSION`, README and changelog identify 3.3.2.
- [ ] Install a routing fixture on Windows and Linux.
- [ ] Assert `architect-attempt.ps1` and `.sh` exist and are listed in `managed_tools`.
- [ ] Assert Architect, Build and Plan contain exact entrypoint paths and marker policy.
- [ ] Run the installed entrypoint against a mock OpenCode process that fails primary with a rate limit and succeeds fallback only when environment and argument markers are present.
- [ ] Verify partial `.ai/**` output is restored between attempts.
- [ ] Verify uninstall removes all four managed tools and preserves unrelated files.
- [ ] Run the workflow and confirm failure before implementation.

### Task 2: Install and manage Architect runner entrypoints

**Files:**
- Modify: `scripts/install.ps1`
- Modify: `scripts/install.sh`
- Modify: `scripts/uninstall.ps1`
- Modify: `scripts/uninstall.sh`

- [ ] Back up existing Architect runner entrypoints.
- [ ] Copy repository `run-governed` scripts to stable local `architect-attempt` names.
- [ ] Add all four tools to `managed_tools`.
- [ ] Update routing manifest and installer output to governance 3.3.2.
- [ ] Allow uninstall of only the exact four managed tool paths.

### Task 3: Add deterministic entry gate and recursion marker

**Files:**
- Modify: `scripts/run-governed.ps1`
- Modify: `scripts/run-governed.sh`
- Modify: `templates/commands/ai-init.md`
- Modify: `templates/commands/ai-audit.md`
- Modify: `templates/commands/ai-discover.md`
- Modify: `templates/commands/ai-plan.md`

- [ ] Set `OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1` in every child process.
- [ ] Prefix routed arguments with `[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]`.
- [ ] Require the marker before any governance write when Architect failover is enabled.
- [ ] On direct invocation, return deterministic `ARCHITECT_RUNNER_REQUIRED` commands and never launch a nested runner.

### Task 4: Strengthen verification

**Files:**
- Modify: `scripts/verify-routing.ps1`
- Modify: `scripts/verify-routing.sh`
- Modify: `.github/workflows/verify.yml`

- [ ] Require governance version 3.3.2.
- [ ] Require exactly four managed tool paths.
- [ ] Verify installed Architect entrypoints match repository `run-governed` sources byte-for-byte.
- [ ] Verify exact path, marker, direct-entry and no-recursion policy in Architect, Build and Plan.
- [ ] Keep legacy installation verification unchanged.

### Task 5: Publish release documentation

**Files:**
- Modify: `VERSION`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/model-failover.md`
- Modify: `docs/troubleshooting.md`

- [ ] Document the stable local entrypoints.
- [ ] Document direct slash-command behavior and the correct external invocation.
- [ ] Record the WHMCS `ARCHITECT_RUNNER_UNAVAILABLE` root cause and resolution.
- [ ] State that no model routing, durability or governance authority changes.

### Task 6: Final verification and release merge

- [ ] Run all GitHub Actions workflows on the final head.
- [ ] Inspect the complete PR diff for personal provider/model identifiers and unsafe file operations.
- [ ] Confirm Windows and Linux routing, Executor isolation, durability and Architect runner tests pass.
- [ ] Squash merge into `main` only with the expected final head SHA.
- [ ] Verify `VERSION`, README, changelog and runner files from `main`.
