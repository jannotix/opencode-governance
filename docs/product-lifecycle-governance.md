# Product Lifecycle Governance

## Classification and assistance

Every request receives `WORK_CLASS` and `DISCOVERY_DEPTH: LIGHT|STANDARD|DEEP`. Discovery is always present. The inferred `ASSISTANCE_MODE` affects explanation style, never safety or evidence.

## Adaptive discovery

Ten progressive blocks cover objectives, users/roles, workflows, data/rules/exceptions, UX/accessibility, security/privacy/audit, administration/reporting/communications, integrations, operation/recovery/support and completeness/delivery. Each block records facts, defaults, unknowns, contradictions, recommendations and confirmation.

## Governed research and challenge

Research is classified as requirement, evidence, recommendation, legal/safety constraint or optional opportunity. It does not become scope automatically. `CONSTRUCTIVE_CHALLENGE` separates objective from proposed solution and explains alternatives, trade-offs and the recommendation. The user may consciously override unless the direction is unsafe, illegal, data-destructive, incompatible with approved requirements or requires false claims.

## Guided decisions

Only conventional, reversible, low-risk and scope-neutral technical defaults may be selected automatically. Material product, technical, legal, security, privacy, retention, commercial and operational decisions require approval and are stored in `PRODUCT_DECISIONS.md`.

## Canonical product artifacts

- `.ai/product/PRODUCT_VISION.md`
- `.ai/product/USER_AND_ROLE_MODEL.md`
- `.ai/product/DOMAIN_AND_PROCESS_MODEL.md`
- `.ai/product/PRODUCT_COMPLETENESS_MATRIX.md`
- `.ai/product/PRODUCT_BLUEPRINT.md`
- `.ai/product/PRODUCT_DECISIONS.md`

The completeness matrix evaluates mandatory areas as `REQUIRED|OPTIONAL|NOT_APPLICABLE|DEFERRED`. A deferred required capability keeps the product incomplete unless approved complete scope changes explicitly.

## Independent discovery review

For new products, deep discovery, vague or high-risk work, both reviewers independently use `DISCOVERY_REVIEW`. Final Reviewer returns `DISCOVERY_PASS|DISCOVERY_DEFECT|DISCOVERY_BLOCKED`.

## Vertical delivery

Plans use end-to-end milestones. `MILESTONE_VALIDATED` does not imply `PRODUCT_COMPLETE`; status must list completed and remaining required capability IDs.

## Final verdicts

`PRODUCT_COMPLETENESS_VERDICT` is `PRODUCT_COMPLETE|PRODUCT_DEFECT|PRODUCT_BLOCKED`. `RELEASE_VERDICT` is `READY_FOR_PRODUCTION|NOT_READY_FOR_PRODUCTION`. Production readiness requires product completeness plus legal, packaging, recovery, deployment, human-owner and release evidence. Neither verdict authorizes deployment.

## Migration

v2 state is migrated lazily. Historical artifacts are preserved; only evidence-backed facts are reconstructed; unsupported items remain unknown; approvals and requirements are never fabricated.
