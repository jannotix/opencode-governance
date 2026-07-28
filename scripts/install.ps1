param(
    [string]$ConfigDir,
    [string]$ArchitectModel,
    [string]$ArchitectVariant,
    [string]$ExecutorModel,
    [string]$ExecutorVariant,
    [string]$ReviewerImplementationModel,
    [string]$ReviewerImplementationVariant,
    [string]$ReviewerArchitectureModel,
    [string]$ReviewerArchitectureVariant,
    [string]$FinalReviewerModel,
    [string]$FinalReviewerVariant,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'

if (-not $ConfigDir) {
    $ConfigDir = if ($env:OPENCODE_CONFIG_DIR) {
        $env:OPENCODE_CONFIG_DIR
    } else {
        Join-Path $HOME '.config\opencode'
    }
}

$RootDir = Split-Path -Parent $PSScriptRoot
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir = Join-Path $ConfigDir "backups\opencode-governance-$Stamp"

function Resolve-ModelInput([string]$Value, [string]$Prompt, [string]$ParameterName) {
    if (-not [string]::IsNullOrWhiteSpace($Value)) { return $Value }
    if ($NonInteractive) { throw "$ParameterName is required in non-interactive mode." }
    return Read-Host $Prompt
}

function Resolve-VariantInput([string]$Value, [string]$Prompt, [bool]$WasBound) {
    if ($WasBound) { return $Value }
    if ($NonInteractive) { return '' }
    return Read-Host $Prompt
}

$ArchitectModel = Resolve-ModelInput $ArchitectModel 'Architect model ID (provider/model)' 'ArchitectModel'
$ArchitectVariant = Resolve-VariantInput $ArchitectVariant 'Architect variant/reasoning (optional)' ($PSBoundParameters.ContainsKey('ArchitectVariant'))
$ExecutorModel = Resolve-ModelInput $ExecutorModel 'Executor model ID (provider/model)' 'ExecutorModel'
$ExecutorVariant = Resolve-VariantInput $ExecutorVariant 'Executor variant/reasoning (optional)' ($PSBoundParameters.ContainsKey('ExecutorVariant'))
$ReviewerImplementationModel = Resolve-ModelInput $ReviewerImplementationModel 'Implementation Reviewer model ID (provider/model)' 'ReviewerImplementationModel'
$ReviewerImplementationVariant = Resolve-VariantInput $ReviewerImplementationVariant 'Implementation Reviewer variant/reasoning (optional)' ($PSBoundParameters.ContainsKey('ReviewerImplementationVariant'))
$ReviewerArchitectureModel = Resolve-ModelInput $ReviewerArchitectureModel 'Architecture/Security Reviewer model ID (provider/model)' 'ReviewerArchitectureModel'
$ReviewerArchitectureVariant = Resolve-VariantInput $ReviewerArchitectureVariant 'Architecture/Security Reviewer variant/reasoning (optional)' ($PSBoundParameters.ContainsKey('ReviewerArchitectureVariant'))
$FinalReviewerModel = Resolve-ModelInput $FinalReviewerModel 'Final Reviewer/Judge model ID (provider/model)' 'FinalReviewerModel'
$FinalReviewerVariant = Resolve-VariantInput $FinalReviewerVariant 'Final Reviewer/Judge variant/reasoning (optional)' ($PSBoundParameters.ContainsKey('FinalReviewerVariant'))

$RequiredModels = @(
    $ArchitectModel,
    $ExecutorModel,
    $ReviewerImplementationModel,
    $ReviewerArchitectureModel,
    $FinalReviewerModel
)

if ($RequiredModels | Where-Object { [string]::IsNullOrWhiteSpace($_) }) {
    throw 'Model IDs cannot be empty.'
}
if ($RequiredModels | Where-Object { $_ -notmatch '^[^/\s]+/\S+$' }) {
    throw 'Every model ID must use provider/model format from opencode models.'
}

New-Item -ItemType Directory -Force -Path @(
    (Join-Path $ConfigDir 'agents'),
    (Join-Path $ConfigDir 'commands'),
    $BackupDir
) | Out-Null

$Agents = @(
    'architect', 'build', 'plan', 'executor',
    'reviewer', 'reviewer-architecture', 'final-reviewer'
)
$Commands = @(
    'ai-init', 'ai-audit', 'ai-docs', 'ai-discover',
    'ai-plan', 'ai-execute', 'ai-review', 'ai-workflow',
    'ai-status', 'ai-resume', 'ai-metrics', 'ai-release'
)

function Backup-IfExists([string]$Path) {
    if (Test-Path $Path -PathType Leaf) {
        Copy-Item $Path (Join-Path $BackupDir (Split-Path $Path -Leaf)) -Force
    }
}

foreach ($Name in $Agents) {
    Backup-IfExists (Join-Path $ConfigDir "agents\$Name.md")
}
foreach ($Name in $Commands) {
    Backup-IfExists (Join-Path $ConfigDir "commands\$Name.md")
}
Backup-IfExists (Join-Path $ConfigDir 'opencode.jsonc')
Backup-IfExists (Join-Path $ConfigDir 'opencode.json')

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText(
        $Path,
        $Text,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Render-Agent(
    [string]$Source,
    [string]$Destination,
    [string]$ModelToken,
    [string]$Model,
    [string]$VariantToken,
    [string]$Variant
) {
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

foreach ($Name in $Commands) {
    Copy-Item (Join-Path $RootDir "templates\commands\$Name.md") (Join-Path $ConfigDir "commands\$Name.md") -Force
}

$JsoncPath = Join-Path $ConfigDir 'opencode.jsonc'
$JsonPath = Join-Path $ConfigDir 'opencode.json'
$Target = if ((Test-Path $JsoncPath) -or -not (Test-Path $JsonPath)) {
    $JsoncPath
} else {
    $JsonPath
}

if (Test-Path $Target) {
    $Raw = Get-Content $Target -Raw
    $Stripped = [regex]::Replace($Raw, '/\*.*?\*/', '', 'Singleline')
    $Stripped = [regex]::Replace($Stripped, '(?m)^\s*//.*$', '')
    $Stripped = [regex]::Replace($Stripped, ',\s*([}\]])', '$1')
    if ([string]::IsNullOrWhiteSpace($Stripped)) {
        $Object = [pscustomobject][ordered]@{ '$schema' = 'https://opencode.ai/config.json' }
    } else {
        try {
            $Object = $Stripped | ConvertFrom-Json
        } catch {
            throw "Cannot safely merge $Target. Restore the backup and set default_agent manually."
        }
    }
} else {
    $Object = [pscustomobject][ordered]@{ '$schema' = 'https://opencode.ai/config.json' }
}

$Object | Add-Member -MemberType NoteProperty -Name 'default_agent' -Value 'architect' -Force
Write-Utf8NoBom $Target (($Object | ConvertTo-Json -Depth 20) + [Environment]::NewLine)

& (Join-Path $PSScriptRoot 'verify.ps1') -ConfigDir $ConfigDir
Write-Host 'Installed OpenCode Governance v3.0: 7 agents, 12 commands, adaptive product discovery, constructive challenge, independent discovery review, product completeness, Evidence-Driven Verification and Operational Assurance.'
Write-Host 'Project v2 state is migrated lazily by project commands; installation does not rewrite .ai state.'
Write-Host 'No push, merge, deployment or rollback is automatic. Restart OpenCode Desktop/TUI before use.'
Write-Host "Backup: $BackupDir"
