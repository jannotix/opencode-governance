---
description: Initialize and adversarially validate project-local governance state
agent: architect
subtask: false
---

Initialize governance for the current repository without modifying source code.

Create the project-local governance artifacts if missing:

- `.ai/CODEBASE_BASELINE.md`
- `.ai/DEPLOYMENT_SCOPE.md`
- `.ai/PROJECT_HISTORY.md`
- `.ai/STATUS.md`
- `.ai/tasks/`
- `.ai/baseline-audits/`

Do not overwrite valid existing project state.

## Initial draft baseline

Before first implementation, perform a comprehensive adversarial reverse-engineering intake of the repository and populate a DRAFT `CODEBASE_BASELINE.md` with:

- baseline repository commit/reference;
- stack and supported runtimes;
- entry points;
- architecture map covering major modules, boundaries and responsibilities;
- dependency/call-path map covering important module relationships and high-value execution paths;
- data flows and trust boundaries;
- database/schema state and change mechanism;
- external integrations;
- tests and validation capabilities;
- deployment boundary;
- security-sensitive areas;
- known defects and regression risks;
- technical constraints;
- blocking unknowns;
- material exclusions such as generated, vendored, cached or binary-only content when applicable.

For very large repositories, establish broad structural and risk-based coverage. Do not waste context blindly reading generated/vendor/cache artifacts; record material exclusions and unresolved unknowns.

Set baseline state to `BASELINE_DRAFT`.

## Mandatory independent baseline audit

The Architect draft is not authoritative.

Create `.ai/baseline-audits/<AUDIT-ID>/` and request two independent `BASELINE_AUDIT` reviews against the same repository reference and draft baseline:

- `reviewer`: implementation/runtime/regression audit;
- `reviewer-architecture`: architecture/security/data/dependency/deployment audit.

Neither reviewer may receive or read the sibling reviewer's current audit output. Request both audits before consuming either result and run them concurrently when the runtime supports concurrent Task calls.

After both audits complete, invoke `final-reviewer` in `BASELINE_AUDIT` mode with the draft baseline, repository reference, both audit artifacts and relevant primary evidence.

Only `final-reviewer` controls the baseline verdict:

- `BASELINE_PASS`
- `BASELINE_DEFECT`
- `BLOCKED`

If `BASELINE_DEFECT`, apply only validated baseline corrections to `.ai/`, then run a fresh independent dual baseline audit and final adjudication.

Maximum baseline adjudication cycles: 3.

After the third failed cycle, set `BASELINE_BLOCKED` and stop. Do not begin source implementation.

If `BASELINE_PASS`, set `BASELINE_VALIDATED`, record the validated repository reference and append the validation evidence to `.ai/PROJECT_HISTORY.md`.

`BASELINE_PASS` means the baseline is trustworthy and records material known defects/risks; it does not mean the source code is bug-free.

Populate `DEPLOYMENT_SCOPE.md` with the production runtime boundary and explicitly identify tests, development documentation, `.ai/`, review evidence, local tooling, IDE/temp files and secrets as development-only unless the project demonstrably requires a specific file at runtime.

Initialize `PROJECT_HISTORY.md` as an append-only chronological ledger. Each event should record timestamp, role, configured model when known, task/milestone/slice, action, result, evidence, state transition, Git action/commit message and push status. Never store secret values.

Do not rebuild or re-audit a valid `BASELINE_VALIDATED` baseline merely because `/ai-init` is run again. Use `/ai-audit` when explicit or material baseline revalidation is required.