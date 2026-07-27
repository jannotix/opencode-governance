# Evidence-Driven Verification

Evidence-Driven Verification defines the deterministic proof layer used by governed tasks. Models may reason about evidence, but required correctness claims must be backed by reproducible project or runtime evidence when the project can provide it.

No verification dependency is installed automatically.

## Per-task contract

Every governed task uses:

```text
.ai/tasks/<TASK-ID>/VERIFICATION_PROFILE.md
.ai/tasks/<TASK-ID>/evidence/VERIFICATION_EVIDENCE.md
```

`VERIFICATION_PROFILE.md` plans required proof. `VERIFICATION_EVIDENCE.md` records what was executed or observed.

Planning states:

```text
REQUIRED
CONDITIONAL
NOT_APPLICABLE
```

Evidence states:

```text
PASS
FAIL
UNAVAILABLE
STALE
BLOCKED
```

`UNAVAILABLE` is not `PASS`. A required unavailable mechanism needs a sufficient approved primary-evidence alternative or the task/release remains blocked.

## Task risk profile

`TASK_RISK_PROFILE` classifies at least these dimensions as `NONE | LOW | HIGH`:

```text
SECURITY
DATA_MIGRATION
PUBLIC_CONTRACT
DEPENDENCY
DEPLOYMENT
PERFORMANCE
GENERATED_ARTIFACT
DESTRUCTIVE_ACTION
INPUT_VALIDATION
TEST_RELIABILITY
HUMAN_OWNERSHIP
USER_FLOW
VISUAL_BEHAVIOR
EXTERNAL_TOOLING
RECOVERY
EXPERIMENTATION
```

Risk classification may add verification depth. It never removes requirement provenance, acceptance validation, independent dual review or Final Reviewer adjudication.

## Validation profile

`VALIDATION_PROFILE` discovers the repository's existing authoritative checks first:

- package/build scripts;
- CI commands;
- linters and type/static analysis;
- unit/integration/system tests;
- schema/contract checks;
- project-native security or release tooling.

Governance does not invent commands, thresholds or dependencies merely to satisfy a gate.

## Core gates

### `BUGFIX_PROOF`

For reproducible fixes:

```text
before fix → FAIL
with fix   → PASS
```

Use a bounded negative control for critical fixes only when safe and useful. If the original failure cannot be reproduced, record that honestly and use characterization evidence.

### `TEST_IMPACT_MAP`

Map changed paths to direct, dependent and integration tests and record whether a full suite is still required. Impact selection never overrides authoritative CI or high-risk full-suite policy.

### `CONTRACT_COMPATIBILITY`

For affected public contracts, compare before/after primary artifacts and classify compatible, breaking or explicitly authorized breaking change. Applicable surfaces include APIs, schemas, public libraries, CLI flags, configuration and message/event contracts.

### `ENVIRONMENT_FINGERPRINT`

Record only non-secret facts needed for reproducibility, such as OS/architecture, runtime/compiler/package-manager/test-tool versions, lockfile hashes and container/dev-environment identity.

### `DEPENDENCY_ADMISSION_GATE`

A new direct dependency is assessed before installation.

Required evidence, when applicable:

- exact package/source/version;
- why existing/native/stdlib capability is insufficient;
- package identity/existence;
- compatibility and maintenance evidence;
- available security/license evidence;
- expected lockfile/transitive impact.

Result:

```text
ADMIT
REJECT
HUMAN_DECISION
NOT_APPLICABLE
```

`REJECT`, unresolved `HUMAN_DECISION`, suspected typo/slopsquat or unverifiable identity prevents silent installation. Admission is exact dependency scoped and does not authorize unrelated upgrades.

### `DEPENDENCY_DELTA`

After an admitted dependency change, record direct/transitive additions, removals and upgrades, lockfile consistency and available vulnerability/license/deprecation evidence. Scanner output is evidence, not proof.

### `GENERATED_ARTIFACT_GATE`

When generator inputs change, run the repository's real generator and verify generated output is synchronized. Governance never invents a generator command.

### `PRE_CHANGE_SAFEPOINT`

Before a required high-risk destructive, migration or deployment-state mutation, capture a recoverable starting reference using relevant non-secret evidence such as:

- Git/worktree reference and dirty state;
- schema/migration state;
- lockfile/config/artifact fingerprints;
- required existing backup/snapshot reference;
- authoritative rollback or forward-recovery mechanism.

A required safepoint is captured before mutation. Resume never fabricates it afterward.

### `MIGRATION_PROOF`

Classify migrations:

```text
REVERSIBLE
FORWARD_ONLY
IRREVERSIBLE
```

Verify apply/resulting schema-data/application behavior and rollback when supported. Irreversible changes require the approved backup/forward-recovery evidence and any authoritative approval.

## Conditional gates

These apply only when repository/task evidence makes them relevant:

- `NON_FUNCTIONAL_BUDGETS` — existing performance, memory, bundle, startup, latency or accessibility budgets;
- `FLAKINESS_EVIDENCE` — later reruns never erase an earlier unexplained failure;
- `ADVERSARIAL_INPUT_VALIDATION` — bounded negative/fuzz/property/schema validation for high-risk input surfaces using existing project capabilities;
- `CODEOWNERS_HUMAN_GATE` — authoritative owner/human approval at the boundary required by repository policy.

## Closed-loop learning

`CLOSED_LOOP_LEARNING` applies only when authoritative evidence establishes a reusable lesson, such as an escaped defect, recurring defect, validation gap, stable scoped false positive, recovery lesson or tooling constraint.

Candidate evidence records:

```text
WHAT_ESCAPED
WHY_NOT_DETECTED
WHICH_GATE_SHOULD_HAVE_CAUGHT_IT
WHAT_REUSABLE_RULE_CHANGES
```

Reviewers challenge the candidate independently. Final Reviewer records:

```text
MEMORY_DECISION: NONE | APPROVE | REJECT
```

Only `APPROVE` permits Architect to persist the exact validated lesson to `.ai/GOVERNANCE_MEMORY.md`. Memory remains scoped, evidence-backed and subject to `stale_when` conditions.

## Evidence freshness

Evidence is dependency-specific. Changes to source/docs, contracts, dependency admission/lockfiles, safepoint/recovery inputs, generator inputs, migrations, environment/toolchain, validation configuration or selected skill source/version invalidate only dependent evidence and downstream reviews.

`/ai-resume` reconciles this state instead of restarting unrelated completed phases.

## Review contract

Both reviewers independently challenge risk classification, selected gates, evidence sufficiency/freshness, dependency admission, safepoints and closed-loop candidates within their normal domains.

Final Reviewer independently validates the requirement trail first, then the plan/risk/evidence state and reviewer allegations. Reviewer agreement is never proof.

A task `PASS` requires fresh sufficient required evidence.

## Operational Assurance

Runtime/preview/user-flow/visual/recovery/tool/MCP/isolation proof is defined in [Operational Assurance](operational-assurance.md) and uses the same profile, evidence and status model.
