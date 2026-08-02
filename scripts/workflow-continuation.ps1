param(
    [Parameter(Mandatory=$true)][string]$RunStatePath,
    [Parameter(Mandatory=$true)][ValidateSet('ai-workflow','ai-resume')][string]$ExpectedCommand
)

# Thin wrapper: semantic evaluation is owned by workflow-continuation.py /
# SEMANTIC_WORKFLOW_STATE_MACHINE_V1 (generated contract). Markers retained:
# WORKFLOW_CONTINUATION_GATE_V1 CONTINUE_REQUIRED TERMINAL_ALLOWED INVALID_RUN_STATE
# AUDIT_PASS LOCAL_COMMITTED

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PyCore = Join-Path $ScriptDir 'workflow-continuation.py'
if (-not (Test-Path -LiteralPath $PyCore -PathType Leaf)) {
    Write-Error "WORKFLOW_CONTINUATION_PYTHON_MISSING: $PyCore"
    exit 2
}
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $python) {
    Write-Error 'WORKFLOW_CONTINUATION_PYTHON_MISSING: python is required for SEMANTIC_WORKFLOW_STATE_MACHINE_V1'
    exit 2
}
& $python.Source $PyCore --run-state $RunStatePath --expected-command $ExpectedCommand
exit $LASTEXITCODE
