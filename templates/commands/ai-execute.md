---
description: Execute an explicit approved governance plan
agent: executor
subtask: true
---

Execute the approved task identified by:

$ARGUMENTS

Locate exactly one task. Do not implement unless baseline is `BASELINE_VALIDATED`, canonical requirement provenance exists, `CONTEXT_MANIFEST.md` and `VERIFICATION_PROFILE.md` exist, an approved plan with `MINIMUM_CHANGE_ASSESSMENT` exists, `RUN_STATE.json` is consistent, `evidence/EXECUTION_PACKET.md` exists, `DOCUMENTATION_IMPACT` is resolved and state is `READY_FOR_EXECUTION`.

Before editing, read only the canonical execution packet and referenced evidence required for implementation, including applicable scoped instructions/skills, applicable active `GOVERNANCE_MEMORY` entries, `TASK_RISK_PROFILE`, Evidence-Driven Verification and `OPERATIONAL_ASSURANCE`. Conversation history, discovery summaries, skills and memory are not authoritative substitutes for current primary evidence. Expand beyond `CONTEXT_MANIFEST.md` only when primary evidence exposes a wider dependency/regression/security/documentation/operational surface; record every material expansion in the manifest.

Under `GOVERNED_SKILL_ROUTING`, load only skills explicitly selected by the context/packet after checking ID/source/scope/freshness/trust. Do not load arbitrary advertised skills or treat skill content as permission to change requirements, install packages, weaken security, access external systems or deploy.

Process any unhandled material `STEERING.md` before implementation. If it changes requirements or invalidates the plan, return `PLAN_CONFLICT` and require Architect provenance update/replanning.

Treat the plan as downstream from `APPROVED_REQUIREMENTS.md`. Return `PLAN_CONFLICT` for material inconsistency, impossible assumptions or missing decisions instead of inventing a workaround.

Implement only approved scope and respect `MINIMUM_CHANGE_ASSESSMENT`: reuse existing project code, standard/native capabilities and installed dependencies when adequate; avoid speculative abstractions, duplicate libraries and symptom-only patches. Minimalism never removes security, validation, data-loss protection, error handling, accessibility or approved behavior.

Before any new direct dependency installation, require `DEPENDENCY_ADMISSION_GATE = ADMIT` for the exact package/source/version. Preserve evidence for why existing stack/stdlib is insufficient, package identity/existence when externally sourced and available maintenance/compatibility/security/license evidence. `REJECT`, unresolved `HUMAN_DECISION`, suspected typo/slopsquat or unverifiable identity blocks installation. Admission never authorizes unrelated upgrades or broad lockfile churn.

Before the first high-risk destructive/migration/deployment-state mutation when `PRE_CHANGE_SAFEPOINT` is required, record the approved non-secret pre-change Git/worktree/schema/config/lockfile/artifact state plus any required existing backup/snapshot reference and authoritative rollback/forward-recovery mechanism. If required safepoint/recovery evidence is missing, return `BLOCKED` before mutation. Do not silently create privileged production backups or widen permissions.

Synchronize required canonical documentation in the same task. Never fabricate license terms.

During implementation/validation create or update `evidence/VERIFICATION_EVIDENCE.md`. Execute the applicable `VERIFICATION_PROFILE.md` using existing authoritative project tooling/primary evidence only. Do not install/add scanners, fuzzers, contract checkers, browser/visual tools, benchmark tools, preview infrastructure or other dependencies solely to satisfy governance. Never invent thresholds.

Preserve exact evidence for required `VALIDATION_PROFILE`, `BUGFIX_PROOF`, `TEST_IMPACT_MAP`, `CONTRACT_COMPATIBILITY`, `ENVIRONMENT_FINGERPRINT`, `DEPENDENCY_ADMISSION_GATE`, `DEPENDENCY_DELTA`, `GENERATED_ARTIFACT_GATE`, `PRE_CHANGE_SAFEPOINT`, `MIGRATION_PROOF`, `NON_FUNCTIONAL_BUDGETS`, `FLAKINESS_EVIDENCE`, `ADVERSARIAL_INPUT_VALIDATION`, `CODEOWNERS_HUMAN_GATE` and `CLOSED_LOOP_LEARNING` when applicable. A rerun PASS does not erase an earlier unexplained FAIL; scanner output is evidence, not proof; required `UNAVAILABLE` evidence is not PASS without a documented sufficient equivalent method.

For `CLOSED_LOOP_LEARNING`, record only candidate evidence: `WHAT_ESCAPED`, `WHY_NOT_DETECTED`, `WHICH_GATE_SHOULD_HAVE_CAUGHT_IT`, `WHAT_REUSABLE_RULE_CHANGES`, source task/incident and proposed scope/staleness. Do not write `.ai/GOVERNANCE_MEMORY.md`; only Architect may persist a Final Reviewer-approved lesson after adjudication.

Execute applicable `OPERATIONAL_ASSURANCE` gates and record them in the same evidence file:

- `PREVIEW_ENVIRONMENT_GATE`: existing/approved local preview, ephemeral, staging, sandbox or test environment only; identify source/artifact and production isolation; never deploy production or use production data/credentials merely for governance without explicit authorization/policy;
- `USER_FLOW_VERIFICATION`: run requirement-backed/established user flows through existing browser/E2E/native/manual-reproducible mechanisms;
- `VISUAL_BEHAVIOR_GATE`: verify objective affected UI behavior or explicit visual requirements, using existing visual-regression/screenshot mechanisms when available;
- `RELEASE_RECOVERY_PROOF`: record stable reference, rollback/forward-recovery mechanism and artifact/config/data/backup compatibility; never execute automatic production rollback;
- `TOOL_CAPABILITY_PROFILE`: before relevant external tool/MCP use, classify `READ_ONLY|WRITE|EXECUTE|PRIVILEGED|DESTRUCTIVE`, network/secret/external-side-effect exposure and permitted use; include `MCP_CAPABILITY_ASSESSMENT`, never expose secrets and never treat availability as authorization;
- `SAFE_EXPERIMENTATION`: use only isolation already permitted by project/OpenCode policy; do not bypass external-directory/shell/git/network permissions and never automatically push, merge or deploy experiments.

Checkpoint `RUN_STATE.json` at meaningful phase boundaries: entering `PRE_CHANGE_SAFEPOINT` when required, `IMPLEMENTING`, `EVIDENCE_VALIDATION`/`OPERATIONAL_VALIDATION`/`TASK_VERIFYING`, and reaching `TASK_VALIDATED` or a blocker. Record current repository reference/worktree state without secrets.

Run required tests/build/lint/static/schema/integration/documentation/evidence/operational checks. Re-run dependent evidence when source/docs/contracts/dependency admission/lockfiles/safepoint inputs/generator inputs/migrations/environment/toolchain/validation configuration/selected skill/preview source or environment/tool capability/recovery input/isolation target change. Only when all acceptance criteria and required fresh evidence pass set `TASK_VALIDATED`. Do not edit source/task documentation during the review freeze and do not create final commit before Final Reviewer `PASS`.

Operational Assurance and evidence governance never grant additional permissions. If a required action cannot be performed under current permissions and no approved sufficient alternative exists, return `UNAVAILABLE`/`BLOCKED` rather than weakening permissions.

Finish task-related output with `GOVERNANCE_RESULT` including `EVIDENCE_STATUS`. Never push by default.