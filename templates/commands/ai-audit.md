---
description: Run a full adversarial validation of the reusable codebase baseline
agent: architect
subtask: false
---

Run an explicit adversarial baseline, context-index and documentation-inventory audit without modifying application source or project documentation.

Use for a missing/materially stale baseline or context index, inaccurate documentation scope, large merge/rebase/import, major architecture/dependency change, broad milestone or explicit user audit. Do not use automatically for routine task-local changes when validated reusable evidence remains sufficient.

Audit flow:

1. record exact repository reference;
2. broadly refresh DRAFT `.ai/CODEBASE_BASELINE.md` and `.ai/CONTEXT_INDEX.md` using structural/risk-based coverage;
3. refresh `.ai/DOCUMENTATION_SCOPE.md` and deployment/license state from primary evidence;
4. use `question` for material decisions evidence cannot establish; never infer a software license;
5. record material generated/vendor/cache/binary exclusions;
6. set `BASELINE_REVALIDATION_REQUIRED` while active;
7. create `.ai/baseline-audits/<AUDIT-ID>/`;
8. invoke `reviewer` and `reviewer-architecture` independently in `BASELINE_AUDIT` mode against the same repository reference, baseline, context index and documentation inventory; do not expose sibling reports;
9. after both complete, invoke `final-reviewer` in `BASELINE_AUDIT` mode;
10. on `BASELINE_DEFECT`, apply only validated baseline/context-index/documentation-scope corrections to `.ai/` and repeat with fresh review artifacts;
11. on `BASELINE_PASS`, set `BASELINE_VALIDATED`, record validated reference/index freshness and append history;
12. after three failed baseline adjudications set `BASELINE_BLOCKED`.

A validated baseline/index may record pre-existing defects, documentation gaps, `LICENSE_DECISION_REQUIRED` and unknowns. Validation means reusable governance context is materially faithful, not that the codebase is defect-free.

Never send baseline findings to Executor automatically. Never expose secret values.
