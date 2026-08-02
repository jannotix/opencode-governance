# Architect stdin prompt transport (3.7.4)

Contract: **`ARCHITECT_STDIN_PROMPT_TRANSPORT_V1`**

## Incident

OpenCode Governance 3.7.3 placed the complete governed Architect handoff on the child process command line. Large `/ai-resume` owner handoffs exceeded the Windows command-line length limit. `Process.Start()` failed with “The filename or extension is too long” before OpenCode started. This is a launcher transport defect, not a model, provider, permission, or TorentIA defect.

## Contract

External governed Architect runner invocations:

1. Keep control arguments on argv only:

   ```text
   opencode run
     --dir <project>
     --agent architect
     --model <model>
     [--variant <variant>]
     --command <ai-*>
     --format json
   ```

2. Write the complete governed prompt (`$RoutedArguments` / runner arguments including the governance marker) to the child **standard input** as exact UTF-8 without BOM.
3. Close stdin after the full payload is written so the child receives EOF.
4. Never place the complete handoff on argv, in environment variables, or via shell interpolation.
5. Never silently fall back to command-line transport.
6. Never log the complete prompt. Sanitised logs report size and SHA-256 only.
7. Preserve Unicode, line endings, and the exact transported UTF-8 byte sequence (no truncation, no unaccounted prefix/suffix).

## Logging

```text
ARCHITECT_PROMPT_TRANSPORT
contract=ARCHITECT_STDIN_PROMPT_TRANSPORT_V1
mode=stdin
bytes=<utf8-byte-count>
sha256=<sha256-of-stdin-payload>
argv_prompt_bytes=0
```

## Transaction binding

`ARCHITECT_TRANSACTION_V2` is extended compatibly with:

| Field | Value |
| --- | --- |
| `prompt_transport` | `stdin` |
| `prompt_transport_contract` | `ARCHITECT_STDIN_PROMPT_TRANSPORT_V1` |
| `arguments_sha256` | existing authoritative hash (unchanged by transport) |
| `arguments_utf8_bytes` | UTF-8 byte length of the stdin payload |
| `argv_prompt_bytes` | `0` |

## Failure types

| Code | When | Fallback |
| --- | --- | --- |
| `ARCHITECT_PROMPT_TRANSPORT_FAILED` | Process start / stdin write-close / broken pipe / transport OS errors | Never model-fallback |
| `ARCHITECT_PROMPT_SIZE_LIMIT_EXCEEDED` | Payload exceeds explicit safety max before child start | Never model-fallback |

Both restore `.ai/**` when the project-state fingerprint is unchanged, preserve application source, and report only size + SHA-256 (never prompt text).

### Safety maximum

Default: **64 MiB**. Override with `OPENCODE_GOVERNANCE_PROMPT_MAX_BYTES` (integer ≥ 1 MiB). The runner fails closed before starting the child and never truncates.

## PowerShell

```powershell
$info.RedirectStandardInput = $true
$info.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
# ArgumentList: control args only — not $RoutedArguments
$process.Start()
# async stdout/stderr reads first
$process.StandardInput.Write($RoutedArguments)
$process.StandardInput.Close()
```

## Unix

Direct `subprocess.run(..., input=prompt_utf8, capture_output=True)` (bytes UTF-8). No shell pipeline, so the OpenCode exit code is preserved. No temporary prompt file is required for direct stdin writing.

## Security properties

- Prompt is not visible in process listings as an argv element.
- Prompt is not written to launcher logs or error strings.
- Prompt is not placed in environment variables.
- Prompt text beginning with `-`, quotes, pipes, or newlines cannot alter CLI argv structure.
- Headless permission contract and external-directory allow-list are unchanged.
- No broader Architect read/write permissions are granted for transport.

## Verification

Windows:

```powershell
pwsh -NoProfile -File tests/test-prompt-transport.ps1
```

Unix:

```bash
bash tests/test-prompt-transport.sh
```

Sizes covered: 1 KiB, 32 KiB, 64 KiB, 256 KiB, 1 MiB (mock child), plus Unicode, empty optional arguments, early-close, and size-limit paths.
