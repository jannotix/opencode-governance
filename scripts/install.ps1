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
$PublicAgents = @('architect','build','plan','executor','reviewer','reviewer-architecture','final-reviewer')
$Commands = @('ai-init','ai-audit','ai-docs','ai-discover','ai-plan','ai-execute','ai-review','ai-workflow','ai-status','ai-resume','ai-metrics','ai-release')
$FailoverRoles = @('reviewer','reviewer-architecture','final-reviewer')
$EligibleFailures = @('PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT')
$OnlyOnFailures = $EligibleFailures + @('MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS')

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

function Validate-Candidate([object]$Candidate, [string]$Context, [bool]$NeedsPriority) {
    Test-ModelId ([string]$Candidate.model) $Context
    if ([string]::IsNullOrWhiteSpace([string]$Candidate.model_family)) { throw "$Context model_family is required." }
    $Policy = [string]$Candidate.variant_policy
    if ($Policy -notin @('explicit','provider_default','highest_supported')) { throw "$Context variant_policy is invalid." }
    $Variant = [string]$Candidate.variant
    if ($Policy -eq 'explicit' -and [string]::IsNullOrWhiteSpace($Variant)) { throw "$Context explicit variant is required." }
    if ($Policy -eq 'provider_default' -and -not [string]::IsNullOrWhiteSpace($Variant)) { throw "$Context provider_default must use a null/blank variant." }
    if ($Policy -eq 'highest_supported' -and [string]::IsNullOrWhiteSpace($Variant)) {
        throw "$Context highest_supported must be resolved locally to a concrete variant before installation."
    }
    if ($Variant -eq 'highest_supported') { throw "$Context cannot use highest_supported as a literal variant." }
    if ($NeedsPriority) {
        $Priority = 0
        if (-not [int]::TryParse([string]$Candidate.priority, [ref]$Priority) -or $Priority -lt 1) { throw "$Context priority must be a positive integer." }
    }
    foreach ($Failure in @($Candidate.only_on)) {
        if ([string]$Failure -notin $OnlyOnFailures) { throw "$Context contains unsupported only_on value: $Failure" }
    }
}

$Routing = $null
$ManagedAliases = @()
$RouteMetadata = @{}
$FailoverPolicyBlock = ''

if ($RoutingConfigPath) {
    if (-not (Test-Path $RoutingConfigPath -PathType Leaf)) { throw "Routing profile not found: $RoutingConfigPath" }
    try { $Routing = Get-Content $RoutingConfigPath -Raw | ConvertFrom-Json } catch { throw "Invalid routing profile JSON: $RoutingConfigPath" }
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
        if ([string]$Role -notin $FailoverRoles) { throw "v3.1 supports failover only for reviewer, reviewer-architecture and final-reviewer: $Role" }
    }
    foreach ($Role in $PublicAgents | Where-Object { $_ -notin @('build','plan') }) {
        $RoleConfig = Get-Role $Routing $Role
        Validate-Candidate $RoleConfig.primary "$Role primary" $false
        if ($Role -notin $FailoverRoles -and @($RoleConfig.fallbacks).Count -gt 0) {
            throw "Fallbacks for $Role activate in a later governance release."
        }
        $Priorities = @()
        foreach ($Candidate in @($RoleConfig.fallbacks)) {
            Validate-Candidate $Candidate "$Role fallback" $true
            $Priority = [int]$Candidate.priority
            if ($Priorities -contains $Priority) { throw "$Role fallback priorities must be unique." }
            $Priorities += $Priority
        }
    }

    $ArchitectRoute = (Get-Role $Routing 'architect').primary
    $ExecutorRoute = (Get-Role $Routing 'executor').primary
    $ReviewerRoute = (Get-Role $Routing 'reviewer').primary
    $ArchitectureRoute = (Get-Role $Routing 'reviewer-architecture').primary
    $FinalRoute = (Get-Role $Routing 'final-reviewer').primary
    $ArchitectModel = [string]$ArchitectRoute.model; $ArchitectVariant = [string]$ArchitectRoute.variant
    $ExecutorModel = [string]$ExecutorRoute.model; $ExecutorVariant = [string]$ExecutorRoute.variant
    $ReviewerImplementationModel = [string]$ReviewerRoute.model; $ReviewerImplementationVariant = [string]$ReviewerRoute.variant
    $ReviewerArchitectureModel = [string]$ArchitectureRoute.model; $ReviewerArchitectureVariant = [string]$ArchitectureRoute.variant
    $FinalReviewerModel = [string]$FinalRoute.model; $FinalReviewerVariant = [string]$FinalRoute.variant

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

$RequiredModels = @($ArchitectModel,$ExecutorModel,$ReviewerImplementationModel,$ReviewerArchitectureModel,$FinalReviewerModel)
foreach ($Model in $RequiredModels) { Test-ModelId $Model 'Configured role' }

New-Item -ItemType Directory -Force -Path @((Join-Path $ConfigDir 'agents'),(Join-Path $ConfigDir 'commands'),$BackupDir) | Out-Null

function Backup-IfExists([string]$Path) {
    if (Test-Path $Path -PathType Leaf) { Copy-Item $Path (Join-Path $BackupDir (Split-Path $Path -Leaf)) -Force }
}

foreach ($Name in $PublicAgents) { Backup-IfExists (Join-Path $ConfigDir "agents\$Name.md") }
foreach ($Name in $Commands) { Backup-IfExists (Join-Path $ConfigDir "commands\$Name.md") }
Backup-IfExists (Join-Path $ConfigDir 'opencode.jsonc'); Backup-IfExists (Join-Path $ConfigDir 'opencode.json'); Backup-IfExists $RoutingManifestPath

if (Test-Path $RoutingManifestPath -PathType Leaf) {
    try {
        $PreviousManifest = Get-Content $RoutingManifestPath -Raw | ConvertFrom-Json
        foreach ($Alias in @($PreviousManifest.managed_aliases)) {
            $AliasName = [string]$Alias
            if ($AliasName -match '^(reviewer|reviewer-architecture|final-reviewer)-fallback-[0-9]+$') {
                $AliasPath = Join-Path $ConfigDir "agents\$AliasName.md"
                Backup-IfExists $AliasPath
                Remove-Item $AliasPath -Force -ErrorAction SilentlyContinue
            }
        }
    } catch { throw 'Existing routing manifest is invalid; refusing to remove managed aliases.' }
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

function Add-RouteMetadata([string]$Text, [string]$Role, [string]$RouteAgent, [object]$Candidate, [int]$Attempt, [bool]$HiddenAlias) {
    if ($HiddenAlias) { $Text = [regex]::Replace($Text, '(?m)^mode: subagent\r?$', "mode: subagent`nhidden: true", 1) }
    $Variant = if ([string]::IsNullOrWhiteSpace([string]$Candidate.variant)) { 'PROVIDER_DEFAULT' } else { [string]$Candidate.variant }
    $Priority = if ($Attempt -eq 1) { 0 } else { [int]$Candidate.priority }
    $OnlyOn = if (@($Candidate.only_on).Count -eq 0) { 'ANY_ELIGIBLE_FAILURE' } else { (@($Candidate.only_on) -join '|') }
    $Rebalance = if ($Candidate.requires_role_rebalance -eq $true) { 'YES' } else { 'NO' }
    $Block = @"

## MODEL_ROUTE_METADATA

AUTHORITATIVE_ROLE: $Role
ROUTE_AGENT: $RouteAgent
SELECTED_MODEL: $($Candidate.model)
SELECTED_VARIANT: $Variant
MODEL_FAMILY: $($Candidate.model_family)
ROUTE_PRIORITY: $Priority
ROUTE_ONLY_ON: $OnlyOn
REQUIRES_ROLE_REBALANCE: $Rebalance

Read only the frozen role packet and primary evidence. Never read or continue a previous partial role report. Require `ROLE_ATTEMPT_ID`, `PACKET_SHA256` and `FROZEN_TARGET_SHA` from the packet. The completed report must repeat those exact values and include `REPORT_COMPLETE: YES`; otherwise it is non-authoritative and must not be consumed.
"@
    return [regex]::Replace($Text, '(?s)\A(---\r?\n.*?\r?\n---\r?\n)', ('$1' + $Block), 1)
}

function Render-Agent([string]$Source,[string]$Destination,[string]$ModelToken,[string]$Model,[string]$VariantToken,[string]$Variant,[string]$Role,[string]$RouteAgent,[object]$Candidate,[int]$Attempt,[bool]$HiddenAlias) {
    $Text = Get-Content $Source -Raw
    $Text = $Text.Replace($ModelToken,$Model)
    $VariantLine = if ([string]::IsNullOrWhiteSpace($Variant)) { '' } else { "variant: $Variant" }
    $Text = $Text.Replace($VariantToken,$VariantLine)
    if ((Split-Path $Source -LeafBase) -ne 'executor') {
        if ($Text -notmatch $LegacyAiEditPattern) { throw "Cannot render portable .ai permissions for $Source." }
        $Text = [regex]::Replace($Text,$LegacyAiEditPattern,($PortableAiEditBlock.TrimEnd()+"`n"))
    }
    if ($Candidate) { $Text = Add-RouteMetadata $Text $Role $RouteAgent $Candidate $Attempt $HiddenAlias }
    Write-Utf8NoBom $Destination $Text
}

function Render-Public([string]$Name,[string]$Template,[string]$ModelToken,[string]$Model,[string]$VariantToken,[string]$Variant,[string]$Role) {
    $Candidate = if ($Routing) { $RouteMetadata[$Name] } else { $null }
    Render-Agent (Join-Path $RootDir "templates\agents\$Template.md") (Join-Path $ConfigDir "agents\$Name.md") $ModelToken $Model $VariantToken $Variant $Role $Name $Candidate 1 $false
}

Render-Public 'architect' 'architect' '__ARCHITECT_MODEL__' $ArchitectModel '__ARCHITECT_VARIANT_LINE__' $ArchitectVariant 'architect'
Render-Public 'build' 'build' '__ARCHITECT_MODEL__' $ArchitectModel '__ARCHITECT_VARIANT_LINE__' $ArchitectVariant 'architect'
Render-Public 'plan' 'plan' '__ARCHITECT_MODEL__' $ArchitectModel '__ARCHITECT_VARIANT_LINE__' $ArchitectVariant 'architect'
Render-Public 'executor' 'executor' '__EXECUTOR_MODEL__' $ExecutorModel '__EXECUTOR_VARIANT_LINE__' $ExecutorVariant 'executor'
Render-Public 'reviewer' 'reviewer' '__REVIEWER_IMPLEMENTATION_MODEL__' $ReviewerImplementationModel '__REVIEWER_IMPLEMENTATION_VARIANT_LINE__' $ReviewerImplementationVariant 'reviewer'
Render-Public 'reviewer-architecture' 'reviewer-architecture' '__REVIEWER_ARCHITECTURE_MODEL__' $ReviewerArchitectureModel '__REVIEWER_ARCHITECTURE_VARIANT_LINE__' $ReviewerArchitectureVariant 'reviewer-architecture'
Render-Public 'final-reviewer' 'final-reviewer' '__FINAL_REVIEWER_MODEL__' $FinalReviewerModel '__FINAL_REVIEWER_VARIANT_LINE__' $FinalReviewerVariant 'final-reviewer'

if ($Routing) {
    $TemplateMap = @{
        'reviewer' = @('reviewer','__REVIEWER_IMPLEMENTATION_MODEL__','__REVIEWER_IMPLEMENTATION_VARIANT_LINE__')
        'reviewer-architecture' = @('reviewer-architecture','__REVIEWER_ARCHITECTURE_MODEL__','__REVIEWER_ARCHITECTURE_VARIANT_LINE__')
        'final-reviewer' = @('final-reviewer','__FINAL_REVIEWER_MODEL__','__FINAL_REVIEWER_VARIANT_LINE__')
    }
    $PolicyLines = @()
    foreach ($Role in $FailoverRoles) {
        if ($Role -notin @($Routing.settings.enabled_roles)) { continue }
        $RoleConfig = Get-Role $Routing $Role
        foreach ($Candidate in @($RoleConfig.fallbacks | Sort-Object { [int]$_.priority })) {
            $Alias = "$Role-fallback-$([int]$Candidate.priority)"
            $ManagedAliases += $Alias
            $Map = $TemplateMap[$Role]
            Render-Agent (Join-Path $RootDir "templates\agents\$($Map[0]).md") (Join-Path $ConfigDir "agents\$Alias.md") $Map[1] ([string]$Candidate.model) $Map[2] ([string]$Candidate.variant) $Role $Alias $Candidate ([int]$Candidate.priority + 1) $true
            $OnlyOn = if (@($Candidate.only_on).Count -eq 0) { 'ANY_ELIGIBLE_FAILURE' } else { @($Candidate.only_on) -join '|' }
            $PolicyLines += "- $Role -> $Alias; priority=$($Candidate.priority); family=$($Candidate.model_family); only_on=$OnlyOn; rebalance=$($Candidate.requires_role_rebalance -eq $true)"
        }
    }
    $PolicyBlock = @"

## ROLE_FAILOVER_POLICY

Automatic failover is enabled only for configured review roles. Eligible failures are: $(@($Routing.settings.eligible_failures) -join '|'). Ineligible, ambiguous or unclassified failures stop the workflow.

For every attempt persist `ROLE_ATTEMPT_ID`, `AUTHORITATIVE_ROLE`, `ROUTE_AGENT`, `SELECTED_MODEL`, `SELECTED_VARIANT`, `MODEL_FAMILY`, `ATTEMPT_NUMBER`, `PACKET_SHA256`, `FROZEN_TARGET_SHA`, `FAILURE_CLASS`, `FALLBACK_STATUS`, `REPORT_COMPLETE` in existing `RUN_STATE.json`, `.ai/STATUS.md` and the role report.

On eligible failure reject all partial output, preserve only non-secret attempt metadata, keep packet bytes and frozen target unchanged, and restart the complete role through the next eligible alias. Never continue a prior response. Once a fallback starts it is sticky for that role attempt; primary recovery never preempts it. Reconsider primary only on a later role/task after cooldown ($($Routing.settings.default_cooldown_seconds) seconds unless an authoritative Retry-After/reset is available).

Provider/rate/quota failures prefer the same model family through another provider. `MODEL_RETIRED` and `MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS` skip that whole family. Never retry the same route candidate in one role invocation.

Enforce actual-family independence. Implementation Reviewer differs from Executor when known; Architecture Reviewer differs from Executor and accepted Implementation Reviewer; Final Reviewer differs from Executor and both accepted reviewers. `MODEL_INDEPENDENCE_STATUS: PASS|DEGRADED|CONFLICT`. `allow_degraded_independence` is $($Routing.settings.allow_degraded_independence). A route requiring role rebalance may run only after conflicting reviewer roles are restarted from their original frozen packets with non-conflicting families. If no valid independent route exists, return `MODEL_INDEPENDENCE_CONFLICT`.

Configured hidden routes:
$($PolicyLines -join "`n")
"@
    foreach ($Name in @('architect','build')) {
        $Path = Join-Path $ConfigDir "agents\$Name.md"
        $Text = Get-Content $Path -Raw
        $TaskRules = "    `"reviewer-fallback-*`": allow`n    `"reviewer-architecture-fallback-*`": allow`n    `"final-reviewer-fallback-*`": allow"
        $Text = [regex]::Replace($Text,'(?m)^(    final-reviewer: allow\r?$)',("`$1`n"+$TaskRules),1)
        $Text = [regex]::Replace($Text,'(?m)^## Core invariants\r?$',$PolicyBlock+"`n## Core invariants",1)
        if ($Name -eq 'build' -and $Text -notmatch '## Core invariants') { $Text += $PolicyBlock }
        Write-Utf8NoBom $Path $Text
    }
    $Manifest = [ordered]@{
        schema_version = '1.0'
        governance_version = '3.1.0'
        settings = $Routing.settings
        roles = $Routing.roles
        managed_aliases = $ManagedAliases
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-Utf8NoBom $RoutingManifestPath (($Manifest | ConvertTo-Json -Depth 30) + [Environment]::NewLine)
}

foreach ($Name in $Commands) { Copy-Item (Join-Path $RootDir "templates\commands\$Name.md") (Join-Path $ConfigDir "commands\$Name.md") -Force }

$JsoncPath = Join-Path $ConfigDir 'opencode.jsonc'; $JsonPath = Join-Path $ConfigDir 'opencode.json'
$Target = if ((Test-Path $JsoncPath) -or -not (Test-Path $JsonPath)) { $JsoncPath } else { $JsonPath }
if (Test-Path $Target) {
    $Raw = Get-Content $Target -Raw
    $Stripped = [regex]::Replace($Raw,'/\*.*?\*/','','Singleline')
    $Stripped = [regex]::Replace($Stripped,'(?m)^\s*//.*$','')
    $Stripped = [regex]::Replace($Stripped,',\s*([}\]])','$1')
    if ([string]::IsNullOrWhiteSpace($Stripped)) { $Object = [pscustomobject][ordered]@{ '$schema'='https://opencode.ai/config.json' } }
    else { try { $Object = $Stripped | ConvertFrom-Json } catch { throw "Cannot safely merge $Target. Restore the backup and set default_agent manually." } }
} else { $Object = [pscustomobject][ordered]@{ '$schema'='https://opencode.ai/config.json' } }
$Object | Add-Member -MemberType NoteProperty -Name 'default_agent' -Value 'architect' -Force
Write-Utf8NoBom $Target (($Object | ConvertTo-Json -Depth 20)+[Environment]::NewLine)

& (Join-Path $PSScriptRoot 'verify.ps1') -ConfigDir $ConfigDir
$Mode = if ($Routing) { "reviewer failover with $($ManagedAliases.Count) hidden routes" } else { 'legacy single-model routing' }
Write-Host "Installed OpenCode Governance v3.1.0: 7 public agents, 12 commands, $Mode."
Write-Host 'No fallback continues partial output or preempts an active fallback. No push, merge, deployment or rollback is automatic.'
Write-Host 'Restart OpenCode Desktop/TUI before use.'
Write-Host "Backup: $BackupDir"
