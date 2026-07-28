---
description: Discover refresh or audit the governed product definition
agent: architect
subtask: false
---

Run `ADAPTIVE_PRODUCT_DISCOVERY` for `$ARGUMENTS`.

Modes: `/ai-discover` starts or continues; `/ai-discover refresh` updates after an approved change; `/ai-discover audit` finds omissions, contradictions, stale decisions and incomplete coverage.

Always set `WORK_CLASS`, `DISCOVERY_DEPTH: LIGHT|STANDARD|DEEP`, `ASSISTANCE_MODE` and `MATERIAL_UNKNOWN_COUNT`. Apply `GOVERNED_DOMAIN_RESEARCH`, `CONSTRUCTIVE_CHALLENGE`, `GUIDED_DECISION_POLICY` and approval rules. Never implement source/docs or turn research into requirements automatically.

Create/update only:
- `.ai/product/PRODUCT_VISION.md`
- `.ai/product/USER_AND_ROLE_MODEL.md`
- `.ai/product/DOMAIN_AND_PROCESS_MODEL.md`
- `.ai/product/PRODUCT_COMPLETENESS_MATRIX.md`
- `.ai/product/PRODUCT_BLUEPRINT.md`
- `.ai/product/PRODUCT_DECISIONS.md`

For required independent review reuse existing reviewer packet/report names with `REVIEW_MODE: DISCOVERY_REVIEW`. Only Final Reviewer controls `DISCOVERY_PASS|DISCOVERY_DEFECT|DISCOVERY_BLOCKED`. Stop after discovery/review/approval and emit `GOVERNANCE_RESULT` with `EVIDENCE_STATUS`.

## Progressive discovery contract

Process ten blocks in order, skipping only items proven irrelevant by authoritative evidence: objective/outcomes; users/roles; end-to-end workflows; data/rules/exceptions; UX/accessibility and all states; security/privacy/authorization/audit; administration/configuration/reporting/communications; integrations/technical constraints; installation/operation/recovery/support; completeness/exclusions/delivery. After each block record `CONFIRMED_FACTS`, `PROPOSED_DEFAULTS`, `MATERIAL_UNKNOWNS`, `CONTRADICTIONS`, `RECOMMENDATIONS`, `USER_CONFIRMATION`.

Research records source, source class, date, applicability, evidence summary, product impact and requirement status. A competitor pattern is never requirement authority. Challenge only when a materially better option exists; explain consequences and recommendation. Only conventional low-risk reversible scope-neutral technical defaults may be selected without approval. Record every material decision, override, blocker, deferral and supersession append-only.

For required `DISCOVERY_REVIEW`, create same-target isolated reviewer packets, request both before consuming either and invoke Final Reviewer only after both complete. `DISCOVERY_PASS` requires zero unresolved material unknowns plus required scope/approval. Do not implement, install dependencies, push, merge or deploy.

`NO_AUTOMATIC_EXTERNAL_ACTION` applies: do not push, merge, deploy, publish, rollback or widen permissions.
