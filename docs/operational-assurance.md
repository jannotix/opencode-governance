# Operational Assurance

Operational Assurance extends Evidence-Driven Verification from code/test correctness to runtime behavior, recovery and external side effects.

It does not add agents, commands or mandatory runtime dependencies.

The governing invariant is:

> Governance may require more proof, but it may never grant more privilege.

Operational gates are planned in:

```text
.ai/tasks/<TASK-ID>/VERIFICATION_PROFILE.md
```

and recorded in:

```text
.ai/tasks/<TASK-ID>/evidence/VERIFICATION_EVIDENCE.md
```

Planning states:

```text
REQUIRED | CONDITIONAL | NOT_APPLICABLE
```

Evidence states:

```text
PASS | FAIL | UNAVAILABLE | STALE | BLOCKED
```

## `PREVIEW_ENVIRONMENT_GATE`

When realistic runtime evidence is required, use an existing or explicitly approved environment such as:

```text
LOCAL_PREVIEW
EPHEMERAL
STAGING
SANDBOX
TEST_ENVIRONMENT
```

Evidence identifies:

- exact source/artifact under test;
- environment type;
- required services;
- production-isolation boundary.

A preview/staging label alone is not proof of isolation. Governance does not provision production infrastructure or use production data/credentials merely to satisfy this gate.

## `USER_FLOW_VERIFICATION`

Critical flows come from approved requirements or established product behavior.

Use existing project mechanisms such as browser/E2E tests, native UI automation, project scripts or deterministic manual reproduction when automation is unavailable.

A flow records:

- flow ID;
- entry point;
- decisive actions;
- assertions;
- runtime result.

Mocks do not replace required end-to-end runtime evidence.

## `VISUAL_BEHAVIOR_GATE`

For affected UI surfaces, verify objective behavior only:

- visibility and interaction reachability;
- clipping/overflow;
- responsive states/viewports;
- loading/error/empty states;
- existing screenshot or visual-regression baselines;
- explicit accessibility/visual requirements owned by the project.

Subjective aesthetics are not governance defects without an authoritative requirement.

## `RELEASE_RECOVERY_PROOF`

Recovery-sensitive tasks/releases record, when applicable:

- previous stable reference/artifact;
- authoritative rollback or forward-recovery mechanism;
- application/config/schema/data compatibility;
- backup/restore requirements;
- safe recovery validation evidence.

Forward-only recovery is valid when it reflects the real architecture. Governance never automatically executes production rollback.

`PRE_CHANGE_SAFEPOINT` is complementary: the safepoint proves the starting state was captured before a risky mutation; recovery proof validates the recovery path for the resulting change.

## `TOOL_CAPABILITY_PROFILE`

Classify relevant external tools before use:

```text
READ_ONLY
WRITE
EXECUTE
PRIVILEGED
DESTRUCTIVE
```

Record, without secret values:

- network exposure;
- secret/credential boundary;
- external side effects;
- permitted task/role use;
- required authorization.

Tool availability is not authorization.

### `MCP_CAPABILITY_ASSESSMENT`

MCP is part of `TOOL_CAPABILITY_PROFILE`, not a separate Operational Assurance feature.

For MCP used by the task, record the relevant read/write/execute/privileged/destructive capabilities, external side effects, secret boundary and authorization state.

Never persist MCP credentials or secret values in `.ai/**`.

A changed tool/MCP configuration, capability or permission invalidates dependent capability evidence.

## `SAFE_EXPERIMENTATION`

For genuinely experimental or high-risk work, use only an existing permitted isolation mechanism, for example:

- project-local sandbox;
- container;
- approved worktree/temporary clone;
- preview/test environment;
- equivalent project-native isolation.

Isolation must protect the canonical workspace, production data, secrets and deployment boundaries.

Operational Assurance never weakens OpenCode permissions to make an isolation mechanism available. If the configured policy forbids the required mechanism, use an approved alternative or record `UNAVAILABLE`/`BLOCKED`.

Safe experimentation does not imply automatic branch push, merge or deployment.

## Risk routing

Operational Assurance uses these `TASK_RISK_PROFILE` dimensions:

```text
USER_FLOW
VISUAL_BEHAVIOR
EXTERNAL_TOOLING
RECOVERY
EXPERIMENTATION
```

Each is `NONE | LOW | HIGH` and may increase required proof. Risk classification never removes normal validation or independent review.

## Freshness

Operational evidence is invalidated only by changes that affect it, including:

- preview source/artifact/environment;
- runtime/toolchain;
- tool/MCP configuration or permissions;
- release artifact/config/schema/data/migration state;
- recovery references;
- isolation target.

`/ai-resume` reruns or replans only dependent evidence.

## Review and release

Implementation and Architecture/Security Reviewers independently challenge applicable Operational Assurance evidence from separate packets.

Final Reviewer independently verifies the requirement trail, plan/risk authorization, operational evidence and reviewer allegations.

`/ai-release` may require fresh Operational Assurance evidence for the production candidate, but it remains an assessment gate. It does not automatically deploy, rollback, merge or push.

## Related controls

- Evidence and risk semantics: [Evidence-Driven Verification](evidence-driven-verification.md)
- Context, skills, memory and resume: [Context efficiency and resumable governance](context-efficiency-resume.md)
- Agent/tool permissions: [Permissions](permissions.md)
