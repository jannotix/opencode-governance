param([string]$ConfigDir)
$ErrorActionPreference='Stop'
if(-not$ConfigDir){$ConfigDir=if($env:OPENCODE_CONFIG_DIR){$env:OPENCODE_CONFIG_DIR}else{Join-Path $HOME '.config\opencode'}}
$ManifestPath=Join-Path $ConfigDir 'opencode-governance-routing.json'
if(Test-Path $ManifestPath -PathType Leaf){
  try{$Manifest=Get-Content $ManifestPath -Raw|ConvertFrom-Json}catch{throw 'Routing manifest is invalid; refusing to remove unknown managed files.'}
  $Version=[string]$Manifest.governance_version
  if($Version-in@('3.3.2','3.3.3','3.3.4','3.4.0','3.5.0')){
    $Tools=Join-Path $ConfigDir 'opencode-governance-tools'
    $Expected=@((Join-Path $Tools 'architect-attempt.ps1'),(Join-Path $Tools 'architect-attempt.sh'),(Join-Path $Tools 'executor-attempt.ps1'),(Join-Path $Tools 'executor-attempt.sh'))
    if($Version-in@('3.4.0','3.5.0')){$Expected+=@((Join-Path $Tools 'context-intelligence.ps1'),(Join-Path $Tools 'context-intelligence.sh'),(Join-Path $Tools 'context-intelligence.py'))}
    if($Version-eq'3.5.0'){$Expected+=@((Join-Path $Tools 'quality-gates.ps1'),(Join-Path $Tools 'quality-gates.sh'),(Join-Path $Tools 'quality-gates.py'))}
    $Managed=@($Manifest.managed_tools|ForEach-Object{[string]$_})
    if($Managed.Count-ne$Expected.Count){throw "Unsafe managed tool count in v$Version routing manifest."}
    foreach($tool in $Expected){if($tool-notin$Managed){throw "Unsafe managed tool set in v$Version routing manifest: $tool"}}
    $Remove=@($Expected[0],$Expected[1]);if($Version-in@('3.4.0','3.5.0')){$Remove+=$Expected[4..6]};if($Version-eq'3.5.0'){$Remove+=$Expected[7..9]}
    Remove-Item -LiteralPath $Remove -Force -ErrorAction SilentlyContinue
    $Manifest.governance_version='3.3.0';$Manifest.PSObject.Properties.Remove('architect_runner_version');$Manifest.PSObject.Properties.Remove('context_intelligence_version');$Manifest.PSObject.Properties.Remove('quality_gates_version')
    $Manifest.managed_tools=@($Expected[2],$Expected[3])
    [IO.File]::WriteAllText($ManifestPath,(($Manifest|ConvertTo-Json -Depth 30)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
  }
}
& (Join-Path $PSScriptRoot 'uninstall-core.ps1') -ConfigDir $ConfigDir
