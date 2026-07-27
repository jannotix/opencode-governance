# Token efficiency and usage telemetry

OpenCode Governance v1.7 adds output-efficiency rules and observational usage telemetry without changing model reasoning, provider routing or the governed lifecycle.

## Adaptive output efficiency

All seven governance agents use `ADAPTIVE_OUTPUT_EFFICIENCY`:

- reason fully, communicate compactly;
- omit pleasantries, duplicated conclusions and obvious tool narration;
- reference canonical `.ai/**` artifacts instead of copying them;
- preserve exact code, commands, paths, identifiers, errors, verdicts and material evidence;
- keep reviewer findings structured and evidence-dense.

Agents must expand their explanation when compression could reduce correctness or create ambiguity, especially for security findings, destructive/irreversible operations, schema/data migrations, unresolved requirements, architectural disagreements, blockers and recovery instructions.

Output efficiency never overrides requirement provenance, safety, evidence completeness, reviewer independence or Final Reviewer authority.

## `/ai-metrics`

```text
/ai-metrics [scope]
```

The command is read-only. It uses usage data recorded by the installed OpenCode runtime, preferring the narrowest applicable combination of:

```text
opencode stats
opencode stats --models
opencode session list --format json
opencode export <sessionID> --sanitize
```

Where the runtime data proves attribution, the report can aggregate actual usage by governance role and model. Depending on the OpenCode version/provider/session data, available fields may include requests/turns, input tokens, output tokens, reasoning tokens, cache read/write tokens, total tokens and cost.

Missing data is reported as `UNAVAILABLE`. Model totals are never proportionally split across roles, and token usage is never estimated from text length, context size, model pricing or prompt size.

If model-level usage is available but role attribution cannot be proven, `/ai-metrics` reports the real model totals and marks role attribution `PARTIAL` or `UNAVAILABLE`.

## Privacy

Sanitized session export is used when supported and needed for attribution. Session exports are temporary analysis inputs and are not persisted in the project or `.ai/**` by default. Metrics output must not reproduce conversation bodies, credentials, secret values or private keys.

`/ai-metrics` does not change `RUN_STATE.json`, `.ai/STATUS.md`, task verdicts, provider authentication or application files.

## Machine-readable summary

Metrics output ends with:

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

This makes model-pool optimization evidence-based while keeping unavailable telemetry explicit instead of inventing precision.