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

$ErrorActionPreference='Stop'
if(-not$ConfigDir){$ConfigDir=if($env:OPENCODE_CONFIG_DIR){$env:OPENCODE_CONFIG_DIR}else{Join-Path $HOME '.config/opencode'}}
$BaseInstaller=Join-Path $PSScriptRoot 'install-base.ps1'
$Capabilities=Join-Path $PSScriptRoot 'governance-capabilities.py'
$Transaction=Join-Path $PSScriptRoot 'governance-install-transaction.py'
foreach($Required in @($BaseInstaller,$Capabilities,$Transaction)){if(-not(Test-Path -LiteralPath $Required -PathType Leaf)){throw "Required Governance installer component not found: $Required"}}

$SnapshotOutput=& python $Transaction snapshot --config-dir $ConfigDir
if($LASTEXITCODE-ne0){throw "Governance pre-install snapshot failed with exit code $LASTEXITCODE."}
try{$Snapshot=$SnapshotOutput|ConvertFrom-Json}catch{throw 'Governance pre-install snapshot returned invalid JSON.'}
$BackupDir=[string]$Snapshot.backup_dir
if([string]::IsNullOrWhiteSpace($BackupDir)-or-not(Test-Path -LiteralPath $BackupDir -PathType Container)){throw 'Governance pre-install snapshot directory was not created.'}

try{
    & $BaseInstaller @PSBoundParameters
    if($RoutingConfigPath){
        & python $Capabilities install --source-dir $PSScriptRoot --config-dir $ConfigDir
        if($LASTEXITCODE-ne0){throw "Canonical Governance 3.6.0 capability installation failed with exit code $LASTEXITCODE."}
        & (Join-Path $PSScriptRoot 'verify-routing.ps1') -ConfigDir $ConfigDir
        Write-Host 'Installed OpenCode Governance v3.6.0 — Governed Authority, Memory & Evidence.'
        Write-Host 'Candidate receipts, actionable continuation, focused review lenses, governed memory, exact evidence reuse, staged commit validation and simulation are active.'
    }else{
        Write-Host 'Installed OpenCode Governance v3.6.0 in legacy single-model mode.'
        Write-Host 'Provider/model routing was not changed. Advanced routed capabilities require a local routing profile.'
    }
    Write-Host "Canonical pre-install backup: $BackupDir"
}catch{
    $InstallError=$_
    & python $Transaction restore --config-dir $ConfigDir --backup-dir $BackupDir
    if($LASTEXITCODE-ne0){throw "Governance installation failed and rollback also failed. Original error: $InstallError"}
    throw $InstallError
}
