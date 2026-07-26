# Model configuration

The project does not prescribe a provider or model.

## Choosing models

Connect your preferred providers in OpenCode, then inspect the locally available model registry:

```text
/models
```

or:

```bash
opencode models
```

Copy the exact model ID shown by OpenCode. The installer requires the full `provider/model-id` form.

The workflow has five independently configurable roles:

1. Architect
2. Executor
3. Implementation Reviewer
4. Architecture/Security Reviewer
5. Final Reviewer/Judge

The governed built-in `Build` and `Plan` entry points use the configured Architect model and variant. `Build` runs the complete governed lifecycle; `Plan` is planning-only.

You may use:

- five different models;
- one model for every role;
- any mixed allocation between those extremes.

The repository intentionally contains no recommended vendor/model IDs because availability, naming and model quality change independently of the governance workflow.

## Multiple providers exposing the same model

OpenCode routes an agent through the exact provider named in its model ID. If the same model is available from more than one connected provider, those are separate routes.

For example, a direct provider model and the same model exposed by an aggregator/subscription are not interchangeable unless their `provider/model-id` values are identical. Select the intended route explicitly from `opencode models`.

This allows a direct provider to be used as the primary route while another provider remains available as a manual fallback without changing governance logic.

Do not use an unqualified model name and do not rely on display names to select a subscription.

## Role selection guidance

For Architect, prefer strong repository reasoning, planning, dependency tracing and architectural judgement.

For Executor, prefer reliable tool use, implementation quality, test execution, throughput and long-session stability.

For the two independent Reviewers, diversity is useful when available. They should not share current-cycle findings before completing their own review.

For Final Reviewer/Judge, prefer strong reasoning and evidence adjudication. It may use the same model as Architect or a different model; the workflow does not assume either choice.

## Variant / reasoning

Variants are optional. Enter a value only if the selected model exposes that variant in your OpenCode installation.

Examples are intentionally omitted because variant names are provider-specific and may change.
