# OpenCode Governance

Provider- and model-agnostic product-lifecycle and engineering governance for OpenCode projects.

> Community project. Not affiliated with or maintained by the OpenCode team.

v3 guides an idea through adaptive product discovery, constructive technical challenge, approved product definition, vertical delivery, evidence-driven implementation, independent review, product-completeness reconciliation and production-readiness assessment.

## Core invariants

- Seven public governance agents; `architect` is default and orchestrator.
- Only `executor` writes application source and approved project documentation.
- Implementation and architecture/security reviewers remain independent.
- Final Reviewer controls baseline, discovery, task, product and release adjudication.
- Requirement provenance and evidence outrank summaries and assertions.
- No automatic push, merge, deployment or rollback.
- Provider/model IDs are supplied during installation.
- Optional fallback aliases are hidden routing transports, not additional governance authorities.

## Commands

```text
/ai-init
/ai-audit
/ai-docs
/ai-discover
/ai-plan
/ai-execute
/ai-review
/ai-workflow
/ai-status
/ai-resume
/ai-metrics
/ai-release
```

## Installation

Legacy single-model routing:

- Windows: `./scripts/install.ps1`
- macOS/Linux: `chmod +x scripts/install.sh && ./scripts/install.sh`

Reviewer failover routing:

- copy `examples/routing/continuous-coding.template.json` to a local untracked file;
- replace every model ID with the exact value returned by the local OpenCode catalog;
- resolve every `variant_policy: highest_supported` to a concrete supported `variant`;
- Windows: `./scripts/install.ps1 -NonInteractive -RoutingConfigPath <profile.json>`;
- macOS/Linux: `./scripts/install.sh --routing-config <profile.json>`.

The installer renders seven public agents and twelve commands, preserves unrelated configuration and creates a timestamped backup. With a routing profile it also renders hidden reviewer/final fallback aliases and writes the non-secret `opencode-governance-routing.json` manifest. This README is the canonical installation reference.

A fallback never continues a partial response. It restarts the complete role from the same packet and frozen target. A recovering primary does not interrupt an active fallback; it becomes eligible again only for a later invocation after cooldown.

## Project state

```text
.ai/
├── CODEBASE_BASELINE.md
├── CONTEXT_INDEX.md
├── INSTRUCTION_INDEX.md
├── GOVERNANCE_MEMORY.md
├── DOCUMENTATION_SCOPE.md
├── DEPLOYMENT_SCOPE.md
├── PROJECT_HISTORY.md
├── STATUS.md
├── product/
│   ├── PRODUCT_VISION.md
│   ├── USER_AND_ROLE_MODEL.md
│   ├── DOMAIN_AND_PROCESS_MODEL.md
│   ├── PRODUCT_COMPLETENESS_MATRIX.md
│   ├── PRODUCT_BLUEPRINT.md
│   └── PRODUCT_DECISIONS.md
├── baseline-audits/
└── tasks/
```

Discovery is always `LIGHT`, `STANDARD` or `DEEP`. Domain evidence and recommendations do not become requirements automatically. A validated milestone may remain `PRODUCT_INCOMPLETE`. `PRODUCT_COMPLETENESS_VERDICT` is separate from `RELEASE_VERDICT`.

## Documentation

Focused references: [Product Lifecycle Governance](docs/product-lifecycle-governance.md), [Model Failover](docs/model-failover.md), [Workflow](docs/workflow.md), [Requirement Provenance](docs/requirement-provenance.md), [Context Efficiency and Resume](docs/context-efficiency-resume.md), [Evidence-Driven Verification](docs/evidence-driven-verification.md), [Operational Assurance](docs/operational-assurance.md), [Permissions](docs/permissions.md), [Project Documentation](docs/project-documentation.md) and [Troubleshooting](docs/troubleshooting.md).

## Verification

Base rendered contract:

- Windows: `./scripts/verify.ps1`
- macOS/Linux: `./scripts/verify.sh`

Optional routing contract:

- Windows: `./scripts/verify-routing.ps1`
- macOS/Linux: `bash ./scripts/verify-routing.sh`

## License

FSL-1.1-MIT. Each released version becomes available under the MIT License on the second anniversary of its release date. See [LICENSE](LICENSE).
