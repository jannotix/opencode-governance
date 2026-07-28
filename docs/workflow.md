# Workflow

## Lifecycle

```text
BASELINE_VALIDATED
→ IDEA_INTAKE
→ PRODUCT_CLASSIFICATION
→ ADAPTIVE_PRODUCT_DISCOVERY
→ GOVERNED_DOMAIN_RESEARCH
→ CONSTRUCTIVE_CHALLENGE
→ PRODUCT_DEFINITION
→ DISCOVERY_DUAL_REVIEW
→ DISCOVERY_ADJUDICATION
→ PRODUCT_SCOPE_APPROVAL
→ CONTEXT_ROUTING
→ DELIVERY_ARCHITECTURE
→ VERTICAL_MILESTONE_PLANNING
→ EVIDENCE + OPERATIONAL PLANNING
→ READY_FOR_EXECUTION
→ IMPLEMENTATION
→ DOCUMENTATION_SYNC
→ EVIDENCE + OPERATIONAL VALIDATION
→ TASK_DUAL_REVIEW
→ TASK_FINAL_ADJUDICATION
→ PRODUCT_COMPLETENESS_RECONCILIATION
→ RELEASE_READINESS
→ VALIDATED_LEARNING
→ LOCAL_COMMITTED
```

Small tasks still use `LIGHT` discovery. Product-specific phases may be `NOT_REQUIRED` only when primary evidence proves no product-scope effect. `NONE` is not a discovery depth.

Use `/ai-workflow` for the complete lifecycle, `/ai-discover` for discovery/refresh/audit, `/ai-plan` for planning only, `/ai-resume` after interruption and `/ai-release` for completeness plus production readiness. Independent reviewers never see sibling current-cycle findings. Only Executor writes source/docs. Push, merge, deploy and rollback remain separate authorizations.
