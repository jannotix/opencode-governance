# Design: lossless `/ai-resume` handoff and postcondition validation

## Incident

A pre-side-effect `/ai-resume` was routed through the 3.7.2 transactional Architect runner. The child exited with code 0 and the runner emitted `ARCHITECT_FAILOVER_COMPLETE`, but the task checkpoint and the complete `.ai/**` tree were byte-identical to the pre-run state. No Context Intelligence artifacts, reviewer packets, reviewer reports, candidate or approval receipt were created.

The handoff also shortened the original multiline owner prompt and a `pwsh -NoProfile` process could not resolve an npm-installed `opencode.ps1` without a manual wrapper.

## Reliability contract

The corrected runner treats an exit code as transport evidence, not semantic completion.

For `ai-resume` it now binds:

- an explicit task ID;
- `.ai/tasks/<TASK-ID>/RUN_STATE.json`;
- the checkpoint SHA-256;
- the complete `.ai/**` hash;
- the project-state fingerprint outside `.ai/**`;
- the exact UTF-8 prompt hash;
- the child `GOVERNANCE_RESULT`.

A zero exit is accepted only when the checkpoint or `.ai/**` advances and the child emits `GOVERNANCE_RESULT`. A zero exit with byte-identical state fails as `ARCHITECT_NO_PROGRESS`, restores `.ai/**` and retains attempt logs.

## Lossless arguments

The runners accept `-ArgumentsFile` / `--arguments-file`. The file is read as UTF-8 before the transaction starts, its SHA-256 is bound into `ARCHITECT_TRANSACTION_V2`, and the full prompt is not required in the process command line.

The `/ai-resume` command contract requires the direct entry gate to create a safe user-local handoff file and pass its path together with the explicit task ID. It must not summarize or reconstruct the owner prompt.

## Explicit task selection

Resume mode and postcondition checks use only the supplied task ID. Other newer `RUN_STATE.json` files cannot influence classification.

Failures:

- `RESUME_TASK_ID_REQUIRED`
- `RESUME_TASK_NOT_FOUND`
- `RESUME_TASK_ID_MISMATCH`
- `INVALID_RUN_STATE`

## CLI and working directory

Windows resolution supports explicit commands, `Get-Command`, npm `.ps1`/`.cmd`, WinGet, Scoop and Chocolatey paths. PowerShell scripts are launched through `pwsh -NoProfile -File`; command files use `cmd.exe /d /s /c`.

Unix resolves an explicit command, `PATH`, `~/.opencode/bin`, `~/.local/bin`, `/usr/local/bin` and `/usr/bin`.

The child working directory is always the canonical project root.

## Failure and fallback behavior

`ARCHITECT_NO_PROGRESS`, `ARCHITECT_CHILD_RESULT_MISSING` and `ARCHITECT_CHILD_RESULT_MISMATCH` are semantic failures. They are not provider-availability failures and do not trigger model fallback by default.

The 3.7.2 rollback, project fingerprint and orphan recovery contracts remain in force.

## Regression coverage

- `tests/test-ai-resume-postcondition.ps1`
- `tests/test-ai-resume-postcondition.sh`

The tests cover:

1. a 25,000+ character Unicode/Markdown/JSON prompt passed through an arguments file;
2. explicit task selection in a project containing a newer post-side-effect task;
3. exact child working directory;
4. zero-exit/no-change rejection and rollback;
5. valid checkpoint transition plus surfaced `GOVERNANCE_RESULT`.
