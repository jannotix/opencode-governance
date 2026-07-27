---
description: Run final production-readiness governance gates
agent: architect
subtask: false
---

Run the final governed release assessment for:

$ARGUMENTS

Do not modify source code or project documentation yourself.

Requirements:

1. read `.ai/CODEBASE_BASELINE.md`, `.ai/CONTEXT_INDEX.md`, `.ai/INSTRUCTION_INDEX.md`, `.ai/GOVERNANCE_MEMORY.md`, latest baseline audit evidence, `.ai/DOCUMENTATION_SCOPE.md`, `.ai/DEPLOYMENT_SCOPE.md`, `.ai/PROJECT_HISTORY.md`, current task artifacts, canonical project documentation and repository state;
2. require the baseline state to be `BASELINE_VALIDATED`; if it is missing, blocked or materially stale, complete `/ai-audit`-equivalent adversarial baseline revalidation before release review continues;
3. confirm all required tasks are validated and locally committed, with required `VERIFICATION_PROFILE.md`/`VERIFICATION_EVIDENCE.md` Evidence-Driven Verification and `OPERATIONAL_ASSURANCE` evidence fresh for the production candidate;
4. treat `READ_ONLY_DISCOVERY_SWARM` outputs, skills and Governance Memory as routing/advisory evidence only; release claims still require current primary artifact/runtime evidence. Revalidate any selected skill or active memory entry whose source/scope/freshness/`stale_when` changed materially;
5. identify unresolved material release ambiguities/instruction/skill conflicts; when product/project decisions cannot be resolved from authoritative evidence, use `question` rather than inventing an answer;
6. require an explicit project software-license decision; if `.ai/DOCUMENTATION_SCOPE.md` contains `LICENSE_DECISION_REQUIRED` or legal files conflict with the explicit license decision, return `NOT_READY_FOR_PRODUCTION` until resolved;
7. require applicable project documentation to be complete and synchronized with the production candidate;
8. for distributable applications, verify at minimum applicable project overview/readme, complete step-by-step installation guide, user manual, wiki/index, changelog and licensing documentation; also verify admin, upgrade, architecture, configuration, API, security, troubleshooting and release notes when marked required;
9. verify installation/manual/wiki instructions, commands, paths, configuration examples and stated behaviour against the actual release artifact and runtime evidence;
10. verify the production artifact contains only runtime-required production files according to `DEPLOYMENT_SCOPE.md`;
11. exclude `docs/**`, `.ai/**`, tests, development/review evidence, local tooling, IDE/temp files and secrets from the production artifact by default;
12. allow a specific license/notice or documentation file inside the production artifact only when `.ai/DEPLOYMENT_SCOPE.md` records an explicit legal, packaging or runtime requirement;
13. verify no plaintext secrets or tracked credential files are present in source, documentation or release artifact;
14. re-evaluate release-wide `TASK_RISK_PROFILE` surfaces and require fresh applicable Evidence-Driven Verification: authoritative `VALIDATION_PROFILE`/CI parity, bugfix proof where relevant, test impact/full-suite policy, public contract compatibility, environment/release-toolchain fingerprint, `DEPENDENCY_ADMISSION_GATE`, dependency delta/lockfile consistency, generated artifacts, `PRE_CHANGE_SAFEPOINT`, migrations/data preservation, existing non-functional budgets, unresolved flakiness, adversarial input validation and repository-required human-owner gates;
15. every new direct dependency shipped by the candidate must have exact package/source/version admission evidence from before installation. `REJECT`, unresolved `HUMAN_DECISION`, suspected typo/slopsquat, unverifiable identity, materially unresolved security/license risk or broad unapproved lockfile churn requires `NOT_READY_FOR_PRODUCTION`;
16. any release-critical high-risk destructive/migration/deployment-state change whose profile required `PRE_CHANGE_SAFEPOINT` must have sufficient pre-change Git/worktree/schema/config/artifact plus required backup/recovery evidence captured before mutation. Never fabricate a historical safepoint at release time;
17. require fresh applicable `OPERATIONAL_ASSURANCE` for the actual production candidate: `PREVIEW_ENVIRONMENT_GATE`, `USER_FLOW_VERIFICATION`, `VISUAL_BEHAVIOR_GATE`, `RELEASE_RECOVERY_PROOF`, `TOOL_CAPABILITY_PROFILE`/`MCP_CAPABILITY_ASSESSMENT`, `SAFE_EXPERIMENTATION` contamination/isolation evidence;
18. `PREVIEW_ENVIRONMENT_GATE`: when required, prove the preview/staging/test runtime used the correct release source/artifact and was appropriately isolated. Preview evidence never authorizes production deployment, and governance never provisions production infrastructure merely to satisfy this gate;
19. `USER_FLOW_VERIFICATION`: require release-critical approved/established user flows to pass in an appropriate real preview/staging/test runtime when the task/release requires them; mocks alone do not replace required end-to-end evidence;
20. `VISUAL_BEHAVIOR_GATE`: for affected UI releases require objective responsive/state/interaction/approved visual behavior evidence when applicable, using existing project mechanisms rather than invented aesthetic criteria;
21. `RELEASE_RECOVERY_PROOF`: identify previous stable reference and authoritative rollback or forward-recovery path; verify artifact/config/schema/data compatibility and backup/restore assumptions as safely possible. Missing required recovery proof blocks production readiness. Never execute automatic production rollback as part of governance;
22. `TOOL_CAPABILITY_PROFILE`: re-evaluate relevant release/deployment tools and MCP side effects, `READ_ONLY|WRITE|EXECUTE|PRIVILEGED|DESTRUCTIVE` classification, network/secret exposure and authorization. Tool availability is not authorization; secret values are never persisted;
23. `SAFE_EXPERIMENTATION`: ensure experimental/sandbox/worktree/container/preview activity left no unexplained source/config/environment contamination and respected permissions. Experiments never imply automatic push/merge/deploy;
24. if any completed task carried `CLOSED_LOOP_LEARNING`, verify Final Reviewer `MEMORY_DECISION` was respected: `APPROVE` entries must be persisted exactly with validated scope/evidence/`stale_when`, `REJECT` candidates must not appear as active memory, and memory is never treated as a release waiver;
25. do not install/add external verification/browser/visual tools or provision infrastructure solely for governance and never invent thresholds; existing scanner/checker/tool output is evidence, not proof. Required unavailable evidence needs a sufficient primary-evidence alternative or production remains blocked;
26. ensure a rerun PASS has not hidden an unresolved earlier failure and that stale task evidence was rerun after source/contract/dependency-admission/lockfile/safepoint/generator/migration/environment/validation/skill/preview/tool/recovery/isolation changes;
27. require public breaking changes to be explicitly authorized by controlling requirements/release policy;
28. for irreversible migrations require recorded backup/forward-recovery evidence and any authoritative approval; never pretend rollback exists;
29. build the final artifact/package using the project's real release mechanism;
30. extract/copy that final artifact into a clean directory/environment and perform a clean installation/startup/smoke test from the artifact itself, following maintained installation documentation where applicable;
31. run the strongest relevant authoritative test/build/static-analysis checks;
32. execute mandatory real sandbox/test validation for external integrations where applicable; mocks alone are insufficient;
33. require `CODEOWNERS_HUMAN_GATE`/equivalent human approval when authoritative repository policy requires it for release/merge; never fabricate approval;
34. invoke `reviewer` and `reviewer-architecture` as fresh independent `RELEASE_REVIEW` assessments of the same production candidate, Evidence-Driven/Operational Assurance state and canonical documentation, without sharing either reviewer's output with the other;
35. request both release reviews before consuming either result and run them concurrently when supported;
36. invoke `final-reviewer` in `RELEASE_REVIEW` mode after both reviews complete and require it to independently adjudicate production, evidence, operational assurance, dependency admission/safepoint, documentation, licensing and reviewer findings.

Only `final-reviewer` returns the production verdict:

- `READY_FOR_PRODUCTION`
- `NOT_READY_FOR_PRODUCTION`

Any baseline that is not currently validated, unresolved material release decision/instruction/skill conflict, required stale/failed/insufficient Evidence-Driven or Operational Assurance evidence, unadmitted/unverified new direct dependency, missing required safepoint, unsafe preview/production boundary, unverified required user flow/visual behavior, missing required recovery proof, unauthorized privileged/destructive external tool/MCP action, unsafe experiment contamination, unauthorized breaking contract change, unresolved authoritative human-owner gate, `LICENSE_DECISION_REQUIRED`, missing/incorrect legal files, materially stale/missing required documentation, documentation contradicted by the shipped app, unresolved security finding, plaintext/tracked secret, failed clean install, unsafe schema/data-change state, invalid production package, failed required test, or mandatory external validation not executed requires `NOT_READY_FOR_PRODUCTION`.

Append the release assessment and evidence to `.ai/PROJECT_HISTORY.md` without secret values.

Do not deploy, rollback or push unless the user/project policy separately and explicitly authorizes that specific action. `/ai-release` is an assessment gate, not automatic production execution.