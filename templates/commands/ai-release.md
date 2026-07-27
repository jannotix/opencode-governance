---
description: Run final production-readiness governance gates
agent: architect
subtask: false
---

Run the final governed release assessment for:

$ARGUMENTS

Do not modify source code or project documentation yourself.

Requirements:

1. read `.ai/CODEBASE_BASELINE.md`, `.ai/CONTEXT_INDEX.md`, `.ai/INSTRUCTION_INDEX.md`, latest baseline audit evidence, `.ai/DOCUMENTATION_SCOPE.md`, `.ai/DEPLOYMENT_SCOPE.md`, `.ai/PROJECT_HISTORY.md`, current task artifacts, canonical project documentation and repository state;
2. require the baseline state to be `BASELINE_VALIDATED`; if it is missing, blocked or materially stale, complete `/ai-audit`-equivalent adversarial baseline revalidation before release review continues;
3. confirm all required tasks are validated and locally committed, with required `VERIFICATION_PROFILE.md`/`VERIFICATION_EVIDENCE.md` Evidence-Driven Verification and `OPERATIONAL_ASSURANCE` evidence fresh for the production candidate;
4. identify unresolved material release ambiguities/instruction conflicts; when product/project decisions cannot be resolved from authoritative evidence, use `question` rather than inventing an answer;
5. require an explicit project software-license decision; if `.ai/DOCUMENTATION_SCOPE.md` contains `LICENSE_DECISION_REQUIRED` or legal files conflict with the explicit license decision, return `NOT_READY_FOR_PRODUCTION` until resolved;
6. require applicable project documentation to be complete and synchronized with the production candidate;
7. for distributable applications, verify at minimum applicable project overview/readme, complete step-by-step installation guide, user manual, wiki/index, changelog and licensing documentation; also verify admin, upgrade, architecture, configuration, API, security, troubleshooting and release notes when marked required;
8. verify installation/manual/wiki instructions, commands, paths, configuration examples and stated behaviour against the actual release artifact and runtime evidence;
9. verify the production artifact contains only runtime-required production files according to `DEPLOYMENT_SCOPE.md`;
10. exclude `docs/**`, `.ai/**`, tests, development/review evidence, local tooling, IDE/temp files and secrets from the production artifact by default;
11. allow a specific license/notice or documentation file inside the production artifact only when `.ai/DEPLOYMENT_SCOPE.md` records an explicit legal, packaging or runtime requirement;
12. verify no plaintext secrets or tracked credential files are present in source, documentation or release artifact;
13. re-evaluate release-wide `TASK_RISK_PROFILE` surfaces and require fresh applicable Evidence-Driven Verification: authoritative `VALIDATION_PROFILE`/CI parity, bugfix proof where relevant, test impact/full-suite policy, public contract compatibility, environment/release-toolchain fingerprint, dependency delta/lockfile consistency, generated artifacts, migrations/data preservation, existing non-functional budgets, unresolved flakiness, adversarial input validation and repository-required human-owner gates;
14. require fresh applicable `OPERATIONAL_ASSURANCE` for the actual production candidate: `PREVIEW_ENVIRONMENT_GATE`, `USER_FLOW_VERIFICATION`, `VISUAL_BEHAVIOR_GATE`, `RELEASE_RECOVERY_PROOF`, `TOOL_CAPABILITY_PROFILE`/`MCP_CAPABILITY_ASSESSMENT`, `SAFE_EXPERIMENTATION` contamination/isolation evidence;
15. `PREVIEW_ENVIRONMENT_GATE`: when required, prove the preview/staging/test runtime used the correct release source/artifact and was appropriately isolated. Preview evidence never authorizes production deployment, and governance never provisions production infrastructure merely to satisfy this gate;
16. `USER_FLOW_VERIFICATION`: require release-critical approved/established user flows to pass in an appropriate real preview/staging/test runtime when the task/release requires them; mocks alone do not replace required end-to-end evidence;
17. `VISUAL_BEHAVIOR_GATE`: for affected UI releases require objective responsive/state/interaction/approved visual behavior evidence when applicable, using existing project mechanisms rather than invented aesthetic criteria;
18. `RELEASE_RECOVERY_PROOF`: identify previous stable reference and authoritative rollback or forward-recovery path; verify artifact/config/schema/data compatibility and backup/restore assumptions as safely possible. Missing required recovery proof blocks production readiness. Never execute automatic production rollback as part of governance;
19. `TOOL_CAPABILITY_PROFILE`: re-evaluate relevant release/deployment tools and MCP side effects, `READ_ONLY|WRITE|EXECUTE|PRIVILEGED|DESTRUCTIVE` classification, network/secret exposure and authorization. Tool availability is not authorization; secret values are never persisted;
20. `SAFE_EXPERIMENTATION`: ensure experimental/sandbox/worktree/container/preview activity left no unexplained source/config/environment contamination and respected permissions. Experiments never imply automatic push/merge/deploy;
21. do not install/add external verification/browser/visual tools or provision infrastructure solely for governance and never invent thresholds; existing scanner/checker/tool output is evidence, not proof. Required unavailable evidence needs a sufficient primary-evidence alternative or production remains blocked;
22. ensure a rerun PASS has not hidden an unresolved earlier failure and that stale task evidence was rerun after source/contract/lockfile/generator/migration/environment/validation/preview/tool/recovery/isolation changes;
23. require public breaking changes to be explicitly authorized by controlling requirements/release policy;
24. for irreversible migrations require recorded backup/forward-recovery evidence and any authoritative approval; never pretend rollback exists;
25. build the final artifact/package using the project's real release mechanism;
26. extract/copy that final artifact into a clean directory/environment and perform a clean installation/startup/smoke test from the artifact itself, following maintained installation documentation where applicable;
27. run the strongest relevant authoritative test/build/static-analysis checks;
28. execute mandatory real sandbox/test validation for external integrations where applicable; mocks alone are insufficient;
29. require `CODEOWNERS_HUMAN_GATE`/equivalent human approval when authoritative repository policy requires it for release/merge; never fabricate approval;
30. invoke `reviewer` and `reviewer-architecture` as fresh independent `RELEASE_REVIEW` assessments of the same production candidate, Evidence-Driven/Operational Assurance state and canonical documentation, without sharing either reviewer's output with the other;
31. request both release reviews before consuming either result and run them concurrently when supported;
32. invoke `final-reviewer` in `RELEASE_REVIEW` mode after both reviews complete and require it to independently adjudicate production, evidence, operational assurance, documentation, licensing and reviewer findings.

Only `final-reviewer` returns the production verdict:

- `READY_FOR_PRODUCTION`
- `NOT_READY_FOR_PRODUCTION`

Any baseline that is not currently validated, unresolved material release decision/instruction conflict, required stale/failed/insufficient Evidence-Driven or Operational Assurance evidence, unsafe preview/production boundary, unverified required user flow/visual behavior, missing required recovery proof, unauthorized privileged/destructive external tool/MCP action, unsafe experiment contamination, unauthorized breaking contract change, unresolved authoritative human-owner gate, `LICENSE_DECISION_REQUIRED`, missing/incorrect legal files, materially stale/missing required documentation, documentation contradicted by the shipped app, unresolved security finding, plaintext/tracked secret, failed clean install, unsafe schema/data-change state, invalid production package, failed required test, or mandatory external validation not executed requires `NOT_READY_FOR_PRODUCTION`.

Append the release assessment and evidence to `.ai/PROJECT_HISTORY.md` without secret values.

Do not deploy, rollback or push unless the user/project policy separately and explicitly authorizes that specific action. `/ai-release` is an assessment gate, not automatic production execution.
