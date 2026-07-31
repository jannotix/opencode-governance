# Troubleshooting

## Model does not load

```bash
opencode models
```

Confirm the configured model ID matches a locally registered ID exactly. Re-run the installer to reassign models.

## Variant rejected

Re-run the installer with a blank variant, or with a variant the selected model actually supports. Resolve `highest_supported` locally before install.

## Commands missing

Restart OpenCode. Confirm `OPENCODE_CONFIG_DIR` and run `verify` / `verify-routing`.

## Install or config corruption

Timestamped backups live under the OpenCode configuration directory. Restore the relevant backup, then re-run the installer with the same routing profile.

## `CONTINUE_REQUIRED` / non-terminal workflow

`/ai-workflow` is not complete. Inspect `RUN_STATE.json`:

- non-terminal phases require typed `next_action` and empty `terminal_reason`
- only `LOCAL_COMMITTED` or an explicit blocker with `terminal_reason` is terminal
- run installed `workflow-continuation.py` against the task state

## `INVALID_RUN_STATE`

Repair `top_level_command`, `current_phase`, `next_required_phase`, `terminal_reason` and `next_action` from primary evidence. Narrative “retry” is not an executable action.

## `APPROVAL_RECEIPT_MISMATCH` / pre-commit blocked

The staged tree no longer matches the receipt candidate identity. Re-freeze the candidate, re-run review, or disarm the project pre-commit gate if the owner intentionally abandons the arming.

## `PROJECT_STATE_CHANGED` / `ARCHITECT_RUNNER_*`

The Architect runner detected unexpected project mutation outside allowed `.ai/**` writes, or a host/runner contract failure. Discard the failed attempt, restore from safepoint if needed, and restart the full role from the same packet.

## `CAPABILITY_*` / routing verify failure

Capability tools and managed prompt sections are hash-checked. Re-run the unified installer with the routing profile; do not hand-edit installed agent sections.

## PowerShell host errors on Windows

Use PowerShell 7+ (`pwsh`). Windows PowerShell 5.1 is rejected by the Architect runner.

## Workflow blocked

Run `/ai-status` and inspect `.ai/tasks/<TASK-ID>/`. A `BLOCKED` verdict must name the missing evidence or environment dependency.
