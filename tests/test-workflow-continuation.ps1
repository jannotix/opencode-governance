param()
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Core=Join-Path $Root 'scripts/workflow-continuation.py'
$Temp=Join-Path ([IO.Path]::GetTempPath()) ('opencode-workflow-continuation-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Force -Path $Temp|Out-Null
    $RunState=Join-Path $Temp 'RUN_STATE.json'
    @{top_level_command='ai-workflow';current_phase='AUDIT_PASS';next_required_phase='IDEA_INTAKE';terminal_reason=$null}|ConvertTo-Json|Set-Content -LiteralPath $RunState -Encoding utf8
    $Output=& python $Core --run-state $RunState --expected-command ai-workflow 2>&1;$Code=$LASTEXITCODE
    if($Code-ne3){throw "Expected exit 3, got $Code. Output: $($Output-join"`n")"}
    if((($Output-join"`n")|ConvertFrom-Json).decision-ne'CONTINUE_REQUIRED'){throw 'Expected CONTINUE_REQUIRED'}
    @{top_level_command='ai-workflow';current_phase='LOCAL_COMMITTED';next_required_phase=$null;terminal_reason=$null}|ConvertTo-Json|Set-Content -LiteralPath $RunState -Encoding utf8
    $Output=& python $Core --run-state $RunState --expected-command ai-workflow 2>&1
    if($LASTEXITCODE-ne0-or(($Output-join"`n")|ConvertFrom-Json).decision-ne'TERMINAL_ALLOWED'){throw 'Expected TERMINAL_ALLOWED'}
}finally{Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'PASS: Windows workflow continuation gate'
