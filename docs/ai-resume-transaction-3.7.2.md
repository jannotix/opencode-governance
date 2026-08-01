# Design: OpenCode Governance 3.7.2 — transactional `/ai-resume`

## Problem

In 3.7.1 the Architect transactional runner accepted only:

```text
ai-init | ai-audit | ai-discover | ai-plan
```

`/ai-resume` reconstructed state and applied `WORKFLOW_CONTINUATION_GATE_V1`, but had no entry gate forcing a transactional snapshot. Direct in-process resume could write `.ai/**`, abort mid-tool, and leave partial governance state with no external runner and no rollback.

## Goals

1. Transactional `/ai-resume` for **pre-side-effect** phases.
2. Rollback of `.ai/**` on any non-successful exit when project content is unchanged.
3. Explicit `TOOL_EXECUTION_ABORTED` classification.
4. Recovery of orphan Architect transactions via durable journals.
5. Hard separation of pre-implementation vs post-implementation resume.
6. Windows and Unix regressions that reproduce the abort incident.

## Non-goals

- Automatic restart of `/ai-workflow`, `/ai-execute`, `/ai-review`, `/ai-release`.
- Rolling back application source (still forbidden; `PROJECT_STATE_CHANGED` fails closed).
- Blind full `.ai/**` rollback after `IMPLEMENTING`.

## Resume mode (`RESUME_MODE_V1`)

| Mode | When | Runner | `.ai/**` rollback |
|------|------|--------|-------------------|
| `PRE_SIDE_EFFECT` | `current_phase` / `state` / `last_safe_transition` not in post set (e.g. still at `READY_FOR_EXECUTION`) | Required | Yes |
| `POST_SIDE_EFFECT` | Those fields are `IMPLEMENTING` or later | Refused (`RESUME_POST_SIDE_EFFECT`) | No automatic full-tree rollback |

`next_required_phase` alone is **not** a post-side-effect signal. A task at `READY_FOR_EXECUTION` with next `IMPLEMENTING` is still pre-side-effect.

## Durable transaction journal

```text
<OPENCODE_CONFIG_DIR>/opencode-governance-architect-tx/<sha256(project-path)>/
  meta.json          # ARCHITECT_TRANSACTION_V1
  ai-snapshot/       # frozen .ai/**
```

Lifecycle:

1. Recover orphan (dead PID + matching project fingerprint → restore).
2. Open journal (PID, hashes, command).
3. Route attempts with restore-on-eligible-failure.
4. Success → close journal.
5. Failure with successful restore → close journal.
6. Failure without restore → retain orphan for next invocation.

## Failure class

`TOOL_EXECUTION_ABORTED` matches abort phrasing and abnormal exit codes. Profiles may list it under `settings.eligible_failures` for bounded failover (included in the architect failover test fixture).

## Tests

- `tests/test-ai-resume-transaction.ps1`
- `tests/test-ai-resume-transaction.sh`

Scenarios:

1. Abort mid-resume → classify `TOOL_EXECUTION_ABORTED` → restore partial `.ai/**` → failover success.
2. Post-side-effect resume → `RESUME_POST_SIDE_EFFECT`, tree preserved.
3. Orphan journal with dead PID → `ARCHITECT_ORPHAN_RECOVERED` → resume succeeds.

## Surface changes

- `scripts/run-governed.ps1` / `.sh` (installed as `architect-attempt.*`)
- `scripts/install-base.*` entry gate injection for `ai-resume`
- `templates/commands/ai-resume.md`
- `scripts/verify-routing.*`, install eligible-failure allowlists
- Docs + CHANGELOG + VERSION `3.7.2`
