# Workflow

## Initial repository validation

```text
/ai-init
```

Creates/reuses baseline, context index, instruction/skill index, governance memory, documentation/deployment scope, history/status, audit and task directories. Architect performs broad structural/risk-based intake, then two independent baseline audits and Final Reviewer adjudication:

```text
BASELINE_DRAFT
→ BASELINE_DUAL_AUDIT
   ├── reviewer / BASELINE_AUDIT
   └── reviewer-architecture / BASELINE_AUDIT
→ final-reviewer / BASELINE_AUDIT
→ BASELINE_VALIDATED
```

`BASELINE_PASS` means reusable baseline/context/instruction/skill/memory/documentation evidence is materially trustworthy; it does not mean the codebase is defect-free. Maximum failed baseline adjudications: three, then `BASELINE_BLOCKED`.

`GOVERNANCE_MEMORY.md` starts empty unless authoritative validated historical evidence exists. Memory is never reconstructed from chat history.

## Requirement and clarification gate

Every task begins with:

```text
ORIGINAL_USER_REQUEST.md
CLARIFICATION_TRANSCRIPT.md
APPROVED_REQUIREMENTS.md
```

Original user intent remains distinct from Architect interpretation. Material unanswered decisions or unresolved instruction/skill conflicts are resolved with OpenCode `question`; answered questions are not repeated. A plan cannot override the canonical requirement trail.

## Governed discovery, skills, context and memory

Validated repositories maintain:

- `.ai/CONTEXT_INDEX.md` — code/system routing;
- `.ai/INSTRUCTION_INDEX.md` — authoritative instructions plus indexed skills, scope, precedence/trust and conflicts;
- `.ai/GOVERNANCE_MEMORY.md` — only validated reusable lessons with scope/evidence/`stale_when`.

For materially multi-surface tasks, Architect/Build may use `READ_ONLY_DISCOVERY_SWARM`: 2–4 independent OpenCode `Explore`/`Scout` subtasks. `Explore` is for local codebase discovery, `Scout` for external dependency/upstream/documentation research. Writable `General` is not part of governance discovery.

Discovery summaries are not authoritative. Material claims are checked against primary evidence before entering `CONTEXT_MANIFEST.md`.

`GOVERNED_SKILL_ROUTING` selects only task-relevant indexed skills after checking winning ID/source, scope/trigger, freshness and trust:

```text
PROJECT_AUTHORITATIVE
PROJECT_ADVISORY
WORKSPACE_ADVISORY
EXTERNAL_UNTRUSTED
```

Skills never outrank the canonical user requirement trail and never silently authorize side effects.

Each task builds `CONTEXT_MANIFEST.md` from validated indexes, relevant active memory, selected skills, current Git delta and verified discovery evidence. Full repository rescans are not the default for routine work.

## Minimum-change planning

Implementation-ready plans contain `MINIMUM_CHANGE_ASSESSMENT`: root cause/evidence-backed hypothesis, existing capability/pattern reuse, stdlib/native-platform option, installed dependency option, new dependency/abstraction justification and smallest correct secure maintainable proposed change.

For bugs, inspect relevant callers and prefer the correct shared root-cause fix. Minimalism never removes security, trust-boundary validation, data-loss protection, required error handling, accessibility or approved behavior.

## Evidence-Driven Verification

Every governed task creates:

```text
VERIFICATION_PROFILE.md
evidence/VERIFICATION_EVIDENCE.md
```

`VERIFICATION_PROFILE.md` contains `TASK_RISK_PROFILE` and discovers authoritative `VALIDATION_PROFILE`/CI-equivalent mechanisms.

Core gates:

```text
BUGFIX_PROOF
TEST_IMPACT_MAP
CONTRACT_COMPATIBILITY
ENVIRONMENT_FINGERPRINT
DEPENDENCY_ADMISSION_GATE
DEPENDENCY_DELTA
GENERATED_ARTIFACT_GATE
PRE_CHANGE_SAFEPOINT
MIGRATION_PROOF
NON_FUNCTIONAL_BUDGETS
FLAKINESS_EVIDENCE
ADVERSARIAL_INPUT_VALIDATION
CODEOWNERS_HUMAN_GATE
CLOSED_LOOP_LEARNING
```

Planning states are `REQUIRED | CONDITIONAL | NOT_APPLICABLE`. Evidence states are `PASS | FAIL | UNAVAILABLE | STALE | BLOCKED`.

`UNAVAILABLE` is never silently converted to `PASS`.

### Dependency admission

A new direct dependency must be admitted **before installation**. `DEPENDENCY_ADMISSION_GATE` records exact package/source/version, why existing/native capabilities are insufficient, external identity/existence evidence, available maintenance/compatibility/security/license evidence and one result:

```text
ADMIT
REJECT
HUMAN_DECISION
NOT_APPLICABLE
```

Suspected typo/slopsquat, unverifiable identity or unresolved material risk cannot be silently admitted. Admission does not authorize unrelated upgrades.

### Pre-change safepoint

When a high-risk destructive/migration/deployment-state mutation requires `PRE_CHANGE_SAFEPOINT`, evidence is captured before mutation:

- Git/worktree state;
- relevant schema/migration state;
- lockfile/config/artifact fingerprints;
- required existing backup/snapshot reference;
- authoritative rollback/forward-recovery path.

Governance does not fabricate a historical safepoint or silently create privileged production backups.

### Closed-loop learning

When evidence shows an escaped/repeated defect, validation gap, stable false-positive rationale, recovery lesson or tooling constraint, `CLOSED_LOOP_LEARNING` records:

```text
WHAT_ESCAPED
WHY_NOT_DETECTED
WHICH_GATE_SHOULD_HAVE_CAUGHT_IT
WHAT_REUSABLE_RULE_CHANGES
```

Reviewers challenge the candidate independently. Final Reviewer writes `MEMORY_DECISION: NONE | APPROVE | REJECT`. Only an approved candidate may be persisted by Architect to `GOVERNANCE_MEMORY.md` with exact scope/evidence/`stale_when`.

See [Evidence-Driven Verification](evidence-driven-verification.md).

## Operational Assurance

v2.0 adds these conditional gates inside the same verification profile/evidence pair:

```text
PREVIEW_ENVIRONMENT_GATE
USER_FLOW_VERIFICATION
VISUAL_BEHAVIOR_GATE
RELEASE_RECOVERY_PROOF
TOOL_CAPABILITY_PROFILE
MCP_CAPABILITY_ASSESSMENT
SAFE_EXPERIMENTATION
```

The six Operational Assurance features are preview, user-flow, visual behavior, recovery proof, tool/MCP capability governance and safe experimentation. MCP assessment is part of the tool capability feature, not a separate agent or command.

Operational Assurance may require more proof but may never grant more privilege. It never silently provisions production infrastructure, uses production data/credentials, widens OpenCode permissions, deploys, rolls back, pushes or merges merely to satisfy a gate.

See [Operational Assurance](operational-assurance.md).

## Checkpoint state and evidence freshness

Each active task maintains `RUN_STATE.json` at governance phase boundaries. Task commands expose `GOVERNANCE_RESULT` plus `EVIDENCE_STATUS`.

Evidence freshness is dependency-specific. Changes to source/docs, public contracts, dependency admission/lockfiles, safepoint/recovery inputs, generator inputs, migrations, environment/toolchain, validation configuration, selected skill, preview runtime, tool/MCP capability or isolation target invalidate only dependent evidence/reviews.

A stale/revoked Governance Memory entry is removed from routing; it does not force unrelated task phases to restart.

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
→ GOVERNED_DISCOVERY
→ SKILL_ROUTING
→ CONTEXT_ROUTING
→ PLANNING
→ MINIMUM_CHANGE_GATE
→ EVIDENCE_PLANNING
→ OPERATIONAL_PLANNING
→ TASK_PLANNED
→ READY_FOR_EXECUTION
→ PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED
→ IMPLEMENTING
→ DOCUMENTATION_SYNC
→ EVIDENCE_VALIDATION
→ OPERATIONAL_VALIDATION
→ TASK_VERIFYING
→ TASK_VALIDATED
→ DUAL_REVIEW
→ FINAL_ADJUDICATION
→ VALIDATED_LEARNING
→ LOCAL_COMMITTED
```

Executor is the only application-source/project-documentation writer. It implements only an approved plan, synchronizes required documentation and produces fresh required verification/operational evidence before `TASK_VALIDATED`.

At `TASK_VALIDATED`, source/task documentation and evidence target are frozen. Architect creates two fresh independent reviewer packets and requests both reviewers before consuming either result.

Final Reviewer validates requirement provenance first, then plan authorization, skill/memory relevance, risk classification, dependency admission/safepoint, evidence sufficiency/freshness, implementation and reviewer allegations. Reviewer agreement is never counted as proof.

Final task verdicts:

- `PASS`;
- `IMPLEMENTATION_DEFECT`;
- `PLAN_DEFECT`;
- `BLOCKED`.

A perfect implementation of a materially wrong plan is `PLAN_DEFECT`. Required stale/insufficient evidence cannot support PASS. Maximum failed final-adjudication cycles: three, then `BLOCKED`.

After an approved `MEMORY_DECISION`, Architect may update Governance Memory. After final `PASS`, Executor creates one scoped local task commit. Push requires explicit user authorization.

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

Resume reads checkpoint/provenance/context/instruction/skill/memory/verification artifacts and Git state. It never fabricates historical dependency admission, safepoint, Operational Assurance execution or memory approval.

Examples:

- `READY_FOR_EXECUTION` → refresh skill/memory refs and execution packet; route through required safepoint before risky mutation;
- interrupted `PRE_CHANGE_SAFEPOINT` → finish/validate safepoint before mutation;
- interrupted `IMPLEMENTING` → reconcile worktree/admission/safepoint/evidence dependencies;
- interrupted validation → rerun only missing/stale required gates;
- `TASK_VALIDATED` → confirm evidence freshness, then fresh dual review;
- interrupted `FINAL_ADJUDICATION` → rebuild final packet from fresh canonical evidence;
- `PASS` + approved unpersisted memory → persist exact validated entry, then finalization;
- `LOCAL_COMMITTED` → nothing to resume;
- `BLOCKED`/`BASELINE_BLOCKED` → remain blocked until authoritative resolution.

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

Release review re-evaluates production-wide evidence, including dependency admission, dependency/lockfile delta, required safepoint/recovery proof, public contract compatibility, generated artifacts, migrations/data preservation, environment/release toolchain, Operational Assurance, existing non-functional budgets, unresolved flakiness, high-risk input evidence and authoritative human-owner release gates when applicable.

Final release verdict remains:

```text
READY_FOR_PRODUCTION
NOT_READY_FOR_PRODUCTION
```

## Documentation and license

`.ai/DOCUMENTATION_SCOPE.md` maps canonical documentation/applicability. Required documentation is synchronized before validation and reviewed with code. `.ai/**` and project `docs/**` remain outside runtime artifacts by default except explicit legal/packaging/runtime exceptions.

Governance never chooses/invents software licenses. Missing explicit license state becomes `LICENSE_DECISION_REQUIRED` and blocks release readiness.

## Large repositories

Routine tasks reuse validated indexes/memory, Git delta, context routing, optional bounded read-only discovery and test-impact evidence. Full revalidation remains reserved for materially stale evidence or broad architectural/dependency/import changes.