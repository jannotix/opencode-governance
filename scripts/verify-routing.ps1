param([string]$ConfigDir)

$ErrorActionPreference = 'Stop'
if (-not $ConfigDir) {
    $ConfigDir = if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $HOME '.config\opencode' }
}
$ManifestPath = Join-Path $ConfigDir 'opencode-governance-routing.json'
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    Write-Host 'PASS: model failover routing is not configured.'
    return
}
try { $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json } catch { throw 'Routing manifest is invalid JSON.' }
$Version = [string]$Manifest.governance_version
if ($Version -eq '3.3.0') {
    & (Join-Path $PSScriptRoot 'verify-routing-core.ps1') -ConfigDir $ConfigDir
    return
}
if ($Version -notin @('3.3.2','3.3.3','3.3.4')) { throw "Routing manifest governance_version must be 3.3.0, 3.3.2, 3.3.3 or 3.3.4, got: $Version" }
if ([string]$Manifest.architect_runner_version -ne $Version) { throw "architect_runner_version must be $Version." }

$ToolsDir = Join-Path $ConfigDir 'opencode-governance-tools'
$ExpectedTools = @(
    (Join-Path $ToolsDir 'architect-attempt.ps1'),
    (Join-Path $ToolsDir 'architect-attempt.sh'),
    (Join-Path $ToolsDir 'executor-attempt.ps1'),
    (Join-Path $ToolsDir 'executor-attempt.sh')
)
$ManagedTools = @($Manifest.managed_tools | ForEach-Object { [string]$_ })
if ($ManagedTools.Count -ne $ExpectedTools.Count) { throw "Managed tool count does not match the v$Version contract." }
foreach ($Tool in $ExpectedTools) {
    if ($Tool -notin $ManagedTools) { throw "Managed tool missing from manifest: $Tool" }
    if (-not (Test-Path -LiteralPath $Tool -PathType Leaf)) { throw "Managed tool missing from disk: $Tool" }
}
$Marker = '[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
$PolicyMarkers = @('ARCHITECT_RUNNER_INTEGRATION','ARCHITECT_RUNNER_REQUIRED',$Marker,$ExpectedTools[0],$ExpectedTools[1],'Never invoke the Architect runner from inside the active OpenCode process.')
if ($Version -in @('3.3.3','3.3.4')) { $PolicyMarkers += @('POWERSHELL_7_REQUIRED','pwsh -NoProfile -File') }
if ($Version -eq '3.3.4') { $PolicyMarkers += @('PROJECT_STATE_FINGERPRINT_V1','NON_GIT_PROJECT_SUPPORTED','PROJECT_STATE_CHANGED') }
foreach ($Name in @('architect','build','plan')) {
    $Text = Get-Content -LiteralPath (Join-Path $ConfigDir "agents\$Name.md") -Raw
    foreach ($Value in $PolicyMarkers) {
        if ($Text -notlike "*$Value*") { throw "$Name missing Architect runner marker: $Value" }
    }
}
$GateMarkers = @('ARCHITECT_RUNNER_ENTRY_GATE','ARCHITECT_RUNNER_REQUIRED',$Marker,$ExpectedTools[0],$ExpectedTools[1])
if ($Version -in @('3.3.3','3.3.4')) { $GateMarkers += 'pwsh -NoProfile -File' }
if ($Version -eq '3.3.4') { $GateMarkers += 'PROJECT_STATE_CHANGED' }
foreach ($Command in @('ai-init','ai-audit','ai-discover','ai-plan')) {
    $Text = Get-Content -LiteralPath (Join-Path $ConfigDir "commands\$Command.md") -Raw
    foreach ($Value in $GateMarkers) {
        if ($Text -notlike "*$Value*") { throw "$Command missing Architect entry gate marker: $Value" }
    }
}
if ($Version -eq '3.3.4') {
    $PowerShellRunner = Get-Content -LiteralPath $ExpectedTools[0] -Raw
    $UnixRunner = Get-Content -LiteralPath $ExpectedTools[1] -Raw
    foreach ($Value in @('PROJECT_STATE_FINGERPRINT_V1','PROJECT_STATE_CHANGED','Get-ProjectStateFingerprint')) {
        if ($PowerShellRunner -notlike "*$Value*") { throw "PowerShell Architect runner missing project-state marker: $Value" }
    }
    foreach ($Value in @('PROJECT_STATE_FINGERPRINT_V1','PROJECT_STATE_CHANGED','project_state_fingerprint')) {
        if ($UnixRunner -notlike "*$Value*") { throw "Unix Architect runner missing project-state marker: $Value" }
    }
}

$Temp = Join-Path ([IO.Path]::GetTempPath()) ('opencode-v334-verify-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $Temp 'agents'),(Join-Path $Temp 'opencode-governance-tools') | Out-Null
    Copy-Item (Join-Path $ConfigDir 'agents\*.md') (Join-Path $Temp 'agents') -Force
    Copy-Item (Join-Path $ToolsDir 'executor-attempt.ps1') (Join-Path $Temp 'opencode-governance-tools\executor-attempt.ps1') -Force
    Copy-Item (Join-Path $ToolsDir 'executor-attempt.sh') (Join-Path $Temp 'opencode-governance-tools\executor-attempt.sh') -Force
    $Normalized = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $Normalized | Add-Member -MemberType NoteProperty -Name governance_version -Value '3.3.0' -Force
    $Normalized.PSObject.Properties.Remove('architect_runner_version')
    $Normalized | Add-Member -MemberType NoteProperty -Name managed_tools -Value @(
        (Join-Path $Temp 'opencode-governance-tools\executor-attempt.ps1'),
        (Join-Path $Temp 'opencode-governance-tools\executor-attempt.sh')
    ) -Force
    [IO.File]::WriteAllText((Join-Path $Temp 'opencode-governance-routing.json'), (($Normalized | ConvertTo-Json -Depth 30) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
    & (Join-Path $PSScriptRoot 'verify-routing-core.ps1') -ConfigDir $Temp
} finally {
    Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "PASS: OpenCode Governance v$Version routing verified ($(@($Manifest.managed_aliases).Count) hidden routes; Architect and Executor transactional tools verified)."
