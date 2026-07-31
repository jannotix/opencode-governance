$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Runner = Join-Path $Root 'scripts/run-governed.ps1'
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('opencode-runner-' + [guid]::NewGuid().ToString('N'))
$Project = Join-Path $Temp 'project'
$Config = Join-Path $Temp 'config'
$Routing = Join-Path $Temp 'routing.json'

try {
    New-Item -ItemType Directory -Force -Path $Project, $Config | Out-Null
    $Profile = [ordered]@{
        schema_version = '1.0'
        settings = [ordered]@{
            enabled_roles = @('architect')
            eligible_failures = @('PROVIDER_UNAVAILABLE')
            default_cooldown_seconds = 0
            allow_degraded_independence = $false
        }
        roles = [ordered]@{
            architect = [ordered]@{
                primary = [ordered]@{ model='test/primary'; variant=$null; variant_policy='provider_default'; model_family='family-a'; only_on=@() }
                fallbacks = @([ordered]@{ model='test/fallback'; variant=$null; variant_policy='provider_default'; model_family='family-a'; priority=1; only_on=@('PROVIDER_UNAVAILABLE') })
            }
        }
    }
    $Profile | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Routing -Encoding utf8NoBOM

    $Output = & pwsh -NoProfile -File $Runner `
        -ProjectDir $Project `
        -Command ai-plan `
        -Arguments test `
        -RoutingConfigPath $Routing `
        -ConfigDir $Config `
        -OpenCodeCommand 'definitely-not-a-real-opencode-command' 2>&1
    $Code = $LASTEXITCODE
    $Text = $Output -join "`n"

    if ($Code -eq 0) { throw 'PowerShell runner accepted an invalid cooldown.' }
    if ($Text -notmatch 'cooldown.*(?:60|between)') {
        throw "PowerShell runner did not reject the invalid cooldown deterministically. Output: $Text"
    }
    Write-Host 'PASS: PowerShell runner contract regressions'
}
finally {
    Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 0
}

pwsh -NoProfile -File (Join-Path $PSScriptRoot 'test-executor-transaction.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Windows Executor transaction regression failed.' }
