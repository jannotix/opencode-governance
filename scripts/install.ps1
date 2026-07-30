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
if(-not(Test-Path -LiteralPath $BaseInstaller -PathType Leaf)){throw "Internal base installer not found: $BaseInstaller"}
if(-not(Test-Path -LiteralPath $Capabilities -PathType Leaf)){throw "Governance capability installer not found: $Capabilities"}

& $BaseInstaller @PSBoundParameters

if($RoutingConfigPath){
    python $Capabilities install --source-dir $PSScriptRoot --config-dir $ConfigDir
    if($LASTEXITCODE-ne0){throw "Canonical Governance 3.6.0 capability installation failed with exit code $LASTEXITCODE."}
    & (Join-Path $PSScriptRoot 'verify-routing.ps1') -ConfigDir $ConfigDir
    Write-Host 'Installed OpenCode Governance v3.6.0 — Governed Authority, Memory & Evidence.'
    Write-Host 'Candidate receipts, actionable continuation, focused review lenses, governed memory, exact evidence reuse, staged commit validation and simulation are active.'
}else{
    Write-Host 'Installed OpenCode Governance v3.6.0 in legacy single-model mode.'
    Write-Host 'Provider/model routing was not changed. Advanced routed capabilities require a local routing profile.'
}
