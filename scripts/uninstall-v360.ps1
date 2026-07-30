param([string]$ConfigDir)

$ErrorActionPreference='Stop'
if(-not$ConfigDir){$ConfigDir=if($env:OPENCODE_CONFIG_DIR){$env:OPENCODE_CONFIG_DIR}else{Join-Path $HOME '.config/opencode'}}
python (Join-Path $PSScriptRoot 'governance-runtime-install.py') uninstall --source-dir $PSScriptRoot --config-dir $ConfigDir
if($LASTEXITCODE-ne0){throw "Governance runtime overlay removal failed with exit code $LASTEXITCODE."}
& (Join-Path $PSScriptRoot 'uninstall.ps1') -ConfigDir $ConfigDir
