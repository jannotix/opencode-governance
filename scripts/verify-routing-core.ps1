param([string]$ConfigDir)

$ErrorActionPreference = 'Stop'
if (-not $ConfigDir) {
    $ConfigDir = if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $HOME '.config\opencode' }
}

$ManifestPath = Join-Path $ConfigDir 'opencode-governance-routing.json'
if (-not (Test-Path $ManifestPath -PathType Leaf)) {
    Write-Host 'PASS: model failover routing is not configured.'
    exit 0
}

try {
    $Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
} catch {
    throw 'Routing manifest is invalid JSON.'
}
if ([string]$Manifest.schema_version -ne '1.0') { throw 'Routing manifest schema_version must be 1.0.' }
if ([string]$Manifest.governance_version -ne '3.3.0') { throw 'Routing manifest governance_version must be 3.3.0.' }

$EnabledRoles = @('architect','executor','reviewer','reviewer-architecture','final-reviewer')
$AliasRoles = @('executor','reviewer','reviewer-architecture','final-reviewer')
$AllowedFailures = @('PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT','TOOL_EXECUTION_ABORTED')
$WorkClasses = @('PATCH','BOUNDED_FEATURE','MAJOR_FEATURE','EXISTING_PRODUCT_EVOLUTION','NEW_PRODUCT','HIGH_RISK_CHANGE')
$ExpectedAliases = @{}

function Require-Line([string]$Text, [string]$Line, [string]$Context) {
    if (($Text -split "`r?`n") -cnotcontains $Line) {
        throw "$Context missing exact line: $Line"
    }
}

function Get-RoleConfig([string]$Role) {
    $Property = $Manifest.roles.PSObject.Properties[$Role]
    if (-not $Property) { throw "Routing manifest missing role: $Role" }
    return $Property.Value
}

function Get-OnlyOn([object]$Candidate, [string]$Context) {
    if (-not $Candidate.PSObject.Properties['only_on']) { throw "$Context missing only_on" }
    return @($Candidate.only_on | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Get-WorkClasses([object]$Candidate, [string]$Role, [string]$Context) {
    $Values = @()
    if ($Candidate.PSObject.Properties['work_classes']) {
        $Values = @($Candidate.work_classes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
    if ($Role -ne 'executor' -and $Values.Count -gt 0) { throw "$Context uses work_classes outside Executor." }
    foreach ($Value in $Values) {
        if ([string]$Value -notin $WorkClasses) { throw "$Context contains an invalid work class: $Value" }
    }
    return $Values
}

function Verify-RenderedCandidate(
    [string]$Agent,
    [string]$Role,
    [object]$Candidate,
    [int]$Priority,
    [bool]$Hidden
) {
    $Path = Join-Path $ConfigDir "agents\$Agent.md"
    if (-not (Test-Path $Path -PathType Leaf)) { throw "Missing routed agent: $Agent" }
    $Text = Get-Content $Path -Raw
    $Variant = if ([string]::IsNullOrWhiteSpace([string]$Candidate.variant)) { 'PROVIDER_DEFAULT' } else { [string]$Candidate.variant }
    $OnlyValues = Get-OnlyOn $Candidate "$Agent route"
    $Only = if ($OnlyValues.Count -eq 0) { 'ANY_ELIGIBLE_FAILURE' } else { $OnlyValues -join '|' }
    $ClassValues = Get-WorkClasses $Candidate $Role "$Agent route"
    $Classes = if ($ClassValues.Count -eq 0) { 'ALL' } else { $ClassValues -join '|' }
    $Rebalance = if ($Candidate.requires_role_rebalance -eq $true) { 'YES' } else { 'NO' }

    Require-Line $Text "model: $($Candidate.model)" $Agent
    if ([string]::IsNullOrWhiteSpace([string]$Candidate.variant)) {
        if ($Text -match '(?m)^variant:\s*\S+') { throw "$Agent rendered an unconfigured variant." }
    } else {
        Require-Line $Text "variant: $($Candidate.variant)" $Agent
    }
    foreach ($Line in @(
        '## MODEL_ROUTE_METADATA',
        "AUTHORITATIVE_ROLE: $Role",
        "ROUTE_AGENT: $Agent",
        "SELECTED_MODEL: $($Candidate.model)",
        "SELECTED_VARIANT: $Variant",
        "MODEL_FAMILY: $($Candidate.model_family)",
        "ROUTE_PRIORITY: $Priority",
        "ROUTE_ONLY_ON: $Only",
        "ROUTE_WORK_CLASSES: $Classes",
        "REQUIRES_ROLE_REBALANCE: $Rebalance"
    )) {
        Require-Line $Text $Line $Agent
    }
    if ($Role -eq 'executor') {
        foreach ($Marker in @('EXECUTOR_ATTEMPT_ID','PACKET_SHA256','FROZEN_TARGET_SHA','REPORT_COMPLETE')) {
            if ($Text -notlike "*$Marker*") { throw "$Agent missing Executor route marker: $Marker" }
        }
    } elseif ($Text -notlike '*Require matching attempt, packet and frozen-target identifiers plus a complete report.*') {
        throw "$Agent missing complete-role restart contract."
    }
    if ($Hidden) {
        Require-Line $Text 'mode: subagent' $Agent
        Require-Line $Text 'hidden: true' $Agent
        Require-Line $Text '  task: deny' $Agent
    }
}

foreach ($Role in @($Manifest.settings.enabled_roles)) {
    if ([string]$Role -notin $EnabledRoles) { throw "Unsupported enabled failover role: $Role" }
}
foreach ($Failure in @($Manifest.settings.eligible_failures)) {
    if ([string]$Failure -notin $AllowedFailures) { throw "Unsupported eligible failure: $Failure" }
}
if ($Manifest.settings.allow_degraded_independence -ne $false) {
    throw 'Default routing must fail closed on degraded independence.'
}

foreach ($Role in $AliasRoles) {
    $Config = Get-RoleConfig $Role
    Verify-RenderedCandidate $Role $Role $Config.primary 0 $false
    $Priorities = @()
    foreach ($Candidate in @($Config.fallbacks)) {
        $Priority = [int]$Candidate.priority
        if ($Priority -lt 1 -or $Priorities -contains $Priority) {
            throw "$Role fallback priorities must be unique positive integers."
        }
        $Priorities += $Priority
        if ($Role -in @($Manifest.settings.enabled_roles)) {
            $Alias = "$Role-fallback-$Priority"
            $ExpectedAliases[$Alias] = $true
            Verify-RenderedCandidate $Alias $Role $Candidate $Priority $true
        }
    }
}

foreach ($Entry in @(
    @('architect','architect'),
    @('build','architect'),
    @('plan','architect')
)) {
    $Name = $Entry[0]
    $Role = $Entry[1]
    $RoleConfig = Get-RoleConfig $Role
    Verify-RenderedCandidate $Name $Role $RoleConfig.primary 0 $false
}

$ArchitectConfig = Get-RoleConfig 'architect'
if ('architect' -in @($Manifest.settings.enabled_roles)) {
    if (@($ArchitectConfig.fallbacks).Count -eq 0) { throw 'Architect routing enabled without fallbacks.' }
    foreach ($Name in @('architect','build')) {
        $Text = Get-Content (Join-Path $ConfigDir "agents\$Name.md") -Raw
        foreach ($Marker in @('ai-init|ai-audit|ai-discover|ai-plan','external transactional runner')) {
            if ($Text -notlike "*$Marker*") { throw "$Name missing Architect runner policy: $Marker" }
        }
    }
}

if ('executor' -in @($Manifest.settings.enabled_roles)) {
    $ExecutorConfig = Get-RoleConfig 'executor'
    if (@($ExecutorConfig.fallbacks).Count -eq 0) { throw 'Executor routing enabled without fallbacks.' }
    foreach ($Name in @('architect','build')) {
        $Text = Get-Content (Join-Path $ConfigDir "agents\$Name.md") -Raw
        foreach ($Marker in @(
            'select -> prepare -> delegate selected route -> finalize -> promote',
            'discard',
            'same canonical packet and frozen target',
            'Never delegate a routed Executor against the real project root',
            '"executor-fallback-*": allow',
            'opencode-governance-tools/executor-attempt.sh',
            'opencode-governance-tools\executor-attempt.ps1'
        )) {
            if ($Text -notlike "*$Marker*") { throw "$Name missing Executor failover policy marker: $Marker" }
        }
    }
}

$ManagedAliases = @($Manifest.managed_aliases)
if ($ManagedAliases.Count -ne $ExpectedAliases.Count) {
    throw 'Managed alias count does not match enabled fallback candidates.'
}
foreach ($Alias in $ManagedAliases) {
    $AliasName = [string]$Alias
    if ($AliasName -notmatch '^(executor|reviewer|reviewer-architecture|final-reviewer)-fallback-[0-9]+$') {
        throw "Unsafe managed alias name: $AliasName"
    }
    if (-not $ExpectedAliases.ContainsKey($AliasName)) { throw "Unexpected managed alias: $AliasName" }
}
$RenderedAliases = @(Get-ChildItem (Join-Path $ConfigDir 'agents') -Filter '*-fallback-*.md' | ForEach-Object BaseName)
foreach ($Alias in $RenderedAliases) {
    if ($Alias -notin $ManagedAliases) { throw "Unmanaged fallback alias present: $Alias" }
    if ($Alias -like 'architect-fallback-*') { throw 'Architect fallback aliases are forbidden.' }
}
if ($RenderedAliases.Count -ne $ManagedAliases.Count) {
    throw 'Rendered fallback aliases do not exactly match manifest.'
}

$ExpectedToolPaths = @(
    (Join-Path $ConfigDir 'opencode-governance-tools\executor-attempt.ps1'),
    (Join-Path $ConfigDir 'opencode-governance-tools\executor-attempt.sh')
)
$ManagedToolPaths = @($Manifest.managed_tools | ForEach-Object { [string]$_ })
if ($ManagedToolPaths.Count -ne $ExpectedToolPaths.Count) {
    throw 'Managed Executor tool count is invalid.'
}
foreach ($ToolPath in $ExpectedToolPaths) {
    if ($ToolPath -notin $ManagedToolPaths) { throw "Managed Executor tool missing from manifest: $ToolPath" }
    if (-not (Test-Path $ToolPath -PathType Leaf)) { throw "Managed Executor tool missing from disk: $ToolPath" }
}

foreach ($Name in @('architect','build')) {
    $Text = Get-Content (Join-Path $ConfigDir "agents\$Name.md") -Raw
    foreach ($Marker in @(
        'ROLE_FAILOVER_POLICY',
        'Never retry the same route',
        'Executor promotion is not validation',
        '"reviewer-fallback-*": allow',
        '"reviewer-architecture-fallback-*": allow',
        '"final-reviewer-fallback-*": allow'
    )) {
        if ($Text -notlike "*$Marker*") { throw "$Name missing failover policy marker: $Marker" }
    }
}

Write-Host "PASS: OpenCode Governance v3.3 routing verified ($($ManagedAliases.Count) hidden routes; Executor isolation tools verified)."
