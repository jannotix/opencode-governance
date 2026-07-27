# Evidence-Driven Verification

OpenCode Governance v1.8 adds a deterministic evidence layer around the existing multi-model workflow. Models still reason, implement and review, but important correctness claims should be supported by reproducible repository/runtime evidence whenever the project can provide it.

No external verification dependency is required or installed by governance.

## Repository instruction index

Validated repositories maintain `.ai/INSTRUCTION_INDEX.md` alongside the existing context index. It records authoritative repository-local instruction sources, their applicable paths/scope, precedence/specificity, material constraints and unresolved conflicts.

`CONTEXT_INDEX.md` answers which code/evidence is relevant. `INSTRUCTION_INDEX.md` answers which repository rules apply to that selected code.

Material instruction conflicts that repository evidence cannot resolve are never silently arbitrated; they require authoritative clarification.

## Per-task verification profile

Every new/in-progress v1.8 governed task creates:

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

## Dependency delta

When manifests/lockfiles change, record direct/transitive additions, removals and upgrades, lockfile consistency and any vulnerability/license/deprecation evidence already available from project tooling.

Scanner output is evidence, not proof. Governance never auto-fixes dependencies.

## Generated artifact gate

When generator inputs are affected, run the repository's real generation command and verify generated output is synchronized and unexplained generated diffs do not remain.

Governance never invents a generator command.

## Migration proof

Schema/data migrations are classified:

```text
REVERSIBLE
FORWARD_ONLY
IRREVERSIBLE
```

Verify apply/resulting schema-data/application behavior and rollback when supported. Irreversible changes require the approved backup/forward-recovery evidence and any authoritative approval; governance never pretends rollback exists.

## Conditional evidence

The following apply only when repository/task evidence makes them relevant:

- `NON_FUNCTIONAL_BUDGETS` — existing performance, memory, bundle, startup, latency or accessibility budgets only; never invented thresholds.
- `FLAKINESS_EVIDENCE` — a rerun PASS never erases an earlier unexplained FAIL; preserve failure signature/seed/environment when available and rerun count.
- `ADVERSARIAL_INPUT_VALIDATION` — for high-risk parsers, deserializers, authentication input, uploads, APIs, protocols or user-controlled input; use existing fuzz/property/schema-negative testing or equivalent bounded primary evidence.
- `CODEOWNERS_HUMAN_GATE` — authoritative repository-required owner/human approval is recorded and enforced at the boundary defined by project policy. Approval is never fabricated.

## Evidence freshness

Evidence is dependency-specific. Changes to source/docs, contracts, lockfiles/dependency manifests, generator inputs, migrations, environment/toolchain or validation configuration invalidate only the evidence and downstream reviews that depend on those changed surfaces.

`/ai-resume` reconciles this freshness before continuing instead of restarting every completed phase.

## Review and final adjudication

Implementation and Architecture/Security Reviewers independently challenge:

- risk classification;
- selected evidence gates;
- evidence sufficiency/freshness;
- implementation correctness in their normal review domains.

The Final Reviewer independently validates the requirement trail first, then the evidence profile and task result. Reviewer agreement is never counted as proof.

A clean `PASS` requires sufficient fresh required evidence. Human-owner gates may remain a separate merge/release/push prerequisite when repository policy places them at that boundary.

## No new agents and no automatic dependencies

v1.8 does not add another reviewer/agent and does not hardcode Stryker, Nx, OASDiff, Buf, OSV, Syft, Grype, Lighthouse, fuzzers or any other external verifier.

When equivalent tooling already exists in the project, governance may use it as evidence. Otherwise it uses available primary evidence or records the capability as unavailable according to the task risk/acceptance requirements.
