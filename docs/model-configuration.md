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

Copy the exact model ID shown by OpenCode.

The workflow has five independently configurable roles:

1. Architect
2. Executor
3. Implementation Reviewer
4. Architecture/Security Reviewer
5. Final Reviewer/Judge

You may use:

- five different models;
- one model for every role;
- any mixed allocation between those extremes.

The repository intentionally contains no recommended vendor/model IDs because availability, naming and model quality change independently of the governance workflow.

## Role selection guidance

For Architect, prefer strong repository reasoning, planning, dependency tracing and architectural judgement.

For Executor, prefer reliable tool use, implementation quality, test execution, throughput and long-session stability.

For the two independent Reviewers, diversity is useful when available. They should not share current-cycle findings before completing their own review.

For Final Reviewer/Judge, prefer strong reasoning and evidence adjudication. It may use the same model as Architect or a different model; the workflow does not assume either choice.

## Variant / reasoning

Variants are optional. Enter a value only if the selected model exposes that variant in your OpenCode installation.

Examples are intentionally omitted because variant names are provider-specific and may change.