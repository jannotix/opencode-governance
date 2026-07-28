param([string]$ConfigDir)

$ErrorActionPreference = 'Stop'
if (-not $ConfigDir) {
    $ConfigDir = if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $HOME '.config\opencode' }
}
$ManifestPath = Join-Path $ConfigDir 'opencode-governance-routing.json'
if (-not (Test-Path $ManifestPath -PathType Leaf)) {
    Write-Host 'PASS: reviewer failover routing is not configured.'
    exit 0
}

try { $Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json } catch { throw 'Routing manifest is invalid JSON.' }
if ([string]$Manifest.schema_version -ne '1.0') { throw 'Routing manifest schema_version must be 1.0.' }
if ([string]$Manifest.governance_version -ne '3.1.0') { throw 'Routing manifest governance_version must be 3.1.0.' }
$AllowedRoles = @('reviewer','reviewer-architecture','final-reviewer')
$AllowedFailures = @('PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT')
$Expected = @{}

function Require-Line([string]$Text,[string]$Line,[string]$Context) {
    if (($Text -split "`r?`n") -cnotcontains $Line) { throw "$Context missing exact line: $Line" }
}
function Get-RoleConfig([string]$Role) {
    $Property = $Manifest.roles.PSObject.Properties[$Role]
    if (-not $Property) { throw "Routing manifest missing role: $Role" }
    return $Property.Value
}
function Verify-RenderedCandidate([string]$Agent,[string]$Role,[object]$Candidate,[int]$Priority,[bool]$Hidden) {
    $Path = Join-Path $ConfigDir "agents\$Agent.md"
    if (-not (Test-Path $Path -PathType Leaf)) { throw "Missing routed agent: $Agent" }
    $Text = Get-Content $Path -Raw
    $Variant = if ([string]::IsNullOrWhiteSpace([string]$Candidate.variant)) { 'PROVIDER_DEFAULT' } else { [string]$Candidate.variant }
    $OnlyOn = if (@($Candidate.only_on).Count -eq 0) { 'ANY_ELIGIBLE_FAILURE' } else { @($Candidate.only_on) -join '|' }
    $Rebalance = if ($Candidate.requires_role_rebalance -eq $true) { 'YES' } else { 'NO' }
    Require-Line $Text "model: $($Candidate.model)" $Agent
    if ([string]::IsNullOrWhiteSpace([string]$Candidate.variant)) {
        if ($Text -match '(?m)^variant:\s*\S+') { throw "$Agent rendered an unconfigured variant." }
    } else { Require-Line $Text "variant: $($Candidate.variant)" $Agent }
    foreach ($Line in @(
        '## MODEL_ROUTE_METADATA',
        "AUTHORITATIVE_ROLE: $Role",
        "ROUTE_AGENT: $Agent",
        "SELECTED_MODEL: $($Candidate.model)",
        "SELECTED_VARIANT: $Variant",
        "MODEL_FAMILY: $($Candidate.model_family)",
        "ROUTE_PRIORITY: $Priority",
        "ROUTE_ONLY_ON: $OnlyOn",
        "REQUIRES_ROLE_REBALANCE: $Rebalance"
    )) { Require-Line $Text $Line $Agent }
    foreach ($Marker in @('ROLE_ATTEMPT_ID','PACKET_SHA256','FROZEN_TARGET_SHA','REPORT_COMPLETE: YES')) {
        if ($Text -notlike "*$Marker*") { throw "$Agent missing route marker: $Marker" }
    }
    if ($Hidden) {
        Require-Line $Text 'mode: subagent' $Agent
        Require-Line $Text 'hidden: true' $Agent
        Require-Line $Text '  task: deny' $Agent
    }
}

foreach ($Role in @($Manifest.settings.enabled_roles)) {
    if ([string]$Role -notin $AllowedRoles) { throw "Unsupported enabled failover role: $Role" }
}
foreach ($Failure in @($Manifest.settings.eligible_failures)) {
    if ([string]$Failure -notin $AllowedFailures) { throw "Unsupported eligible failure: $Failure" }
}
if ($Manifest.settings.allow_degraded_independence -ne $false) { throw 'Default routing must fail closed on degraded independence.' }

foreach ($Role in $AllowedRoles) {
    $RoleConfig = Get-RoleConfig $Role
    Verify-RenderedCandidate $Role $Role $RoleConfig.primary 0 $false
    $Priorities = @()
    foreach ($Candidate in @($RoleConfig.fallbacks)) {
        $Priority = [int]$Candidate.priority
        if ($Priority -lt 1 -or $Priorities -contains $Priority) { throw "$Role fallback priorities must be unique positive integers." }
        $Priorities += $Priority
        if ([string]::IsNullOrWhiteSpace([string]$Candidate.model_family)) { throw "$Role fallback missing model_family." }
        if ([string]$Candidate.model -notmatch '^[^/\s]+/\S+$') { throw "$Role fallback has invalid provider/model." }
        if ([string]$Candidate.variant_policy -eq 'highest_supported' -and [string]::IsNullOrWhiteSpace([string]$Candidate.variant)) { throw "$Role fallback highest_supported variant was not resolved." }
        if ([string]$Candidate.variant -eq 'highest_supported') { throw "$Role fallback uses unresolved literal highest_supported." }
        if ($Role -in @($Manifest.settings.enabled_roles)) {
            $Alias = "$Role-fallback-$Priority"
            $Expected[$Alias] = $true
            Verify-RenderedCandidate $Alias $Role $Candidate $Priority $true
        }
    }
}

$PublicMap = @{
    'architect' = @('architect',(Get-RoleConfig 'architect').primary)
    'build' = @('architect',(Get-RoleConfig 'architect').primary)
    'plan' = @('architect',(Get-RoleConfig 'architect').primary)
    'executor' = @('executor',(Get-RoleConfig 'executor').primary)
}
foreach ($Name in $PublicMap.Keys) { Verify-RenderedCandidate $Name $PublicMap[$Name][0] $PublicMap[$Name][1] 0 $false }

$Managed = @($Manifest.managed_aliases)
if ($Managed.Count -ne $Expected.Count) { throw 'Managed alias count does not match enabled fallback candidates.' }
foreach ($Alias in $Managed) {
    if ([string]$Alias -notmatch '^(reviewer|reviewer-architecture|final-reviewer)-fallback-[0-9]+$') { throw "Unsafe managed alias name: $Alias" }
    if (-not $Expected.ContainsKey([string]$Alias)) { throw "Unexpected managed alias: $Alias" }
}
$RenderedAliases = @(Get-ChildItem (Join-Path $ConfigDir 'agents') -Filter '*-fallback-*.md' | ForEach-Object BaseName)
foreach ($Alias in $RenderedAliases) { if ($Alias -notin $Managed) { throw "Unmanaged fallback alias present: $Alias" } }

foreach ($Name in @('architect','build')) {
    $Path = Join-Path $ConfigDir "agents\$Name.md"
    $Text = Get-Content $Path -Raw
    foreach ($Marker in @('ROLE_FAILOVER_POLICY','MODEL_INDEPENDENCE_STATUS','MODEL_INDEPENDENCE_CONFLICT','primary recovery never preempts','PACKET_SHA256','FROZEN_TARGET_SHA','Never retry the same route candidate')) {
        if ($Text -notlike "*$Marker*") { throw "$Name missing failover policy marker: $Marker" }
    }
    foreach ($Pattern in @('"reviewer-fallback-*": allow','"reviewer-architecture-fallback-*": allow','"final-reviewer-fallback-*": allow')) {
        if ($Text -notlike "*$Pattern*") { throw "$Name missing fallback task permission: $Pattern" }
    }
}

Write-Host "PASS: OpenCode Governance v3.1 reviewer failover verified ($($Managed.Count) hidden routes, exact manifest reconciliation)."
