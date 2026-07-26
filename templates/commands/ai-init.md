---
description: Initialize and adversarially validate project-local governance state
agent: architect
subtask: false
---

Initialize governance for the current repository without modifying application source code or project documentation.

Create the project-local governance artifacts if missing:

- `.ai/CODEBASE_BASELINE.md`
- `.ai/DEPLOYMENT_SCOPE.md`
- `.ai/DOCUMENTATION_SCOPE.md`
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
- existing documentation state and contradictions with implementation;
- blocking unknowns;
- material exclusions such as generated, vendored, cached or binary-only content when applicable.

For very large repositories, establish broad structural and risk-based coverage. Do not waste context blindly reading generated/vendor/cache artifacts; record material exclusions and unresolved unknowns.

When repository evidence does not resolve a material product/project decision, use the `question` tool to ask the developer/project owner instead of inventing an answer. Do not repeat questions already answered by the user or authoritative project evidence.

Set baseline state to `BASELINE_DRAFT`.

## Project documentation inventory

Create or update `.ai/DOCUMENTATION_SCOPE.md` without creating project docs directly from Architect.

Detect and preserve any coherent existing documentation convention. If no convention exists, set the default documentation root to top-level `docs/`, explicitly outside the production/runtime boundary.

For distributable applications, record the default minimum documentation set as `REQUIRED` unless genuinely not applicable:

- `docs/README.md` — overview, requirements, capabilities and documentation index;
- `docs/INSTALLATION.md` — complete step-by-step installation and first-start guide;
- `docs/USER_MANUAL.md` — task-oriented user guide;
- `docs/wiki/README.md` — wiki/index for operational/task-oriented pages;
- `docs/CHANGELOG.md` — maintained version/change history;
- licensing documentation backed by an explicit project license decision.

Also assess `ADMIN_MANUAL`, `UPGRADE`, `ARCHITECTURE`, `CONFIGURATION`, `API`, `SECURITY`, `TROUBLESHOOTING` and `RELEASE_NOTES` as `REQUIRED`, `OPTIONAL` or `NOT_APPLICABLE` based on the project.

For each canonical document record:

- canonical path;
- status/applicability;
- intended audience/purpose;
- implementation/configuration sources of truth;
- current state: present/current, stale, missing, contradictory or unknown;
- last synchronized reference when known.

Determine the software license state only from explicit user/project-owner instruction or authoritative existing legal files. Never choose or infer a license. If no explicit license decision exists, record `LICENSE_DECISION_REQUIRED`; ask the developer/project owner when a decision is needed, and keep release readiness blocked until resolved.

Populate `DEPLOYMENT_SCOPE.md` with the production runtime boundary and explicitly identify `docs/**`, `.ai/**`, tests, development documentation/evidence, local tooling, IDE/temp files and secrets as development/repository-only by default. Record specific legal/notice documentation exceptions only when required.

## Mandatory independent baseline audit

The Architect draft is not authoritative.

Create `.ai/baseline-audits/<AUDIT-ID>/` and request two independent `BASELINE_AUDIT` reviews against the same repository reference and draft baseline/documentation inventory:

- `reviewer`: implementation/runtime/regression/documentation-accuracy audit;
- `reviewer-architecture`: architecture/security/data/dependency/deployment/documentation/license audit.

Neither reviewer may receive or read the sibling reviewer's current audit output. Request both audits before consuming either result and run them concurrently when the runtime supports concurrent Task calls.

After both audits complete, invoke `final-reviewer` in `BASELINE_AUDIT` mode with the draft baseline, documentation scope, repository reference, both audit artifacts and relevant primary evidence.

Only `final-reviewer` controls the baseline verdict:

- `BASELINE_PASS`
- `BASELINE_DEFECT`
- `BLOCKED`

If `BASELINE_DEFECT`, apply only validated governance corrections to `.ai/`, then run a fresh independent dual baseline audit and final adjudication.

Maximum baseline adjudication cycles: 3.

After the third failed cycle, set `BASELINE_BLOCKED` and stop. Do not begin source implementation.

If `BASELINE_PASS`, set `BASELINE_VALIDATED`, record the validated repository reference and append the validation evidence to `.ai/PROJECT_HISTORY.md`.

`BASELINE_PASS` means the baseline and documentation inventory are trustworthy enough for planning; it does not mean the source code or existing docs are defect-free.

Initialize `PROJECT_HISTORY.md` as an append-only chronological ledger. Each event should record timestamp, role, configured model when known, task/milestone/slice, action, result, evidence, state transition, Git action/commit message and push status. Never store secret values.

Do not rebuild or re-audit a valid `BASELINE_VALIDATED` baseline merely because `/ai-init` is run again. Use `/ai-audit` when explicit or material baseline revalidation is required.