# Workflow

## Initial repository validation

```text
/ai-init
```

Creates/reuses baseline, context index, instruction index, documentation/deployment scope, history/status, audit and task directories. Architect performs broad structural/risk-based intake, then two independent baseline audits and Final Reviewer adjudication:

```text
BASELINE_DRAFT
→ BASELINE_DUAL_AUDIT
   ├── reviewer / BASELINE_AUDIT
   └── reviewer-architecture / BASELINE_AUDIT
→ final-reviewer / BASELINE_AUDIT
→ BASELINE_VALIDATED
```

`BASELINE_PASS` means reusable baseline/context/instruction/documentation evidence is materially trustworthy; it does not mean the codebase is defect-free. Maximum failed baseline adjudications: three, then `BASELINE_BLOCKED`.

## Requirement and clarification gate

Every task begins with:

```text
ORIGINAL_USER_REQUEST.md
CLARIFICATION_TRANSCRIPT.md
APPROVED_REQUIREMENTS.md
```

Original user intent remains distinct from Architect interpretation. Material unanswered decisions or unresolved instruction conflicts are resolved with OpenCode `question`; answered questions are not repeated. A plan cannot override the canonical requirement trail.

## Context and instruction routing

A validated repository maintains:

- `.ai/CONTEXT_INDEX.md` for material module/path, call/dependency, data/trust, security, documentation, validation and risk routing metadata;
- `.ai/INSTRUCTION_INDEX.md` for authoritative repository-local instruction sources, applicable paths/scope, precedence/specificity and unresolved conflicts.

Each task builds `CONTEXT_MANIFEST.md` from validated indexes plus current Git delta. Full repository rescans are not the default for routine work.

## Minimum-change planning

Implementation-ready plans contain `MINIMUM_CHANGE_ASSESSMENT`: root cause/evidence-backed hypothesis, existing capability/pattern reuse, stdlib/native-platform option, installed dependency option, new dependency/abstraction justification and smallest correct secure maintainable proposed change.

For bugs, inspect relevant callers and prefer the correct shared root-cause fix. Minimalism never removes security, trust-boundary validation, data-loss protection, required error handling, accessibility or approved behavior.

## Evidence-Driven Verification

Every v1.8 task creates:

```text
VERIFICATION_PROFILE.md
evidence/VERIFICATION_EVIDENCE.md
```

`VERIFICATION_PROFILE.md` contains `TASK_RISK_PROFILE` with `NONE | LOW | HIGH` for security, data migration, public contracts, dependencies, deployment, performance, generated artifacts, destructive actions, input validation, test reliability and human ownership.

Risk may add proof requirements but never removes normal validation, independent dual review or Final Reviewer adjudication.

The profile discovers existing authoritative `VALIDATION_PROFILE`/CI-equivalent mechanisms and plans applicable gates:

```text
BUGFIX_PROOF
TEST_IMPACT_MAP
CONTRACT_COMPATIBILITY
ENVIRONMENT_FINGERPRINT
DEPENDENCY_DELTA
GENERATED_ARTIFACT_GATE
MIGRATION_PROOF
NON_FUNCTIONAL_BUDGETS
FLAKINESS_EVIDENCE
ADVERSARIAL_INPUT_VALIDATION
CODEOWNERS_HUMAN_GATE
```

Planning states are `REQUIRED | CONDITIONAL | NOT_APPLICABLE`. Evidence states are `PASS | FAIL | UNAVAILABLE | STALE | BLOCKED`.

Governance does not install/add external tools merely to satisfy a gate and does not invent thresholds. Existing repository tooling is preferred. Required `UNAVAILABLE` evidence needs a justified sufficient primary-evidence alternative or remains blocking.

Important semantics:

- reproducible bug fixes preserve pre-fix FAIL and post-fix PASS; critical fixes may use a safe bounded negative control;
- test-impact selection may optimize large-repository validation but never bypass authoritative CI/high-risk full-suite requirements;
- public contract changes are classified compatible, breaking or explicitly authorized breaking;
- environment/toolchain facts are non-secret and can make runtime/build/test evidence stale;
- dependency scanner output is evidence, not proof, and dependencies are never auto-fixed;
- generator inputs require the project's real generation mechanism when applicable;
- migrations are `REVERSIBLE | FORWARD_ONLY | IRREVERSIBLE`; irreversible work requires approved backup/forward-recovery evidence;
- only existing authoritative non-functional budgets are enforced;
- rerun PASS never erases an earlier unexplained FAIL;
- high-risk input surfaces use existing fuzz/property/schema-negative testing or equivalent bounded primary evidence when required;
- repository-required human-owner approval is recorded and never fabricated.

See [Evidence-Driven Verification](evidence-driven-verification.md).

## Checkpoint state and evidence freshness

Each active task maintains `RUN_STATE.json` at governance phase boundaries. Task commands expose `GOVERNANCE_RESULT` plus `EVIDENCE_STATUS`.

Evidence is dependency-specific. Source/docs, public contracts, lockfiles/dependency manifests, generator inputs, migrations, environment/toolchain or validation configuration changes invalidate only dependent evidence and downstream reviews.

## Fresh evidence packets

Role handoffs are built under `.ai/tasks/<TASK-ID>/evidence/`:

```text
EXECUTION_PACKET.md
VERIFICATION_EVIDENCE.md
REVIEW_IMPLEMENTATION_PACKET.md
REVIEW_ARCHITECTURE_PACKET.md
FINAL_PACKET.md
```

Packets reference canonical evidence instead of copying chat history. Reviewer packets target the same frozen task state but never contain sibling current-cycle findings. Final packet is built only after both independent reviews complete.

## Complete workflow

```text
/ai-workflow <task>
```

Lifecycle:

```text
BASELINE_VALIDATED
→ REQUIREMENT_CAPTURE
→ CLARIFICATION
→ APPROVED_REQUIREMENTS
→ CONTEXT_ROUTING
→ PLANNING
→ MINIMUM_CHANGE_GATE
→ EVIDENCE_PLANNING
→ TASK_PLANNED
→ READY_FOR_EXECUTION
→ IMPLEMENTING
→ DOCUMENTATION_SYNC
→ EVIDENCE_VALIDATION
→ TASK_VERIFYING
→ TASK_VALIDATED
→ DUAL_REVIEW
→ FINAL_ADJUDICATION
→ LOCAL_COMMITTED
```

Executor implements only an approved plan, synchronizes required documentation and produces fresh required verification evidence before `TASK_VALIDATED`.

At `TASK_VALIDATED`, source/task documentation and evidence target are frozen. Architect creates two fresh independent reviewer packets and requests both reviewers before consuming either result.

Final Reviewer validates requirement provenance first, then plan authorization, risk classification, evidence sufficiency/freshness, implementation and reviewer allegations. Reviewer agreement is never counted as proof.

Final task verdicts:

- `PASS`;
- `IMPLEMENTATION_DEFECT`;
- `PLAN_DEFECT`;
- `BLOCKED`.

A perfect implementation of a materially wrong plan is `PLAN_DEFECT`. Required stale/insufficient evidence cannot support PASS. Maximum failed final-adjudication cycles: three, then `BLOCKED`.

After `PASS`, Executor creates one scoped local task commit. Push requires explicit user authorization. Repository-required human-owner approval remains enforced at the boundary defined by project policy.

## Adaptive output efficiency

All governance agents use `ADAPTIVE_OUTPUT_EFFICIENCY`: full reasoning with concise evidence-dense handoffs. Compression stops when it could weaken correctness, safety, evidence or recovery instructions.

## Usage telemetry

```text
/ai-metrics [scope]
```

Reads usage already recorded by OpenCode. It never estimates missing token counts or proportionally assigns model totals to roles. Missing fields/attribution remain `UNAVAILABLE`/`PARTIAL`.

See [Token efficiency and usage telemetry](token-efficiency.md).

## Governed steering

Material `STEERING.md` direction is appended to clarification provenance, updates approved requirements only when authorized and forces replanning when the plan became stale.

## Resume after interruption

```text
/ai-resume <TASK-ID>
```

Resume reads checkpoint/provenance/context/instruction/verification artifacts and Git state. It reconciles `ENVIRONMENT_FINGERPRINT` and evidence dependencies before routing to the last safe unfinished phase.

Examples:

- `READY_FOR_EXECUTION` → fresh execution packet/Executor;
- interrupted `IMPLEMENTING` → reconcile worktree/evidence dependencies;
- interrupted `EVIDENCE_VALIDATION` → rerun only missing/stale required gates;
- `TASK_VALIDATED` → confirm evidence freshness, then fresh dual review;
- interrupted `FINAL_ADJUDICATION` → rebuild final packet from fresh canonical evidence;
- `PASS` without commit → scoped Executor finalization;
- `LOCAL_COMMITTED` → nothing to resume;
- `BLOCKED`/`BASELINE_BLOCKED` → remain blocked until authoritative resolution.

Resume never fabricates missing provenance/review/evidence history and never erases prior failures/flakiness evidence.

## Optional task queue

Large milestones may add `.ai/TASK_QUEUE.json` containing task IDs, priorities, dependencies and state. Scheduling never bypasses the normal lifecycle or three-cycle limits.

## Other commands

```text
/ai-plan <task>
/ai-execute <task-id-or-plan-id>
/ai-review <task-id>
/ai-audit
/ai-docs
/ai-status
/ai-metrics [scope]
/ai-release
```

## Release gate

Release review re-evaluates production-wide evidence, including public contract compatibility, dependency/lockfile delta, generated artifacts, migrations/data preservation, environment/release toolchain, existing non-functional budgets, unresolved flakiness, high-risk input evidence and authoritative human-owner release gates when applicable.

Final release verdict remains:

```text
READY_FOR_PRODUCTION
NOT_READY_FOR_PRODUCTION
```

## Documentation and license

`.ai/DOCUMENTATION_SCOPE.md` maps canonical documentation/applicability. Required documentation is synchronized before validation and reviewed with code. `.ai/**` and project `docs/**` remain outside runtime artifacts by default except explicit legal/packaging/runtime exceptions.

Governance never chooses/invents software licenses. Missing explicit license state becomes `LICENSE_DECISION_REQUIRED` and blocks release readiness.

## Large repositories

Routine tasks reuse validated indexes, Git delta, context routing and test-impact evidence. Full revalidation remains reserved for materially stale evidence or broad architectural/dependency/import changes.
