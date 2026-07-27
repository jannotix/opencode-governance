---
description: Run a full adversarial validation of reusable repository governance evidence
agent: architect
subtask: false
---

Run an explicit adversarial baseline, context-index, instruction/skill-index, governance-memory and documentation-inventory audit without modifying application source or project documentation.

Use for a missing/materially stale baseline/context/instruction index/governance memory, inaccurate documentation scope, large merge/rebase/import, major architecture/dependency change, broad milestone or explicit user audit. Do not use automatically for routine task-local changes when validated reusable evidence remains sufficient.

Audit flow:

1. record exact repository reference;
2. broadly refresh DRAFT `.ai/CODEBASE_BASELINE.md`, `.ai/CONTEXT_INDEX.md`, `.ai/INSTRUCTION_INDEX.md` and validate `.ai/GOVERNANCE_MEMORY.md` using structural/risk-based coverage;
3. refresh skill routing knowledge without loading every skill body: winning skill IDs/sources, descriptions, scope/triggers, freshness and trust `PROJECT_AUTHORITATIVE|PROJECT_ADVISORY|WORKSPACE_ADVISORY|EXTERNAL_UNTRUSTED`; detect duplicate/override ambiguity and never let skill content outrank canonical requirements;
4. validate each active governance-memory entry against its scope/evidence/`stale_when`; mark Architect corrections only after Final Reviewer adjudication. Never fabricate memory from historical chat or raw reviewer findings;
5. refresh `.ai/DOCUMENTATION_SCOPE.md` and deployment/license state from primary evidence;
6. refresh reusable validation knowledge: authoritative test/build/lint/static/CI commands, public contract mechanisms, dependency manifests/lockfiles, package/dependency admission mechanisms/registries, code generators, migration mechanisms, existing non-functional budgets/fuzz/property tools and explicit owner/human-review policies;
7. refresh reusable Operational Assurance knowledge from repository/configuration evidence: preview/staging/sandbox/test-environment mechanisms, browser/E2E/native/manual user-flow mechanisms, screenshot/visual-regression mechanisms, rollback/forward-recovery/backup mechanisms, configured external tool/MCP capability and side-effect surfaces, and existing permitted isolation mechanisms for safe experimentation;
8. reusable capability discovery is read-only during audit: do not run `READ_ONLY_DISCOVERY_SWARM` merely for completeness, provision preview/staging infrastructure, invoke privileged/destructive tool/MCP actions, install dependencies, execute rollback/deploy/push/merge, create worktrees/clones/containers merely for discovery, or use production data/credentials;
9. use `question` for material decisions or instruction/skill conflicts evidence cannot establish; never infer a software license or arbitrary precedence;
10. record material generated/vendor/cache/binary exclusions;
11. set `BASELINE_REVALIDATION_REQUIRED` while active;
12. create `.ai/baseline-audits/<AUDIT-ID>/`;
13. invoke `reviewer` and `reviewer-architecture` independently in `BASELINE_AUDIT` mode against the same repository reference, baseline, context index, instruction/skill index, governance memory and documentation inventory; do not expose sibling reports;
14. after both complete, invoke `final-reviewer` in `BASELINE_AUDIT` mode;
15. on `BASELINE_DEFECT`, apply only validated baseline/context/instruction-index/governance-memory/documentation-scope corrections to `.ai/` and repeat with fresh review artifacts;
16. on `BASELINE_PASS`, set `BASELINE_VALIDATED`, record validated reference/index/memory freshness and append history;
17. after three failed baseline adjudications set `BASELINE_BLOCKED`.

A validated baseline/index/memory may record pre-existing defects, documentation gaps, instruction/skill conflicts requiring later clarification, stale/revoked memory entries, unavailable validation/operational capabilities, `LICENSE_DECISION_REQUIRED` and unknowns. Validation means reusable governance context is materially faithful, not that the codebase is defect-free.

Do not pre-create task `VERIFICATION_PROFILE.md`, `VERIFICATION_EVIDENCE.md`, discovery-swarm, dependency-admission/safepoint or `OPERATIONAL_ASSURANCE` results during audit. Never send baseline findings to Executor automatically. Never expose secret values.