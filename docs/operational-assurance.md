# Operational Assurance

OpenCode Governance v2.0 adds **Operational Assurance** on top of v1.8 Evidence-Driven Verification. Evidence-Driven Verification proves code, contracts, tests, dependencies and migrations; Operational Assurance extends the same evidence model to realistic runtime behavior, recovery and tools that can create external side effects.

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

`TASK_RISK_PROFILE` retains the v1.8 dimensions and adds:

```text
USER_FLOW
VISUAL_BEHAVIOR
EXTERNAL_TOOLING
RECOVERY
EXPERIMENTATION
```

Each remains `NONE | LOW | HIGH`. Risk may increase required proof but never removes normal validation, independent dual review or Final Reviewer adjudication.

Operational gates use the same planning states:

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
- a deterministic manual reproduction when automation is unavailable.

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

MCP is governed as part of `TOOL_CAPABILITY_PROFILE`, not as a seventh feature.

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

## Evidence freshness

Operational evidence is dependency-specific:

- preview source/artifact/environment changes can stale preview, user-flow and visual evidence;
- runtime/toolchain changes can stale runtime/user-flow/visual evidence;
- tool/MCP configuration or permission changes stale capability evidence;
- release artifact/config/schema/data/migration changes can stale recovery proof;
- isolation target changes stale safe-experiment evidence.

`/ai-resume` reruns only dependent evidence instead of restarting unrelated completed phases.

## Review and release

Implementation and Architecture/Security Reviewers independently challenge Operational Assurance from their own evidence packets. Neither receives the sibling current-cycle review.

Final Reviewer independently verifies requirement provenance first, then plan/risk authorization, Evidence-Driven Verification, Operational Assurance and the reviewer allegations. Reviewer agreement is never proof.

`/ai-release` is an assessment gate. It may require fresh preview/user-flow/visual/recovery/tool evidence for the production candidate, but it does not automatically deploy, rollback, push or merge.

## Permission invariant

The central v2.0 rule is:

> Operational Assurance may require more proof, but it may never grant more privilege.

If required evidence needs a capability that current project/OpenCode policy does not permit, governance uses a sufficient approved alternative or reports `UNAVAILABLE`/`BLOCKED`. It does not silently broaden permissions.
