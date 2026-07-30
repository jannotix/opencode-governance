# OpenCode Governance 3.5.0 — Quality Gates & Governed Learning Design

## Status

APPROVED_FOR_IMPLEMENTATION

The owner approved autonomous execution of the roadmap on 2026-07-30.

## Objective

Improve generated-code correctness and reduce avoidable review cycles by adding deterministic debug-first evidence, risk-adaptive TDD, AI-system eval contracts, pre-review self-check and governed learning candidates.

The release must remain provider/model agnostic, preserve independent review and Final Reviewer authority, add no network service or package dependency, and never promote inferred memory automatically.

## Architecture

Routing-enabled installations add three managed files:

```text
opencode-governance-tools/quality-gates.ps1
opencode-governance-tools/quality-gates.sh
opencode-governance-tools/quality-gates.py
```

The PowerShell implementation is native PowerShell 7. The Unix shell entrypoint invokes the managed Python 3 standard-library core.

The routing manifest records independent component versions:

```text
governance_version: 3.5.0
architect_runner_version: 3.3.4
context_intelligence_version: 3.4.0
quality_gates_version: 3.5.0
```

With Architect/Executor, Context Intelligence and Quality Gates enabled, the manifest contains exactly ten managed tools.

## Task artifacts

```text
.ai/tasks/<TASK-ID>/QUALITY_PROFILE.json
.ai/tasks/<TASK-ID>/DEBUG_PROOF.json
.ai/tasks/<TASK-ID>/TDD_PROOF.json
.ai/tasks/<TASK-ID>/EVAL_PLAN.json
.ai/tasks/<TASK-ID>/IMPLEMENTATION_SELF_CHECK.json
.ai/tasks/<TASK-ID>/QUALITY_VALIDATION.json
.ai/learning/CANDIDATES.jsonl
.ai/learning/PROMOTIONS.jsonl
```

Missing artifacts are created only for new, resumed or replanned tasks. Existing historical tasks are never mass-rewritten.

## Quality profile

`QUALITY_PROFILE_V1` is initialized from:

- exact work class;
- task kind: `BUGFIX|FEATURE|REFACTOR|DOCS|CONFIG|GENERATED|SPIKE`;
- risk flags;
- AI-system involvement.

It determines:

- `debug_first_required`;
- `tdd_required`;
- `eval_required`;
- `self_check_required`;
- `learning_capture_enabled`.

Rules:

- bug fixes require Debug-First and TDD unless reproduction is authoritatively blocked and an approved exception exists;
- security, authorization, routing, parser, migration, public-contract and high-risk changes require TDD;
- AI-agent, prompt, classifier or nondeterministic behavior changes require an eval plan;
- documentation-only, generated-only, environment-only configuration and explicitly non-promotable spikes may use a recorded exception;
- exceptions never waive security, data-safety, migration, authorization or public-contract proof.

## Debug-First Gate

`DEBUG_PROOF_V1` records:

```text
symptom
reproduction_status
root_cause_status
root_cause_evidence
hypothesis
minimal_experiment
disproving_condition
hypothesis_attempts
architecture_review_required
```

Allowed reproduction states:

```text
REPRODUCED
EQUIVALENT_PROOF
BLOCKED
```

Allowed root-cause states:

```text
CONFIRMED
HYPOTHESIS
BLOCKED
```

A required Debug-First gate passes only when the symptom is reproduced or proven equivalently and the root cause is confirmed. After three failed hypotheses, `architecture_review_required` must be true and execution remains blocked until architecture review.

The gate distinguishes application, environment and governance defects. It does not permit speculative stacks of fixes.

## Risk-adaptive TDD

`TDD_PROOF_V1` records:

```text
red_command
red_exit_code
red_expected_failure
red_observed_failure
red_evidence_refs
green_command
green_exit_code
green_evidence_refs
regression_command
regression_exit_code
regression_evidence_refs
exception_class
exception_reason
```

A required TDD gate passes only when:

- RED is a real non-zero failure matching the targeted behavior;
- GREEN exits zero after the implementation;
- the regression suite exits zero;
- evidence references are present;
- no exception is claimed.

Allowed exception classes:

```text
DOCUMENTATION_ONLY
GENERATED_ARTIFACT
ENVIRONMENT_CONFIGURATION_ONLY
NO_EXECUTABLE_HARNESS
NON_PROMOTABLE_SPIKE
```

`NO_EXECUTABLE_HARNESS` requires a documented equivalent verification plan and does not waive reviewer scrutiny.

## Eval-driven development

`EVAL_PLAN_V1` is required for AI-system behavior and contains:

```text
capability_evals
regression_evals
negative_cases
forbidden_behaviors
grader_type
success_threshold
reliability_mode
run_count
evidence_refs
```

Grader types:

```text
CODE_BASED
MODEL_BASED
HUMAN
HYBRID
```

Reliability modes:

```text
PASS_K
PASS_AT_K
```

Governance-critical and high-risk AI changes require `PASS_K`; one lucky run is not sufficient. `PASS_AT_K` is allowed only for exploratory non-promotable work with an explicit reason.

## Pre-review self-check

`IMPLEMENTATION_SELF_CHECK_V1` is produced by Executor before review and checks:

- plan and scope compliance;
- tests, lint, type and format status;
- security invariants;
- dependency and migration deltas;
- documentation impact;
- unresolved assumptions;
- dead code and temporary files;
- external-action compliance.

The self-check has no approval authority and is not supplied as a conclusion to independent reviewers. Its purpose is to catch cheap defects before reviewer tokens are spent.

## Governed learning candidates

Learning is append-only and candidate-first.

`LEARNING_CANDIDATE_V1` contains:

```text
candidate_id
source
scope
statement
evidence_refs
confidence
dedup_key
privacy_class
stale_when
promotion_status
```

Allowed sources:

```text
USER_CORRECTION
FAILED_TASK
REVIEW_FINDING
SUCCESSFUL_PATTERN
```

The helper rejects duplicate active `dedup_key` values. It never writes `GOVERNANCE_MEMORY.md`.

Promotion requires `LEARNING_PROMOTION_V1` with:

- exact candidate ID and dedup key;
- `approved_by: FINAL_REVIEWER`;
- evidence-backed approval verdict;
- approved scope and `stale_when`;
- privacy classification;
- timestamp.

Promotion writes an append-only event to `PROMOTIONS.jsonl`. Updating `GOVERNANCE_MEMORY.md` remains a separate Final Reviewer-controlled governance action using current primary evidence.

## Periodic agent architecture audit

`/ai-audit` and `/ai-metrics` may request `AGENT_ARCHITECTURE_AUDIT_V1`, covering:

- duplicated or conflicting agent instructions;
- excessive mandatory context;
- stale skills or memory;
- reviewer information leakage;
- unbounded loops;
- redundant roles or gates;
- token/quality ratios from available metrics.

The audit is advisory and cannot change models, permissions, roles or routing automatically.

## Failure handling

- invalid task/candidate IDs, path escape, malformed schema and duplicate learning keys fail closed;
- required missing proof is `BLOCKED`, never `PASS`;
- self-check failure returns `NOT_READY_FOR_REVIEW`;
- a failed eval threshold returns `EVAL_GATE_FAILED`;
- three unresolved debug hypotheses require architecture review;
- unavailable runtime/token evidence remains `UNAVAILABLE`.

## Compatibility

- Existing 3.3.x and 3.4.0 manifests remain verifiable.
- 3.5.0 preserves provider/model routes, variants, fallback priorities, `only_on`, hidden aliases, work classes, reviewer independence, Durability and no-push/no-deploy rules.
- Uninstall removes only exact manifest-managed Quality Gate files and preserves `.ai/learning/**` evidence.

## Verification

Windows and Linux CI must prove:

- quality-profile derivation for every task kind and risk class;
- required Debug-First blocking and architecture-review escalation;
- RED/GREEN/regression validation and exception handling;
- PASS_K enforcement for high-risk AI work;
- self-check readiness and no approval authority;
- learning deduplication and Final Reviewer-only promotion;
- no automatic Governance Memory modification;
- installer/verifier/uninstaller preservation;
- compatibility with 3.3.x and 3.4.0 manifests;
- every existing workflow remains green.
