---
description: Report recorded OpenCode governance usage without estimates
agent: architect
subtask: false
---

Report only usage recorded by OpenCode using `opencode stats`, `--models`, `opencode session list` and sanitized `opencode export --sanitize` evidence where available. Emit `GOVERNANCE_METRICS`, preserve exact attribution, and use `ESTIMATED_VALUES: NONE`. Missing role/model/token/cost/cache/reasoning attribution remains `UNAVAILABLE`; never allocate totals proportionally or infer discovery cost.

This command is observational. Do not mutate governance state, project files, provider authentication or external systems. `NO_AUTOMATIC_EXTERNAL_ACTION` applies.
