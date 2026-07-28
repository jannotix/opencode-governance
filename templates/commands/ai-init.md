---
description: Initialize and adversarially validate project governance state
agent: architect
subtask: false
---

Initialize `.ai/CODEBASE_BASELINE.md`, `.ai/CONTEXT_INDEX.md`, `.ai/INSTRUCTION_INDEX.md`, `.ai/GOVERNANCE_MEMORY.md`, documentation/deployment scope, history/status, tasks and baseline audits without source/doc edits.

Create only missing product files:
- `.ai/product/PRODUCT_VISION.md`
- `.ai/product/USER_AND_ROLE_MODEL.md`
- `.ai/product/DOMAIN_AND_PROCESS_MODEL.md`
- `.ai/product/PRODUCT_COMPLETENESS_MATRIX.md`
- `.ai/product/PRODUCT_BLUEPRINT.md`
- `.ai/product/PRODUCT_DECISIONS.md`

For v2 state use `PRODUCT_MIGRATION_DRAFT`: preserve history; reconstruct only evidence-backed facts; mark unsupported content unknown; never convert assumptions to approvals; never rewrite task provenance; append migration evidence; extend legacy `RUN_STATE.json`. Do not force deep discovery solely because a project predates v3.

Discover read-only `Explore`/`Scout`, skills, validation and `OPERATIONAL_ASSURANCE` capabilities. Run independent baseline audit and Final Reviewer adjudication, maximum three failures. Never create task-specific evidence during init.
