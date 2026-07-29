[CmdletBinding()]
param(
    [string]$ConfigDir,
    [string]$DurabilityRoot,
    [Parameter(Mandatory = $true)]
    [string]$UpdateExecutable,
    [string[]]$UpdateArguments = @(),
    [string[]]$ProcessNames = @('opencode', 'OpenCode'),
    [switch]$StopRunningOpenCode,
    [switch]$SkipEnvironmentPersistence,
    [switch]$SkipGovernanceVerification,
    [switch]$NoAutomaticRestore,
    [string]$GovernanceRepoPath,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$DurabilityScript = Join-Path $PSScriptRoot 'config-durability.ps1'
if (-not (Test-Path -LiteralPath $DurabilityScript -PathType Leaf)) {
    throw "Durability engine not found: $DurabilityScript"
}

if ([string]::IsNullOrWhiteSpace($GovernanceRepoPath)) {
    $GovernanceRepoPath = Split-Path -Parent $PSScriptRoot
}
$GovernanceRepoPath = [System.IO.Path]::GetFullPath($GovernanceRepoPath)

function Invoke-Durability([hashtable]$Parameters) {
    return & $DurabilityScript @Parameters -PassThru
}

function Move-ToQuarantine([string]$ResolvedDurabilityRoot, [string]$SnapshotId) {
    $SnapshotsRoot = Join-Path $ResolvedDurabilityRoot 'snapshots'
    $Source = Join-Path $SnapshotsRoot $SnapshotId
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Drift snapshot not found: $Source" }
    $QuarantineRoot = Join-Path $ResolvedDurabilityRoot 'quarantine'
    New-Item -ItemType Directory -Force -Path $QuarantineRoot | Out-Null
    $Destination = Join-Path $QuarantineRoot $SnapshotId
    if (Test-Path -LiteralPath $Destination) { throw "Quarantine snapshot already exists: $Destination" }
    Move-Item -LiteralPath $Source -Destination $Destination

    $ManifestPath = Join-Path $Destination 'manifest.json'
    if (Test-Path -LiteralPath $ManifestPath -PathType Leaf) {
        $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
        $Manifest.collection = 'quarantine'
        [System.IO.File]::WriteAllText(
            $ManifestPath,
            (($Manifest | ConvertTo-Json -Depth 20) + [Environment]::NewLine),
            (New-Object System.Text.UTF8Encoding($false))
        )
    }
    return $SnapshotId
}

function Get-RunningOpenCodeProcesses([string[]]$Names) {
    $Processes = @()
    foreach ($Name in @($Names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)) {
        $Processes += @(Get-Process -Name $Name -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID })
    }
    return @($Processes | Sort-Object Id -Unique)
}

$StatusParameters = @{ Action = 'Status' }
if ($ConfigDir) { $StatusParameters.ConfigDir = $ConfigDir }
if ($DurabilityRoot) { $StatusParameters.DurabilityRoot = $DurabilityRoot }
$Status = Invoke-Durability $StatusParameters
$ResolvedConfigDir = [string]$Status.config_dir
$ResolvedDurabilityRoot = [string]$Status.durability_root

if (-not $SkipEnvironmentPersistence) {
    [Environment]::SetEnvironmentVariable('OPENCODE_CONFIG_DIR', $ResolvedConfigDir, 'User')
    $env:OPENCODE_CONFIG_DIR = $ResolvedConfigDir
}

$Running = Get-RunningOpenCodeProcesses $ProcessNames
if ($Running.Count -gt 0 -and -not $StopRunningOpenCode) {
    $Details = ($Running | ForEach-Object { "$($_.ProcessName):$($_.Id)" }) -join ', '
    throw "OpenCode processes are running. Close them or pass -StopRunningOpenCode: $Details"
}
if ($Running.Count -gt 0) {
    foreach ($Process in $Running) { Stop-Process -Id $Process.Id -Force -ErrorAction Stop }
    foreach ($Process in $Running) {
        try { Wait-Process -Id $Process.Id -Timeout 30 -ErrorAction Stop } catch {
            if (Get-Process -Id $Process.Id -ErrorAction SilentlyContinue) { throw "Process did not stop: $($Process.ProcessName):$($Process.Id)" }
        }
    }
}

$PreSnapshot = Invoke-Durability @{
    Action = 'Snapshot'
    ConfigDir = $ResolvedConfigDir
    DurabilityRoot = $ResolvedDurabilityRoot
}

$UpdateExitCode = -1
$UpdateInvocationError = $null
$PreviousNativePreference = $null
$HasNativePreference = Test-Path variable:PSNativeCommandUseErrorActionPreference
if ($HasNativePreference) {
    $PreviousNativePreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
}
try {
    try {
        & $UpdateExecutable @UpdateArguments
        $UpdateExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    } catch {
        $UpdateInvocationError = $_.Exception.Message
        $UpdateExitCode = -1
    }
} finally {
    if ($HasNativePreference) { $PSNativeCommandUseErrorActionPreference = $PreviousNativePreference }
}

$PostVerification = $null
$VerificationError = $null
try {
    $PostVerification = Invoke-Durability @{
        Action = 'Verify'
        ConfigDir = $ResolvedConfigDir
        DurabilityRoot = $ResolvedDurabilityRoot
        SnapshotId = $PreSnapshot.snapshot_id
    }
} catch {
    $VerificationError = $_.Exception.Message
}

$DriftDetected = ($null -eq $PostVerification -or -not $PostVerification.match)
$QuarantineSnapshotId = $null
$ConfigurationState = if ($DriftDetected) { 'DRIFT_DETECTED' } else { 'UNCHANGED' }
$RestoreVerification = $null

if ($DriftDetected) {
    try {
        $DriftSnapshot = Invoke-Durability @{
            Action = 'Snapshot'
            ConfigDir = $ResolvedConfigDir
            DurabilityRoot = $ResolvedDurabilityRoot
        }
        $QuarantineSnapshotId = Move-ToQuarantine $ResolvedDurabilityRoot $DriftSnapshot.snapshot_id
    } catch {
        throw "Configuration drift was detected but quarantine failed: $($_.Exception.Message)"
    }

    if (-not $NoAutomaticRestore) {
        $RestoreVerification = Invoke-Durability @{
            Action = 'Restore'
            ConfigDir = $ResolvedConfigDir
            DurabilityRoot = $ResolvedDurabilityRoot
            SnapshotId = $PreSnapshot.snapshot_id
        }
        if (-not $RestoreVerification.match) { throw 'Automatic configuration restore did not verify.' }
        $ConfigurationState = 'RESTORED'
    }
}

$GovernanceVerification = 'SKIPPED'
if (-not $SkipGovernanceVerification) {
    $VerifyScript = Join-Path $GovernanceRepoPath 'scripts\verify.ps1'
    $VerifyRoutingScript = Join-Path $GovernanceRepoPath 'scripts\verify-routing.ps1'
    if (-not (Test-Path -LiteralPath $VerifyScript -PathType Leaf)) { throw "Governance verifier not found: $VerifyScript" }
    if (-not (Test-Path -LiteralPath $VerifyRoutingScript -PathType Leaf)) { throw "Routing verifier not found: $VerifyRoutingScript" }
    & $VerifyScript -ConfigDir $ResolvedConfigDir
    & $VerifyRoutingScript -ConfigDir $ResolvedConfigDir
    $GovernanceVerification = 'PASS'
}

$Result = [pscustomobject]@{
    durability_version = '3.3.1'
    config_dir = $ResolvedConfigDir
    durability_root = $ResolvedDurabilityRoot
    pre_update_snapshot_id = $PreSnapshot.snapshot_id
    quarantine_snapshot_id = $QuarantineSnapshotId
    updater_executable = $UpdateExecutable
    updater_exit_code = $UpdateExitCode
    updater_invocation_error = $UpdateInvocationError
    verification_error = $VerificationError
    configuration_state = $ConfigurationState
    drift_added = if ($PostVerification) { @($PostVerification.added) } else { @() }
    drift_removed = if ($PostVerification) { @($PostVerification.removed) } else { @() }
    drift_changed = if ($PostVerification) { @($PostVerification.changed) } else { @() }
    automatic_restore = (-not $NoAutomaticRestore)
    governance_verification = $GovernanceVerification
}

if ($UpdateExitCode -ne 0) {
    $Recovery = if ($ConfigurationState -eq 'RESTORED') { 'configuration restored' } elseif ($ConfigurationState -eq 'UNCHANGED') { 'configuration unchanged' } else { 'configuration drift remains' }
    $Message = if ($UpdateInvocationError) {
        "Updater invocation failed; $Recovery. $UpdateInvocationError"
    } else {
        "Updater exited with code $UpdateExitCode; $Recovery."
    }
    throw $Message
}

if ($DriftDetected -and $NoAutomaticRestore) {
    throw "Configuration drift detected. Quarantine snapshot: $QuarantineSnapshotId"
}

if ($PassThru) {
    return $Result
}
$Result | ConvertTo-Json -Depth 20
