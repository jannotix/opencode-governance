param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('select','prepare','finalize','promote','discard')]
    [string]$Operation,
    [string]$ProjectDir,
    [string]$ConfigDir,
    [string]$RoutingConfigPath,
    [string]$TaskId,
    [string]$AttemptId,
    [string]$FrozenTarget,
    [ValidateSet('PATCH','BOUNDED_FEATURE','MAJOR_FEATURE','EXISTING_PRODUCT_EVOLUTION','NEW_PRODUCT','HIGH_RISK_CHANGE')]
    [string]$WorkClass,
    [string]$FailureClass,
    [string]$FailedRoute,
    [string[]]$AttemptedRoute = @(),
    [string]$RouteAgent,
    [string]$PacketSha256,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$WorkClasses = @('PATCH','BOUNDED_FEATURE','MAJOR_FEATURE','EXISTING_PRODUCT_EVOLUTION','NEW_PRODUCT','HIGH_RISK_CHANGE')
$EligibleFailures = @('PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT')
$DerivedFailure = 'MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS'

if (-not $ConfigDir) {
    $ConfigDir = if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $HOME '.config\opencode' }
}
if (-not $RoutingConfigPath) {
    $RoutingConfigPath = Join-Path $ConfigDir 'opencode-governance-routing.json'
}

function Write-Json([object]$Value, [string]$Path) {
    [System.IO.File]::WriteAllText(
        $Path,
        (($Value | ConvertTo-Json -Depth 30) + [Environment]::NewLine),
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Invoke-Git([string]$Directory, [string[]]$Arguments, [switch]$AllowFailure) {
    $Output = & git -C $Directory @Arguments 2>&1
    $ExitCode = $LASTEXITCODE
    $Text = ($Output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    if (-not $AllowFailure -and $ExitCode -ne 0) {
        if ([string]::IsNullOrWhiteSpace($Text)) {
            throw "git $($Arguments[0]) failed with exit code $ExitCode."
        }
        throw $Text.Trim()
    }
    return [pscustomobject]@{
        ExitCode = $ExitCode
        Text = $Text
    }
}

function Load-Routing {
    if (-not (Test-Path $RoutingConfigPath -PathType Leaf)) {
        throw "Routing manifest not found: $RoutingConfigPath"
    }
    try {
        $Routing = Get-Content $RoutingConfigPath -Raw | ConvertFrom-Json
    } catch {
        throw 'Routing manifest is invalid JSON.'
    }
    if ([string]$Routing.schema_version -ne '1.0') {
        throw 'Routing schema_version must be 1.0.'
    }
    if ('executor' -notin @($Routing.settings.enabled_roles)) {
        throw 'Executor failover is not enabled.'
    }
    return $Routing
}

function Get-OnlyOn([object]$Candidate) {
    if (-not $Candidate.PSObject.Properties['only_on']) {
        throw 'Every Executor route must define only_on.'
    }
    return @($Candidate.only_on | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Get-RouteWorkClasses([object]$Candidate) {
    $Values = @()
    if ($Candidate.PSObject.Properties['work_classes']) {
        $Values = @($Candidate.work_classes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
    if ($Values.Count -eq 0) { return $WorkClasses }
    foreach ($Value in $Values) {
        if ([string]$Value -notin $WorkClasses) {
            throw 'Executor route contains an invalid work class.'
        }
    }
    return $Values
}

function Get-Routes([object]$Routing) {
    $Config = $Routing.roles.executor
    $Routes = @(
        [pscustomobject]@{
            route_agent = 'executor'
            priority = 0
            candidate = $Config.primary
        }
    )
    foreach ($Candidate in @($Config.fallbacks | Sort-Object { [int]$_.priority })) {
        $Routes += [pscustomobject]@{
            route_agent = "executor-fallback-$([int]$Candidate.priority)"
            priority = [int]$Candidate.priority
            candidate = $Candidate
        }
    }
    return $Routes
}

function Find-Route([object]$Routing, [string]$Agent) {
    foreach ($Route in (Get-Routes $Routing)) {
        if ($Route.route_agent -eq $Agent) { return $Route }
    }
    throw "Unknown Executor route agent: $Agent"
}

function Get-StatePath {
    return Join-Path $ConfigDir 'opencode-governance-routing-state.tsv'
}

function Get-Epoch {
    return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}

function Load-Cooldowns {
    $Result = @{}
    $Path = Get-StatePath
    if (Test-Path $Path -PathType Leaf) {
        foreach ($Line in Get-Content $Path) {
            $Parts = $Line -split "`t", 2
            if ($Parts.Count -ne 2) { continue }
            $Until = 0L
            if ([long]::TryParse($Parts[1], [ref]$Until) -and $Until -gt (Get-Epoch)) {
                $Result[$Parts[0]] = $Until
            }
        }
    }
    return $Result
}

function Save-Cooldowns([hashtable]$Values) {
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    $Lines = @()
    foreach ($Key in ($Values.Keys | Sort-Object)) {
        $Lines += "$Key`t$($Values[$Key])"
    }
    [System.IO.File]::WriteAllLines(
        (Get-StatePath),
        $Lines,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Validate-Identifier([string]$Value, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^[A-Za-z0-9._-]+$') {
        throw "Invalid $Label."
    }
}

function Get-Project {
    if (-not $ProjectDir) { throw '-ProjectDir is required.' }
    $Resolved = (Resolve-Path $ProjectDir).Path
    $Probe = Invoke-Git $Resolved @('rev-parse','--is-inside-work-tree') -AllowFailure
    if ($Probe.ExitCode -ne 0 -or $Probe.Text.Trim() -ne 'true') {
        throw 'Project must be a Git worktree.'
    }
    Validate-Identifier $TaskId 'task id'
    Validate-Identifier $AttemptId 'attempt id'
    return $Resolved
}

function Get-StatusEntries([string]$Project) {
    $Result = Invoke-Git $Project @('-c','core.quotePath=false','status','--porcelain=v1','--untracked-files=all')
    $Entries = @()
    foreach ($Line in ($Result.Text -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($Line)) { continue }
        if ($Line -match '^..\s+"?\.ai([\\/]|"?$)') { continue }
        $Entries += $Line
    }
    return @($Entries | Sort-Object)
}

function Get-StatusPaths([string[]]$Entries) {
    $Paths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($Entry in $Entries) {
        $Body = if ($Entry.Length -ge 4) { $Entry.Substring(3) } else { $Entry }
        if ($Body.Contains(' -> ')) {
            $Body = $Body.Split(@(' -> '), 2, [StringSplitOptions]::None)[1]
        }
        $Normalized = $Body.Trim('"').Replace('\','/')
        $null = $Paths.Add($Normalized)
    }
    return $Paths
}

function Get-PathFingerprint([string]$Project, [string]$RelativePath) {
    $NativeRelative = $RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $FullPath = Join-Path $Project $NativeRelative
    if (-not (Test-Path $FullPath)) { return 'MISSING' }
    $Item = Get-Item $FullPath -Force
    if ($Item.LinkType) {
        return 'SYMLINK:' + (@($Item.Target) -join '|')
    }
    if ($Item.PSIsContainer) { return 'DIRECTORY' }
    return 'FILE:' + (Get-FileHash $FullPath -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-RealState([string]$Project) {
    $Entries = @(Get-StatusEntries $Project)
    $Paths = Get-StatusPaths $Entries
    $Fingerprints = [ordered]@{}
    foreach ($Path in ($Paths | Sort-Object)) {
        $Fingerprints[$Path] = Get-PathFingerprint $Project $Path
    }
    $Canonical = [ordered]@{
        status = $Entries
        path_fingerprints = $Fingerprints
    }
    $CanonicalJson = $Canonical | ConvertTo-Json -Depth 10 -Compress
    $Bytes = [Text.Encoding]::UTF8.GetBytes($CanonicalJson)
    $Hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
    return [pscustomobject]@{
        status = $Entries
        path_fingerprints = $Fingerprints
        state_sha256 = $Hash
    }
}

function Get-AttemptPaths([string]$Project, [string]$Task, [string]$Attempt) {
    $Root = Join-Path $Project ".ai\tasks\$Task\evidence\executor-attempts"
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    return [pscustomobject]@{
        manifest = Join-Path $Root "$Attempt.json"
        patch = Join-Path $Root "$Attempt.patch"
    }
}

function Read-Attempt([string]$Project) {
    $Paths = Get-AttemptPaths $Project $TaskId $AttemptId
    if (-not (Test-Path $Paths.manifest -PathType Leaf)) {
        throw "Executor attempt manifest not found: $($Paths.manifest)"
    }
    try {
        $Data = Get-Content $Paths.manifest -Raw | ConvertFrom-Json
    } catch {
        throw 'Executor attempt manifest is invalid JSON.'
    }
    return [pscustomobject]@{
        data = $Data
        paths = $Paths
    }
}

function Resolve-ReportPath([string]$Project) {
    if ([System.IO.Path]::IsPathRooted($ReportPath)) { return $ReportPath }
    return Join-Path $Project $ReportPath
}

function Select-Route([object]$Routing) {
    if (-not $WorkClass) { throw '-WorkClass is required for select.' }
    $Attempted = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($Attempt in $AttemptedRoute) { $null = $Attempted.Add($Attempt) }
    $Cooldowns = Load-Cooldowns
    $Now = Get-Epoch
    $Failed = if ($FailedRoute) { Find-Route $Routing $FailedRoute } else { $null }
    $Candidates = @()

    foreach ($Route in (Get-Routes $Routing)) {
        $Candidate = $Route.candidate
        if ($Attempted.Contains([string]$Route.route_agent)) { continue }
        if ($Cooldowns.ContainsKey([string]$Candidate.model) -and $Cooldowns[[string]$Candidate.model] -gt $Now) { continue }
        if ($WorkClass -notin @(Get-RouteWorkClasses $Candidate)) { continue }

        $Scope = @(Get-OnlyOn $Candidate)
        if ($FailureClass) {
            if ($FailureClass -notin $EligibleFailures -and $FailureClass -ne $DerivedFailure) { continue }
            if ($Scope.Count -gt 0 -and $FailureClass -notin $Scope) {
                $SameFamilyLeft = @(
                    (Get-Routes $Routing) | Where-Object {
                        $Failed -and
                        $_.candidate.model_family -eq $Failed.candidate.model_family -and
                        -not $Attempted.Contains([string]$_.route_agent) -and
                        $WorkClass -in @(Get-RouteWorkClasses $_.candidate)
                    }
                )
                if (-not ($DerivedFailure -in $Scope -and $SameFamilyLeft.Count -eq 0)) { continue }
            }
            if ($FailureClass -in @('MODEL_RETIRED',$DerivedFailure) -and $Failed -and $Candidate.model_family -eq $Failed.candidate.model_family) {
                continue
            }
        }
        $Candidates += $Route
    }

    if ($Candidates.Count -eq 0) {
        throw 'EXECUTOR_FAILOVER_BLOCKED: no eligible route remains. HUMAN_RECOVERY_REQUIRED'
    }

    $FailedFamily = if ($Failed) { [string]$Failed.candidate.model_family } else { '' }
    $Chosen = @(
        $Candidates | Sort-Object \
            @{ Expression = { if ($FailureClass -and $FailedFamily -and $_.candidate.model_family -eq $FailedFamily) { 0 } else { 1 } } }, \
            @{ Expression = { [int]$_.priority } }
    )[0]
    $Candidate = $Chosen.candidate
    [pscustomobject]@{
        route_agent = $Chosen.route_agent
        model = $Candidate.model
        variant = $Candidate.variant
        model_family = $Candidate.model_family
        priority = $Chosen.priority
        work_class = $WorkClass
    } | ConvertTo-Json -Compress
}

function Prepare-Attempt([object]$Routing) {
    $Project = Get-Project
    if (-not $FrozenTarget -or $FrozenTarget -notmatch '^[0-9a-fA-F]{7,64}$') {
        throw 'A Git frozen target SHA is required.'
    }
    if (-not $RouteAgent -or $PacketSha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw 'Route agent and 64-character packet SHA-256 are required.'
    }
    if (-not $WorkClass) { throw '-WorkClass is required.' }

    $Route = Find-Route $Routing $RouteAgent
    if ($WorkClass -notin @(Get-RouteWorkClasses $Route.candidate)) {
        throw "Executor route $RouteAgent is not eligible for work class $WorkClass."
    }
    Invoke-Git $Project @('cat-file','-e',"$FrozenTarget^{commit}") | Out-Null
    $ResolvedTarget = (Invoke-Git $Project @('rev-parse',$FrozenTarget)).Text.Trim()
    $Head = (Invoke-Git $Project @('rev-parse','HEAD')).Text.Trim()
    if ($Head -ne $ResolvedTarget) {
        throw 'EXECUTOR_FAILOVER_BLOCKED: real HEAD differs from frozen target.'
    }

    $Worktree = Join-Path $Project ".ai\executor-worktrees\$AttemptId"
    if (Test-Path $Worktree) { throw 'Executor attempt worktree already exists.' }
    $PreState = Get-RealState $Project
    Invoke-Git $Project @('worktree','add','--detach',$Worktree,$FrozenTarget) | Out-Null

    $Paths = Get-AttemptPaths $Project $TaskId $AttemptId
    $Data = [ordered]@{
        schema_version = '1.0'
        state = 'PREPARED'
        task_id = $TaskId
        attempt_id = $AttemptId
        work_class = $WorkClass
        route_agent = $RouteAgent
        model = $Route.candidate.model
        variant = $Route.candidate.variant
        model_family = $Route.candidate.model_family
        frozen_target = $ResolvedTarget
        packet_sha256 = $PacketSha256.ToLowerInvariant()
        execution_root = $Worktree
        pre_status = $PreState.status
        pre_path_fingerprints = $PreState.path_fingerprints
        pre_state_sha256 = $PreState.state_sha256
        created_at = [DateTime]::UtcNow.ToString('o')
    }
    Write-Json $Data $Paths.manifest
    [pscustomobject]@{
        execution_root = $Worktree
        attempt_manifest = $Paths.manifest
        route_agent = $RouteAgent
    } | ConvertTo-Json -Compress
}

function Finalize-Attempt([object]$Routing) {
    $Project = Get-Project
    $Attempt = Read-Attempt $Project
    $Data = $Attempt.data
    if ($Data.state -ne 'PREPARED') { throw 'Executor attempt is not PREPARED.' }
    if (-not $ReportPath) { throw '-ReportPath is required.' }

    $ReportFile = Resolve-ReportPath $Project
    try {
        $Report = Get-Content $ReportFile -Raw | ConvertFrom-Json
    } catch {
        throw 'Executor report must be valid JSON.'
    }
    $Expected = [ordered]@{
        EXECUTOR_ATTEMPT_ID = $Data.attempt_id
        PACKET_SHA256 = $Data.packet_sha256
        FROZEN_TARGET_SHA = $Data.frozen_target
        REPORT_COMPLETE = 'YES'
    }
    foreach ($Key in $Expected.Keys) {
        if (([string]$Report.$Key).ToLowerInvariant() -ne ([string]$Expected[$Key]).ToLowerInvariant()) {
            throw "Executor report mismatch: $Key"
        }
    }

    $Worktree = [string]$Data.execution_root
    $StatusEntries = @(Get-StatusEntries $Worktree)
    foreach ($Path in (Get-StatusPaths $StatusEntries)) {
        if ($Path -eq '.ai' -or $Path.StartsWith('.ai/') -or $Path -eq '.git' -or $Path.StartsWith('.git/')) {
            throw "Executor attempt changed forbidden path: $Path"
        }
    }

    Invoke-Git $Worktree @('add','-A') | Out-Null
    $ChangedResult = Invoke-Git $Worktree @('-c','core.quotePath=false','diff','--cached','--name-only')
    $ChangedPaths = @(
        $ChangedResult.Text -split "`r?`n" |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Replace('\','/') }
    )
    if ($ChangedPaths.Count -eq 0) {
        throw 'Executor attempt produced no application or project-documentation changes.'
    }

    $PatchArgument = "--output=$($Attempt.paths.patch)"
    Invoke-Git $Worktree @('diff','--cached','--binary','--full-index',$PatchArgument) | Out-Null
    if (-not (Test-Path $Attempt.paths.patch -PathType Leaf)) {
        throw 'Executor binary patch was not created.'
    }

    $Data.state = 'FINALIZED'
    $Data | Add-Member NoteProperty report_path $ReportFile -Force
    $Data | Add-Member NoteProperty report_sha256 (Get-FileHash $ReportFile -Algorithm SHA256).Hash.ToLowerInvariant() -Force
    $Data | Add-Member NoteProperty patch_path $Attempt.paths.patch -Force
    $Data | Add-Member NoteProperty patch_sha256 (Get-FileHash $Attempt.paths.patch -Algorithm SHA256).Hash.ToLowerInvariant() -Force
    $Data | Add-Member NoteProperty changed_paths $ChangedPaths -Force
    $Data | Add-Member NoteProperty finalized_at ([DateTime]::UtcNow.ToString('o')) -Force
    Write-Json $Data $Attempt.paths.manifest

    [pscustomobject]@{
        patch_path = $Attempt.paths.patch
        patch_sha256 = $Data.patch_sha256
        changed_paths = $ChangedPaths
    } | ConvertTo-Json -Compress
}

function Promote-Attempt([object]$Routing) {
    $Project = Get-Project
    $Attempt = Read-Attempt $Project
    $Data = $Attempt.data
    if ($Data.state -ne 'FINALIZED') { throw 'Executor attempt is not FINALIZED.' }
    if ((Invoke-Git $Project @('rev-parse','HEAD')).Text.Trim() -ne $Data.frozen_target) {
        throw 'EXECUTOR_FAILOVER_BLOCKED: real HEAD changed before promotion.'
    }

    $CurrentState = Get-RealState $Project
    if ($CurrentState.state_sha256 -ne $Data.pre_state_sha256) {
        throw 'EXECUTOR_FAILOVER_BLOCKED: real worktree state changed before promotion.'
    }
    $DirtyPaths = Get-StatusPaths @($Data.pre_status)
    $Overlap = @($Data.changed_paths | Where-Object { $DirtyPaths.Contains([string]$_) })
    if ($Overlap.Count -gt 0) {
        throw "EXECUTOR_FAILOVER_BLOCKED: proposed patch overlaps pre-existing dirty paths: $($Overlap -join ',')"
    }
    if ((Get-FileHash $Attempt.paths.patch -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Data.patch_sha256) {
        throw 'Executor patch hash mismatch.'
    }

    $Check = Invoke-Git $Project @('apply','--check','--binary',$Attempt.paths.patch) -AllowFailure
    if ($Check.ExitCode -ne 0) {
        throw "EXECUTOR_FAILOVER_BLOCKED: patch apply check failed: $($Check.Text)"
    }
    Invoke-Git $Project @('apply','--binary',$Attempt.paths.patch) | Out-Null
    $ReverseCheck = Invoke-Git $Project @('apply','--check','--reverse','--binary',$Attempt.paths.patch) -AllowFailure
    if ($ReverseCheck.ExitCode -ne 0) {
        throw 'EXECUTOR_FAILOVER_BLOCKED: applied patch verification failed.'
    }

    Invoke-Git $Project @('worktree','remove','--force',[string]$Data.execution_root) | Out-Null
    $Data.state = 'PROMOTED'
    $Data | Add-Member NoteProperty promoted_at ([DateTime]::UtcNow.ToString('o')) -Force
    $Data | Add-Member NoteProperty post_status @(Get-StatusEntries $Project) -Force
    Write-Json $Data $Attempt.paths.manifest

    [pscustomobject]@{
        state = 'PROMOTED'
        changed_paths = $Data.changed_paths
        patch_sha256 = $Data.patch_sha256
    } | ConvertTo-Json -Compress
}

function Discard-Attempt([object]$Routing) {
    $Project = Get-Project
    $Attempt = Read-Attempt $Project
    $Data = $Attempt.data
    if (Test-Path ([string]$Data.execution_root)) {
        Invoke-Git $Project @('worktree','remove','--force',[string]$Data.execution_root) | Out-Null
    }
    if (Test-Path $Attempt.paths.patch -PathType Leaf) {
        Remove-Item $Attempt.paths.patch -Force
    }
    if ($FailureClass) {
        if ($FailureClass -notin $EligibleFailures) {
            throw 'Cannot mark cooldown for an ineligible failure.'
        }
        $Cooldowns = Load-Cooldowns
        $Cooldowns[[string]$Data.model] = (Get-Epoch) + [int]$Routing.settings.default_cooldown_seconds
        Save-Cooldowns $Cooldowns
    }
    $Data.state = 'DISCARDED'
    $Data | Add-Member NoteProperty discarded_at ([DateTime]::UtcNow.ToString('o')) -Force
    $Data | Add-Member NoteProperty failure_class $FailureClass -Force
    Write-Json $Data $Attempt.paths.manifest

    [pscustomobject]@{
        state = 'DISCARDED'
        route_agent = $Data.route_agent
    } | ConvertTo-Json -Compress
}

$Routing = Load-Routing
switch ($Operation) {
    'select' { Select-Route $Routing }
    'prepare' { Prepare-Attempt $Routing }
    'finalize' { Finalize-Attempt $Routing }
    'promote' { Promote-Attempt $Routing }
    'discard' { Discard-Attempt $Routing }
}
