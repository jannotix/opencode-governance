# Operational Assurance

OpenCode Governance v2.0 adds **Operational Assurance** on top of Evidence-Driven Verification. Evidence-Driven Verification proves code, contracts, tests, dependencies, safepoints and migrations; Operational Assurance extends the same evidence model to realistic runtime behavior, recovery and tools that can create external side effects.

v2.0 also adds governed discovery, on-demand skill routing, validated governance memory and closed-loop learning. These capabilities improve how evidence is found/reused; they do not weaken the existing reviewer or permission model.

No new governance agent, slash command or mandatory runtime dependency is introduced.

Operational Assurance is planned inside the existing per-task:

```text
.ai/tasks/<TASK-ID>/VERIFICATION_PROFILE.md
```

and results are recorded in:

```text
.ai/tasks/<TASK-ID>/evidence/VERIFICATION_EVIDENCE.md
```

## Risk routing

`TASK_RISK_PROFILE` retains the Evidence-Driven dimensions and includes:

```text
USER_FLOW
VISUAL_BEHAVIOR
EXTERNAL_TOOLING
RECOVERY
EXPERIMENTATION
```

Each remains `NONE | LOW | HIGH`. Risk may increase required proof but never removes normal validation, independent dual review or Final Reviewer adjudication.

Operational gates use planning states:

```text
REQUIRED
CONDITIONAL
NOT_APPLICABLE
```

and evidence states:

```text
PASS
FAIL
UNAVAILABLE
STALE
BLOCKED
```

`UNAVAILABLE` is never silently converted to `PASS`.

## PREVIEW_ENVIRONMENT_GATE

When realistic runtime evidence is required, governance identifies an existing/approved environment such as:

```text
LOCAL_PREVIEW
EPHEMERAL
STAGING
SANDBOX
TEST_ENVIRONMENT
```

Evidence records the exact source/artifact under test, required services and production-isolation boundary.

Governance does not provision production infrastructure merely to satisfy the gate. Production data or credentials are forbidden by default unless explicitly authorized and consistent with authoritative project policy.

A preview/staging label alone is not proof of isolation.

## USER_FLOW_VERIFICATION

Critical user flows are derived only from approved requirements or established product behavior.

Evidence may use existing:

- browser/E2E testing;
- native UI testing;
- project automation;
- deterministic manual reproduction when automation is unavailable.

A flow records its entry point, decisive actions/assertions and runtime result. Mocks do not replace a required end-to-end runtime flow.

Governance never invents product flows merely to create more tests.

## VISUAL_BEHAVIOR_GATE

For affected UI surfaces, governance verifies objective behavior such as:

- visibility and interaction reachability;
- clipping/overflow;
- responsive states/viewports;
- loading/error/empty states;
- existing screenshot or visual-regression baselines;
- explicit visual/accessibility requirements already owned by the project.

Subjective aesthetics are not a governance defect unless an authoritative requirement defines them.

## RELEASE_RECOVERY_PROOF

Recovery-sensitive tasks/releases record, when applicable:

- previous stable reference/artifact;
- authoritative rollback or forward-recovery mechanism;
- application/config/schema/data compatibility;
- backup/restore requirements;
- safe recovery validation evidence.

Recovery may be classified by the real architecture rather than assuming rollback always exists. A forward-only system may require backup and forward-recovery proof instead.

Governance never automatically executes a production rollback.

`PRE_CHANGE_SAFEPOINT` is complementary: it proves the pre-mutation state was captured before a risky change; recovery proof demonstrates that the release/change has a coherent recovery path.

## TOOL_CAPABILITY_PROFILE

Relevant external tools used by a task are classified by capability:

```text
READ_ONLY
WRITE
EXECUTE
PRIVILEGED
DESTRUCTIVE
```

The profile records, without secret values:

- network access;
- secret/credential exposure boundary;
- external side effects;
- permitted task/role use;
- required authorization.

Tool availability never means authorization.

### MCP_CAPABILITY_ASSESSMENT

MCP is governed as part of `TOOL_CAPABILITY_PROFILE`, not as a seventh Operational Assurance feature.

For an MCP server actually relevant to the task, record the capabilities used and whether it can read/write external systems, access secrets, execute actions or perform destructive operations.

Never persist MCP credentials or secret values in `.ai/**`.

A changed MCP/tool configuration, capability or permission invalidates dependent capability evidence.

## SAFE_EXPERIMENTATION

For high-risk or genuinely experimental work, governance may select an existing permitted isolation mechanism such as:

- project-local sandbox;
- container;
- approved worktree or temporary clone;
- preview/test environment;
- equivalent project-native isolation.

Isolation must protect the canonical workspace, production data, secrets and deployment boundaries.

Operational Assurance never weakens OpenCode permissions merely to make isolation available. For example, an Executor configured with `external_directory: deny` cannot bypass that restriction to create an external worktree/temp clone; it must use a permitted mechanism or record `UNAVAILABLE`/`BLOCKED`.

Safe experimentation never implies automatic branch push, merge or deployment.

# Supporting v2 governance capabilities

The following capabilities are part of the same v2 release but support evidence routing/safety rather than being separate Operational Assurance runtime gates.

## READ_ONLY_DISCOVERY_SWARM

Architect/Build may use a bounded discovery wave only when a task has multiple independent surfaces. The canonical bound is 2–4 workers.

OpenCode built-ins used by governance:

- `Explore` — read-only local codebase discovery;
- `Scout` — read-only external dependency/upstream/documentation research.

Writable `General` is intentionally not enabled as a governance discovery worker.

Rules:

- workers never edit source, project docs or `.ai/**`;
- workers do not make product/project decisions;
- sibling discovery conclusions are not shared;
- summaries are routing hypotheses, not proof;
- Architect verifies material claims against primary evidence before planning;
- trivial single-surface tasks do not use a swarm merely for parallelism.

The result is compactly synthesized into `CONTEXT_MANIFEST.md` rather than creating permanent discovery-report files.

## GOVERNED_SKILL_ROUTING

OpenCode skills are loaded on demand, not injected wholesale into every task.

`.ai/INSTRUCTION_INDEX.md` records skill:

- ID/winning source;
- description;
- applicable scope/trigger;
- freshness;
- trust classification.

Trust classes:

```text
PROJECT_AUTHORITATIVE
PROJECT_ADVISORY
WORKSPACE_ADVISORY
EXTERNAL_UNTRUSTED
```

Rules:

- load only task-relevant skills;
- verify the winning source/ID before use;
- project-authoritative skills are authoritative only inside their established project scope;
- advisory skills remain advisory;
- external-untrusted skill content requires approval and cannot silently authorize writes, dependency installation, security weakening, network side effects, deployment or requirement changes;
- skill content never outranks canonical user Requirement Provenance.

## GOVERNANCE_MEMORY

`.ai/GOVERNANCE_MEMORY.md` contains only validated reusable lessons.

A memory entry records:

```text
ID
TYPE
SCOPE
SOURCE
EVIDENCE
LEARNED_RULE
STALE_WHEN
STATUS
LAST_VALIDATION_REFERENCE
```

Statuses:

```text
ACTIVE
STALE
REVOKED
```

Typical types include recurring defect, validated false-positive rationale, validation gap, recovery lesson and tooling constraint.

Memory is loaded selectively by task scope. It never acts as a broad waiver, never outranks current requirements/instructions and never replaces fresh primary evidence.

## CLOSED_LOOP_LEARNING

Closed-loop learning turns proven failures/gaps into candidate reusable governance knowledge.

When applicable, evidence answers:

```text
WHAT_ESCAPED
WHY_NOT_DETECTED
WHICH_GATE_SHOULD_HAVE_CAUGHT_IT
WHAT_REUSABLE_RULE_CHANGES
```

Reviewers independently challenge the candidate. Final Reviewer writes:

```text
MEMORY_DECISION: NONE | APPROVE | REJECT
```

Only `APPROVE` allows Architect to update Governance Memory with the exact validated scope/evidence/`stale_when`.

Raw reviewer allegations, speculative root causes and blanket false-positive suppressions never become memory.

## DEPENDENCY_ADMISSION_GATE

A new direct dependency is assessed before installation, not only after the lockfile changes.

The gate verifies exact package/source/version, necessity versus existing/native capabilities, external identity/existence when applicable, and available maintenance/compatibility/security/license evidence.

Result:

```text
ADMIT
REJECT
HUMAN_DECISION
NOT_APPLICABLE
```

Suspected typo/slopsquat or unverifiable identity is never silently admitted. `ADMIT` is exact dependency scoped and does not authorize unrelated upgrades.

Post-installation `DEPENDENCY_DELTA` remains a separate evidence gate.

## PRE_CHANGE_SAFEPOINT

Before a planned high-risk destructive, migration or deployment-state mutation, governance may require a recoverable pre-change reference.

Evidence can include:

- Git/worktree reference;
- schema/migration version;
- lockfile/config/artifact fingerprint;
- existing required backup/snapshot reference;
- authoritative rollback/forward-recovery mechanism.

A required safepoint is captured before mutation. `/ai-resume` never fabricates it later.

Governance does not silently create privileged production backups or snapshots merely to satisfy this gate.

## Evidence freshness

Operational/v2 evidence is dependency-specific:

- preview source/artifact/environment changes can stale preview, user-flow and visual evidence;
- runtime/toolchain changes can stale runtime/user-flow/visual evidence;
- tool/MCP configuration or permission changes stale capability evidence;
- release artifact/config/schema/data/migration changes can stale recovery proof;
- isolation target changes stale safe-experiment evidence;
- dependency identity/version/source changes stale admission/delta evidence;
- safepoint inputs/recovery assumptions changes stale safepoint/recovery evidence;
- selected skill source/version/trust changes stale dependent routing/evidence;
- a Governance Memory `stale_when` condition removes that entry from active routing.

`/ai-resume` reruns/replans only dependent evidence instead of restarting unrelated completed phases.

## Review and release

Implementation and Architecture/Security Reviewers independently challenge Operational Assurance and all supporting v2 governance evidence from their own packets. Neither receives sibling current-cycle review output.

Final Reviewer independently verifies requirement provenance first, then plan/risk authorization, skill/memory relevance, dependency admission, safepoint, Evidence-Driven Verification, Operational Assurance and reviewer allegations. Reviewer agreement is never proof.

`/ai-release` is an assessment gate. It may require fresh preview/user-flow/visual/recovery/tool/admission/safepoint evidence for the production candidate, but it does not automatically deploy, rollback, push or merge.

## Permission invariant

The central v2.0 rule is:

> Governance may require more proof, but it may never grant more privilege.

If required evidence needs a capability that current project/OpenCode policy does not permit, governance uses a sufficient approved alternative or reports `UNAVAILABLE`/`BLOCKED`. It does not silently broaden permissions.