$ErrorActionPreference = 'Stop'
$ConfigDir = if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $HOME '.config\opencode' }
$RootDir = Split-Path -Parent $PSScriptRoot
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir = Join-Path $ConfigDir "backups\opencode-governance-$Stamp"

$ArchitectModel = Read-Host 'Architect model ID (provider/model)'
$ArchitectVariant = Read-Host 'Architect variant/reasoning (optional)'
$ExecutorModel = Read-Host 'Executor model ID (provider/model)'
$ExecutorVariant = Read-Host 'Executor variant/reasoning (optional)'
$ReviewerImplementationModel = Read-Host 'Implementation Reviewer model ID (provider/model)'
$ReviewerImplementationVariant = Read-Host 'Implementation Reviewer variant/reasoning (optional)'
$ReviewerArchitectureModel = Read-Host 'Architecture/Security Reviewer model ID (provider/model)'
$ReviewerArchitectureVariant = Read-Host 'Architecture/Security Reviewer variant/reasoning (optional)'
$FinalReviewerModel = Read-Host 'Final Reviewer/Judge model ID (provider/model)'
$FinalReviewerVariant = Read-Host 'Final Reviewer/Judge variant/reasoning (optional)'

$RequiredModels = @($ArchitectModel, $ExecutorModel, $ReviewerImplementationModel, $ReviewerArchitectureModel, $FinalReviewerModel)
if ($RequiredModels | Where-Object { [string]::IsNullOrWhiteSpace($_) }) {
    throw 'Model IDs cannot be empty. The same model ID may be reused across roles if desired.'
}
if ($RequiredModels | Where-Object { $_ -notmatch '^[^/\s]+/\S+$' }) {
    throw 'Every model ID must use the full OpenCode provider/model format returned by `opencode models`.'
}

New-Item -ItemType Directory -Force -Path (Join-Path $ConfigDir 'agents'), (Join-Path $ConfigDir 'commands'), $BackupDir | Out-Null

function Backup-IfExists([string]$Path) {
    if (Test-Path $Path -PathType Leaf) { Copy-Item $Path (Join-Path $BackupDir (Split-Path $Path -Leaf)) -Force }
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $Encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $Encoding)
}

@('architect.md','build.md','plan.md','executor.md','reviewer.md','reviewer-architecture.md','final-reviewer.md') | ForEach-Object { Backup-IfExists (Join-Path $ConfigDir "agents\$_") }
@('ai-init.md','ai-audit.md','ai-docs.md','ai-plan.md','ai-execute.md','ai-review.md','ai-workflow.md','ai-status.md','ai-release.md') | ForEach-Object { Backup-IfExists (Join-Path $ConfigDir "commands\$_") }
Backup-IfExists (Join-Path $ConfigDir 'opencode.jsonc')
Backup-IfExists (Join-Path $ConfigDir 'opencode.json')

function Render-Agent($Source, $Destination, $ModelToken, $Model, $VariantToken, $Variant) {
    $Text = Get-Content $Source -Raw
    $Text = $Text.Replace($ModelToken, $Model)
    $VariantLine = if ([string]::IsNullOrWhiteSpace($Variant)) { '' } else { "variant: $Variant" }
    $Text = $Text.Replace($VariantToken, $VariantLine)
    Write-Utf8NoBom $Destination $Text
}

Render-Agent (Join-Path $RootDir 'templates\agents\architect.md') (Join-Path $ConfigDir 'agents\architect.md') '__ARCHITECT_MODEL__' $ArchitectModel '__ARCHITECT_VARIANT_LINE__' $ArchitectVariant
Render-Agent (Join-Path $RootDir 'templates\agents\build.md') (Join-Path $ConfigDir 'agents\build.md') '__ARCHITECT_MODEL__' $ArchitectModel '__ARCHITECT_VARIANT_LINE__' $ArchitectVariant
Render-Agent (Join-Path $RootDir 'templates\agents\plan.md') (Join-Path $ConfigDir 'agents\plan.md') '__ARCHITECT_MODEL__' $ArchitectModel '__ARCHITECT_VARIANT_LINE__' $ArchitectVariant
Render-Agent (Join-Path $RootDir 'templates\agents\executor.md') (Join-Path $ConfigDir 'agents\executor.md') '__EXECUTOR_MODEL__' $ExecutorModel '__EXECUTOR_VARIANT_LINE__' $ExecutorVariant
Render-Agent (Join-Path $RootDir 'templates\agents\reviewer.md') (Join-Path $ConfigDir 'agents\reviewer.md') '__REVIEWER_IMPLEMENTATION_MODEL__' $ReviewerImplementationModel '__REVIEWER_IMPLEMENTATION_VARIANT_LINE__' $ReviewerImplementationVariant
Render-Agent (Join-Path $RootDir 'templates\agents\reviewer-architecture.md') (Join-Path $ConfigDir 'agents\reviewer-architecture.md') '__REVIEWER_ARCHITECTURE_MODEL__' $ReviewerArchitectureModel '__REVIEWER_ARCHITECTURE_VARIANT_LINE__' $ReviewerArchitectureVariant
Render-Agent (Join-Path $RootDir 'templates\agents\final-reviewer.md') (Join-Path $ConfigDir 'agents\final-reviewer.md') '__FINAL_REVIEWER_MODEL__' $FinalReviewerModel '__FINAL_REVIEWER_VARIANT_LINE__' $FinalReviewerVariant
Copy-Item (Join-Path $RootDir 'templates\commands\*.md') (Join-Path $ConfigDir 'commands') -Force

$JsoncPath = Join-Path $ConfigDir 'opencode.jsonc'
$JsonPath = Join-Path $ConfigDir 'opencode.json'
$Target = if ((Test-Path $JsoncPath) -or -not (Test-Path $JsonPath)) { $JsoncPath } else { $JsonPath }

if (Test-Path $Target) {
    $Raw = Get-Content $Target -Raw
    $Stripped = [regex]::Replace($Raw, '/\*.*?\*/', '', 'Singleline')
    $Stripped = [regex]::Replace($Stripped, '(?m)^\s*//.*$', '')
    $Stripped = [regex]::Replace($Stripped, ',\s*([}\]])', '$1')
    if ([string]::IsNullOrWhiteSpace($Stripped)) {
        $Obj = [pscustomobject][ordered]@{ '$schema' = 'https://opencode.ai/config.json' }
    } else {
        try { $Obj = $Stripped | ConvertFrom-Json } catch { throw "Cannot safely merge $Target. Restore the backup and set default_agent manually to architect." }
    }
} else {
    $Obj = [pscustomobject][ordered]@{ '$schema' = 'https://opencode.ai/config.json' }
}

$Obj | Add-Member -MemberType NoteProperty -Name 'default_agent' -Value 'architect' -Force
$Json = $Obj | ConvertTo-Json -Depth 20
Write-Utf8NoBom $Target ($Json + [Environment]::NewLine)

& (Join-Path $PSScriptRoot 'verify.ps1') -ConfigDir $ConfigDir
Write-Host 'Installed. Architect is default; built-in Build is governed full workflow and Plan is governed planning-only.'
Write-Host 'Initial or materially stale codebase baselines require independent dual audit plus final adjudication before implementation.'
Write-Host 'Project documentation is governed through DOCUMENTATION_SCOPE and /ai-docs, outside the production runtime boundary by default.'
Write-Host 'Architect/Build/Plan must clarify material ambiguities with the user instead of inventing decisions.'
Write-Host 'Use full provider/model IDs to select the exact subscription/provider path for each role.'
Write-Host 'Restart OpenCode Desktop/TUI before use.'
Write-Host "Backup: $BackupDir"