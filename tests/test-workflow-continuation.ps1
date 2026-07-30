param()

$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Wrapper=Join-Path $Root 'scripts/workflow-continuation.ps1'
$Temp=Join-Path ([IO.Path]::GetTempPath()) ('opencode-workflow-continuation-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Force -Path $Temp|Out-Null
    $RunState=Join-Path $Temp 'RUN_STATE.json'
    @{
        top_level_command='ai-workflow'
        current_phase='AUDIT_PASS'
        next_required_phase='IDEA_INTAKE'
        terminal_reason=$null
    }|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $RunState -Encoding utf8
    $Output=& pwsh -NoProfile -File $Wrapper -RunStatePath $RunState -ExpectedCommand ai-workflow 2>&1
    $Code=$LASTEXITCODE
    if($Code-ne3){throw "Expected CONTINUE_REQUIRED exit 3, got $Code. Output: $($Output-join"`n")"}
    $Payload=($Output-join"`n")|ConvertFrom-Json
    if($Payload.decision-ne'CONTINUE_REQUIRED'){throw 'PowerShell wrapper did not return CONTINUE_REQUIRED.'}

    @{
        top_level_command='ai-workflow'
        current_phase='LOCAL_COMMITTED'
        next_required_phase=$null
        terminal_reason=$null
    }|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $RunState -Encoding utf8
    $Output=& pwsh -NoProfile -File $Wrapper -RunStatePath $RunState -ExpectedCommand ai-workflow 2>&1
    if($LASTEXITCODE-ne0){throw "Expected terminal success. Output: $($Output-join"`n")"}
    $Payload=($Output-join"`n")|ConvertFrom-Json
    if($Payload.decision-ne'TERMINAL_ALLOWED'){throw 'PowerShell wrapper did not return TERMINAL_ALLOWED.'}
}finally{
    Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host 'PASS: Windows workflow continuation wrapper'
