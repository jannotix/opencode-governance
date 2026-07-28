---
description: Create or synchronize governed project documentation
agent: architect
subtask: false
---

Create/update canonical project documentation only through Executor and approved scope. Reconcile docs with `.ai/product/PRODUCT_BLUEPRINT.md`, `.ai/product/PRODUCT_COMPLETENESS_MATRIX.md`, `.ai/product/PRODUCT_DECISIONS.md`, task requirements and validated behavior. Do not label a partial milestone complete.

Assess `docs/INSTALLATION.md`, `docs/USER_MANUAL.md`, `docs/wiki/README.md`, overview, changelog, admin/upgrade/API/security/troubleshooting/release docs as applicable. Never invent license terms. Preserve documentation/deployment scope and evidence requirements.

## Documentation correctness contract

Determine exactly one `DOCUMENTATION_IMPACT: NONE|UPDATE_REQUIRED|CREATE_REQUIRED` for each governed task. Documentation must describe current validated behavior, exact installation/configuration/upgrade/recovery steps and approved limitations. Product, task, source, configuration and release docs must not contradict one another. Keep `.ai/**` and normal `docs/**` outside runtime packaging unless an explicit requirement/legal mechanism says otherwise.

Executor is the only documentation writer. Documentation changes pass the same evidence, dual review and Final Reviewer gates as source. `NO_AUTOMATIC_EXTERNAL_ACTION` applies.
