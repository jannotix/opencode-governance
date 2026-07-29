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
    [string]$RoutingConfigPath,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
$CoreInstaller = Join-Path $PSScriptRoot 'install-core.ps1'
if (-not (Test-Path -LiteralPath $CoreInstaller -PathType Leaf)) {
    throw "Core installer not found: $CoreInstaller"
}

& $CoreInstaller @PSBoundParameters

if (-not $ConfigDir) {
    $ConfigDir = if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $HOME '.config\opencode' }
}

if ($RoutingConfigPath) {
    $ToolsDir = Join-Path $ConfigDir 'opencode-governance-tools'
    $ManifestPath = Join-Path $ConfigDir 'opencode-governance-routing.json'
    $ArchitectRunnerPs = Join-Path $ToolsDir 'architect-attempt.ps1'
    $ArchitectRunnerSh = Join-Path $ToolsDir 'architect-attempt.sh'
    Copy-Item (Join-Path $PSScriptRoot 'run-governed.ps1') $ArchitectRunnerPs -Force
    Copy-Item (Join-Path $PSScriptRoot 'run-governed.sh') $ArchitectRunnerSh -Force

    try {
        $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    } catch {
        throw 'Routing manifest is invalid after core installation.'
    }
    if ([string]$Manifest.schema_version -ne '1.0') { throw 'Routing manifest schema_version must be 1.0.' }
    $Manifest | Add-Member -MemberType NoteProperty -Name governance_version -Value '3.3.3' -Force
    $Manifest | Add-Member -MemberType NoteProperty -Name architect_runner_version -Value '3.3.3' -Force
    $Manifest | Add-Member -MemberType NoteProperty -Name managed_tools -Value @(
        $ArchitectRunnerPs,
        $ArchitectRunnerSh,
        (Join-Path $ToolsDir 'executor-attempt.ps1'),
        (Join-Path $ToolsDir 'executor-attempt.sh')
    ) -Force
    [IO.File]::WriteAllText($ManifestPath, (($Manifest | ConvertTo-Json -Depth 30) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))

    $Marker = '[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
    $PolicyBlock = @"

## ARCHITECT_RUNNER_INTEGRATION

Architect pre-execution commands ``ai-init|ai-audit|ai-discover|ai-plan`` require the installed transactional runner.

WINDOWS_ARCHITECT_RUNNER: $ArchitectRunnerPs
WINDOWS_ARCHITECT_HOST: pwsh -NoProfile -File
UNIX_ARCHITECT_RUNNER: $ArchitectRunnerSh
ACTIVE_CHILD_MARKER: $Marker

The PowerShell runner requires PowerShell 7 or newer and fails before any project-state mutation with ``POWERSHELL_7_REQUIRED`` under Windows PowerShell 5.1. Invoke it through ``pwsh -NoProfile -File``.

When the marker is absent, do not write ``.ai/**``; return ``ARCHITECT_RUNNER_REQUIRED`` with the exact installed runner path and command. Never invent ``architect-attempt`` at another path. Never invoke the Architect runner from inside the active OpenCode process. A routed child invocation containing the marker continues normally.
"@
    foreach ($Name in @('architect','build','plan')) {
        $Path = Join-Path $ConfigDir "agents\$Name.md"
        $Text = Get-Content -LiteralPath $Path -Raw
        $Text = [regex]::Replace($Text, '(?s)\r?\n## ARCHITECT_RUNNER_INTEGRATION\r?\n.*?(?=\r?\n## Core invariants|\z)', '')
        if ($Text -match '(?m)^## Core invariants\r?$') {
            $Text = [regex]::Replace($Text, '(?m)^## Core invariants\r?$', ($PolicyBlock.TrimEnd() + "`n`n## Core invariants"), 1)
        } else {
            $Text += $PolicyBlock
        }
        [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
    }

    foreach ($Command in @('ai-init','ai-audit','ai-discover','ai-plan')) {
        $Path = Join-Path $ConfigDir "commands\$Command.md"
        $Text = Get-Content -LiteralPath $Path -Raw
        $Text = [regex]::Replace($Text, '(?s)\r?\n## ARCHITECT_RUNNER_ENTRY_GATE\r?\n.*?(?=\r?\n## |\z)', '')
        $Gate = @"

## ARCHITECT_RUNNER_ENTRY_GATE

Before any ``.ai/**`` write, require the exact invocation marker ``$Marker`` in the command arguments.

When the marker is absent, stop immediately with:

``````text
ARCHITECT_RUNNER_REQUIRED
COMMAND: $Command
WINDOWS_HOST: pwsh -NoProfile -File
WINDOWS_RUNNER: $ArchitectRunnerPs
UNIX_RUNNER: $ArchitectRunnerSh
PROJECT_DIR: <CURRENT_PROJECT_ROOT>
``````

Do not create, edit or delete ``.ai/**``. Do not invoke the runner from inside this OpenCode process. Tell the owner to run ``pwsh -NoProfile -File "$ArchitectRunnerPs"`` with the current project root and ``-Command $Command`` on Windows, or the installed Unix runner with ``--command $Command``. Do not invent another runner path.

When the exact marker is present, this is already a transactional child attempt; continue with the command contract below.
"@
        $FrontMatter = [regex]::Match($Text, '(?s)\A---\r?\n.*?\r?\n---\r?\n')
        if (-not $FrontMatter.Success) { throw "Command front matter not found: $Path" }
        $Text = $Text.Insert($FrontMatter.Length, $Gate)
        [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
    }

    & (Join-Path $PSScriptRoot 'verify-routing.ps1') -ConfigDir $ConfigDir
}

Write-Host 'Installed OpenCode Governance v3.3.3 — PowerShell Host & Verifier Reliability.'
Write-Host 'Architect PowerShell failover now requires pwsh 7+ explicitly; PowerShell child-script failures propagate through exceptions rather than stale native exit codes.'
