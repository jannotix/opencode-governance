# Workflow

## Complete workflow

```text
/ai-workflow <task>
```

Architect inspects the repository and creates the plan. Executor implements it. Reviewer independently verifies the result.

Reviewer verdicts:

- `PASS`
- `IMPLEMENTATION_DEFECT`
- `PLAN_DEFECT`
- `BLOCKED`

Implementation defects go back to Executor for targeted correction.

Plan defects go back to Architect for re-investigation and a revised plan.

Automatic correction is limited to three review cycles.

## Planning only

```text
/ai-plan <task>
```

No implementation is performed.

## Execute an existing plan

```text
/ai-execute <task-id-or-plan-id>
```

## Independent review

```text
/ai-review <task-id>
```

## Status

```text
/ai-status
```
