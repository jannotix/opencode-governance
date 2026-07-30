param()
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Core=Join-Path $Root 'scripts/workflow-continuation.ps1'
$Temp=Join-Path ([IO.Path]::GetTempPath()) ('opencode-workflow-continuation-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Force -Path $Temp|Out-Null
    $RunState=Join-Path $Temp 'RUN_STATE.json'
    @{top_level_command='ai-workflow';current_phase='AUDIT_PASS';next_required_phase='IDEA_INTAKE';terminal_reason=$null}|ConvertTo-Json|Set-Content -LiteralPath $RunState -Encoding utf8
    $Output=& pwsh -NoProfile -File $Core -RunStatePath $RunState -ExpectedCommand ai-workflow 2>&1;$Code=$LASTEXITCODE
    if($Code-ne3){throw "Expected exit 3, got $Code. Output: $($Output-join"`n")"}
    if((($Output-join"`n")|ConvertFrom-Json).decision-ne'CONTINUE_REQUIRED'){throw 'Expected CONTINUE_REQUIRED'}
    @{top_level_command='ai-workflow';current_phase='LOCAL_COMMITTED';next_required_phase=$null;terminal_reason=$null}|ConvertTo-Json|Set-Content -LiteralPath $RunState -Encoding utf8
    $Output=& pwsh -NoProfile -File $Core -RunStatePath $RunState -ExpectedCommand ai-workflow 2>&1
    if($LASTEXITCODE-ne0-or(($Output-join"`n")|ConvertFrom-Json).decision-ne'TERMINAL_ALLOWED'){throw 'Expected TERMINAL_ALLOWED'}
    @{top_level_command='ai-workflow';current_phase='BLOCKED';next_required_phase=$null;terminal_reason=$null}|ConvertTo-Json|Set-Content -LiteralPath $RunState -Encoding utf8
    $Output=& pwsh -NoProfile -File $Core -RunStatePath $RunState -ExpectedCommand ai-workflow 2>&1
    if($LASTEXITCODE-ne2-or(($Output-join"`n")|ConvertFrom-Json).error-ne'TERMINAL_REASON_REQUIRED'){throw 'Expected fail-closed blocker validation'}
}finally{Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'PASS: native Windows workflow continuation gate'
