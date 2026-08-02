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

## `ARCHITECT_PERMISSION_BLOCKED` / headless shell auto-reject

A headless external Architect child requested a shell or tool permission that could not be approved non-interactively, or that violates `ARCHITECT_HEADLESS_PERMISSION_CONTRACT_V1`.

- This is **not** a provider/model failure and does **not** trigger model fallback.
- The runner restores `.ai/**` when the project fingerprint is unchanged and preserves attempt logs.
- Prefer native OpenCode tools (`read`/`list`/`glob`/`grep`/LSP) for discovery.
- Upgrade to Governance 3.7.4+, reinstall, run `verify` / `verify-routing`, then retry.

### Architect child never starts / “filename or extension is too long”

Symptom (Windows): `Process.Start` fails with “The filename or extension is too long” before OpenCode logs appear; routing and headless permission lines may already be printed.

Cause (pre-3.7.4): the governed handoff was placed on the process command line and exceeded the OS limit.

Fix: install Governance **3.7.4+** so runners use `ARCHITECT_STDIN_PROMPT_TRANSPORT_V1` (prompt on stdin, control args only on argv). Confirm logs include `ARCHITECT_PROMPT_TRANSPORT contract=ARCHITECT_STDIN_PROMPT_TRANSPORT_V1` and `argv_prompt_bytes=0`. This is not a model, provider, or permission failure and must not trigger model fallback.
- Do not enable blanket `bash: "*": allow` or unrestricted `--auto`.

See [Architect Headless Permission Contract](architect-headless-permission-contract.md).

## Routing profile is invalid JSON (JSONC comments)

Installed routing may be JSONC. Governance 3.7.3+ loads routing through the official JSONC normaliser in memory and does not require a manual strict-JSON copy. If load still fails, the file is malformed—repair comments/commas without removing intentional documentation.

### `ARCHITECT_PROMPT_TRANSPORT_FAILED` / `ARCHITECT_PROMPT_SIZE_LIMIT_EXCEEDED`

These are transport-layer failures (stdin write/close, process start, or explicit size safety limit). They do not consume implementation or review cycles and are not eligible for Architect model failover. Check sanitised logs for `bytes=` and `sha256=` only (never the prompt body). Raise `OPENCODE_GOVERNANCE_PROMPT_MAX_BYTES` only when a deliberate larger ceiling is required (minimum configurable floor 1 MiB; default 64 MiB).

## `CAPABILITY_*` / routing verify failure

Capability tools and managed prompt sections are hash-checked. Re-run the unified installer with the routing profile; do not hand-edit installed agent sections.

## PowerShell host errors on Windows

Use PowerShell 7+ (`pwsh`). Windows PowerShell 5.1 is rejected by the Architect runner.

## Workflow blocked

Run `/ai-status` and inspect `.ai/tasks/<TASK-ID>/`. A `BLOCKED` verdict must name the missing evidence or environment dependency.
