param([string]$ConfigDir)
$ErrorActionPreference='Stop'
if(-not $ConfigDir){$ConfigDir=if($env:OPENCODE_CONFIG_DIR){$env:OPENCODE_CONFIG_DIR}else{Join-Path $HOME '.config\opencode'}}
$Agents=@('architect','build','plan','executor','reviewer','reviewer-architecture','final-reviewer')
$Commands=@('ai-init','ai-audit','ai-docs','ai-discover','ai-plan','ai-execute','ai-review','ai-workflow','ai-status','ai-resume','ai-metrics','ai-release')
foreach($name in $Agents){$p=Join-Path $ConfigDir "agents\$name.md";if(Test-Path $p){Remove-Item $p -Force}}
foreach($name in $Commands){$p=Join-Path $ConfigDir "commands\$name.md";if(Test-Path $p){Remove-Item $p -Force}}
Write-Host 'Removed OpenCode Governance managed agents and commands. Provider authentication, config, project .ai state, project documentation, backups and unrelated files were preserved.'
