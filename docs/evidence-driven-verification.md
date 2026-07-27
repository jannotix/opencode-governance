# Evidence-Driven Verification

OpenCode Governance uses a deterministic evidence layer around the multi-model workflow. Models still reason, implement and review, but important correctness claims should be supported by reproducible repository/runtime evidence whenever the project can provide it.

No external verification dependency is required or installed by governance.

## Repository instruction, skill and memory evidence

Validated repositories maintain:

```text
.ai/INSTRUCTION_INDEX.md
.ai/GOVERNANCE_MEMORY.md
```

`INSTRUCTION_INDEX.md` records authoritative repository-local instruction sources plus project/OpenCode skill metadata. Skills are indexed by ID/source, scope/trigger, freshness and trust:

```text
PROJECT_AUTHORITATIVE
PROJECT_ADVISORY
WORKSPACE_ADVISORY
EXTERNAL_UNTRUSTED
```

Skill content never outranks the canonical user requirement trail.

`GOVERNANCE_MEMORY.md` stores only reusable lessons validated from governed outcomes. Each entry includes stable ID, type, scope, source task/release/incident, evidence references, learned rule, `stale_when`, status `ACTIVE | STALE | REVOKED` and last validation reference.

Memory is advisory routing evidence. It is never a permanent waiver and never replaces fresh primary evidence.

## Per-task verification profile

Every governed task creates:

```text
.ai/tasks/<TASK-ID>/VERIFICATION_PROFILE.md
.ai/tasks/<TASK-ID>/evidence/VERIFICATION_EVIDENCE.md
```

`VERIFICATION_PROFILE.md` plans what proof is required. `VERIFICATION_EVIDENCE.md` records what was actually executed/observed. One profile/result pair is used instead of creating a separate governance file for every gate.

Completed historical tasks are not retroactively rewritten.

## Task risk profile

`VERIFICATION_PROFILE.md` contains `TASK_RISK_PROFILE` with `NONE | LOW | HIGH` for at least:

- `SECURITY`
- `DATA_MIGRATION`
- `PUBLIC_CONTRACT`
- `DEPENDENCY`
- `DEPLOYMENT`
- `PERFORMANCE`
- `GENERATED_ARTIFACT`
- `DESTRUCTIVE_ACTION`
- `INPUT_VALIDATION`
- `TEST_RELIABILITY`
- `HUMAN_OWNERSHIP`
- `USER_FLOW`
- `VISUAL_BEHAVIOR`
- `EXTERNAL_TOOLING`
- `RECOVERY`
- `EXPERIMENTATION`

Risk changes the amount/type of required evidence. It never removes requirement provenance, normal acceptance validation, independent dual review or Final Reviewer adjudication.

## Evidence statuses

Planning status:

```text
REQUIRED
CONDITIONAL
NOT_APPLICABLE
```

Execution/review status:

```text
PASS
FAIL
UNAVAILABLE
STALE
BLOCKED
```

`UNAVAILABLE` never silently becomes `PASS`. A required unavailable mechanism needs an explicitly sufficient equivalent primary-evidence method; otherwise the task/release remains blocked or insufficiently evidenced.

## Validation profile and CI parity

Governance discovers the repository's existing authoritative validation mechanisms first: package scripts, CI workflows, test runners, linters, type/static checks, build commands, integration tests and equivalent project tooling.

It does not invent commands, thresholds or new dependencies merely to satisfy governance.

## Bugfix proof

For reproducible bug fixes, evidence should preserve:

```text
before fix -> FAIL
with fix   -> PASS
```

For critical fixes, a bounded negative control may be used when safe/practical to prove the regression test actually detects removal/disablement of the correction.

When the original failure cannot be reproduced, record that honestly and use characterization/primary evidence; never fabricate pre-fix failure history.

## Test impact map

Changed paths are mapped to direct, dependent and integration tests, plus whether a full suite remains required.

Test-impact selection may reduce unnecessary validation on large repositories, but it never overrides authoritative CI policy or high-risk full-suite requirements.

## Contract compatibility

When a task changes a public contract, compare before/after primary artifacts where applicable:

- OpenAPI/API schemas;
- GraphQL;
- Protobuf/wire schemas;
- public library/API surfaces;
- CLI flags/options;
- configuration schemas;
- event/message schemas.

Record compatible, breaking or explicitly authorized breaking change. Governance does not hardcode any particular contract checker.

## Environment fingerprint

Validation evidence records non-secret environment facts relevant to reproducibility, such as:

- OS/architecture;
- runtime/compiler versions;
- package-manager/test-tool versions;
- lockfile hashes;
- container/dev-environment digest when applicable.

Material environment changes can make runtime/build/test evidence stale even when source code is unchanged.

## Dependency admission gate

`DEPENDENCY_ADMISSION_GATE` acts **before** a new direct dependency is installed.

Required evidence, when applicable:

- exact package/source/version;
- why existing project code, installed dependencies or native/stdlib capability is insufficient;
- package/registry identity and existence when externally sourced;
- available maintenance/support evidence;
- compatibility evidence;
- available security/vulnerability evidence;
- license compatibility evidence;
- expected lockfile/transitive impact.

Admission result:

```text
ADMIT
REJECT
HUMAN_DECISION
NOT_APPLICABLE
```

A plausible package name is not evidence. Suspected typo/slopsquat, unverifiable identity, materially unresolved security/license risk or unresolved `HUMAN_DECISION` prevents silent installation.

`ADMIT` is exact package/source/version scoped. It does not authorize unrelated upgrades or broad lockfile churn.

Governance does not hardcode a package firewall or registry scanner. Existing project/registry/security tooling may contribute evidence.

## Dependency delta

After an admitted manifest/lockfile change, record direct/transitive additions, removals and upgrades, lockfile consistency and any vulnerability/license/deprecation evidence already available from project tooling.

Scanner output is evidence, not proof. Governance never auto-fixes dependencies.

Admission answers **whether the dependency may be introduced**; delta answers **what the dependency change actually produced**. They are intentionally separate gates.

## Generated artifact gate

When generator inputs are affected, run the repository's real generation command and verify generated output is synchronized and unexplained generated diffs do not remain.

Governance never invents a generator command.

## Pre-change safepoint

`PRE_CHANGE_SAFEPOINT` applies before approved high-risk destructive, migration, deployment-state or otherwise hard-to-reverse mutation when recoverable pre-change evidence is required.

Depending on the project, record non-secret evidence such as:

- exact Git/worktree reference and dirty state;
- relevant schema/migration version;
- lockfile/config fingerprints;
- current artifact/release reference;
- existing required backup/snapshot identifier;
- authoritative rollback or forward-recovery mechanism.

The safepoint must be captured **before** the risky mutation.

If the approved recovery strategy requires an existing backup/snapshot and it is missing, the mutation remains blocked. Governance does not invent a backup, claim one exists, or silently perform privileged production backup operations merely to satisfy the gate.

A safepoint is not the same as `RELEASE_RECOVERY_PROOF`: the safepoint proves the starting state was captured; recovery proof demonstrates the recovery strategy is coherent for the resulting release/change.

## Migration proof

Schema/data migrations are classified:

```text
REVERSIBLE
FORWARD_ONLY
IRREVERSIBLE
```

Verify apply/resulting schema-data/application behavior and rollback when supported. Irreversible changes require approved backup/forward-recovery evidence and any authoritative approval; governance never pretends rollback exists.

## Conditional evidence

The following apply only when repository/task evidence makes them relevant:

- `NON_FUNCTIONAL_BUDGETS` — existing performance, memory, bundle, startup, latency or accessibility budgets only; never invented thresholds.
- `FLAKINESS_EVIDENCE` — a rerun PASS never erases an earlier unexplained FAIL; preserve failure signature/seed/environment when available and rerun count.
- `ADVERSARIAL_INPUT_VALIDATION` — for high-risk parsers, deserializers, authentication input, uploads, APIs, protocols or user-controlled input; use existing fuzz/property/schema-negative testing or equivalent bounded primary evidence.
- `CODEOWNERS_HUMAN_GATE` — authoritative repository-required owner/human approval is recorded and enforced at the boundary defined by project policy. Approval is never fabricated.

## Closed-loop learning

`CLOSED_LOOP_LEARNING` applies when authoritative evidence shows a reusable governance lesson, for example:

- a defect escaped earlier governed validation or production release;
- the same validated defect pattern recurs;
- a validation gap is proven;
- a repeated reviewer allegation is proven to be a stable scoped false positive;
- a recovery/tooling constraint materially affected correctness.

Candidate analysis records:

```text
WHAT_ESCAPED
WHY_NOT_DETECTED
WHICH_GATE_SHOULD_HAVE_CAUGHT_IT
WHAT_REUSABLE_RULE_CHANGES
```

Executor records candidate evidence only. Reviewers challenge it independently. Final Reviewer writes:

```text
MEMORY_DECISION: NONE
MEMORY_DECISION: APPROVE
MEMORY_DECISION: REJECT
```

An approved candidate includes exact scope, evidence references and `stale_when`. Only Architect may then write/update `.ai/GOVERNANCE_MEMORY.md`.

Rules:

- raw reviewer allegations never become memory;
- speculative root causes never become memory;
- memory cannot create broad permanent suppressions;
- a validated false-positive memory entry applies only to the same evidenced pattern/scope;
- a changed boundary that matches `stale_when` invalidates the entry;
- current primary evidence always wins over memory.

## Evidence freshness

Evidence is dependency-specific. Changes to source/docs, contracts, dependency admission/lockfiles, safepoint/recovery inputs, generator inputs, migrations, environment/toolchain, validation configuration or selected skill version/source invalidate only the evidence and downstream reviews that depend on those changed surfaces.

`/ai-resume` reconciles this freshness before continuing instead of restarting every completed phase. It never retroactively fabricates a missing admission decision or safepoint.

## Review and final adjudication

Implementation and Architecture/Security Reviewers independently challenge:

- risk classification;
- selected evidence gates;
- skill/memory relevance where used;
- dependency admission;
- safepoint sufficiency;
- evidence sufficiency/freshness;
- closed-loop candidates;
- implementation correctness in their normal review domains.

The Final Reviewer independently validates the requirement trail first, then plan/risk, skill/memory relevance, evidence profile and task result. Reviewer agreement is never counted as proof.

A clean `PASS` requires sufficient fresh required evidence. Human-owner gates may remain a separate merge/release/push prerequisite when repository policy places them at that boundary.

## Operational Assurance

Runtime/preview/user-flow/visual/recovery/tool/MCP/isolation evidence is documented separately in [Operational Assurance](operational-assurance.md), but uses this same profile/evidence/status model.

## No automatic dependencies

Governance does not hardcode Stryker, Nx, OASDiff, Buf, OSV, Syft, Grype, Lighthouse, fuzzers, browser frameworks, package firewalls or any other external verifier.

When equivalent tooling already exists in the project, governance may use it as evidence. Otherwise it uses available primary evidence or records the capability as unavailable according to the task risk/acceptance requirements.