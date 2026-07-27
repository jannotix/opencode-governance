---
description: Initialize and adversarially validate project-local governance state
agent: architect
subtask: false
---

Initialize governance for the current repository without modifying application source code or project documentation.

Create project-local governance artifacts if missing:

- `.ai/CODEBASE_BASELINE.md`
- `.ai/CONTEXT_INDEX.md`
- `.ai/INSTRUCTION_INDEX.md`
- `.ai/DEPLOYMENT_SCOPE.md`
- `.ai/DOCUMENTATION_SCOPE.md`
- `.ai/PROJECT_HISTORY.md`
- `.ai/STATUS.md`
- `.ai/tasks/`
- `.ai/baseline-audits/`

Do not overwrite valid existing project state.

Build a DRAFT baseline from broad structural and risk-based reverse engineering: repository reference, stack/runtimes, entry points, architecture, important dependency/call paths, data flows/trust boundaries, schema/data mechanisms, integrations, validation capabilities, public contracts, generated-artifact mechanisms, migration mechanisms, deployment, security-sensitive areas, known defects/risks, documentation state, technical constraints, unknowns and material exclusions. Do not waste context blindly reading generated/vendor/cache/binary artifacts.

Create/update `.ai/CONTEXT_INDEX.md` as a compact routing index of material modules/paths, entry points, important callers/callees, dependency edges, data stores, trust boundaries, security-sensitive surfaces, canonical documentation, tests/validation capabilities and known risks. It is an index, not a copy of source code.

Create/update `.ai/INSTRUCTION_INDEX.md` from authoritative repository-local instruction/contribution/development files. Record source path, scope/applicable paths, precedence/specificity, material constraints and unresolved conflicts. Tool-specific instructions never silently override the canonical user requirement trail. Material unresolved instruction conflicts require authoritative clarification rather than an invented precedence.

Create/update `.ai/DOCUMENTATION_SCOPE.md` and `.ai/DEPLOYMENT_SCOPE.md`. Preserve coherent existing documentation conventions. For distributable applications, normally record overview/readme, step-by-step installation, user manual, wiki/index, changelog and explicit licensing documentation as required when applicable. Never choose/infer a license; record `LICENSE_DECISION_REQUIRED` when unresolved.

Use `question` for material product/project decisions not established by evidence. Do not repeat answered questions.

Set `BASELINE_DRAFT`, create `.ai/baseline-audits/<AUDIT-ID>/`, and request independent `reviewer` and `reviewer-architecture` `BASELINE_AUDIT` reports against the same repository reference and draft baseline/context/instruction indexes/documentation scope. Neither reviewer may see the sibling report. Then invoke `final-reviewer` in `BASELINE_AUDIT` mode.

Only Final Reviewer controls `BASELINE_PASS`, `BASELINE_DEFECT` or `BLOCKED`. Apply only validated `.ai/` corrections after `BASELINE_DEFECT`. Maximum three baseline adjudication cycles; then `BASELINE_BLOCKED`.

On `BASELINE_PASS`, set `BASELINE_VALIDATED`, record the validated repository reference, baseline/context/instruction-index freshness and append evidence to `.ai/PROJECT_HISTORY.md`.

Initialize `PROJECT_HISTORY.md` as append-only. Never store secret values.

Do not build per-task `VERIFICATION_PROFILE.md` or `VERIFICATION_EVIDENCE.md` during initialization; Evidence-Driven Verification is created lazily for each governed task. Do not rebuild/re-audit a valid baseline merely because `/ai-init` is run again. Use `/ai-audit` for explicit/material revalidation.
