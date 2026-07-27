# Permissions

OpenCode permissions enforce the governance role boundaries in addition to prompt policy.

## Architect

- application source/project-documentation writes: denied;
- `.ai/**`: allowed;
- `question`: allowed;
- governed delegation: Executor, both Reviewers and Final Reviewer;
- read-only discovery: `Explore` and `Scout` allowed;
- writable `General` is not enabled as a governance discovery worker;
- skills: ask/authorize under `GOVERNED_SKILL_ROUTING`;
- destructive shell/Git operations: denied or confirmation-gated;
- push: denied.

Architect may persist `.ai/GOVERNANCE_MEMORY.md` only after Final Reviewer approves the exact reusable lesson.

## Governed Build

`build` is the full-workflow primary entry point and uses the Architect model.

- application source/project-documentation writes: denied;
- `.ai/**`: allowed;
- `question`: allowed;
- governed delegation: Executor, both Reviewers and Final Reviewer;
- read-only discovery: `Explore` and `Scout` allowed;
- writable `General` is not enabled as a governance discovery worker;
- skills: ask/authorize under `GOVERNED_SKILL_ROUTING`;
- destructive shell/Git operations: denied or confirmation-gated;
- push: denied.

Implementation/documentation writes are always delegated to Executor.

## Governed Plan

`plan` is planning-only and uses the Architect model.

- application source/project-documentation writes: denied;
- `.ai/**`: allowed;
- `question`: allowed;
- subagent delegation: denied;
- implementation/review execution: denied by policy;
- skills: ask/authorize under `GOVERNED_SKILL_ROUTING`;
- requires `BASELINE_VALIDATED`;
- cannot self-certify a draft/stale baseline;
- destructive shell/Git operations: denied or confirmation-gated;
- push: denied.

## Executor

Executor is the single application/project-documentation writer.

- application source and approved project-documentation writes: allowed;
- subagent delegation: denied;
- `external_directory`: denied;
- skills: ask/authorize only when selected by governed routing;
- execution requires `BASELINE_VALIDATED`, `READY_FOR_EXECUTION` and current task artifacts;
- new direct dependencies require `DEPENDENCY_ADMISSION_GATE: ADMIT` before installation;
- required high-risk mutations require `PRE_CHANGE_SAFEPOINT` before mutation;
- destructive shell/Git operations: denied;
- local add/commit: confirmation-gated;
- push: confirmation-gated and allowed only after explicit authorization for that push.

Evidence requirements never expand Executor permissions. `SAFE_EXPERIMENTATION` must use an already permitted isolation mechanism or return `UNAVAILABLE`/`BLOCKED`.

Executor never writes `.ai/GOVERNANCE_MEMORY.md`.

## Independent reviewers

`reviewer` and `reviewer-architecture` share the same safety boundary:

- application source/project-documentation writes: denied;
- `.ai/**`: allowed only for their own review/audit evidence;
- delegation: denied;
- skills: ask/authorize only for scoped review evidence;
- external directory: denied;
- commit/push: denied;
- destructive shell/Git operations: denied;
- current-cycle sibling review output must not be used as evidence.

Both reviewers independently validate the frozen target and required Evidence-Driven/Operational Assurance evidence within their normal domains.

## Final Reviewer

- application source/project-documentation writes: denied;
- `.ai/**`: allowed for final baseline/task/release adjudication evidence;
- delegation: denied;
- skills: ask/authorize only for scoped adjudication evidence;
- external directory: denied;
- commit/push: denied;
- destructive shell/Git operations: denied.

Final Reviewer independently validates reviewer allegations against primary evidence and controls baseline/task/release verdicts.

For `CLOSED_LOOP_LEARNING`, Final Reviewer records `MEMORY_DECISION: NONE|APPROVE|REJECT`; approval authorizes only Architect to persist the validated memory entry.

## Global invariants

Prompt policy remains stricter than raw tool availability:

- no source implementation before `BASELINE_VALIDATED`;
- unresolved material ambiguity prevents `READY_FOR_EXECUTION`;
- only Executor writes application source/project documentation;
- new direct dependencies require admission before installation;
- required high-risk mutations require a pre-change safepoint;
- required evidence marked `UNAVAILABLE` cannot silently support `PASS`;
- Operational Assurance may require more proof but never more privilege;
- source/task-documentation/evidence targets are frozen during independent review;
- raw reviewer findings never authorize automatic repair;
- local task commit occurs only after Final Reviewer `PASS`;
- commit permission never implies push permission;
- staged changes must be scoped and secret-scanned;
- unrelated user changes are not included;
- `docs/**` and `.ai/**` are excluded from production/runtime artifacts by default unless an explicit legal/packaging/runtime exception is recorded.
