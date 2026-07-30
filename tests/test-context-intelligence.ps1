$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Tool=Join-Path $Root 'scripts/context-intelligence.ps1'
$Temp=Join-Path ([IO.Path]::GetTempPath()) ('opencode-v340-'+[guid]::NewGuid().ToString('N'))
$Project=Join-Path $Temp 'project'
$Cache=Join-Path $Temp 'cache'
New-Item -ItemType Directory -Force -Path $Project|Out-Null

function Invoke-Tool([hashtable]$Parameters){
  $json=& $Tool @Parameters
  if($LASTEXITCODE-ne 0){throw "Context tool failed: $($json -join "`n")"}
  return ($json -join "`n")|ConvertFrom-Json
}
function Invoke-ToolFailure([string[]]$Arguments){
  $output=& pwsh -NoProfile -File $Tool @Arguments 2>&1
  return [pscustomobject]@{Code=$LASTEXITCODE;Text=($output-join"`n")}
}
function Write-Json([string]$Path,[object]$Value){
  $Value|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

try{
  $expected=[ordered]@{
    PATCH=@(1,1,20,20)
    BOUNDED_FEATURE=@(2,2,40,40)
    MAJOR_FEATURE=@(3,3,80,80)
    EXISTING_PRODUCT_EVOLUTION=@(3,3,100,100)
    NEW_PRODUCT=@(3,3,120,120)
    HIGH_RISK_CHANGE=@(3,3,120,120)
  }
  $index=0
  foreach($entry in $expected.GetEnumerator()){
    $index++
    $task="CTX-$index"
    $result=Invoke-Tool @{Action='InitializeBudget';ProjectDir=$Project;TaskId=$task;WorkClass=$entry.Key;CacheRoot=$Cache}
    if($result.schema-ne'CONTEXT_BUDGET_V1'){throw 'Budget schema mismatch'}
    $actual=@($result.max_retrieval_cycles,$result.max_loaded_skills,$result.max_packet_references,$result.max_admitted_paths)
    if(($actual-join ',')-ne($entry.Value-join ',')){throw "Budget mismatch for $($entry.Key)"}
    $stored=Get-Content (Join-Path $Project ".ai/tasks/$task/CONTEXT_BUDGET.json") -Raw|ConvertFrom-Json
    if(($stored|ConvertTo-Json -Depth 20 -Compress)-ne($result|ConvertTo-Json -Depth 20 -Compress)){throw 'Stored budget mismatch'}
  }

  $bad=Invoke-ToolFailure @('-Action','InitializeBudget','-ProjectDir',$Project,'-TaskId','../escape','-WorkClass','PATCH')
  if($bad.Code-eq0){throw 'Invalid task ID was accepted'}
  if($bad.Text-notmatch'INVALID_TASK_ID'){throw "Invalid task ID error missing: $($bad.Text)"}

  $task='CTX-CYCLES'
  Invoke-Tool @{Action='InitializeBudget';ProjectDir=$Project;TaskId=$task;WorkClass='MAJOR_FEATURE';CacheRoot=$Cache}|Out-Null
  $cycle=Join-Path $Temp 'cycle.json'
  Write-Json $cycle ([ordered]@{query='entry points';reason='initial dispatch';candidate_paths=@('src/a.ps1');admitted_paths=@('src/a.ps1');rejected_paths=@();dependency_edges=@();trust_boundaries=@();tests=@();context_gaps=@();stop_reason='REFINE'})
  foreach($number in 1..3){
    $recorded=Invoke-Tool @{Action='RecordCycle';ProjectDir=$Project;TaskId=$task;Cycle=$number;InputJsonPath=$cycle}
    if($recorded.cycle-ne$number){throw 'Cycle number mismatch'}
  }
  $fourth=Invoke-ToolFailure @('-Action','RecordCycle','-ProjectDir',$Project,'-TaskId',$task,'-Cycle','4','-InputJsonPath',$cycle)
  if($fourth.Code-eq0){throw 'Fourth cycle was accepted'}
  if($fourth.Text-notmatch'RETRIEVAL_CYCLE_LIMIT'){throw "Cycle limit error missing: $($fourth.Text)"}

  $catalog=Join-Path $Temp 'skills.json'
  $criteria=Join-Path $Temp 'criteria.json'
  Write-Json $catalog @(
    [ordered]@{schema='SKILL_CAPABILITY_MANIFEST_V1';skill_id='trusted-debug';version='1';content_sha256=('a'*64);source='project';trust_class='PROJECT_AUTHORITATIVE';triggers=@('debug');supported_work_classes=@('MAJOR_FEATURE');languages=@('powershell');frameworks=@();required_tools=@();external_dependencies=@();conflicts_with=@();overlaps_with=@('generic-debug');estimated_context_tokens=600;sections=@([ordered]@{id='root-cause';heading='Root cause'})},
    [ordered]@{schema='SKILL_CAPABILITY_MANIFEST_V1';skill_id='generic-debug';version='1';content_sha256=('b'*64);source='workspace';trust_class='WORKSPACE_ADVISORY';triggers=@('debug');supported_work_classes=@('MAJOR_FEATURE');languages=@('powershell');frameworks=@();required_tools=@();external_dependencies=@();conflicts_with=@();overlaps_with=@('trusted-debug');estimated_context_tokens=200;sections=@()},
    [ordered]@{schema='SKILL_CAPABILITY_MANIFEST_V1';skill_id='network-skill';version='1';content_sha256=('c'*64);source='external';trust_class='EXTERNAL_UNTRUSTED';triggers=@('debug');supported_work_classes=@('MAJOR_FEATURE');languages=@('powershell');frameworks=@();required_tools=@();external_dependencies=@('remote-service');conflicts_with=@();overlaps_with=@();estimated_context_tokens=100;sections=@()}
  )
  Write-Json $criteria ([ordered]@{triggers=@('debug');languages=@('powershell');frameworks=@();required_sections=@('root-cause');available_tools=@()})
  $selection=Invoke-Tool @{Action='SelectSkills';ProjectDir=$Project;TaskId=$task;CatalogPath=$catalog;InputJsonPath=$criteria}
  if(@($selection.selected).Count-ne1-or$selection.selected[0].skill_id-ne'trusted-debug'){throw 'Trusted skill not selected'}
  $rejected=@{};foreach($item in @($selection.rejected)){$rejected[$item.skill_id]=$item.reason}
  if($rejected['generic-debug']-ne'OVERLAP_DEDUPLICATED'){throw 'Overlap was not deduplicated'}
  if($rejected['network-skill']-ne'EXTERNAL_DEPENDENCY_UNAVAILABLE'){throw 'External dependency skill was not rejected'}

  $source=Join-Path $Project 'source.txt';'secret-source-value'|Set-Content $source
  $summary=Join-Path $Temp 'summary.json'
  Write-Json $summary ([ordered]@{responsibility='Example module';public_symbols=@('Run');entry_points=@('Run');callers=@();callees=@();side_effects=@();trust_boundaries=@();tests=@('Test-Run');documentation=@();risks=@()})
  $put=Invoke-Tool @{Action='CachePut';ProjectDir=$Project;FilePath=$source;InputJsonPath=$summary;CacheRoot=$Cache;ParserVersion='1'}
  if($put.status-ne'PUT'){throw 'Cache put failed'}
  $hit=Invoke-Tool @{Action='CacheGet';ProjectDir=$Project;FilePath=$source;CacheRoot=$Cache;ParserVersion='1'}
  if($hit.status-ne'HIT'){throw 'Cache hit failed'}
  foreach($file in Get-ChildItem $Cache -Recurse -File -Filter '*.json'){
    $text=Get-Content $file.FullName -Raw
    if($text-match'secret-source-value'){throw 'Source content leaked to cache'}
    if($text-like"*$Project*"){throw 'Project path leaked to cache'}
  }
  'changed-source-value'|Set-Content $source
  $miss=Invoke-Tool @{Action='CacheGet';ProjectDir=$Project;FilePath=$source;CacheRoot=$Cache;ParserVersion='1'}
  if($miss.status-ne'MISS'){throw 'Changed content did not miss cache'}

  $metrics=Join-Path $Temp 'metrics.json'
  Write-Json $metrics ([ordered]@{files_considered=12;files_admitted=4;files_rejected=8;retrieval_cycles=2;loaded_skills=1;estimated_skill_tokens=600;cache_hits=1;cache_misses=1;cache_invalidations=0;repeated_file_reads=0;context_budget_overrides=0;packet_references=7;input_tokens='UNAVAILABLE';output_tokens='UNAVAILABLE';fallback_discarded_tokens='UNAVAILABLE'})
  $recorded=Invoke-Tool @{Action='RecordMetrics';ProjectDir=$Project;TaskId=$task;InputJsonPath=$metrics}
  if($recorded.schema-ne'CONTEXT_METRICS_V1'){throw 'Metrics schema mismatch'}

  $valid=Invoke-Tool @{Action='ValidateTask';ProjectDir=$Project;TaskId=$task}
  if(-not$valid.valid){throw 'Task validation failed'}
  Write-Host 'PASS: context intelligence PowerShell regressions'
}finally{
  Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue
  $global:LASTEXITCODE=0
}
