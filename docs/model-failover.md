# Model failover

OpenCode Governance can optionally route a governed role through a primary model and bounded fallback candidates.

## Runtime behavior

A fallback is a complete role restart, not continuation of a partial answer.

```text
primary attempt fails with an eligible classified error
→ partial output is rejected
→ packet and frozen target remain byte-identical
→ next eligible independent route is selected
→ the complete role starts again
→ only the completed matching attempt report is accepted
```

A recovering primary never interrupts a fallback already running. Primary is reconsidered only for a later role invocation or later task after cooldown.

## Native implementation

OpenCode currently binds one model to each agent and the Task tool does not dynamically choose another model. The installer therefore creates hidden internal subagent aliases for configured fallback candidates. Hidden aliases are not additional governance authorities and cannot delegate.

## Profile requirements

Every candidate requires:

```json
{
  "model": "provider/model",
  "variant": "concrete-supported-variant-or-null",
  "variant_policy": "explicit",
  "model_family": "stable-family-id",
  "priority": 1
}
```

`variant_policy` may be `explicit`, `provider_default` or `highest_supported`.

When `variant_policy` is `highest_supported`, a local setup process must resolve and write a concrete `variant` before installation. OpenCode variants are model-specific; the installer does not guess `max`, `thinking`, `high` or `xhigh`.

## Eligible triggers

- `PROVIDER_UNAVAILABLE`
- `RATE_LIMIT`
- `PLAN_QUOTA_EXHAUSTED`
- `MODEL_RETIRED`
- `MODEL_TEMPORARILY_UNAVAILABLE`
- `BOUNDED_TIMEOUT`

`MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS` is a derived condition used by routes that permit a different model family only after every configured provider for the current family has failed.

Authentication, invalid configuration, context overflow, permission denial, safety refusal, malformed packets, validation defects, low-quality output and unclassified errors do not trigger automatic fallback.

## Provider versus model failure

Provider outage, rate limit and plan quota exhaustion prefer the same model through another provider.

Model retirement or global model unavailability skips every candidate in that model family and moves to an eligible different family.

## Independence

The accepted model family for each role is recorded. Final adjudication uses actual selected families rather than intended primaries.

Default policy is fail closed:

```text
allow_degraded_independence: false
```

A Final Reviewer candidate marked `requires_role_rebalance` can run only after conflicting reviewer roles are restarted from their original frozen packets using independent model families.

## Personal continuous-coding target

The intended routing can use these families, after exact local model and variant resolution:

| Role | Primary family | Preferred fallback strategy |
|---|---|---|
| Architect / Build / Plan | MiniMax M3 | MiniMax M3 on OpenCode Go, then Qwen Max |
| Executor | MiMo V2.5 Pro | MiMo through OpenCode Go; Qwen Plus for bounded work; Qwen Max for major/high-risk work |
| Implementation Reviewer | DeepSeek V4 Pro | same model through Alibaba; Qwen Max only after global DeepSeek unavailability |
| Architecture Reviewer | GLM-5.2 | same model through Alibaba/OpenCode Go; Qwen Max as different-family fallback |
| Final Reviewer | GPT-5.6 Sol | Qwen Max through independent providers; GLM only with role rebalance when required |

v3.1 activates failover only for both reviewers and Final Reviewer. Architect/Build/Plan activate in v3.2. Executor activates only with safe rollback in v3.3.
