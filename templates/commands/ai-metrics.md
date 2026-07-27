---
description: Report real OpenCode token and cost usage for governance roles without estimating missing data
agent: architect
subtask: false
---

Report governance usage for the requested scope:

$ARGUMENTS

This command is observational. Do not modify application source, project documentation, governance task state or provider authentication.

## Ground truth

Use only usage recorded by the installed OpenCode runtime. Prefer, where supported:

1. `opencode stats` with the narrowest applicable project/date scope;
2. `opencode stats --models` for real model totals;
3. `opencode session list --format json` to identify relevant sessions;
4. `opencode export <sessionID> --sanitize` only when needed to attribute recorded usage to governance roles/tasks.

Never estimate token counts from text length, context-window size, model pricing, prompt size or prose descriptions. Never split model totals proportionally across roles. If OpenCode does not expose a requested field or attribution, report `UNAVAILABLE`.

## Scope and attribution

When a TASK ID is supplied, associate sessions/messages only from explicit task/session evidence such as the task ID, governed task artifacts or unambiguous session metadata. Do not use fuzzy guesses.

When no TASK ID is supplied, report the narrowest requested project/date scope or current project when supported.

Attribute actual usage to these governance roles when the exported runtime data proves the association:

- Architect / Build / Plan;
- Executor;
- Implementation Reviewer;
- Architecture/Security Reviewer;
- Final Reviewer.

Keep Build and Plan distinct when runtime metadata distinguishes them; otherwise report their shared Architect-model usage without inventing a split.

For each attributable role/model report only fields actually exposed by OpenCode, such as requests/turns, input tokens, output tokens, reasoning tokens, cache read/write tokens, total tokens and cost. Missing fields are `UNAVAILABLE`, not zero.

If model-level totals are real but role attribution is not recoverable, report the model totals and `ROLE_ATTRIBUTION: UNAVAILABLE` or `PARTIAL`.

Rank roles/models only when comparable actual token totals are available for the same scope.

## Privacy and temporary data

Use sanitized exports when supported. Raw or sanitized session exports are temporary analysis inputs: do not persist them in the project or `.ai/**` by default. Do not reproduce conversation bodies, credentials, secrets or private keys in the metrics output. Remove temporary exports after aggregation when practical.

If the installed OpenCode version lacks a required stats/session/export capability, return the exact unsupported command/capability and `METRICS_UNAVAILABLE` for the affected scope. Never fabricate a fallback estimate.

## Output

Return a concise human-readable table plus this machine-readable summary:

```text
GOVERNANCE_METRICS
SCOPE: <TASK:<id> | PROJECT:<path/name> | DAYS:<n> | ALL>
SOURCE: <actual OpenCode commands/data used>
ATTRIBUTION: COMPLETE|PARTIAL|UNAVAILABLE
ROLES_WITH_ACTUAL_USAGE: <count>
MODELS_WITH_ACTUAL_USAGE: <count>
TOTAL_TOKENS: <actual total or UNAVAILABLE>
TOTAL_COST: <actual cost or UNAVAILABLE>
ESTIMATED_VALUES: NONE
STATUS: COMPLETE|PARTIAL|METRICS_UNAVAILABLE
```

Keep the report evidence-dense. State limitations once. Do not alter `RUN_STATE.json`, `.ai/STATUS.md` or task verdicts.