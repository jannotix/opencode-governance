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
& (Join-Path $PSScriptRoot 'install.ps1') @PSBoundParameters
python (Join-Path $PSScriptRoot 'governance-runtime-install.py') install --source-dir $PSScriptRoot --config-dir $ConfigDir
if($LASTEXITCODE-ne0){throw "Governance runtime overlay installation failed with exit code $LASTEXITCODE."}
Write-Host 'Installed OpenCode Governance 3.6.0 runtime authority, memory, evidence reuse and simulation overlay.'
