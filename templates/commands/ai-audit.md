---
description: Run a full adversarial validation of the reusable codebase baseline
agent: architect
subtask: false
---

Run an explicit adversarial baseline and documentation-inventory audit for the current repository without modifying application source code or project documentation.

Use this command when:

- the repository has no `BASELINE_VALIDATED` baseline;
- the baseline is materially stale or incomplete;
- `.ai/DOCUMENTATION_SCOPE.md` is missing or materially inaccurate;
- a large merge/rebase materially changed repository structure;
- substantial code was imported;
- a major architecture or dependency change occurred;
- a broad milestone warrants repository-wide revalidation;
- the user explicitly requests a codebase audit.

Do not use this command automatically for routine task-local changes when the validated baseline remains sufficient.

## Audit flow

1. inspect current repository state and record the exact repository reference being audited;
2. reverse-engineer the repository broadly enough to refresh the DRAFT `.ai/CODEBASE_BASELINE.md`, architecture map, dependency/call-path map, known defects/risks, security-sensitive areas and material unknowns;
3. inspect existing project documentation and refresh `.ai/DOCUMENTATION_SCOPE.md` with canonical paths, applicability, stale/missing/contradictory docs and explicit license state;
4. for distributable applications, assess whether the documentation scope includes the applicable minimum overview/readme, step-by-step installation, user manual, wiki/index, changelog and licensing documentation;
5. never choose or infer a software license; if evidence does not establish an explicit license decision, record `LICENSE_DECISION_REQUIRED` and ask the developer/project owner when the audit/release needs that decision;
6. when any other material product/project decision cannot be established from primary evidence, use the `question` tool rather than inventing an answer;
7. for very large repositories use broad structural and risk-based coverage rather than blindly reading generated/vendor/cache/binary artifacts; record material exclusions explicitly;
8. set baseline state to `BASELINE_REVALIDATION_REQUIRED` while audit is active;
9. create `.ai/baseline-audits/<AUDIT-ID>/`;
10. invoke `reviewer` and `reviewer-architecture` independently in `BASELINE_AUDIT` mode against the same repository reference, draft baseline and documentation inventory;
11. do not expose either current audit report to the sibling reviewer;
12. request both audits before consuming either result and run them concurrently when the runtime supports concurrent Task calls;
13. after both complete, invoke `final-reviewer` in `BASELINE_AUDIT` mode;
14. if `BASELINE_DEFECT`, apply only validated baseline/documentation-scope corrections to `.ai/` and repeat with fresh independent audit artifacts;
15. if `BASELINE_PASS`, set `BASELINE_VALIDATED`, record the validated repository reference and append the result to `.ai/PROJECT_HISTORY.md`;
16. after three failed baseline adjudication cycles set `BASELINE_BLOCKED` and stop.

Only `final-reviewer` controls the baseline verdict:

- `BASELINE_PASS`
- `BASELINE_DEFECT`
- `BLOCKED`

A validated baseline may contain documented pre-existing bugs, documentation gaps, `LICENSE_DECISION_REQUIRED` and risks. Validation means those material facts are accurately represented, not that source code/documentation is defect-free or release-ready.

Never send baseline findings to Executor automatically. This command audits and updates governance evidence only; it does not implement source or project-documentation corrections.

Never expose secret values.