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
$ExpectedAliases = @()

foreach ($Role in @($Manifest.settings.enabled_roles)) {
    if ([string]$Role -notin $AllowedRoles) { throw "Unsupported enabled failover role: $Role" }
}
foreach ($Failure in @($Manifest.settings.eligible_failures)) {
    if ([string]$Failure -notin $AllowedFailures) { throw "Unsupported eligible failure: $Failure" }
}
if ($Manifest.settings.allow_degraded_independence -ne $false) { throw 'Default routing must fail closed on degraded independence.' }

foreach ($Role in $AllowedRoles) {
    $RoleProperty = $Manifest.roles.PSObject.Properties[$Role]
    if (-not $RoleProperty) { throw "Routing manifest missing role: $Role" }
    $RoleConfig = $RoleProperty.Value
    $Priorities = @()
    foreach ($Candidate in @($RoleConfig.fallbacks)) {
        $Priority = [int]$Candidate.priority
        if ($Priority -lt 1 -or $Priorities -contains $Priority) { throw "$Role fallback priorities must be unique positive integers." }
        $Priorities += $Priority
        if ([string]::IsNullOrWhiteSpace([string]$Candidate.model_family)) { throw "$Role fallback missing model_family." }
        if ([string]$Candidate.model -notmatch '^[^/\s]+/\S+$') { throw "$Role fallback has invalid provider/model." }
        if ([string]$Candidate.variant_policy -eq 'highest_supported' -and [string]::IsNullOrWhiteSpace([string]$Candidate.variant)) {
            throw "$Role fallback highest_supported variant was not resolved."
        }
        if ([string]$Candidate.variant -eq 'highest_supported') { throw "$Role fallback uses unresolved literal highest_supported." }
        if ($Role -in @($Manifest.settings.enabled_roles)) { $ExpectedAliases += "$Role-fallback-$Priority" }
    }
}

$Managed = @($Manifest.managed_aliases)
if ($Managed.Count -ne $ExpectedAliases.Count) { throw 'Managed alias count does not match enabled fallback candidates.' }
foreach ($Alias in $ExpectedAliases) {
    if ($Alias -notin $Managed) { throw "Routing manifest missing managed alias: $Alias" }
    $Path = Join-Path $ConfigDir "agents\$Alias.md"
    if (-not (Test-Path $Path -PathType Leaf)) { throw "Missing hidden route agent: $Alias" }
    $Text = Get-Content $Path -Raw
    if ($Text -notmatch '(?m)^mode: subagent\r?$') { throw "$Alias must be a subagent." }
    if ($Text -notmatch '(?m)^hidden: true\r?$') { throw "$Alias must be hidden." }
    if ($Text -notmatch '(?m)^  task: deny\r?$') { throw "$Alias must deny task delegation." }
    foreach ($Marker in @('MODEL_ROUTE_METADATA','AUTHORITATIVE_ROLE:','ROUTE_AGENT:','SELECTED_MODEL:','SELECTED_VARIANT:','MODEL_FAMILY:','ROLE_ATTEMPT_ID','PACKET_SHA256','FROZEN_TARGET_SHA','REPORT_COMPLETE: YES')) {
        if ($Text -notlike "*$Marker*") { throw "$Alias missing route marker: $Marker" }
    }
    if ($Text -notmatch '(?m)^model: [^\s/]+/\S+\r?$') { throw "$Alias has no provider-qualified model." }
}

foreach ($Name in @('architect','build')) {
    $Path = Join-Path $ConfigDir "agents\$Name.md"
    $Text = Get-Content $Path -Raw
    foreach ($Marker in @('ROLE_FAILOVER_POLICY','MODEL_INDEPENDENCE_STATUS','MODEL_INDEPENDENCE_CONFLICT','primary recovery never preempts','PACKET_SHA256','FROZEN_TARGET_SHA')) {
        if ($Text -notlike "*$Marker*") { throw "$Name missing failover policy marker: $Marker" }
    }
    foreach ($Pattern in @('"reviewer-fallback-*": allow','"reviewer-architecture-fallback-*": allow','"final-reviewer-fallback-*": allow')) {
        if ($Text -notlike "*$Pattern*") { throw "$Name missing fallback task permission: $Pattern" }
    }
}

foreach ($Alias in $Managed) {
    if ([string]$Alias -notmatch '^(reviewer|reviewer-architecture|final-reviewer)-fallback-[0-9]+$') { throw "Unsafe managed alias name: $Alias" }
}

Write-Host "PASS: OpenCode Governance v3.1 reviewer failover verified ($($Managed.Count) hidden routes)."
