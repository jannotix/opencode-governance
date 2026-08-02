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

function Resolve-GovernancePython {
    foreach($Candidate in @('py','python3','python')){
        $Command=Get-Command $Candidate -ErrorAction SilentlyContinue
        if(-not$Command){continue}
        if($Candidate-eq'py'){
            $Probe=& $Command.Source -3 -c 'import sys;print(sys.version_info[0])' 2>$null
            if($LASTEXITCODE-eq0-and("$Probe".Trim()-eq'3')){return @{Exe=$Command.Source;Prefix=@('-3')}}
            continue
        }
        return @{Exe=$Command.Source;Prefix=@()}
    }
    throw 'Python 3 is required for OpenCode Governance installation. Install Python 3 and ensure py, python3, or python is on PATH.'
}

function Invoke-GovernancePython([string[]]$Arguments,[switch]$CaptureOutput){
    $Python=Resolve-GovernancePython
    $All=@($Python.Prefix+$Arguments)
    $Previous=$ErrorActionPreference
    $ErrorActionPreference='Continue'
    try{
        $Lines=& $Python.Exe @All 2>&1
        $ExitCode=$LASTEXITCODE
    }finally{
        $ErrorActionPreference=$Previous
    }
    $Text=($Lines|ForEach-Object{$_.ToString()}) -join [Environment]::NewLine
    if($ExitCode-ne0){throw "Governance Python command failed with exit code ${ExitCode}: $Text"}
    if($CaptureOutput){return $Text}
    if(-not[string]::IsNullOrWhiteSpace($Text)){Write-Host $Text.TrimEnd()}
}

$SnapshotOutput=Invoke-GovernancePython @($Transaction,'snapshot','--config-dir',$ConfigDir) -CaptureOutput
try{$Snapshot=$SnapshotOutput|ConvertFrom-Json}catch{throw 'Governance pre-install snapshot returned invalid JSON.'}
$BackupDir=[string]$Snapshot.backup_dir
if([string]::IsNullOrWhiteSpace($BackupDir)-or-not(Test-Path -LiteralPath $BackupDir -PathType Container)){throw 'Governance pre-install snapshot directory was not created.'}

try{
    & $BaseInstaller @PSBoundParameters
    if($RoutingConfigPath){
        Invoke-GovernancePython @($Capabilities,'install','--source-dir',$PSScriptRoot,'--config-dir',$ConfigDir)
        & (Join-Path $PSScriptRoot 'verify-routing.ps1') -ConfigDir $ConfigDir
        Write-Host 'Installed OpenCode Governance 3.7.4 with routing and capability tools.'
    }else{
        Write-Host 'Installed OpenCode Governance base in single-model mode (no routing profile).'
        Write-Host 'Authority, memory, evidence, simulation and pre-commit tools require -RoutingConfigPath.'
    }
    Write-Host "Canonical pre-install backup: $BackupDir"
}catch{
    $InstallError=$_
    try{Invoke-GovernancePython @($Transaction,'restore','--config-dir',$ConfigDir,'--backup-dir',$BackupDir)}catch{throw "Governance installation failed and rollback also failed. Original error: $InstallError; rollback error: $_"}
    throw $InstallError
}
