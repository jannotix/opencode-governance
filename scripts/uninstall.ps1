param([string]$ConfigDir)

$ErrorActionPreference='Stop'
if(-not$ConfigDir){$ConfigDir=if($env:OPENCODE_CONFIG_DIR){$env:OPENCODE_CONFIG_DIR}else{Join-Path $HOME '.config/opencode'}}
$ManifestPath=Join-Path $ConfigDir 'opencode-governance-routing.json'
$Capabilities=Join-Path $PSScriptRoot 'governance-capabilities.py'
$BaseUninstaller=Join-Path $PSScriptRoot 'uninstall-base.ps1'
if(-not(Test-Path -LiteralPath $BaseUninstaller -PathType Leaf)){throw "Internal base uninstaller not found: $BaseUninstaller"}

if(Test-Path -LiteralPath $ManifestPath -PathType Leaf){
    try{$Manifest=Get-Content -LiteralPath $ManifestPath -Raw|ConvertFrom-Json}catch{throw 'Routing manifest is invalid; refusing to remove unknown managed files.'}
    if([string]$Manifest.governance_version-in@('3.6.0','3.7.0','3.7.1','3.7.2','3.7.3','3.7.4','3.7.5','3.7.6','3.7.7')){
        if(-not(Test-Path -LiteralPath $Capabilities -PathType Leaf)){throw "Capability uninstaller not found: $Capabilities"}
        $Process=Start-Process -FilePath 'python' -ArgumentList @($Capabilities,'uninstall','--config-dir',$ConfigDir) -NoNewWindow -Wait -PassThru
        if($Process.ExitCode-ne0){throw "Governance capability removal failed with exit code $($Process.ExitCode)."}
    }
}

& $BaseUninstaller -ConfigDir $ConfigDir
Write-Host 'Removed OpenCode Governance 3.7.7 canonical agents, commands, managed routes and managed tools.'
Write-Host 'Provider authentication, project .ai state, project documentation, backups, governed memory and unrelated local files were preserved.'
Write-Host 'Any explicitly installed project pre-commit receipt gate must be removed from that project before deleting its referenced tool path.'
