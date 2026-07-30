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
if (-not (Test-Path -LiteralPath $CoreInstaller -PathType Leaf)) { throw "Core installer not found: $CoreInstaller" }
& $CoreInstaller @PSBoundParameters

if (-not $ConfigDir) { $ConfigDir = if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $HOME '.config\opencode' } }

if ($RoutingConfigPath) {
    $ToolsDir = Join-Path $ConfigDir 'opencode-governance-tools'
    $ManifestPath = Join-Path $ConfigDir 'opencode-governance-routing.json'
    $ArchitectRunnerPs = Join-Path $ToolsDir 'architect-attempt.ps1'
    $ArchitectRunnerSh = Join-Path $ToolsDir 'architect-attempt.sh'
    $ContextToolPs = Join-Path $ToolsDir 'context-intelligence.ps1'
    $ContextToolSh = Join-Path $ToolsDir 'context-intelligence.sh'
    $ContextToolPy = Join-Path $ToolsDir 'context-intelligence.py'

    Copy-Item (Join-Path $PSScriptRoot 'run-governed.ps1') $ArchitectRunnerPs -Force
    Copy-Item (Join-Path $PSScriptRoot 'run-governed.sh') $ArchitectRunnerSh -Force
    Copy-Item (Join-Path $PSScriptRoot 'context-intelligence.ps1') $ContextToolPs -Force
    Copy-Item (Join-Path $PSScriptRoot 'context-intelligence.sh') $ContextToolSh -Force
    Copy-Item (Join-Path $PSScriptRoot 'context-intelligence.py') $ContextToolPy -Force

    try { $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json } catch { throw 'Routing manifest is invalid after core installation.' }
    if ([string]$Manifest.schema_version -ne '1.0') { throw 'Routing manifest schema_version must be 1.0.' }
    $Manifest | Add-Member -MemberType NoteProperty -Name governance_version -Value '3.4.0' -Force
    $Manifest | Add-Member -MemberType NoteProperty -Name architect_runner_version -Value '3.3.4' -Force
    $Manifest | Add-Member -MemberType NoteProperty -Name context_intelligence_version -Value '3.4.0' -Force
    $Manifest | Add-Member -MemberType NoteProperty -Name managed_tools -Value @(
        $ArchitectRunnerPs,
        $ArchitectRunnerSh,
        (Join-Path $ToolsDir 'executor-attempt.ps1'),
        (Join-Path $ToolsDir 'executor-attempt.sh'),
        $ContextToolPs,
        $ContextToolSh,
        $ContextToolPy
    ) -Force
    [IO.File]::WriteAllText($ManifestPath, (($Manifest | ConvertTo-Json -Depth 30) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))

    $Marker = '[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
    $ArchitectPolicy = @"

## ARCHITECT_RUNNER_INTEGRATION

Architect pre-execution commands ``ai-init|ai-audit|ai-discover|ai-plan`` require the installed transactional runner.

WINDOWS_ARCHITECT_RUNNER: $ArchitectRunnerPs
WINDOWS_ARCHITECT_HOST: pwsh -NoProfile -File
UNIX_ARCHITECT_RUNNER: $ArchitectRunnerSh
ACTIVE_CHILD_MARKER: $Marker
PROJECT_STATE_FINGERPRINT: PROJECT_STATE_FINGERPRINT_V1
NON_GIT_PROJECTS: NON_GIT_PROJECT_SUPPORTED

The PowerShell runner requires PowerShell 7 or newer and fails before any project-state mutation with ``POWERSHELL_7_REQUIRED`` under Windows PowerShell 5.1. Invoke it through ``pwsh -NoProfile -File``.

Before and after every routed attempt, both runners fingerprint all project entries outside root ``.ai/**`` and Git metadata. Git projects also bind the fingerprint to HEAD, the Git index and recursive submodule state. Non-Git directories are supported with the same content-integrity contract. Any source or project-documentation change returns ``PROJECT_STATE_CHANGED`` and blocks fallback.

When the marker is absent, do not write ``.ai/**``; return ``ARCHITECT_RUNNER_REQUIRED`` with the exact installed runner path and command. Never invent ``architect-attempt`` at another path. Never invoke the Architect runner from inside the active OpenCode process. A routed child invocation containing the marker continues normally.
"@
    $ContextPolicy = @"

## CONTEXT_INTELLIGENCE_V1

WINDOWS_CONTEXT_TOOL: $ContextToolPs
WINDOWS_CONTEXT_HOST: pwsh -NoProfile -File
UNIX_CONTEXT_TOOL: $ContextToolSh
CONTEXT_CORE: $ContextToolPy

Before finalizing ``CONTEXT_MANIFEST.md``, initialize ``CONTEXT_BUDGET.json`` from the exact ``WORK_CLASS`` and use bounded ``DISPATCH -> EVALUATE -> REFINE`` retrieval. Never exceed three cycles. End with ``CONTEXT_SUFFICIENT`` or ``BLOCKED_CONTEXT_GAP``.

Use ``SKILL_CAPABILITY_MANIFEST_V1`` to deduplicate overlapping skills, prefer the highest-trust narrow applicable capability and load only selected sections within the skill budget. Record accepted and rejected candidates with reasons in ``SKILL_SELECTION.json``.

The external content summary cache is advisory, content-addressed and outside the project. A cache hit never replaces current primary evidence for a material claim. Cache failure is a recorded miss, not permission to fabricate context. Context-budget overrides require an evidence-backed reason and never waive security, migration, recovery, contract or operational evidence.
"@
    foreach ($Name in @('architect','build','plan')) {
        $Path = Join-Path $ConfigDir "agents\$Name.md"
        $Text = Get-Content -LiteralPath $Path -Raw
        $Text = [regex]::Replace($Text, '(?s)\r?\n## ARCHITECT_RUNNER_INTEGRATION\r?\n.*?(?=\r?\n## Core invariants|\z)', '')
        $Text = [regex]::Replace($Text, '(?s)\r?\n## CONTEXT_INTELLIGENCE_V1\r?\n.*?(?=\r?\n## Core invariants|\z)', '')
        $Insertion = $ArchitectPolicy.TrimEnd() + "`n" + $ContextPolicy.TrimEnd()
        if ($Text -match '(?m)^## Core invariants\r?$') { $Text = [regex]::Replace($Text, '(?m)^## Core invariants\r?$', ($Insertion + "`n`n## Core invariants"), 1) } else { $Text += "`n" + $Insertion }
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

The external runner supports Git and non-Git project directories. It fingerprints all source and project-documentation content outside root ``.ai/**`` before and after each attempt and returns ``PROJECT_STATE_CHANGED`` on any delta.

Do not create, edit or delete ``.ai/**``. Do not invoke the runner from inside this OpenCode process. Tell the owner to run ``pwsh -NoProfile -File "$ArchitectRunnerPs"`` with the current project root and ``-Command $Command`` on Windows, or the installed Unix runner with ``--command $Command``. Do not invent another runner path.

When the exact marker is present, this is already a transactional child attempt; continue with the command contract below.
"@
        $FrontMatter = [regex]::Match($Text, '(?s)\A---\r?\n.*?\r?\n---\r?\n')
        if (-not $FrontMatter.Success) { throw "Command front matter not found: $Path" }
        $Text = $Text.Insert($FrontMatter.Length, $Gate)
        [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
    }

    $ContextEntry = @"

## CONTEXT_INTELLIGENCE_ENTRY

Use ``$ContextToolPs`` through ``pwsh -NoProfile -File`` on Windows or ``$ContextToolSh`` on Unix. Initialize the task budget from ``WORK_CLASS`` before context routing; record each retrieval cycle, skill selection and optional metrics. Maximum retrieval cycles: 3. Budget exhaustion with unresolved material context is ``BLOCKED_CONTEXT_GAP``.
"@
    foreach ($Command in @('ai-workflow','ai-resume','ai-metrics')) {
        $Path = Join-Path $ConfigDir "commands\$Command.md"
        $Text = Get-Content -LiteralPath $Path -Raw
        $Text = [regex]::Replace($Text, '(?s)\r?\n## CONTEXT_INTELLIGENCE_ENTRY\r?\n.*?(?=\r?\n## |\z)', '')
        $FrontMatter = [regex]::Match($Text, '(?s)\A---\r?\n.*?\r?\n---\r?\n')
        if (-not $FrontMatter.Success) { throw "Command front matter not found: $Path" }
        $Text = $Text.Insert($FrontMatter.Length, $ContextEntry)
        [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
    }

    & (Join-Path $PSScriptRoot 'verify-routing.ps1') -ConfigDir $ConfigDir
}

Write-Host 'Installed OpenCode Governance v3.4.0 — Context Intelligence & Skill Routing.'
Write-Host 'Bounded retrieval, skill manifests, external summary caching and context metrics are enabled without changing model routing.'
