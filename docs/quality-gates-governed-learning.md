# Quality Gates and Governed Learning

OpenCode Governance 3.5.0 adds deterministic quality-proof and learning-candidate contracts. The helpers validate evidence shape and gate state; they do not approve implementation, replace independent review, change routing or write Governance Memory automatically.

## Installed tools

```text
opencode-governance-tools/quality-gates.ps1
opencode-governance-tools/quality-gates.sh
opencode-governance-tools/quality-gates.py
```

The PowerShell helper requires PowerShell 7. The Unix wrapper invokes the managed Python 3 standard-library core.

The 3.5.0 routing manifest records:

```text
governance_version: 3.5.0
architect_runner_version: 3.3.4
context_intelligence_version: 3.4.0
quality_gates_version: 3.5.0
managed_tools: 10
```

## Quality profile

Initialize `QUALITY_PROFILE_V1` before an implementation-ready plan. Inputs are exact work class, task kind and risk flags.

Task kinds:

```text
BUGFIX
FEATURE
REFACTOR
DOCS
CONFIG
GENERATED
SPIKE
```

The profile determines:

```text
debug_first_required
tdd_required
eval_required
self_check_required
learning_capture_enabled
required_reliability_mode
```

Bug fixes require Debug-First and TDD. Features and refactors require TDD. Security, authorization, routing, parser, data-migration, public-contract and high-risk flags also require TDD. `AI_SYSTEM` requires eval evidence and `PASS_K` reliability.

## Debug-First

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
defect_class
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

Allowed defect classes:

```text
APPLICATION_DEFECT
ENVIRONMENT_DEFECT
GOVERNANCE_DEFECT
```

A required gate passes only when reproduction or equivalent proof exists, the root cause is confirmed and evidence references are present. Three unresolved hypotheses produce `ARCHITECTURE_REVIEW_REQUIRED`.

## Risk-adaptive TDD

`TDD_PROOF_V1` requires:

- RED command exits non-zero with the expected targeted failure;
- GREEN command exits zero after the implementation;
- regression command exits zero;
- every phase has evidence references.

Allowed exception classes:

```text
DOCUMENTATION_ONLY
GENERATED_ARTIFACT
ENVIRONMENT_CONFIGURATION_ONLY
NO_EXECUTABLE_HARNESS
NON_PROMOTABLE_SPIKE
```

An exception never self-approves. For a task whose profile requires TDD, it returns `EXCEPTION_REQUIRES_FINAL_REVIEW`. Equivalent verification and a concrete reason are mandatory.

## Eval-driven development

`EVAL_PLAN_V1` contains:

```text
capability_evals
regression_evals
negative_cases
forbidden_behaviors
grader_type
success_threshold
reliability_mode
run_count
observed_successes
evidence_refs
exploratory_reason
```

Graders:

```text
CODE_BASED
MODEL_BASED
HUMAN
HYBRID
```

Reliability:

```text
PASS_K
PASS_AT_K
```

Governed AI-system tasks require `PASS_K`: all bounded runs must pass. `PASS_AT_K` requires an exploratory reason and cannot satisfy a required governed AI eval gate.

## Pre-review self-check

Executor records `IMPLEMENTATION_SELF_CHECK_V1` before review. It covers:

```text
plan_compliance
scope_compliance
tests_pass
lint_pass
typecheck_pass
format_pass
security_invariants_checked
dependency_delta_checked
migration_delta_checked
documentation_impact_checked
dead_code_checked
temporary_files_checked
external_action_compliance
unresolved_assumptions
evidence_refs
```

Every record includes:

```text
approval_authority: false
```

An incomplete check or unresolved assumption produces `NOT_READY_FOR_REVIEW`. A passing self-check only means the implementation may enter independent review.

## Governed learning

Candidate events are stored in:

```text
.ai/learning/CANDIDATES.jsonl
```

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

Sources:

```text
USER_CORRECTION
FAILED_TASK
REVIEW_FINDING
SUCCESSFUL_PATTERN
```

A duplicate active `dedup_key` is rejected. Candidates remain `PENDING` until a separate promotion event.

Promotion events are stored in:

```text
.ai/learning/PROMOTIONS.jsonl
```

`LEARNING_PROMOTION_V1` requires:

```text
approved_by: FINAL_REVIEWER
approval_verdict: APPROVED
```

It records approved scope, evidence, privacy and staleness conditions. The event always includes:

```text
memory_updated: false
```

The helper never edits `.ai/GOVERNANCE_MEMORY.md`. A later memory update is a separate Final Reviewer-controlled action using current evidence and normal review rules.

## Tool actions

PowerShell:

```text
InitializeProfile
ValidateDebug
ValidateTdd
ValidateEval
RecordSelfCheck
AddLearning
PromoteLearning
ValidateTask
```

Unix/Python:

```text
initialize-profile
validate-debug
validate-tdd
validate-eval
record-self-check
add-learning
promote-learning
validate-task
```

Exit codes:

```text
0  gate passed or not required
2  invalid input, schema or tool contract
3  valid request but governance gate blocked
64 PowerShell 7 required
```

## Review independence

Self-check output is not a reviewer verdict and should not be included as a conclusion in either independent reviewer packet. Learning candidates and promotions are not evidence of implementation correctness. Final Reviewer authority and sibling-review isolation remain unchanged.

## Compatibility

Routing verification supports 3.3.0, 3.3.2, 3.3.3, 3.3.4, 3.4.0 and 3.5.0. A 3.5.0 installation preserves all providers, models, variants, priorities, `only_on`, hidden aliases and Executor work classes.

Uninstall removes exact managed Quality Gate files but preserves task proof, learning events and Governance Memory.
