$ErrorActionPreference = 'Stop'
$ConfigDir = if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $HOME '.config\opencode' }
$RootDir = Split-Path -Parent $PSScriptRoot
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir = Join-Path $ConfigDir "backups\opencode-governance-$Stamp"

$ArchitectModel = Read-Host 'Architect model ID'
$ArchitectVariant = Read-Host 'Architect variant/reasoning (optional)'
$ExecutorModel = Read-Host 'Executor model ID'
$ExecutorVariant = Read-Host 'Executor variant/reasoning (optional)'
$ReviewerModel = Read-Host 'Reviewer model ID'
$ReviewerVariant = Read-Host 'Reviewer variant/reasoning (optional)'

if ([string]::IsNullOrWhiteSpace($ArchitectModel) -or [string]::IsNullOrWhiteSpace($ExecutorModel) -or [string]::IsNullOrWhiteSpace($ReviewerModel)) {
    throw 'Model IDs cannot be empty.'
}

New-Item -ItemType Directory -Force -Path (Join-Path $ConfigDir 'agents'), (Join-Path $ConfigDir 'commands'), $BackupDir | Out-Null

function Backup-IfExists([string]$Path) {
    if (Test-Path $Path -PathType Leaf) { Copy-Item $Path (Join-Path $BackupDir (Split-Path $Path -Leaf)) -Force }
}

@('architect.md','executor.md','reviewer.md') | ForEach-Object { Backup-IfExists (Join-Path $ConfigDir "agents\$_") }
@('ai-init.md','ai-plan.md','ai-execute.md','ai-review.md','ai-workflow.md','ai-status.md','ai-release.md') | ForEach-Object { Backup-IfExists (Join-Path $ConfigDir "commands\$_") }
Backup-IfExists (Join-Path $ConfigDir 'opencode.jsonc')
Backup-IfExists (Join-Path $ConfigDir 'opencode.json')

function Render-Agent($Source, $Destination, $ModelToken, $Model, $VariantToken, $Variant) {
    $Text = Get-Content $Source -Raw
    $Text = $Text.Replace($ModelToken, $Model)
    $VariantLine = if ([string]::IsNullOrWhiteSpace($Variant)) { '' } else { "variant: $Variant" }
    $Text = $Text.Replace($VariantToken, $VariantLine)
    Set-Content -Path $Destination -Value $Text -Encoding UTF8
}

Render-Agent (Join-Path $RootDir 'templates\agents\architect.md') (Join-Path $ConfigDir 'agents\architect.md') '__ARCHITECT_MODEL__' $ArchitectModel '__ARCHITECT_VARIANT_LINE__' $ArchitectVariant
Render-Agent (Join-Path $RootDir 'templates\agents\executor.md') (Join-Path $ConfigDir 'agents\executor.md') '__EXECUTOR_MODEL__' $ExecutorModel '__EXECUTOR_VARIANT_LINE__' $ExecutorVariant
Render-Agent (Join-Path $RootDir 'templates\agents\reviewer.md') (Join-Path $ConfigDir 'agents\reviewer.md') '__REVIEWER_MODEL__' $ReviewerModel '__REVIEWER_VARIANT_LINE__' $ReviewerVariant
Copy-Item (Join-Path $RootDir 'templates\commands\*.md') (Join-Path $ConfigDir 'commands') -Force

$JsoncPath = Join-Path $ConfigDir 'opencode.jsonc'
$JsonPath = Join-Path $ConfigDir 'opencode.json'
$Target = if ((Test-Path $JsoncPath) -or -not (Test-Path $JsonPath)) { $JsoncPath } else { $JsonPath }

if (Test-Path $Target) {
    $Raw = Get-Content $Target -Raw
    $Stripped = [regex]::Replace($Raw, '/\*.*?\*/', '', 'Singleline')
    $Stripped = [regex]::Replace($Stripped, '(?m)^\s*//.*$', '')
    $Stripped = [regex]::Replace($Stripped, ',\s*([}\]])', '$1')
    try { $Obj = $Stripped | ConvertFrom-Json -AsHashtable } catch { throw "Cannot safely merge $Target. Restore the backup and set default_agent manually to architect." }
} else {
    $Obj = @{ '$schema' = 'https://opencode.ai/config.json' }
}
$Obj['default_agent'] = 'architect'
$Obj | ConvertTo-Json -Depth 20 | Set-Content $Target -Encoding UTF8

& (Join-Path $PSScriptRoot 'verify.ps1') -ConfigDir $ConfigDir
Write-Host 'Installed. Restart OpenCode before use.'
Write-Host "Backup: $BackupDir"
