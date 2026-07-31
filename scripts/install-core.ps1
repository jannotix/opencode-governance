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
if (-not $ConfigDir) {
    $ConfigDir = if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $HOME '.config\opencode' }
}

$RootDir = Split-Path -Parent $PSScriptRoot
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir = Join-Path $ConfigDir "backups\opencode-governance-$Stamp"
$RoutingManifestPath = Join-Path $ConfigDir 'opencode-governance-routing.json'
$ToolsDir = Join-Path $ConfigDir 'opencode-governance-tools'
$PublicAgents = @('architect','build','plan','executor','reviewer','reviewer-architecture','final-reviewer')
$Commands = @('ai-init','ai-audit','ai-docs','ai-discover','ai-plan','ai-execute','ai-review','ai-workflow','ai-status','ai-resume','ai-metrics','ai-release')
$SupportedFailoverRoles = @('architect','executor','reviewer','reviewer-architecture','final-reviewer')
$AliasRoles = @('executor','reviewer','reviewer-architecture','final-reviewer')
$EligibleFailures = @('PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT')
$OnlyOnFailures = $EligibleFailures + @('MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS')
$WorkClasses = @('PATCH','BOUNDED_FEATURE','MAJOR_FEATURE','EXISTING_PRODUCT_EVOLUTION','NEW_PRODUCT','HIGH_RISK_CHANGE')

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

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

function Get-Role([object]$Routing, [string]$Role) {
    $Property = $Routing.roles.PSObject.Properties[$Role]
    if (-not $Property) { throw "Routing profile missing role: $Role" }
    return $Property.Value
}

function Test-ModelId([string]$Model, [string]$Context) {
    if ([string]::IsNullOrWhiteSpace($Model) -or $Model -notmatch '^[^/\s]+/\S+$') {
        throw "$Context model must use concrete provider/model format."
    }
}

function Get-OnlyOn([object]$Candidate, [string]$Context) {
    if (-not $Candidate.PSObject.Properties['only_on']) {
        throw "$Context only_on must be present; use an empty array for any eligible failure."
    }
    return @($Candidate.only_on | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Get-WorkClasses([object]$Candidate, [string]$Role, [string]$Context) {
    $Values = @()
    if ($Candidate.PSObject.Properties['work_classes']) {
        $Values = @($Candidate.work_classes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
    if ($Role -ne 'executor' -and $Values.Count -gt 0) {
        throw "$Context work_classes is valid only for Executor routes."
    }
    foreach ($Value in $Values) {
        if ([string]$Value -notin $WorkClasses) {
            throw "$Context contains invalid work class: $Value"
        }
    }
    return $Values
}

function Validate-Candidate([object]$Candidate, [string]$Role, [string]$Context, [bool]$NeedsPriority) {
    if (-not $Candidate) { throw "$Context candidate is required." }
    Test-ModelId ([string]$Candidate.model) $Context
    if ([string]::IsNullOrWhiteSpace([string]$Candidate.model_family)) {
        throw "$Context model_family is required."
    }
    $Policy = [string]$Candidate.variant_policy
    $Variant = [string]$Candidate.variant
    if ($Policy -notin @('explicit','provider_default','highest_supported')) {
        throw "$Context variant_policy is invalid."
    }
    if ($Policy -eq 'explicit' -and [string]::IsNullOrWhiteSpace($Variant)) {
        throw "$Context explicit variant is required."
    }
    if ($Policy -eq 'provider_default' -and -not [string]::IsNullOrWhiteSpace($Variant)) {
        throw "$Context provider_default must use a null/blank variant."
    }
    if ($Policy -eq 'highest_supported' -and [string]::IsNullOrWhiteSpace($Variant)) {
        throw "$Context highest_supported must be resolved locally to a concrete variant before installation."
    }
    if ($Variant -eq 'highest_supported') {
        throw "$Context cannot use highest_supported as a literal variant."
    }
    if ($NeedsPriority) {
        $Priority = 0
        if (-not [int]::TryParse([string]$Candidate.priority, [ref]$Priority) -or $Priority -lt 1) {
            throw "$Context priority must be a positive integer."
        }
    }
    foreach ($Failure in (Get-OnlyOn $Candidate $Context)) {
        if ([string]$Failure -notin $OnlyOnFailures) {
            throw "$Context contains unsupported only_on value: $Failure"
        }
    }
    Get-WorkClasses $Candidate $Role $Context | Out-Null
}

$Routing = $null
$ManagedAliases = @()
$ManagedTools = @()
$RouteMetadata = @{}

if ($RoutingConfigPath) {
    if (-not (Test-Path $RoutingConfigPath -PathType Leaf)) {
        throw "Routing profile not found: $RoutingConfigPath"
    }
    try {
        $Routing = Get-Content $RoutingConfigPath -Raw | ConvertFrom-Json
    } catch {
        throw "Invalid routing profile JSON: $RoutingConfigPath"
    }
    if ([string]$Routing.schema_version -ne '1.0') { throw 'Routing schema_version must be 1.0.' }
    if (-not $Routing.settings -or -not $Routing.roles) { throw 'Routing profile requires settings and roles.' }

    $Cooldown = 0
    if (-not [int]::TryParse([string]$Routing.settings.default_cooldown_seconds, [ref]$Cooldown) -or $Cooldown -lt 60 -or $Cooldown -gt 86400) {
        throw 'default_cooldown_seconds must be between 60 and 86400.'
    }
    foreach ($Failure in @($Routing.settings.eligible_failures)) {
        if ([string]$Failure -notin $EligibleFailures) { throw "Unsupported eligible failure: $Failure" }
    }
    foreach ($Role in @($Routing.settings.enabled_roles)) {
        if ([string]$Role -notin $SupportedFailoverRoles) { throw "Unsupported v3.3 failover role: $Role" }
    }

    foreach ($Role in $SupportedFailoverRoles) {
        $RoleConfig = Get-Role $Routing $Role
        Validate-Candidate $RoleConfig.primary $Role "$Role primary" $false
        $Priorities = @()
        foreach ($Candidate in @($RoleConfig.fallbacks)) {
            Validate-Candidate $Candidate $Role "$Role fallback" $true
            $Priority = [int]$Candidate.priority
            if ($Priorities -contains $Priority) { throw "$Role fallback priorities must be unique." }
            $Priorities += $Priority
        }
        if ($Role -in @($Routing.settings.enabled_roles) -and @($RoleConfig.fallbacks).Count -eq 0) {
            throw "$Role failover is enabled but no fallback is configured."
        }
    }

    $ArchitectRoute = (Get-Role $Routing 'architect').primary
    $ExecutorRoute = (Get-Role $Routing 'executor').primary
    $ReviewerRoute = (Get-Role $Routing 'reviewer').primary
    $ArchitectureRoute = (Get-Role $Routing 'reviewer-architecture').primary
    $FinalRoute = (Get-Role $Routing 'final-reviewer').primary

    $ArchitectModel = [string]$ArchitectRoute.model
    $ArchitectVariant = [string]$ArchitectRoute.variant
    $ExecutorModel = [string]$ExecutorRoute.model
    $ExecutorVariant = [string]$ExecutorRoute.variant
    $ReviewerImplementationModel = [string]$ReviewerRoute.model
    $ReviewerImplementationVariant = [string]$ReviewerRoute.variant
    $ReviewerArchitectureModel = [string]$ArchitectureRoute.model
    $ReviewerArchitectureVariant = [string]$ArchitectureRoute.variant
    $FinalReviewerModel = [string]$FinalRoute.model
    $FinalReviewerVariant = [string]$FinalRoute.variant

    $RouteMetadata['architect'] = $ArchitectRoute
    $RouteMetadata['build'] = $ArchitectRoute
    $RouteMetadata['plan'] = $ArchitectRoute
    $RouteMetadata['executor'] = $ExecutorRoute
    $RouteMetadata['reviewer'] = $ReviewerRoute
    $RouteMetadata['reviewer-architecture'] = $ArchitectureRoute
    $RouteMetadata['final-reviewer'] = $FinalRoute
} else {
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
}

foreach ($Model in @($ArchitectModel, $ExecutorModel, $ReviewerImplementationModel, $ReviewerArchitectureModel, $FinalReviewerModel)) {
    Test-ModelId $Model 'Configured role'
}

New-Item -ItemType Directory -Force -Path @(
    (Join-Path $ConfigDir 'agents'),
    (Join-Path $ConfigDir 'commands'),
    $ToolsDir,
    $BackupDir
) | Out-Null

function Backup-IfExists([string]$Path) {
    if (Test-Path $Path -PathType Leaf) {
        Copy-Item $Path (Join-Path $BackupDir (Split-Path $Path -Leaf)) -Force
    }
}

foreach ($Name in $PublicAgents) { Backup-IfExists (Join-Path $ConfigDir "agents\$Name.md") }
foreach ($Name in $Commands) { Backup-IfExists (Join-Path $ConfigDir "commands\$Name.md") }
Backup-IfExists (Join-Path $ConfigDir 'opencode.jsonc')
Backup-IfExists (Join-Path $ConfigDir 'opencode.json')
Backup-IfExists $RoutingManifestPath
Backup-IfExists (Join-Path $ToolsDir 'executor-attempt.ps1')
Backup-IfExists (Join-Path $ToolsDir 'executor-attempt.sh')

if (Test-Path $RoutingManifestPath -PathType Leaf) {
    try {
        $PreviousManifest = Get-Content $RoutingManifestPath -Raw | ConvertFrom-Json
    } catch {
        throw 'Existing routing manifest is invalid; refusing to remove managed aliases.'
    }
    foreach ($Alias in @($PreviousManifest.managed_aliases)) {
        $AliasName = [string]$Alias
        if ($AliasName -notmatch '^(executor|reviewer|reviewer-architecture|final-reviewer)-fallback-[0-9]+$') {
            throw "Unsafe managed alias in previous manifest: $AliasName"
        }
        $AliasPath = Join-Path $ConfigDir "agents\$AliasName.md"
        Backup-IfExists $AliasPath
        Remove-Item $AliasPath -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $RoutingManifestPath -Force
}

$LegacyAiEditPattern = '(?m)^  edit:\r?\n    "\*": deny\r?\n    "\.ai/\*\*": allow\r?\n'
$PortableAiEditBlock = @'
  edit:
    "*": deny
    ".ai": allow
    ".ai/*": allow
    "*/.ai": allow
    "*/.ai/*": allow
    '.ai\*': allow
    '*\.ai': allow
    '*\.ai\*': allow
'@
$LegacyExecutorEditPattern = '(?m)^  edit:\r?\n    "\*": allow\r?\n    "\.ai/\*\*": deny\r?\n    "\.git/\*\*": deny\r?\n'
$PortableExecutorEditBlock = @'
  edit:
    "*": allow
    ".ai": deny
    ".ai/*": deny
    "*/.ai": deny
    "*/.ai/*": deny
    '.ai\*': deny
    '*\.ai': deny
    '*\.ai\*': deny
    ".git": deny
    ".git/*": deny
    "*/.git": deny
    "*/.git/*": deny
    '.git\*': deny
    '*\.git': deny
    '*\.git\*': deny
'@

function Add-RouteMetadata(
    [string]$Text,
    [string]$Role,
    [string]$RouteAgent,
    [object]$Candidate,
    [int]$Priority,
    [bool]$HiddenAlias
) {
    if ($HiddenAlias) {
        $Text = [regex]::Replace($Text, '(?m)^mode: subagent\r?$', "mode: subagent`nhidden: true", 1)
    }
    $Variant = if ([string]::IsNullOrWhiteSpace([string]$Candidate.variant)) { 'PROVIDER_DEFAULT' } else { [string]$Candidate.variant }
    $OnlyValues = Get-OnlyOn $Candidate "$RouteAgent route"
    $OnlyText = if ($OnlyValues.Count -eq 0) { 'ANY_ELIGIBLE_FAILURE' } else { $OnlyValues -join '|' }
    $ClassValues = Get-WorkClasses $Candidate $Role "$RouteAgent route"
    $ClassText = if ($ClassValues.Count -eq 0) { 'ALL' } else { $ClassValues -join '|' }
    $Rebalance = if ($Candidate.requires_role_rebalance -eq $true) { 'YES' } else { 'NO' }
    $Block = @"

## MODEL_ROUTE_METADATA

AUTHORITATIVE_ROLE: $Role
ROUTE_AGENT: $RouteAgent
SELECTED_MODEL: $($Candidate.model)
SELECTED_VARIANT: $Variant
MODEL_FAMILY: $($Candidate.model_family)
ROUTE_PRIORITY: $Priority
ROUTE_ONLY_ON: $OnlyText
ROUTE_WORK_CLASSES: $ClassText
REQUIRES_ROLE_REBALANCE: $Rebalance

Require matching attempt, packet and frozen-target identifiers plus a complete report. Never read or continue partial output.
"@
    return [regex]::Replace($Text, '(?s)\A(---\r?\n.*?\r?\n---\r?\n)', ('$1' + $Block), 1)
}

function Render-Agent(
    [string]$Template,
    [string]$Name,
    [string]$ModelToken,
    [string]$Model,
    [string]$VariantToken,
    [string]$Variant,
    [string]$Role,
    [object]$Candidate,
    [int]$Priority,
    [bool]$HiddenAlias
) {
    $Source = Join-Path $RootDir "templates\agents\$Template.md"
    $Destination = Join-Path $ConfigDir "agents\$Name.md"
    $Text = Get-Content $Source -Raw
    $Text = $Text.Replace($ModelToken, $Model)
    $VariantLine = if ([string]::IsNullOrWhiteSpace($Variant)) { '' } else { "variant: $Variant" }
    $Text = $Text.Replace($VariantToken, $VariantLine)
    if ($Template -eq 'executor') {
        if ($Text -notmatch $LegacyExecutorEditPattern) { throw "Cannot render portable Executor edit denies for $Source." }
        $Text = [regex]::Replace($Text, $LegacyExecutorEditPattern, ($PortableExecutorEditBlock.TrimEnd() + "`n"))
    } else {
        if ($Text -notmatch $LegacyAiEditPattern) { throw "Cannot render portable .ai permissions for $Source." }
        $Text = [regex]::Replace($Text, $LegacyAiEditPattern, ($PortableAiEditBlock.TrimEnd() + "`n"))
    }
    if ($Candidate) {
        $Text = Add-RouteMetadata $Text $Role $Name $Candidate $Priority $HiddenAlias
    }
    Write-Utf8NoBom $Destination $Text
}

function Render-Public(
    [string]$Name,
    [string]$Template,
    [string]$ModelToken,
    [string]$Model,
    [string]$VariantToken,
    [string]$Variant,
    [string]$Role
) {
    $Candidate = if ($Routing) { $RouteMetadata[$Name] } else { $null }
    Render-Agent $Template $Name $ModelToken $Model $VariantToken $Variant $Role $Candidate 0 $false
}

Render-Public 'architect' 'architect' '__ARCHITECT_MODEL__' $ArchitectModel '__ARCHITECT_VARIANT_LINE__' $ArchitectVariant 'architect'
Render-Public 'build' 'build' '__ARCHITECT_MODEL__' $ArchitectModel '__ARCHITECT_VARIANT_LINE__' $ArchitectVariant 'architect'
Render-Public 'plan' 'plan' '__ARCHITECT_MODEL__' $ArchitectModel '__ARCHITECT_VARIANT_LINE__' $ArchitectVariant 'architect'
Render-Public 'executor' 'executor' '__EXECUTOR_MODEL__' $ExecutorModel '__EXECUTOR_VARIANT_LINE__' $ExecutorVariant 'executor'
Render-Public 'reviewer' 'reviewer' '__REVIEWER_IMPLEMENTATION_MODEL__' $ReviewerImplementationModel '__REVIEWER_IMPLEMENTATION_VARIANT_LINE__' $ReviewerImplementationVariant 'reviewer'
Render-Public 'reviewer-architecture' 'reviewer-architecture' '__REVIEWER_ARCHITECTURE_MODEL__' $ReviewerArchitectureModel '__REVIEWER_ARCHITECTURE_VARIANT_LINE__' $ReviewerArchitectureVariant 'reviewer-architecture'
Render-Public 'final-reviewer' 'final-reviewer' '__FINAL_REVIEWER_MODEL__' $FinalReviewerModel '__FINAL_REVIEWER_VARIANT_LINE__' $FinalReviewerVariant 'final-reviewer'

if ($Routing) {
    foreach ($ToolName in @('executor-attempt.ps1','executor-attempt.sh')) {
        $SourceTool = Join-Path $PSScriptRoot $ToolName
        $DestinationTool = Join-Path $ToolsDir $ToolName
        Copy-Item $SourceTool $DestinationTool -Force
        $ManagedTools += $DestinationTool
    }

    $TemplateMap = @{
        'executor' = @('executor','__EXECUTOR_MODEL__','__EXECUTOR_VARIANT_LINE__')
        'reviewer' = @('reviewer','__REVIEWER_IMPLEMENTATION_MODEL__','__REVIEWER_IMPLEMENTATION_VARIANT_LINE__')
        'reviewer-architecture' = @('reviewer-architecture','__REVIEWER_ARCHITECTURE_MODEL__','__REVIEWER_ARCHITECTURE_VARIANT_LINE__')
        'final-reviewer' = @('final-reviewer','__FINAL_REVIEWER_MODEL__','__FINAL_REVIEWER_VARIANT_LINE__')
    }
    $PolicyLines = @()
    foreach ($Role in $AliasRoles) {
        if ($Role -notin @($Routing.settings.enabled_roles)) { continue }
        $RoleConfig = Get-Role $Routing $Role
        foreach ($Candidate in @($RoleConfig.fallbacks | Sort-Object { [int]$_.priority })) {
            $Alias = "$Role-fallback-$([int]$Candidate.priority)"
            $ManagedAliases += $Alias
            $Map = $TemplateMap[$Role]
            Render-Agent $Map[0] $Alias $Map[1] ([string]$Candidate.model) $Map[2] ([string]$Candidate.variant) $Role $Candidate ([int]$Candidate.priority) $true
            $OnlyValues = Get-OnlyOn $Candidate "$Alias route"
            $OnlyText = if ($OnlyValues.Count -eq 0) { 'ANY_ELIGIBLE_FAILURE' } else { $OnlyValues -join '|' }
            $ClassValues = Get-WorkClasses $Candidate $Role "$Alias route"
            $ClassText = if ($ClassValues.Count -eq 0) { 'ALL' } else { $ClassValues -join '|' }
            $PolicyLines += "- $Role -> $Alias; priority=$($Candidate.priority); family=$($Candidate.model_family); only_on=$OnlyText; work_classes=$ClassText; rebalance=$($Candidate.requires_role_rebalance -eq $true)"
        }
    }

    $ArchitectEnabled = 'architect' -in @($Routing.settings.enabled_roles)
    $ExecutorEnabled = 'executor' -in @($Routing.settings.enabled_roles)
    $ArchitectPolicy = if ($ArchitectEnabled) {
        'Architect top-level failover uses the external transactional runner only for ai-init|ai-audit|ai-discover|ai-plan.'
    } else {
        'Architect top-level failover is disabled.'
    }
    $ExecutorPolicy = if ($ExecutorEnabled) {
        "Executor failover is enabled. Use ``$(Join-Path $ToolsDir 'executor-attempt.ps1')`` on Windows or ``$(Join-Path $ToolsDir 'executor-attempt.sh')`` on macOS/Linux. Execute ``select -> prepare -> delegate selected route -> finalize -> promote``. On an eligible route failure execute ``discard``, then restart the complete Executor from the same canonical packet and frozen target. Never delegate a routed Executor against the real project root. Promotion failure, packet/report mismatch, changed real state, overlap, or an ineligible error stops with human recovery; it never selects another model."
    } else {
        'Executor failover is disabled.'
    }
    $PolicyBlock = @"

## ROLE_FAILOVER_POLICY

Eligible failures: $(@($Routing.settings.eligible_failures) -join '|'). Ineligible or unclassified failures stop. Every fallback restarts the complete role or command; active fallback attempts are sticky; primary returns only on a later invocation after cooldown. Provider, rate-limit, and quota failures prefer the same model family. Retired or globally unavailable families are skipped. Never retry the same route.

$ArchitectPolicy

$ExecutorPolicy

Reviewer and Final Reviewer routes retain frozen packet and target evidence and actual-family independence. Executor promotion is not validation; normal evidence, review, commit, and external-action gates remain mandatory.

Configured hidden routes:
$($PolicyLines -join "`n")
"@

    $TaskRules = "    `"executor-fallback-*`": allow`n    `"reviewer-fallback-*`": allow`n    `"reviewer-architecture-fallback-*`": allow`n    `"final-reviewer-fallback-*`": allow"
    $BashRules = "    `"*opencode-governance-tools/executor-attempt.sh*`": allow`n    `"*opencode-governance-tools\\executor-attempt.ps1*`": allow"
    foreach ($Name in @('architect','build')) {
        $Path = Join-Path $ConfigDir "agents\$Name.md"
        $Text = Get-Content $Path -Raw
        $Text = [regex]::Replace($Text, '(?m)^(    final-reviewer: allow\r?$)', ("`$1`n" + $TaskRules), 1)
        $Text = [regex]::Replace($Text, '(?m)^(    "rg \*": allow\r?$)', ("`$1`n" + $BashRules), 1)
        if ($Text -match '(?m)^## Core invariants\r?$') {
            $Text = [regex]::Replace($Text, '(?m)^## Core invariants\r?$', ($PolicyBlock + "`n## Core invariants"), 1)
        } else {
            $Text += $PolicyBlock
        }
        Write-Utf8NoBom $Path $Text
    }

    $Manifest = [ordered]@{
        schema_version = '1.0'
        governance_version = '3.4.4'
        architect_runner_version = '3.4.4'
        context_intelligence_version = '3.4.4'
        workflow_continuation_version = '3.4.4'
        settings = $Routing.settings
        roles = $Routing.roles
        managed_aliases = $ManagedAliases
        managed_tools = $ManagedTools
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-Utf8NoBom $RoutingManifestPath (($Manifest | ConvertTo-Json -Depth 30) + [Environment]::NewLine)
}

foreach ($Name in $Commands) {
    Copy-Item (Join-Path $RootDir "templates\commands\$Name.md") (Join-Path $ConfigDir "commands\$Name.md") -Force
}

$JsoncPath = Join-Path $ConfigDir 'opencode.jsonc'
$JsonPath = Join-Path $ConfigDir 'opencode.json'
$Target = if ((Test-Path $JsoncPath) -or -not (Test-Path $JsonPath)) { $JsoncPath } else { $JsonPath }
if (Test-Path $Target) {
    $Raw = Get-Content $Target -Raw
    $Stripped = [regex]::Replace($Raw, '/\*.*?\*/', '', 'Singleline')
    $Stripped = [regex]::Replace($Stripped, '(?m)^\s*//.*$', '')
    $Stripped = [regex]::Replace($Stripped, ',\s*([}\]])', '$1')
    if ([string]::IsNullOrWhiteSpace($Stripped)) {
        $Object = [pscustomobject][ordered]@{'$schema'='https://opencode.ai/config.json'}
    } else {
        try { $Object = $Stripped | ConvertFrom-Json } catch { throw "Cannot safely merge $Target. Restore the backup and set default_agent manually." }
    }
} else {
    $Object = [pscustomobject][ordered]@{'$schema'='https://opencode.ai/config.json'}
}
$Object | Add-Member -MemberType NoteProperty -Name 'default_agent' -Value 'architect' -Force
Write-Utf8NoBom $Target (($Object | ConvertTo-Json -Depth 20) + [Environment]::NewLine)

& (Join-Path $PSScriptRoot 'verify.ps1') -ConfigDir $ConfigDir
& (Join-Path $PSScriptRoot 'verify-routing.ps1') -ConfigDir $ConfigDir

$Mode = if ($Routing) { "routing manifest with $($ManagedAliases.Count) hidden routes" } else { 'legacy single-model routing' }
Write-Host "Installed OpenCode Governance routing base: 7 public agents, 12 commands, $Mode. Capability tools require the unified install with a routing profile."
Write-Host 'Executor fallback uses isolated worktrees and never bypasses normal review or commit gates.'
Write-Host 'No push, merge, deployment or production rollback is automatic. Restart OpenCode before use.'
Write-Host "Backup: $BackupDir"
