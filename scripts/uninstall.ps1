param([string]$ConfigDir)
$ErrorActionPreference='Stop'
if(-not $ConfigDir){$ConfigDir=if($env:OPENCODE_CONFIG_DIR){$env:OPENCODE_CONFIG_DIR}else{Join-Path $HOME '.config\opencode'}}
$Agents=@('architect','build','plan','executor','reviewer','reviewer-architecture','final-reviewer')
$Commands=@('ai-init','ai-audit','ai-docs','ai-discover','ai-plan','ai-execute','ai-review','ai-workflow','ai-status','ai-resume','ai-metrics','ai-release')
$ManifestPath=Join-Path $ConfigDir 'opencode-governance-routing.json'
if(Test-Path $ManifestPath -PathType Leaf){
  try{$Manifest=Get-Content $ManifestPath -Raw|ConvertFrom-Json}catch{throw 'Routing manifest is invalid; refusing to remove unknown aliases.'}
  foreach($Alias in @($Manifest.managed_aliases)){
    if([string]$Alias -match '^(reviewer|reviewer-architecture|final-reviewer)-fallback-[0-9]+$'){
      $Path=Join-Path $ConfigDir "agents\$Alias.md"
      if(Test-Path $Path -PathType Leaf){Remove-Item $Path -Force}
    }else{throw "Unsafe managed alias in routing manifest: $Alias"}
  }
  Remove-Item $ManifestPath -Force
}
foreach($name in $Agents){$p=Join-Path $ConfigDir "agents\$name.md";if(Test-Path $p){Remove-Item $p -Force}}
foreach($name in $Commands){$p=Join-Path $ConfigDir "commands\$name.md";if(Test-Path $p){Remove-Item $p -Force}}
Write-Host 'Removed OpenCode Governance public agents, commands, managed hidden routing aliases and routing manifest. Provider authentication, config, project .ai state, project documentation, backups and unrelated files were preserved.'
