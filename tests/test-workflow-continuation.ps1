param()
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Core = Join-Path $Root 'scripts/workflow-continuation.ps1'
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('opencode-workflow-continuation-' + [guid]::NewGuid().ToString('N'))

function Invoke-Gate([hashtable]$State) {
    $RunState = Join-Path $Temp 'RUN_STATE.json'
    ($State | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $RunState -Encoding utf8
    $Output = & pwsh -NoProfile -File $Core -RunStatePath $RunState -ExpectedCommand ai-workflow 2>&1
    return @{ Code = $LASTEXITCODE; Output = ($Output -join "`n") }
}

try {
    New-Item -ItemType Directory -Force -Path $Temp | Out-Null
    $Action = [ordered]@{
        kind                   = 'execute'
        command                = '/ai-init'
        arguments              = @()
        expected_postcondition = 'IDEA_INTAKE'
    }
    $Result = Invoke-Gate @{
        top_level_command    = 'ai-workflow'
        current_phase        = 'AUDIT_PASS'
        next_required_phase  = 'IDEA_INTAKE'
        terminal_reason      = $null
        lifecycle_mode       = 'STANDARD'
        next_action          = $Action
    }
    if ($Result.Code -ne 3) { throw "Expected exit 3, got $($Result.Code). Output: $($Result.Output)" }
    if ((($Result.Output) | ConvertFrom-Json).decision -ne 'CONTINUE_REQUIRED') { throw 'Expected CONTINUE_REQUIRED' }

    $Cases = @(
        @{ phase = 'BASELINE_DEFECT'; next = 'BASELINE_VALIDATED'; command = '/ai-audit'; post = 'BASELINE_VALIDATED' },
        @{ phase = 'DISCOVERY_DEFECT'; next = 'ADAPTIVE_PRODUCT_DISCOVERY'; command = '/ai-discover'; post = 'ADAPTIVE_PRODUCT_DISCOVERY' },
        @{ phase = 'PASS'; next = 'PRODUCT_COMPLETENESS_RECONCILIATION'; command = '/ai-workflow'; post = 'PRODUCT_COMPLETENESS_RECONCILIATION' },
        @{ phase = 'IMPLEMENTATION_DEFECT'; next = 'IMPLEMENTING'; command = '/ai-execute'; post = 'IMPLEMENTING'; arts = @('EXECUTION_PACKET') },
        @{ phase = 'PLAN_DEFECT'; next = 'CONTEXT_ROUTING'; command = '/ai-plan'; post = 'CONTEXT_ROUTING' },
        @{ phase = 'PRODUCT_DEFECT'; next = 'IMPLEMENTING'; command = '/ai-execute'; post = 'IMPLEMENTING'; arts = @('EXECUTION_PACKET') },
        @{ phase = 'NOT_READY_FOR_PRODUCTION'; next = 'VALIDATED_LEARNING'; command = '/ai-metrics'; post = 'VALIDATED_LEARNING' }
    )
    foreach ($Case in $Cases) {
        $Action = [ordered]@{
            kind                   = 'execute'
            command                = $Case.command
            arguments              = @()
            expected_postcondition = $Case.post
        }
        $State = @{
            top_level_command   = 'ai-workflow'
            current_phase       = $Case.phase
            next_required_phase = $Case.next
            terminal_reason     = $null
            lifecycle_mode      = 'STANDARD'
            next_action         = $Action
        }
        if ($Case.arts) { $State.present_artifacts = $Case.arts }
        $Result = Invoke-Gate $State
        if ($Result.Code -ne 3 -or (($Result.Output) | ConvertFrom-Json).decision -ne 'CONTINUE_REQUIRED') {
            throw "Expected continuation for $($Case.phase): $($Result.Output)"
        }
    }

    $Result = Invoke-Gate @{
        top_level_command   = 'ai-workflow'
        current_phase       = 'AUDIT_PASS'
        next_required_phase = 'IDEA_INTAKE'
        terminal_reason     = $null
    }
    if ($Result.Code -ne 2 -or (($Result.Output) | ConvertFrom-Json).error -ne 'ACTIONABLE_CONTINUATION_REQUIRED') {
        throw 'Expected actionable continuation requirement'
    }

    $Result = Invoke-Gate @{
        top_level_command   = 'ai-workflow'
        current_phase       = 'LOCAL_COMMITTED'
        next_required_phase = $null
        terminal_reason     = $null
    }
    if ($Result.Code -ne 0 -or (($Result.Output) | ConvertFrom-Json).decision -ne 'TERMINAL_ALLOWED') {
        throw 'Expected TERMINAL_ALLOWED'
    }

    $Result = Invoke-Gate @{
        top_level_command   = 'ai-workflow'
        current_phase       = 'BLOCKED'
        next_required_phase = $null
        terminal_reason     = $null
    }
    if ($Result.Code -ne 2 -or (($Result.Output) | ConvertFrom-Json).error -ne 'TERMINAL_REASON_REQUIRED') {
        throw 'Expected fail-closed blocker validation'
    }
}
finally {
    Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host 'PASS: native Windows workflow continuation gate'
