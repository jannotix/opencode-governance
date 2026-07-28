---
description: Initialize and adversarially validate project governance state
agent: architect
subtask: false
---

Before any other governance write, run `PERMISSION_BOOTSTRAP_PROBE` against the current project root:

1. create `.ai/permission-verification.tmp` with a non-secret timestamp and fixed probe marker;
2. read the file back and verify the marker;
3. delete the file;
4. verify the temporary file no longer exists.

If create, read-back or deletion is denied or fails, stop immediately with:

```text
GOVERNANCE_PERMISSION_BLOCKED
FAILED_PATH: .ai/permission-verification.tmp
REQUIRED_ACTION: reinstall the current governance version, fully restart OpenCode, then rerun /ai-init
```

Do not continue with a partially initialized `.ai/**` state after a failed probe.

Initialize `.ai/CODEBASE_BASELINE.md`, `.ai/CONTEXT_INDEX.md`, `.ai/INSTRUCTION_INDEX.md`, `.ai/GOVERNANCE_MEMORY.md`, documentation/deployment scope, history/status, tasks and baseline audits without source/doc edits.

Create only missing product files:
- `.ai/product/PRODUCT_VISION.md`
- `.ai/product/USER_AND_ROLE_MODEL.md`
- `.ai/product/DOMAIN_AND_PROCESS_MODEL.md`
- `.ai/product/PRODUCT_COMPLETENESS_MATRIX.md`
- `.ai/product/PRODUCT_BLUEPRINT.md`
- `.ai/product/PRODUCT_DECISIONS.md`

For v2 state use `PRODUCT_MIGRATION_DRAFT`: preserve history; reconstruct only evidence-backed facts; mark unsupported content unknown; never convert assumptions to approvals; never rewrite task provenance; append migration evidence; extend legacy `RUN_STATE.json`. Do not force deep discovery solely because a project predates v3.

After initialization or migration, run `PRODUCT_ARTIFACT_SET_VERIFIED`: verify that all six canonical product files exist, are readable and contain at least their required schema metadata. Create only genuinely missing DRAFT files from authoritative evidence. Do not report initialization success while any canonical product file is absent, empty or unreadable.

Discover read-only `Explore`/`Scout`, skills, validation and `OPERATIONAL_ASSURANCE` capabilities. Run independent baseline audit and Final Reviewer adjudication, maximum three failures. Never create task-specific evidence during init.

## Initialization contract

Initialization is read-only outside `.ai/**`. Build a DRAFT baseline and reusable routing indexes from primary repository evidence: repository reference, stack/runtimes, entry points, architecture, important dependency/call paths, data/trust boundaries, schema/migrations, public contracts, integrations, validation, deployment, security-sensitive areas, known defects/risks, documentation, instructions/skills, dependency admission and operational capabilities. Record unknowns and exclusions; do not blindly consume generated/vendor/cache/binary content.

Run `BASELINE_DUAL_AUDIT`: request both independent reviewers before consuming either report, keep sibling reports isolated and let Final Reviewer alone return `BASELINE_PASS|BASELINE_DEFECT|BLOCKED`. Apply only validated `.ai/**` corrections, maximum three failed cycles. No source implementation begins before `BASELINE_VALIDATED`.

Product migration never fabricates history or approval. Existing v2 tasks remain resumable; product gaps unrelated to a small active task may remain explicit without forcing a full product interview. `NO_AUTOMATIC_EXTERNAL_ACTION` applies.
