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

The three roles can use:

- the same model;
- three different models;
- two models split across the three roles.

For Architect and Reviewer, prefer models with strong reasoning, repository comprehension and review performance.

For Executor, prefer a model with reliable tool use, implementation quality and test execution.

## Variant / reasoning

Variants are optional. Enter a value only if the selected model exposes that variant in your OpenCode installation.

Examples are intentionally omitted because variant names are provider-specific and may change.
