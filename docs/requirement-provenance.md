# Requirement provenance

OpenCode Governance keeps the user's request separate from Architect interpretation so a planning error cannot become the new source of truth.

## Canonical task evidence

Every governed task stores three requirement artifacts under:

```text
.ai/tasks/<TASK-ID>/
```

### `ORIGINAL_USER_REQUEST.md`

Preserves the actual request supplied by the user/developer before Architect interpretation.

- Preserve wording and intent.
- Redact secret values before persistence.
- Do not replace the original request with a summary.
- Do not silently rewrite it when the plan changes.

### `CLARIFICATION_TRANSCRIPT.md`

Stores material Architect questions and authoritative user/developer answers in chronological order.

- Append clarification rounds.
- Do not rewrite earlier answers silently.
- When a later decision supersedes an earlier one, record the superseding decision explicitly.
- Record explicitly when no clarification was required.

### `APPROVED_REQUIREMENTS.md`

Contains the normalized executable requirement set.

It may be derived only from:

- the original user request;
- authoritative clarification answers;
- primary repository evidence that establishes facts about the existing system.

Material normalized requirements should retain provenance to the input that authorizes them.

## Authority order

The implementation plan is downstream evidence.

It cannot override the canonical requirement trail.

```text
ORIGINAL_USER_REQUEST
        +
CLARIFICATION_TRANSCRIPT
        ↓
APPROVED_REQUIREMENTS
        ↓
ARCHITECT PLAN
        ↓
EXECUTOR IMPLEMENTATION
```

A plan that materially weakens, omits, contradicts or unauthorizedly broadens a controlling user instruction is defective even when Executor implements it perfectly.

## Final Reviewer responsibility

For `TASK_REVIEW`, Final Reviewer must first compare:

```text
ORIGINAL_USER_REQUEST.md
CLARIFICATION_TRANSCRIPT.md
APPROVED_REQUIREMENTS.md
ARCHITECT PLAN
```

Only after validating that interpretation may it judge the implementation.

Example:

```text
User request: application must work completely offline
Architect plan: cloud API is mandatory
Executor: implements cloud API exactly as planned
```

The correct final verdict is:

```text
PLAN_DEFECT
```

Passing tests or perfect plan adherence cannot convert a wrong interpretation into a valid implementation.

## Reviewer independence

Implementation Reviewer and Architecture/Security Reviewer receive the same canonical requirement trail for the task.

They remain independent from each other and must not read the sibling review artifact for the active cycle.

Final Reviewer receives both advisory reports only after they complete and independently validates their findings against primary evidence and the canonical requirement trail.

## Clarification conflicts

When user instructions conflict, Architect must ask which instruction controls.

It must not silently choose one interpretation.

When a later clarification intentionally changes an earlier requirement:

1. preserve the historical instruction;
2. record the later answer in `CLARIFICATION_TRANSCRIPT.md`;
3. identify it as superseding the earlier decision;
4. update `APPROVED_REQUIREMENTS.md` accordingly.

## Secrets

Requirement evidence must never persist real secret values.

Tokens, passwords, credentials, private keys and similar values are redacted with explicit placeholders while preserving the semantic requirement.

## Execution gate

A task cannot reach `READY_FOR_EXECUTION` when:

- any canonical requirement artifact is missing;
- approved requirements materially conflict with controlling user instructions;
- a material ambiguity remains unresolved;
- conflicting user instructions have no explicit controlling decision.

## Repair loop

When Final Reviewer returns `PLAN_DEFECT`, Architect must reopen the canonical requirement trail before revising the plan.

Architect may change `APPROVED_REQUIREMENTS.md` only when authoritative user input or valid primary evidence justifies the change.

The requirement trail exists to prevent an Architect mistake from propagating unchecked through Executor and review.