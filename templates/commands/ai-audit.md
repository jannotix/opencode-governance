---
description: Run a full adversarial validation of reusable repository governance evidence
agent: architect
subtask: false
---

Run an explicit adversarial baseline, context-index, instruction-index and documentation-inventory audit without modifying application source or project documentation.

Use for a missing/materially stale baseline/context/instruction index, inaccurate documentation scope, large merge/rebase/import, major architecture/dependency change, broad milestone or explicit user audit. Do not use automatically for routine task-local changes when validated reusable evidence remains sufficient.

Audit flow:

1. record exact repository reference;
2. broadly refresh DRAFT `.ai/CODEBASE_BASELINE.md`, `.ai/CONTEXT_INDEX.md` and `.ai/INSTRUCTION_INDEX.md` using structural/risk-based coverage;
3. refresh `.ai/DOCUMENTATION_SCOPE.md` and deployment/license state from primary evidence;
4. refresh reusable validation knowledge: authoritative test/build/lint/static/CI commands, public contract mechanisms, dependency manifests/lockfiles, code generators, migration mechanisms, existing non-functional budgets/fuzz/property tools and explicit owner/human-review policies;
5. use `question` for material decisions or instruction conflicts evidence cannot establish; never infer a software license or arbitrary instruction precedence;
6. record material generated/vendor/cache/binary exclusions;
7. set `BASELINE_REVALIDATION_REQUIRED` while active;
8. create `.ai/baseline-audits/<AUDIT-ID>/`;
9. invoke `reviewer` and `reviewer-architecture` independently in `BASELINE_AUDIT` mode against the same repository reference, baseline, context index, instruction index and documentation inventory; do not expose sibling reports;
10. after both complete, invoke `final-reviewer` in `BASELINE_AUDIT` mode;
11. on `BASELINE_DEFECT`, apply only validated baseline/context/instruction-index/documentation-scope corrections to `.ai/` and repeat with fresh review artifacts;
12. on `BASELINE_PASS`, set `BASELINE_VALIDATED`, record validated reference/index freshness and append history;
13. after three failed baseline adjudications set `BASELINE_BLOCKED`.

A validated baseline/index may record pre-existing defects, documentation gaps, instruction conflicts requiring later clarification, unavailable validation capabilities, `LICENSE_DECISION_REQUIRED` and unknowns. Validation means reusable governance context is materially faithful, not that the codebase is defect-free.

Do not pre-create task `VERIFICATION_PROFILE.md` artifacts during audit. Never send baseline findings to Executor automatically. Never expose secret values.
