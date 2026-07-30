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
    $QualityToolPs = Join-Path $ToolsDir 'quality-gates.ps1'
    $QualityToolSh = Join-Path $ToolsDir 'quality-gates.sh'
    $QualityToolPy = Join-Path $ToolsDir 'quality-gates.py'

    Copy-Item (Join-Path $PSScriptRoot 'run-governed.ps1') $ArchitectRunnerPs -Force
    Copy-Item (Join-Path $PSScriptRoot 'run-governed.sh') $ArchitectRunnerSh -Force
    Copy-Item (Join-Path $PSScriptRoot 'context-intelligence.ps1') $ContextToolPs -Force
    Copy-Item (Join-Path $PSScriptRoot 'context-intelligence.sh') $ContextToolSh -Force
    Copy-Item (Join-Path $PSScriptRoot 'context-intelligence.py') $ContextToolPy -Force
    Copy-Item (Join-Path $PSScriptRoot 'quality-gates.ps1') $QualityToolPs -Force
    Copy-Item (Join-Path $PSScriptRoot 'quality-gates.sh') $QualityToolSh -Force
    Copy-Item (Join-Path $PSScriptRoot 'quality-gates.py') $QualityToolPy -Force

    try { $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json } catch { throw 'Routing manifest is invalid after core installation.' }
    if ([string]$Manifest.schema_version -ne '1.0') { throw 'Routing manifest schema_version must be 1.0.' }
    $Manifest | Add-Member -MemberType NoteProperty -Name governance_version -Value '3.5.0' -Force
    $Manifest | Add-Member -MemberType NoteProperty -Name architect_runner_version -Value '3.3.4' -Force
    $Manifest | Add-Member -MemberType NoteProperty -Name context_intelligence_version -Value '3.4.0' -Force
    $Manifest | Add-Member -MemberType NoteProperty -Name quality_gates_version -Value '3.5.0' -Force
    $Manifest | Add-Member -MemberType NoteProperty -Name managed_tools -Value @(
        $ArchitectRunnerPs,$ArchitectRunnerSh,
        (Join-Path $ToolsDir 'executor-attempt.ps1'),(Join-Path $ToolsDir 'executor-attempt.sh'),
        $ContextToolPs,$ContextToolSh,$ContextToolPy,
        $QualityToolPs,$QualityToolSh,$QualityToolPy
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

The PowerShell runner requires PowerShell 7 or newer and fails before any project-state mutation with ``POWERSHELL_7_REQUIRED`` under Windows PowerShell 5.1. Before and after every routed attempt, both runners fingerprint all project entries outside root ``.ai/**`` and Git metadata. Non-Git directories use the same integrity contract. Any source or project-documentation change returns ``PROJECT_STATE_CHANGED`` and blocks fallback.

When the marker is absent, do not write ``.ai/**``; return ``ARCHITECT_RUNNER_REQUIRED`` with the exact installed runner path. Never invoke the Architect runner from inside the active OpenCode process.
"@
    $ContextPolicy = @"

## CONTEXT_INTELLIGENCE_V1

WINDOWS_CONTEXT_TOOL: $ContextToolPs
WINDOWS_CONTEXT_HOST: pwsh -NoProfile -File
UNIX_CONTEXT_TOOL: $ContextToolSh
CONTEXT_CORE: $ContextToolPy

Initialize ``CONTEXT_BUDGET.json`` from exact ``WORK_CLASS`` and use at most three ``DISPATCH -> EVALUATE -> REFINE`` cycles. End with ``CONTEXT_SUFFICIENT`` or ``BLOCKED_CONTEXT_GAP``. Use ``SKILL_CAPABILITY_MANIFEST_V1`` for trust-aware deduplication and section-level loading. External summaries are advisory and never replace current primary evidence.
"@
    $QualityPolicy = @"

## QUALITY_GATES_V1

WINDOWS_QUALITY_TOOL: $QualityToolPs
WINDOWS_QUALITY_HOST: pwsh -NoProfile -File
UNIX_QUALITY_TOOL: $QualityToolSh
QUALITY_CORE: $QualityToolPy

Initialize ``QUALITY_PROFILE.json`` from exact ``WORK_CLASS``, task kind and risks before an implementation-ready plan. Required bug fixes must pass ``DEBUG_PROOF_V1`` and ``TDD_PROOF_V1``. Security, authorization, routing, parser, migration, public-contract and high-risk changes require TDD. AI-system behavior requires ``EVAL_PLAN_V1`` and high-risk work requires ``PASS_K`` reliability.

Executor must produce ``IMPLEMENTATION_SELF_CHECK_V1`` before review. It has ``approval_authority: false`` and never replaces independent review. Failed self-check is ``NOT_READY_FOR_REVIEW``.

Learning is candidate-first and append-only under ``.ai/learning/**``. ``LEARNING_CANDIDATE_V1`` never edits ``GOVERNANCE_MEMORY.md``. Promotion requires ``approved_by: FINAL_REVIEWER`` and records ``LEARNING_PROMOTION_V1`` with ``memory_updated: false``. Memory update remains a separate Final Reviewer-controlled action.
"@
    foreach ($Name in @('architect','build','plan','executor')) {
        $Path = Join-Path $ConfigDir "agents\$Name.md"
        $Text = Get-Content -LiteralPath $Path -Raw
        foreach($Header in @('ARCHITECT_RUNNER_INTEGRATION','CONTEXT_INTELLIGENCE_V1','QUALITY_GATES_V1')){$Text=[regex]::Replace($Text,"(?s)\r?\n## $Header\r?\n.*?(?=\r?\n## Core invariants|\z)",'')}
        $Insertion = if($Name-eq'executor'){$ContextPolicy.TrimEnd()+"`n"+$QualityPolicy.TrimEnd()}else{$ArchitectPolicy.TrimEnd()+"`n"+$ContextPolicy.TrimEnd()+"`n"+$QualityPolicy.TrimEnd()}
        if ($Text -match '(?m)^## Core invariants\r?$') { $Text = [regex]::Replace($Text, '(?m)^## Core invariants\r?$', ($Insertion + "`n`n## Core invariants"), 1) } else { $Text += "`n" + $Insertion }
        [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
    }

    foreach ($Command in @('ai-init','ai-audit','ai-discover','ai-plan')) {
        $Path = Join-Path $ConfigDir "commands\$Command.md";$Text = Get-Content -LiteralPath $Path -Raw
        $Text = [regex]::Replace($Text, '(?s)\r?\n## ARCHITECT_RUNNER_ENTRY_GATE\r?\n.*?(?=\r?\n## |\z)', '')
        $Gate = @"

## ARCHITECT_RUNNER_ENTRY_GATE

Before any ``.ai/**`` write, require the exact invocation marker ``$Marker``. When absent, stop with ``ARCHITECT_RUNNER_REQUIRED`` and the exact Windows/Unix runner paths. The external runner supports Git and non-Git directories and returns ``PROJECT_STATE_CHANGED`` on any protected content delta. Do not invoke the runner recursively.

WINDOWS_HOST: pwsh -NoProfile -File
WINDOWS_RUNNER: $ArchitectRunnerPs
UNIX_RUNNER: $ArchitectRunnerSh
"@
        $FrontMatter=[regex]::Match($Text,'(?s)\A---\r?\n.*?\r?\n---\r?\n');if(-not$FrontMatter.Success){throw "Command front matter not found: $Path"}
        $Text=$Text.Insert($FrontMatter.Length,$Gate);[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
    }

    $ContextEntry=@"

## CONTEXT_INTELLIGENCE_ENTRY

Use ``$ContextToolPs`` through ``pwsh -NoProfile -File`` on Windows or ``$ContextToolSh`` on Unix. Initialize the task context budget, record retrieval cycles and skill selection, and stop with ``BLOCKED_CONTEXT_GAP`` when material context remains unresolved after the allowed cycles.
"@
    $QualityEntry=@"

## QUALITY_GATES_ENTRY

Use ``$QualityToolPs`` through ``pwsh -NoProfile -File`` on Windows or ``$QualityToolSh`` on Unix. Require the task ``QUALITY_PROFILE.json`` and every applicable Debug, TDD, Eval and self-check artifact. Missing required proof is ``BLOCKED``. Learning promotion requires Final Reviewer approval and never updates Governance Memory automatically.
"@
    foreach ($Command in @('ai-plan','ai-execute','ai-workflow','ai-review','ai-resume','ai-audit','ai-metrics')) {
        $Path=Join-Path $ConfigDir "commands\$Command.md";$Text=Get-Content -LiteralPath $Path -Raw
        foreach($Header in @('CONTEXT_INTELLIGENCE_ENTRY','QUALITY_GATES_ENTRY')){$Text=[regex]::Replace($Text,"(?s)\r?\n## $Header\r?\n.*?(?=\r?\n## |\z)",'')}
        $FrontMatter=[regex]::Match($Text,'(?s)\A---\r?\n.*?\r?\n---\r?\n');if(-not$FrontMatter.Success){throw "Command front matter not found: $Path"}
        $Insertion=$QualityEntry;if($Command-in@('ai-workflow','ai-resume','ai-metrics')){$Insertion=$ContextEntry+$QualityEntry}
        $Text=$Text.Insert($FrontMatter.Length,$Insertion);[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
    }

    & (Join-Path $PSScriptRoot 'verify-routing.ps1') -ConfigDir $ConfigDir
}

Write-Host 'Installed OpenCode Governance v3.5.0 — Quality Gates & Governed Learning.'
Write-Host 'Debug-First, adaptive TDD, eval, pre-review self-check and candidate-first learning are enabled without changing model routing.'
