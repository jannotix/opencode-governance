# Architect Runner Integration Fix Design

## Problem

Governance 3.2 introduced transactional Architect failover through repository scripts named `run-governed.ps1` and `run-governed.sh`, but routing installations copy only Executor helpers into the OpenCode configuration directory. The rendered Architect policy names an external runner without a deterministic installed path. A direct `/ai-init` invocation can therefore invent `opencode-governance-tools/architect-attempt.ps1`, fail to find it and stop before governance initialization.

## Goal

Make Architect failover executable and deterministic from every routing installation while preventing recursive nested runner invocation and preserving all existing role, routing, review and durability contracts.

## Design

1. Keep `scripts/run-governed.ps1` and `scripts/run-governed.sh` as the repository source implementations.
2. Install those scripts under stable local entrypoint names:
   - `opencode-governance-tools/architect-attempt.ps1`
   - `opencode-governance-tools/architect-attempt.sh`
3. Add both paths to `managed_tools`, backup them before replacement, verify their content against repository sources and remove them conservatively during uninstall.
4. Render exact Windows and Unix entrypoint paths into Architect, Build and Plan policies. The policy forbids inventing another path.
5. Add an entry gate to `ai-init`, `ai-audit`, `ai-discover` and `ai-plan`:
   - routed invocations contain the exact marker `[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]` and continue normally after removing it from the request;
   - direct invocations with Architect failover enabled stop before `.ai/**` writes and return `ARCHITECT_RUNNER_REQUIRED` with deterministic commands using the installed paths;
   - the active OpenCode process never launches a nested Architect runner itself.
6. The runner sets both the process environment variable `OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1` and the argument marker for every child route attempt. This prevents recursion without requiring the model to infer process state.
7. Preserve transactional semantics: same project root, complete `.ai/**` snapshot/restore, source-state freeze, eligible-failure classification, same-family preference, cooldown and complete-command restart.

## Failure behavior

Missing or stale installed runner, manifest mismatch, absent marker in a routed child, source drift, failed `.ai/**` restoration, ineligible failure or exhausted routes remain fail-closed and require human recovery. Direct slash-command invocation is not treated as a provider failure and does not consume a fallback route.

## Compatibility

Legacy single-model installation remains unchanged and does not require the runner entry gate. Routing profiles remain schema `1.0`; only `governance_version` and the managed tool set change to 3.3.2. Personal provider/model identifiers and credentials remain local and untracked.

## Verification

Windows and Linux CI reproduce the WHMCS failure mode, verify installation of the exact runner path, exercise primary-to-fallback transactional restart through the installed entrypoint, assert marker propagation, verify no recursive invocation contract and confirm conservative uninstall.
