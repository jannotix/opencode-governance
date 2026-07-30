---
description: Report persisted governance product task and evidence state
agent: architect
subtask: false
---

Report current state from Git and `.ai/**`, never chat history. Include `WORK_CLASS`, `DISCOVERY_DEPTH`, `DISCOVERY_STATUS`, `MATERIAL_UNKNOWN_COUNT`, `PRODUCT_SCOPE_STATUS`, `PRODUCT_BLUEPRINT_VERSION`, `CURRENT_MILESTONE`, `MILESTONE_STATE`, `COMPLETED_REQUIRED_CAPABILITIES`, `REMAINING_REQUIRED_CAPABILITIES`, `PRODUCT_STATE`, task/review cycle, `EVIDENCE_STATUS`, blockers and resumability.

Read:
- `.ai/product/PRODUCT_VISION.md`
- `.ai/product/USER_AND_ROLE_MODEL.md`
- `.ai/product/DOMAIN_AND_PROCESS_MODEL.md`
- `.ai/product/PRODUCT_COMPLETENESS_MATRIX.md`
- `.ai/product/PRODUCT_BLUEPRINT.md`
- `.ai/product/PRODUCT_DECISIONS.md`

Also report `GOVERNANCE_MEMORY`, `READ_ONLY_DISCOVERY_SWARM`, `GOVERNED_SKILL_ROUTING`, `DEPENDENCY_ADMISSION_GATE`, `PRE_CHANGE_SAFEPOINT`, `CLOSED_LOOP_LEARNING`, `MEMORY_DECISION`, `OPERATIONAL_ASSURANCE`. Do not invent percentages or missing evidence.

## Status integrity contract

Report exact persisted states and evidence references, not optimistic summaries. Include baseline/reference freshness, requirement integrity, approval/blocker, review freeze, current cycle, dependency/safepoint/operational status, failed/unavailable/stale gates and next safe action. An approved deferral remains visible. A partial milestone never produces a completion percentage based on unknown capabilities.

This command is observational: do not mutate source, project documentation, governance state or external systems. `NO_AUTOMATIC_EXTERNAL_ACTION` applies.
