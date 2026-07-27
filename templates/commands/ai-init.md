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
- `.ai/GOVERNANCE_MEMORY.md`
- `.ai/DEPLOYMENT_SCOPE.md`
- `.ai/DOCUMENTATION_SCOPE.md`
- `.ai/PROJECT_HISTORY.md`
- `.ai/STATUS.md`
- `.ai/tasks/`
- `.ai/baseline-audits/`

Do not overwrite valid existing project state. Initialize `GOVERNANCE_MEMORY.md` empty when no validated reusable lesson exists; never invent historical memory.

Build a DRAFT baseline from broad structural and risk-based reverse engineering: repository reference, stack/runtimes, entry points, architecture, important dependency/call paths, data flows/trust boundaries, schema/data mechanisms, integrations, validation capabilities, public contracts, dependency/package-admission mechanisms, generated-artifact mechanisms, migration mechanisms, deployment, security-sensitive areas, known defects/risks, documentation state, technical constraints, unknowns and material exclusions. Do not waste context blindly reading generated/vendor/cache/binary artifacts.

Discover reusable governed-discovery/skill capabilities from repository/OpenCode evidence when present:

- OpenCode/project skill definitions and winning IDs/sources, descriptions, scope/triggers and freshness without loading all skill bodies;
- classify indexed skills `PROJECT_AUTHORITATIVE|PROJECT_ADVISORY|WORKSPACE_ADVISORY|EXTERNAL_UNTRUSTED`; skills never outrank canonical user requirements;
- record that built-in `Explore` is read-only local-code discovery and `Scout` is read-only external dependency/upstream/documentation discovery when available; do not invoke a discovery swarm merely to initialize governance;
- never enable/use writable `General` as a governance discovery worker.

Discover reusable Operational Assurance capabilities from repository/configuration evidence when present:

- existing local preview, ephemeral, staging, sandbox or test-environment mechanisms and their documented production boundaries;
- existing browser/E2E/native/manual-reproducible user-flow mechanisms;
- existing screenshot/visual-regression/responsive-state mechanisms;
- documented release rollback, forward-recovery, previous-artifact, backup/restore and recovery mechanisms;
- configured external tools/MCP surfaces and their documented capabilities/side effects, without reading or persisting secret values;
- existing project-local sandbox/container/worktree/temporary-isolation mechanisms suitable for safe experimentation.

Capability discovery during `/ai-init` is read-only. Do not provision environments, invoke privileged/destructive external tools or MCP actions, execute user flows merely for discovery, create worktrees/clones/containers, deploy, rollback, push, merge, install dependencies, or use production data/credentials.

Create/update `.ai/CONTEXT_INDEX.md` as a compact routing index of material modules/paths, entry points, important callers/callees, dependency edges, data stores, trust boundaries, security-sensitive surfaces, canonical documentation, tests/validation capabilities and known risks. It is an index, not a copy of source code.

Create/update `.ai/INSTRUCTION_INDEX.md` from authoritative repository-local instruction/contribution/development files and discovered skills. Record instruction source path, scope/applicable paths, precedence/specificity, material constraints and unresolved conflicts. For skills record ID/source, description, scope/trigger, trust classification and freshness. Tool/skill-specific instructions never silently override the canonical user requirement trail. Material unresolved conflicts require authoritative clarification rather than invented precedence.

Create/update `.ai/GOVERNANCE_MEMORY.md` only with already-authoritative validated historical entries if such evidence exists. Each entry requires stable ID, type, scope, source task/release/incident, evidence references, learned rule, `stale_when`, status `ACTIVE|STALE|REVOKED` and last validation reference. Memory is advisory routing evidence and never overrides current requirements or primary evidence.

Create/update `.ai/DOCUMENTATION_SCOPE.md` and `.ai/DEPLOYMENT_SCOPE.md`. Preserve coherent existing documentation conventions. For distributable applications, normally record overview/readme, step-by-step installation, user manual, wiki/index, changelog and explicit licensing documentation as required when applicable. Never choose/infer a license; record `LICENSE_DECISION_REQUIRED` when unresolved.

Use `question` for material product/project decisions not established by evidence. Do not repeat answered questions.

Set `BASELINE_DRAFT`, create `.ai/baseline-audits/<AUDIT-ID>/`, and request independent `reviewer` and `reviewer-architecture` `BASELINE_AUDIT` reports against the same repository reference and draft baseline/context/instruction indexes/governance memory/documentation scope. Neither reviewer may see the sibling report. Then invoke `final-reviewer` in `BASELINE_AUDIT` mode.

Only Final Reviewer controls `BASELINE_PASS`, `BASELINE_DEFECT` or `BLOCKED`. Apply only validated `.ai/` corrections after `BASELINE_DEFECT`. Maximum three baseline adjudication cycles; then `BASELINE_BLOCKED`.

On `BASELINE_PASS`, set `BASELINE_VALIDATED`, record the validated repository reference, baseline/context/instruction-index/governance-memory freshness and append evidence to `.ai/PROJECT_HISTORY.md`.

Initialize `PROJECT_HISTORY.md` as append-only. Never store secret values.

Do not build per-task `VERIFICATION_PROFILE.md`, `VERIFICATION_EVIDENCE.md`, `READ_ONLY_DISCOVERY_SWARM`, `DEPENDENCY_ADMISSION_GATE`, `PRE_CHANGE_SAFEPOINT` or `OPERATIONAL_ASSURANCE` results during initialization. Task-specific evidence is created lazily. Do not rebuild/re-audit a valid baseline merely because `/ai-init` is run again. Use `/ai-audit` for explicit/material revalidation.