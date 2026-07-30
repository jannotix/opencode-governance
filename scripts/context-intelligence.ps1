param(
  [Parameter(Mandatory)][ValidateSet('InitializeBudget','RecordCycle','SelectSkills','CacheGet','CachePut','RecordMetrics','ValidateTask')][string]$Action,
  [Parameter(Mandatory)][string]$ProjectDir,
  [string]$TaskId,
  [ValidateSet('PATCH','BOUNDED_FEATURE','MAJOR_FEATURE','EXISTING_PRODUCT_EVOLUTION','NEW_PRODUCT','HIGH_RISK_CHANGE')][string]$WorkClass,
  [int]$Cycle,
  [string]$InputJsonPath,
  [string]$CatalogPath,
  [string]$CacheRoot,
  [string]$FilePath,
  [string]$ParserVersion='1',
  [string]$SkillContext=''
)

$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major-lt7){[Console]::Error.WriteLine('POWERSHELL_7_REQUIRED');exit 64}

$Budgets=[ordered]@{
  PATCH=@(1,1,20,20)
  BOUNDED_FEATURE=@(2,2,40,40)
  MAJOR_FEATURE=@(3,3,80,80)
  EXISTING_PRODUCT_EVOLUTION=@(3,3,100,100)
  NEW_PRODUCT=@(3,3,120,120)
  HIGH_RISK_CHANGE=@(3,3,120,120)
}
$TrustRank=@{PROJECT_AUTHORITATIVE=4;PROJECT_ADVISORY=3;WORKSPACE_ADVISORY=2;EXTERNAL_UNTRUSTED=1}
$SummaryFields=@('responsibility','public_symbols','entry_points','callers','callees','side_effects','trust_boundaries','tests','documentation','risks')
$SummaryListFields=@('public_symbols','entry_points','callers','callees','side_effects','trust_boundaries','tests','documentation','risks')
$MetricFields=@('files_considered','files_admitted','files_rejected','retrieval_cycles','loaded_skills','estimated_skill_tokens','cache_hits','cache_misses','cache_invalidations','repeated_file_reads','context_budget_overrides','packet_references','input_tokens','output_tokens','fallback_discarded_tokens')
$RetrievalListFields=@('candidate_paths','admitted_paths','rejected_paths','dependency_edges','trust_boundaries','tests','context_gaps')
$StopReasons=@('REFINE','CONTEXT_SUFFICIENT','BLOCKED_CONTEXT_GAP')
$TerminalReasons=@('CONTEXT_SUFFICIENT','BLOCKED_CONTEXT_GAP')

function Get-Now {[DateTime]::UtcNow.ToString('o')}
function Get-TextHash([string]$Text){
  $bytes=[Text.Encoding]::UTF8.GetBytes($Text)
  $hash=[Security.Cryptography.SHA256]::HashData($bytes)
  [Convert]::ToHexString($hash).ToLowerInvariant()
}
function Get-FileSha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Write-JsonFile([string]$Path,[object]$Value){
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)|Out-Null
  [IO.File]::WriteAllText($Path,(($Value|ConvertTo-Json -Depth 50)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
}
function Write-JsonLine([string]$Path,[object]$Value){
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)|Out-Null
  [IO.File]::AppendAllText($Path,(($Value|ConvertTo-Json -Depth 50 -Compress)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
}
function Read-JsonFile([string]$Path){
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "INVALID_JSON_PATH: $Path"}
  try{Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}catch{throw "INVALID_JSON: $([IO.Path]::GetFileName($Path)): $($_.Exception.Message)"}
}
function Assert-TaskId([string]$Value){
  if([string]::IsNullOrWhiteSpace($Value)-or$Value-notmatch'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'){throw 'INVALID_TASK_ID: use 1-128 ASCII letters, digits, underscore or hyphen'}
}
function Get-ProjectRoot{
  if(-not(Test-Path -LiteralPath $ProjectDir -PathType Container)){throw 'INVALID_PROJECT_DIR: directory does not exist'}
  [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectDir).Path)
}
function Test-LinkLike([string]$Path){
  $item=Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if($null-eq$item){return $false}
  (($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0)
}
function Test-Inside([string]$Path,[string]$Root){
  $rootPrefix=$Root.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
  $Path-eq$Root-or$Path.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)
}
function Get-GovernancePath([string]$Root,[string[]]$Parts){
  $current=Join-Path $Root '.ai'
  foreach($part in @('.ai')+$Parts){
    if($part-ne'.ai'){$current=Join-Path $current $part}
    if(Test-Path -LiteralPath $current -ErrorAction SilentlyContinue){
      if(Test-LinkLike $current){throw 'GOVERNANCE_STATE_LINK_FORBIDDEN'}
      $resolved=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $current).Path)
      if(-not(Test-Inside $resolved $Root)){throw 'GOVERNANCE_STATE_PATH_ESCAPE'}
    }
  }
  $full=[IO.Path]::GetFullPath($current)
  if(-not(Test-Inside $full $Root)){throw 'GOVERNANCE_STATE_PATH_ESCAPE'}
  $full
}
function Get-TaskDir([string]$Root,[string]$Id){Assert-TaskId $Id;Get-GovernancePath $Root @('tasks',$Id)}
function Get-DefaultCacheRoot{
  if($env:OPENCODE_GOVERNANCE_CONTEXT_CACHE){return [IO.Path]::GetFullPath($env:OPENCODE_GOVERNANCE_CONTEXT_CACHE)}
  if($env:LOCALAPPDATA){return [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'OpenCodeGovernance/context-cache'))}
  [IO.Path]::GetFullPath((Join-Path $HOME '.cache/opencode-governance/context-cache'))
}
function Get-CacheRoot([string]$Root){
  $cache=if($CacheRoot){[IO.Path]::GetFullPath($CacheRoot)}else{Get-DefaultCacheRoot}
  $rootPrefix=$Root.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
  $cachePrefix=$cache.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
  if($cache-eq$Root-or$cache.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)-or$Root.StartsWith($cachePrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'CACHE_ROOT_OVERLAP: cache root must be outside the project'}
  $cache
}
function Get-ProjectIdentity([string]$Root){
  $identity="PROJECT_IDENTITY_V1`n$([IO.Path]::GetFullPath($Root).ToLowerInvariant())"
  if(Test-Path -LiteralPath (Join-Path $Root '.git')){$identity+="`nGIT_METADATA_PRESENT"}
  Get-TextHash $identity
}
function Assert-ExactProperties([object]$Value,[string[]]$Expected,[string]$Error){
  $actual=@($Value.PSObject.Properties.Name|Sort-Object);$wanted=@($Expected|Sort-Object)
  if(($actual-join'|')-ne($wanted-join'|')){throw $Error}
}
function Assert-StringList([object]$Value,[string]$Field,[bool]$NonEmpty=$false){
  if($null-eq$Value){throw "INVALID_STRING_LIST: $Field"}
  $items=@($Value)
  if($NonEmpty-and$items.Count-eq0){throw "EMPTY_STRING_LIST: $Field"}
  foreach($item in $items){if($item-isnot[string]-or[string]::IsNullOrWhiteSpace([string]$item)){throw "INVALID_STRING_LIST: $Field"}}
  @($items|ForEach-Object{[string]$_})
}
function Get-Budget([string]$Root,[string]$Id){
  $path=Join-Path (Get-TaskDir $Root $Id) 'CONTEXT_BUDGET.json'
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'CONTEXT_BUDGET_MISSING'}
  $budget=Read-JsonFile $path
  Assert-ExactProperties $budget @('schema','task_id','work_class','max_retrieval_cycles','max_loaded_skills','max_packet_references','max_admitted_paths','max_cycles_global','cache_namespace','cache_root_id','override_requires_reason','created_at') 'CONTEXT_BUDGET_SCHEMA_INVALID'
  if($budget.schema-ne'CONTEXT_BUDGET_V1'-or$budget.task_id-ne$Id){throw 'CONTEXT_BUDGET_SCHEMA_INVALID'}
  $budget
}
function Get-RelativeFile([string]$Root,[string]$Value){
  $candidate=if([IO.Path]::IsPathRooted($Value)){$Value}else{Join-Path $Root $Value}
  if(Test-LinkLike $candidate){throw 'FILE_LINK_FORBIDDEN'}
  if(-not(Test-Path -LiteralPath $candidate -PathType Leaf)){throw 'FILE_PATH_NOT_FOUND'}
  $full=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $candidate).Path)
  if(-not(Test-Inside $full $Root)){throw 'FILE_PATH_ESCAPE'}
  $current=Split-Path -Parent $full
  while($current-ne$Root){if(Test-LinkLike $current){throw 'FILE_LINK_FORBIDDEN'};$current=Split-Path -Parent $current}
  $relative=[IO.Path]::GetRelativePath($Root,$full).Replace('\','/')
  if($relative-eq'.ai'-or$relative.StartsWith('.ai/',[StringComparison]::OrdinalIgnoreCase)){throw 'CACHE_GOVERNANCE_STATE_FORBIDDEN'}
  [pscustomobject]@{Full=$full;Relative=$relative}
}
function Get-CacheInfo([string]$Root){
  $file=Get-RelativeFile $Root $FilePath;$cache=Get-CacheRoot $Root;$fileHash=Get-FileSha $file.Full;$projectId=Get-ProjectIdentity $Root
  $relativeHash=Get-TextHash $file.Relative;$skillHash=Get-TextHash $SkillContext
  $keyMaterial=([ordered]@{schema='CONTENT_SUMMARY_CACHE_KEY_V1';project=$projectId;relative_path_hash=$relativeHash;file_sha256=$fileHash;summary_schema='CONTENT_SUMMARY_V1';parser_version=$ParserVersion;skill_context_hash=$skillHash}|ConvertTo-Json -Compress)
  $key=Get-TextHash $keyMaterial
  [pscustomobject]@{Path=(Join-Path $cache "$projectId/entries/$key.json");Key=$key;FileHash=$fileHash;RelativeHash=$relativeHash;SkillHash=$skillHash;ParserVersion=$ParserVersion}
}
function Read-JsonLines([string]$Path){
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return @()}
  try{@(Get-Content -LiteralPath $Path|Where-Object{$_}|ForEach-Object{$_|ConvertFrom-Json})}catch{throw 'CONTEXT_RETRIEVAL_INVALID'}
}
function Test-Applicable([object]$Values,[object]$Requested){
  $left=@($Values|ForEach-Object{[string]$_});$right=@($Requested|ForEach-Object{[string]$_})
  $left.Count-eq0-or@($left|Where-Object{$_-in$right}).Count-gt0
}
function Assert-Summary([object]$Summary){
  Assert-ExactProperties $Summary $SummaryFields 'CONTENT_SUMMARY_FIELDS_INVALID'
  if([string]::IsNullOrWhiteSpace([string]$Summary.responsibility)){throw 'CONTENT_SUMMARY_FIELDS_INVALID'}
  foreach($field in $SummaryListFields){Assert-StringList $Summary.$field $field|Out-Null}
}

try{
  $Root=Get-ProjectRoot
  switch($Action){
    'InitializeBudget'{
      Assert-TaskId $TaskId
      if(-not$Budgets.Contains($WorkClass)){throw 'INVALID_WORK_CLASS'}
      $values=$Budgets[$WorkClass];$cache=Get-CacheRoot $Root
      $result=[ordered]@{schema='CONTEXT_BUDGET_V1';task_id=$TaskId;work_class=$WorkClass;max_retrieval_cycles=$values[0];max_loaded_skills=$values[1];max_packet_references=$values[2];max_admitted_paths=$values[3];max_cycles_global=3;cache_namespace=(Get-ProjectIdentity $Root);cache_root_id=(Get-TextHash $cache);override_requires_reason=$true;created_at=(Get-Now)}
      Write-JsonFile (Join-Path (Get-TaskDir $Root $TaskId) 'CONTEXT_BUDGET.json') $result
    }
    'RecordCycle'{
      $budget=Get-Budget $Root $TaskId
      if($Cycle-lt1-or$Cycle-gt[Math]::Min(3,[int]$budget.max_retrieval_cycles)){throw 'RETRIEVAL_CYCLE_LIMIT'}
      $record=Read-JsonFile $InputJsonPath
      $fields=@('query','reason')+$RetrievalListFields+@('stop_reason')
      Assert-ExactProperties $record $fields 'RETRIEVAL_RECORD_SCHEMA_INVALID'
      if([string]::IsNullOrWhiteSpace([string]$record.query)-or[string]::IsNullOrWhiteSpace([string]$record.reason)){throw 'RETRIEVAL_RECORD_INVALID'}
      foreach($field in $RetrievalListFields){if($null-eq$record.$field){throw "RETRIEVAL_RECORD_INVALID: $field"}}
      Assert-StringList $record.candidate_paths 'candidate_paths'|Out-Null
      Assert-StringList $record.admitted_paths 'admitted_paths'|Out-Null
      if([string]$record.stop_reason-notin$StopReasons){throw 'RETRIEVAL_STOP_REASON_INVALID'}
      if($record.stop_reason-eq'BLOCKED_CONTEXT_GAP'-and@($record.context_gaps).Count-eq0){throw 'BLOCKED_CONTEXT_GAP_REASON_REQUIRED'}
      if(@($record.admitted_paths).Count-gt[int]$budget.max_admitted_paths){throw 'CONTEXT_PATH_BUDGET_EXCEEDED'}
      $path=Join-Path (Get-TaskDir $Root $TaskId) 'CONTEXT_RETRIEVAL.jsonl'
      $existing=Read-JsonLines $path
      if($existing.Count-and[string]$existing[-1].stop_reason-in$TerminalReasons){throw 'RETRIEVAL_ALREADY_TERMINAL'}
      if($Cycle-ne$existing.Count+1){throw 'RETRIEVAL_CYCLE_SEQUENCE_INVALID'}
      $result=[ordered]@{schema='CONTEXT_RETRIEVAL_CYCLE_V1';task_id=$TaskId;cycle=$Cycle;recorded_at=(Get-Now);query=$record.query;reason=$record.reason;candidate_paths=@($record.candidate_paths);admitted_paths=@($record.admitted_paths);rejected_paths=@($record.rejected_paths);dependency_edges=@($record.dependency_edges);trust_boundaries=@($record.trust_boundaries);tests=@($record.tests);context_gaps=@($record.context_gaps);stop_reason=$record.stop_reason}
      Write-JsonLine $path $result
    }
    'SelectSkills'{
      $budget=Get-Budget $Root $TaskId
      $catalog=@(Read-JsonFile $CatalogPath)
      $criteria=Read-JsonFile $InputJsonPath
      Assert-ExactProperties $criteria @('triggers','languages','frameworks','required_sections','available_tools') 'SKILL_SELECTION_INPUT_INVALID'
      foreach($field in @('triggers','languages','frameworks','required_sections','available_tools')){Assert-StringList $criteria.$field $field|Out-Null}
      $available=@($criteria.available_tools|ForEach-Object{[string]$_})
      $requiredSections=@($criteria.required_sections|ForEach-Object{[string]$_}|Select-Object -Unique)
      $candidates=@();$rejected=@()
      foreach($skill in $catalog){
        Assert-ExactProperties $skill @('schema','skill_id','version','content_sha256','source','trust_class','triggers','supported_work_classes','languages','frameworks','required_tools','external_dependencies','conflicts_with','overlaps_with','estimated_context_tokens','sections') 'SKILL_MANIFEST_SCHEMA_INVALID'
        Assert-TaskId ([string]$skill.skill_id)
        if($skill.schema-ne'SKILL_CAPABILITY_MANIFEST_V1'-or-not$TrustRank.ContainsKey([string]$skill.trust_class)-or[string]$skill.content_sha256-notmatch'^[0-9a-fA-F]{64}$'){throw 'SKILL_MANIFEST_IDENTITY_INVALID'}
        foreach($field in @('triggers','supported_work_classes','languages','frameworks','required_tools','external_dependencies','conflicts_with','overlaps_with')){Assert-StringList $skill.$field $field|Out-Null}
        if(@($skill.supported_work_classes|Where-Object{$_-notin$Budgets.Keys}).Count){throw 'SKILL_WORK_CLASS_INVALID'}
        $tokenEstimateValue=$skill.estimated_context_tokens
        if(($tokenEstimateValue-isnot[int]-and$tokenEstimateValue-isnot[long])-or[long]$tokenEstimateValue-lt0-or[long]$tokenEstimateValue-gt[int]::MaxValue){throw 'SKILL_TOKEN_ESTIMATE_INVALID'}
        $tokenEstimate=[int]$tokenEstimateValue
        $sectionIds=@()
        foreach($section in @($skill.sections)){
          Assert-ExactProperties $section @('id','heading') 'SKILL_SECTIONS_INVALID'
          if([string]::IsNullOrWhiteSpace([string]$section.id)){throw 'SKILL_SECTIONS_INVALID'}
          $sectionIds+=[string]$section.id
        }
        if(($sectionIds|Select-Object -Unique).Count-ne$sectionIds.Count){throw 'SKILL_SECTIONS_INVALID'}
        $id=[string]$skill.skill_id;$reason=$null
        if(@($skill.supported_work_classes).Count-and[string]$budget.work_class-notin@($skill.supported_work_classes)){$reason='WORK_CLASS_NOT_APPLICABLE'}
        elseif(-not(Test-Applicable $skill.triggers $criteria.triggers)){$reason='TRIGGER_NOT_APPLICABLE'}
        elseif(-not(Test-Applicable $skill.languages $criteria.languages)){$reason='LANGUAGE_NOT_APPLICABLE'}
        elseif(-not(Test-Applicable $skill.frameworks $criteria.frameworks)){$reason='FRAMEWORK_NOT_APPLICABLE'}
        elseif(@($skill.external_dependencies).Count){$reason='EXTERNAL_DEPENDENCY_UNAVAILABLE'}
        elseif(@($skill.required_tools|Where-Object{$_-notin$available}).Count){$reason='REQUIRED_TOOL_UNAVAILABLE'}
        elseif($sectionIds.Count-and@($requiredSections|Where-Object{$_-notin$sectionIds}).Count){$reason='REQUIRED_SECTION_UNAVAILABLE'}
        if($reason){$rejected+=[ordered]@{skill_id=$id;reason=$reason}}else{$candidates+=$skill}
      }
      $candidates=@($candidates|Sort-Object @{Expression={-$TrustRank[[string]$_.trust_class]}},@{Expression={[int]$_.estimated_context_tokens}},@{Expression={[string]$_.skill_id}})
      $selectedInternal=@();$selectedPublic=@()
      foreach($skill in $candidates){
        $id=[string]$skill.skill_id
        if($selectedInternal.Count-ge[int]$budget.max_loaded_skills){$rejected+=[ordered]@{skill_id=$id;reason='SKILL_BUDGET_EXCEEDED'};continue}
        $selectedIds=@($selectedInternal|ForEach-Object{[string]$_.skill_id})
        $conflict=@($selectedIds|Where-Object{$_-in@($skill.conflicts_with)}).Count-or@($selectedInternal|Where-Object{$id-in@($_.conflicts_with)}).Count
        $overlap=@($selectedIds|Where-Object{$_-in@($skill.overlaps_with)}).Count-or@($selectedInternal|Where-Object{$id-in@($_.overlaps_with)}).Count
        if($conflict){$rejected+=[ordered]@{skill_id=$id;reason='SKILL_CONFLICT'};continue}
        if($overlap){$rejected+=[ordered]@{skill_id=$id;reason='OVERLAP_DEDUPLICATED'};continue}
        $selectedInternal+=$skill
        $sectionIds=@($skill.sections|ForEach-Object{[string]$_.id})
        $sections=if($sectionIds.Count-and$requiredSections.Count){$requiredSections}elseif(-not$sectionIds.Count){@('FULL')}else{@($sectionIds|Sort-Object)}
        $selectedPublic+=[ordered]@{skill_id=$id;version=[string]$skill.version;content_sha256=([string]$skill.content_sha256).ToLowerInvariant();source=[string]$skill.source;trust_class=[string]$skill.trust_class;estimated_context_tokens=$tokenEstimate;sections=@($sections);selection_reason='HIGHEST_TRUST_NARROW_APPLICABLE_CAPABILITY'}
      }
      $result=[ordered]@{schema='SKILL_SELECTION_V1';task_id=$TaskId;work_class=[string]$budget.work_class;max_loaded_skills=[int]$budget.max_loaded_skills;selected=@($selectedPublic);rejected=@($rejected|Sort-Object skill_id);selected_at=(Get-Now)}
      Write-JsonFile (Join-Path (Get-TaskDir $Root $TaskId) 'SKILL_SELECTION.json') $result
    }
    'CachePut'{
      $info=Get-CacheInfo $Root
      $summary=Read-JsonFile $InputJsonPath
      Assert-Summary $summary
      Write-JsonFile $info.Path ([ordered]@{schema='CONTENT_SUMMARY_CACHE_ENTRY_V1';file_sha256=$info.FileHash;relative_path_hash=$info.RelativeHash;parser_version=$info.ParserVersion;skill_context_hash=$info.SkillHash;summary=$summary;stored_at=(Get-Now)})
      $result=[ordered]@{schema='CONTENT_SUMMARY_CACHE_RESULT_V1';status='PUT';cache_key=$info.Key;file_sha256=$info.FileHash}
    }
    'CacheGet'{
      $info=Get-CacheInfo $Root
      if(-not(Test-Path -LiteralPath $info.Path -PathType Leaf)){
        $result=[ordered]@{schema='CONTENT_SUMMARY_CACHE_RESULT_V1';status='MISS';file_sha256=$info.FileHash}
      }else{
        try{
          $entry=Read-JsonFile $info.Path
          Assert-ExactProperties $entry @('schema','file_sha256','relative_path_hash','parser_version','skill_context_hash','summary','stored_at') 'CACHE_ENTRY_INVALID'
          Assert-Summary $entry.summary
          if($entry.schema-ne'CONTENT_SUMMARY_CACHE_ENTRY_V1'-or$entry.file_sha256-ne$info.FileHash-or$entry.relative_path_hash-ne$info.RelativeHash-or$entry.parser_version-ne$info.ParserVersion-or$entry.skill_context_hash-ne$info.SkillHash){throw 'CACHE_ENTRY_INVALID'}
          $result=[ordered]@{schema='CONTENT_SUMMARY_CACHE_RESULT_V1';status='HIT';file_sha256=$info.FileHash;summary=$entry.summary}
        }catch{
          $result=[ordered]@{schema='CONTENT_SUMMARY_CACHE_RESULT_V1';status='MISS';file_sha256=$info.FileHash;reason='CACHE_INVALID'}
        }
      }
    }
    'RecordMetrics'{
      Assert-TaskId $TaskId
      $metrics=Read-JsonFile $InputJsonPath
      Assert-ExactProperties $metrics $MetricFields 'CONTEXT_METRICS_FIELDS_INVALID'
      foreach($field in $MetricFields){
        $value=$metrics.$field
        if($field-like'*tokens'-and$value-eq'UNAVAILABLE'){continue}
        if($value-isnot[int]-and$value-isnot[long]){throw "CONTEXT_METRIC_INVALID: $field"}
        if([long]$value-lt0){throw "CONTEXT_METRIC_INVALID: $field"}
      }
      $result=[ordered]@{schema='CONTEXT_METRICS_V1';task_id=$TaskId;recorded_at=(Get-Now)}
      foreach($field in $MetricFields){$result[$field]=$metrics.$field}
      Write-JsonLine (Get-GovernancePath $Root @('metrics','CONTEXT_METRICS.jsonl')) $result
      Write-JsonLine (Join-Path (Get-TaskDir $Root $TaskId) 'CONTEXT_METRICS.jsonl') $result
    }
    'ValidateTask'{
      $budget=Get-Budget $Root $TaskId
      $task=Get-TaskDir $Root $TaskId
      $errors=@();$cycles=@()
      try{$cycles=Read-JsonLines (Join-Path $task 'CONTEXT_RETRIEVAL.jsonl')}catch{$errors+='CONTEXT_RETRIEVAL_INVALID'}
      if($cycles.Count-gt[Math]::Min(3,[int]$budget.max_retrieval_cycles)){$errors+='RETRIEVAL_CYCLE_LIMIT'}
      for($i=0;$i-lt$cycles.Count;$i++){
        $item=$cycles[$i]
        if([int]$item.cycle-ne$i+1){$errors+='RETRIEVAL_CYCLE_SEQUENCE_INVALID'}
        if($item.schema-ne'CONTEXT_RETRIEVAL_CYCLE_V1'-or$item.task_id-ne$TaskId-or[string]$item.stop_reason-notin$StopReasons){$errors+='CONTEXT_RETRIEVAL_SCHEMA_INVALID'}
        if(@($item.admitted_paths).Count-gt[int]$budget.max_admitted_paths){$errors+='CONTEXT_PATH_BUDGET_EXCEEDED'}
        if($i-lt$cycles.Count-1-and[string]$item.stop_reason-in$TerminalReasons){$errors+='RETRIEVAL_ALREADY_TERMINAL'}
      }
      if($cycles.Count-eq0-or[string]$cycles[-1].stop_reason-notin$TerminalReasons){$errors+='TERMINAL_STATE_REQUIRED'}elseif($cycles[-1].stop_reason-eq'BLOCKED_CONTEXT_GAP'){$errors+='BLOCKED_CONTEXT_GAP'}
      $selectionPath=Join-Path $task 'SKILL_SELECTION.json'
      if(Test-Path -LiteralPath $selectionPath -PathType Leaf){
        $selection=Read-JsonFile $selectionPath
        if($selection.schema-ne'SKILL_SELECTION_V1'-or$selection.task_id-ne$TaskId-or$selection.work_class-ne$budget.work_class){$errors+='SKILL_SELECTION_SCHEMA_INVALID'}
        elseif(@($selection.selected).Count-gt[int]$budget.max_loaded_skills){$errors+='SKILL_BUDGET_EXCEEDED'}
        elseif(@($selection.selected|Where-Object{@($_.sections).Count-eq0}).Count){$errors+='SKILL_SECTION_SELECTION_REQUIRED'}
      }
      $result=[ordered]@{schema='CONTEXT_TASK_VALIDATION_V1';task_id=$TaskId;valid=($errors.Count-eq0);errors=@($errors|Sort-Object -Unique)}
    }
  }
  $result|ConvertTo-Json -Depth 50 -Compress
  $global:LASTEXITCODE=0
  exit 0
}catch{
  [Console]::Error.WriteLine($_.Exception.Message)
  $global:LASTEXITCODE=2
  exit 2
}
