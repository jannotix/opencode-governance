param([string]$ConfigDir)

$ErrorActionPreference='Stop'
if(-not$ConfigDir){$ConfigDir=if($env:OPENCODE_CONFIG_DIR){$env:OPENCODE_CONFIG_DIR}else{Join-Path $HOME '.config\opencode'}}
$ManifestPath=Join-Path $ConfigDir 'opencode-governance-routing.json'
if(-not(Test-Path $ManifestPath -PathType Leaf)){Write-Host 'PASS: model failover routing is not configured.';return}
try{$Manifest=Get-Content $ManifestPath -Raw|ConvertFrom-Json}catch{throw 'Routing manifest is invalid JSON.'}
$Version=[string]$Manifest.governance_version
if($Version-eq'3.3.0'){& (Join-Path $PSScriptRoot 'verify-routing-core.ps1') -ConfigDir $ConfigDir;return}
$Supported=@('3.3.2','3.3.3','3.3.4','3.4.0','3.5.0')
if($Version-notin$Supported){throw "Unsupported routing manifest governance_version: $Version"}
$ToolsDir=Join-Path $ConfigDir 'opencode-governance-tools'
$Base=@((Join-Path $ToolsDir 'architect-attempt.ps1'),(Join-Path $ToolsDir 'architect-attempt.sh'),(Join-Path $ToolsDir 'executor-attempt.ps1'),(Join-Path $ToolsDir 'executor-attempt.sh'))
$Expected=@($Base)
if($Version-in@('3.4.0','3.5.0')){
  if([string]$Manifest.architect_runner_version-ne'3.3.4'){throw 'architect_runner_version must be 3.3.4.'}
  if([string]$Manifest.context_intelligence_version-ne'3.4.0'){throw 'context_intelligence_version must be 3.4.0.'}
  $Expected+=@((Join-Path $ToolsDir 'context-intelligence.ps1'),(Join-Path $ToolsDir 'context-intelligence.sh'),(Join-Path $ToolsDir 'context-intelligence.py'))
}else{
  if([string]$Manifest.architect_runner_version-ne$Version){throw "architect_runner_version must be $Version."}
  if($Manifest.PSObject.Properties.Name-contains'context_intelligence_version'){throw 'Unexpected context_intelligence_version.'}
}
if($Version-eq'3.5.0'){
  if([string]$Manifest.quality_gates_version-ne'3.5.0'){throw 'quality_gates_version must be 3.5.0.'}
  $Expected+=@((Join-Path $ToolsDir 'quality-gates.ps1'),(Join-Path $ToolsDir 'quality-gates.sh'),(Join-Path $ToolsDir 'quality-gates.py'))
}elseif($Manifest.PSObject.Properties.Name-contains'quality_gates_version'){throw 'Unexpected quality_gates_version.'}
$Managed=@($Manifest.managed_tools|ForEach-Object{[string]$_})
if($Managed.Count-ne$Expected.Count){throw "Managed tool count does not match v$Version."}
foreach($tool in $Expected){if($tool-notin$Managed){throw "Managed tool missing from manifest: $tool"};if(-not(Test-Path $tool -PathType Leaf)){throw "Managed tool missing from disk: $tool"}}

$Marker='[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
$Policy=@('ARCHITECT_RUNNER_INTEGRATION','ARCHITECT_RUNNER_REQUIRED',$Marker,$Base[0],$Base[1],'Never invoke the Architect runner from inside the active OpenCode process.')
if($Version-in@('3.3.3','3.3.4','3.4.0','3.5.0')){$Policy+=@('POWERSHELL_7_REQUIRED','pwsh -NoProfile -File')}
if($Version-in@('3.3.4','3.4.0','3.5.0')){$Policy+=@('PROJECT_STATE_FINGERPRINT_V1','NON_GIT_PROJECT_SUPPORTED','PROJECT_STATE_CHANGED')}
if($Version-in@('3.4.0','3.5.0')){$Policy+=@('CONTEXT_INTELLIGENCE_V1','CONTEXT_BUDGET.json','SKILL_CAPABILITY_MANIFEST_V1','CONTEXT_SUFFICIENT','BLOCKED_CONTEXT_GAP',$Expected[4],$Expected[5],$Expected[6])}
if($Version-eq'3.5.0'){$Policy+=@('QUALITY_GATES_V1','QUALITY_PROFILE.json','DEBUG_PROOF_V1','TDD_PROOF_V1','EVAL_PLAN_V1','IMPLEMENTATION_SELF_CHECK_V1','LEARNING_CANDIDATE_V1','FINAL_REVIEWER',$Expected[7],$Expected[8],$Expected[9])}
foreach($name in @('architect','build','plan')){$text=Get-Content (Join-Path $ConfigDir "agents\$name.md") -Raw;foreach($value in $Policy){if($text-notlike"*$value*"){throw "$name missing marker: $value"}}}
if($Version-eq'3.5.0'){$text=Get-Content (Join-Path $ConfigDir 'agents\executor.md') -Raw;foreach($value in @('QUALITY_GATES_V1','IMPLEMENTATION_SELF_CHECK_V1','approval_authority: false',$Expected[7],$Expected[8])){if($text-notlike"*$value*"){throw "executor missing marker: $value"}}}
$Gate=@('ARCHITECT_RUNNER_ENTRY_GATE','ARCHITECT_RUNNER_REQUIRED',$Base[0],$Base[1])
if($Version-in@('3.3.3','3.3.4','3.4.0','3.5.0')){$Gate+='pwsh -NoProfile -File'}
if($Version-in@('3.3.4','3.4.0','3.5.0')){$Gate+='PROJECT_STATE_CHANGED'}
foreach($command in @('ai-init','ai-audit','ai-discover','ai-plan')){$text=Get-Content (Join-Path $ConfigDir "commands\$command.md") -Raw;foreach($value in $Gate){if($text-notlike"*$value*"){throw "$command missing Architect gate marker: $value"}}}
if($Version-in@('3.4.0','3.5.0')){foreach($command in @('ai-workflow','ai-resume','ai-metrics')){$text=Get-Content (Join-Path $ConfigDir "commands\$command.md") -Raw;foreach($value in @('CONTEXT_INTELLIGENCE_ENTRY','BLOCKED_CONTEXT_GAP',$Expected[4],$Expected[5])){if($text-notlike"*$value*"){throw "$command missing Context marker: $value"}}}}
if($Version-eq'3.5.0'){foreach($command in @('ai-plan','ai-execute','ai-workflow','ai-review','ai-resume','ai-audit','ai-metrics')){$text=Get-Content (Join-Path $ConfigDir "commands\$command.md") -Raw;foreach($value in @('QUALITY_GATES_ENTRY','QUALITY_PROFILE.json','BLOCKED',$Expected[7],$Expected[8])){if($text-notlike"*$value*"){throw "$command missing Quality Gate marker: $value"}}}}
if($Version-in@('3.3.4','3.4.0','3.5.0')){
  $ps=Get-Content $Base[0] -Raw;$sh=Get-Content $Base[1] -Raw
  foreach($value in @('PROJECT_STATE_FINGERPRINT_V1','PROJECT_STATE_CHANGED','Get-ProjectStateFingerprint')){if($ps-notlike"*$value*"){throw "PowerShell runner missing $value"}}
  foreach($value in @('PROJECT_STATE_FINGERPRINT_V1','PROJECT_STATE_CHANGED','project_state_fingerprint')){if($sh-notlike"*$value*"){throw "Unix runner missing $value"}}
}
if($Version-in@('3.4.0','3.5.0')){
  $ps=Get-Content $Expected[4] -Raw;$sh=Get-Content $Expected[5] -Raw;$py=Get-Content $Expected[6] -Raw
  foreach($value in @('CONTEXT_BUDGET_V1','SKILL_SELECTION_V1','CONTENT_SUMMARY_CACHE_ENTRY_V1','CONTEXT_METRICS_V1')){if($ps-notlike"*$value*"-or$py-notlike"*$value*"){throw "Context tool missing $value"}}
  if($sh-notlike'*context-intelligence.py*'){throw 'Unix context wrapper is invalid.'}
}
if($Version-eq'3.5.0'){
  $ps=Get-Content $Expected[7] -Raw;$sh=Get-Content $Expected[8] -Raw;$py=Get-Content $Expected[9] -Raw
  foreach($value in @('QUALITY_PROFILE_V1','DEBUG_PROOF_V1','TDD_PROOF_V1','EVAL_PLAN_V1','IMPLEMENTATION_SELF_CHECK_V1','LEARNING_CANDIDATE_V1','LEARNING_PROMOTION_V1')){if($ps-notlike"*$value*"-or$py-notlike"*$value*"){throw "Quality tool missing $value"}}
  if($sh-notlike'*quality-gates.py*'){throw 'Unix Quality Gate wrapper is invalid.'}
}

$Temp=Join-Path ([IO.Path]::GetTempPath()) ('opencode-routing-compat-'+[guid]::NewGuid().ToString('N'))
try{
  New-Item -ItemType Directory -Force -Path (Join-Path $Temp 'agents'),(Join-Path $Temp 'opencode-governance-tools')|Out-Null
  Copy-Item (Join-Path $ConfigDir 'agents\*.md') (Join-Path $Temp 'agents') -Force
  Copy-Item $Base[2] (Join-Path $Temp 'opencode-governance-tools\executor-attempt.ps1') -Force;Copy-Item $Base[3] (Join-Path $Temp 'opencode-governance-tools\executor-attempt.sh') -Force
  $normalized=Get-Content $ManifestPath -Raw|ConvertFrom-Json;$normalized.governance_version='3.3.0';$normalized.PSObject.Properties.Remove('architect_runner_version');$normalized.PSObject.Properties.Remove('context_intelligence_version');$normalized.PSObject.Properties.Remove('quality_gates_version')
  $normalized.managed_tools=@((Join-Path $Temp 'opencode-governance-tools\executor-attempt.ps1'),(Join-Path $Temp 'opencode-governance-tools\executor-attempt.sh'))
  [IO.File]::WriteAllText((Join-Path $Temp 'opencode-governance-routing.json'),(($normalized|ConvertTo-Json -Depth 30)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
  & (Join-Path $PSScriptRoot 'verify-routing-core.ps1') -ConfigDir $Temp
}finally{Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host "PASS: OpenCode Governance v$Version routing verified ($(@($Manifest.managed_aliases).Count) hidden routes; $($Expected.Count) managed tools verified)."
