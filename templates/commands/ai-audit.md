---
description: Run a full adversarial validation of the reusable codebase baseline
agent: architect
subtask: false
---

Run an explicit adversarial baseline audit for the current repository without modifying application source code.

Use this command when:

- the repository has no `BASELINE_VALIDATED` baseline;
- the baseline is materially stale or incomplete;
- a large merge/rebase materially changed repository structure;
- substantial code was imported;
- a major architecture or dependency change occurred;
- a broad milestone warrants repository-wide revalidation;
- the user explicitly requests a codebase audit.

Do not use this command automatically for routine task-local changes when the validated baseline remains sufficient.

## Audit flow

1. inspect current repository state and record the exact repository reference being audited;
2. reverse-engineer the repository broadly enough to refresh the DRAFT `.ai/CODEBASE_BASELINE.md`, architecture map, dependency/call-path map, known defects/risks, security-sensitive areas and material unknowns;
3. for very large repositories use broad structural and risk-based coverage rather than blindly reading generated/vendor/cache/binary artifacts; record material exclusions explicitly;
4. set baseline state to `BASELINE_REVALIDATION_REQUIRED` while audit is active;
5. create `.ai/baseline-audits/<AUDIT-ID>/`;
6. invoke `reviewer` and `reviewer-architecture` independently in `BASELINE_AUDIT` mode against the same repository reference and draft baseline;
7. do not expose either current audit report to the sibling reviewer;
8. request both audits before consuming either result and run them concurrently when the runtime supports concurrent Task calls;
9. after both complete, invoke `final-reviewer` in `BASELINE_AUDIT` mode;
10. if `BASELINE_DEFECT`, apply only validated baseline corrections to `.ai/` and repeat with fresh independent audit artifacts;
11. if `BASELINE_PASS`, set `BASELINE_VALIDATED`, record the validated repository reference and append the result to `.ai/PROJECT_HISTORY.md`;
12. after three failed baseline adjudication cycles set `BASELINE_BLOCKED` and stop.

Only `final-reviewer` controls the baseline verdict:

- `BASELINE_PASS`
- `BASELINE_DEFECT`
- `BLOCKED`

A validated baseline may contain documented pre-existing bugs and risks. Validation means those material facts are accurately represented, not that the source code is defect-free.

Never send baseline findings to Executor automatically. This command audits and updates governance evidence only; it does not implement source corrections.

Never expose secret values.