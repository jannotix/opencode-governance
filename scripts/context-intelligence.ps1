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
$MetricFields=@('files_considered','files_admitted','files_rejected','retrieval_cycles','loaded_skills','estimated_skill_tokens','cache_hits','cache_misses','cache_invalidations','repeated_file_reads','context_budget_overrides','packet_references','input_tokens','output_tokens','fallback_discarded_tokens')

function Get-Now {[DateTime]::UtcNow.ToString('o')}
function Get-TextHash([string]$Text){
  $bytes=[Text.Encoding]::UTF8.GetBytes($Text)
  $hash=[Security.Cryptography.SHA256]::HashData($bytes)
  return [Convert]::ToHexString($hash).ToLowerInvariant()
}
function Get-FileSha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Write-JsonFile([string]$Path,[object]$Value){
  $parent=Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $parent|Out-Null
  [IO.File]::WriteAllText($Path,(($Value|ConvertTo-Json -Depth 40)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
}
function Write-JsonLine([string]$Path,[object]$Value){
  $parent=Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $parent|Out-Null
  [IO.File]::AppendAllText($Path,(($Value|ConvertTo-Json -Depth 40 -Compress)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
}
function Read-JsonFile([string]$Path){
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "INVALID_JSON_PATH: $Path"}
  try{return Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}catch{throw "INVALID_JSON: $([IO.Path]::GetFileName($Path)): $($_.Exception.Message)"}
}
function Assert-TaskId([string]$Value){
  if([string]::IsNullOrWhiteSpace($Value)-or$Value-notmatch'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'){throw 'INVALID_TASK_ID: use 1-128 ASCII letters, digits, underscore or hyphen'}
}
function Get-ProjectRoot{
  if(-not(Test-Path -LiteralPath $ProjectDir -PathType Container)){throw 'INVALID_PROJECT_DIR: directory does not exist'}
  return [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectDir).Path)
}
function Get-TaskDir([string]$Root,[string]$Id){
  Assert-TaskId $Id
  $base=[IO.Path]::GetFullPath((Join-Path $Root '.ai/tasks'))
  $target=[IO.Path]::GetFullPath((Join-Path $base $Id))
  if([IO.Path]::GetDirectoryName($target)-ne$base){throw 'TASK_PATH_ESCAPE'}
  return $target
}
function Get-DefaultCacheRoot{
  if($env:OPENCODE_GOVERNANCE_CONTEXT_CACHE){return [IO.Path]::GetFullPath($env:OPENCODE_GOVERNANCE_CONTEXT_CACHE)}
  if($env:LOCALAPPDATA){return [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'OpenCodeGovernance/context-cache'))}
  return [IO.Path]::GetFullPath((Join-Path $HOME '.cache/opencode-governance/context-cache'))
}
function Get-CacheRoot([string]$Root){
  $cache=if($CacheRoot){[IO.Path]::GetFullPath($CacheRoot)}else{Get-DefaultCacheRoot}
  $rootPrefix=$Root.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
  $cachePrefix=$cache.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
  if($cache-eq$Root-or$cache.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)-or$Root.StartsWith($cachePrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'CACHE_ROOT_OVERLAP: cache root must be outside the project'}
  return $cache
}
function Get-ProjectIdentity([string]$Root){
  $identity="PROJECT_IDENTITY_V1`n$([IO.Path]::GetFullPath($Root).ToLowerInvariant())"
  if(Test-Path -LiteralPath (Join-Path $Root '.git')){$identity+="`nGIT_METADATA_PRESENT"}
  return Get-TextHash $identity
}
function Get-Budget([string]$Root,[string]$Id){
  $path=Join-Path (Get-TaskDir $Root $Id) 'CONTEXT_BUDGET.json'
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'CONTEXT_BUDGET_MISSING'}
  $budget=Read-JsonFile $path
  if($budget.schema-ne'CONTEXT_BUDGET_V1'){throw 'CONTEXT_BUDGET_SCHEMA_INVALID'}
  return $budget
}
function Get-RelativeFile([string]$Root,[string]$Value){
  if(-not(Test-Path -LiteralPath $Value -PathType Leaf)){throw 'FILE_PATH_NOT_FOUND'}
  $full=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Value).Path)
  $prefix=$Root.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
  if(-not$full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'FILE_PATH_ESCAPE'}
  $relative=[IO.Path]::GetRelativePath($Root,$full).Replace('\','/')
  if($relative-eq'.ai'-or$relative.StartsWith('.ai/',[StringComparison]::OrdinalIgnoreCase)){throw 'CACHE_GOVERNANCE_STATE_FORBIDDEN'}
  return [pscustomobject]@{Full=$full;Relative=$relative}
}
function Get-CacheInfo([string]$Root){
  $file=Get-RelativeFile $Root $FilePath
  $cache=Get-CacheRoot $Root
  $fileHash=Get-FileSha $file.Full
  $projectId=Get-ProjectIdentity $Root
  $relativeHash=Get-TextHash $file.Relative
  $skillHash=Get-TextHash $SkillContext
  $keyMaterial=([ordered]@{schema='CONTENT_SUMMARY_CACHE_KEY_V1';project=$projectId;relative_path_hash=$relativeHash;file_sha256=$fileHash;summary_schema='CONTENT_SUMMARY_V1';parser_version=$ParserVersion;skill_context_hash=$skillHash}|ConvertTo-Json -Compress)
  $key=Get-TextHash $keyMaterial
  return [pscustomobject]@{Path=(Join-Path $cache "$projectId/entries/$key.json");Key=$key;FileHash=$fileHash;RelativeHash=$relativeHash;SkillHash=$skillHash}
}
function Assert-ExactProperties([object]$Value,[string[]]$Expected,[string]$Error){
  $actual=@($Value.PSObject.Properties.Name|Sort-Object)
  $wanted=@($Expected|Sort-Object)
  if(($actual-join'|')-ne($wanted-join'|')){throw $Error}
}
function Convert-ToStringArray([object]$Value){return @($Value|ForEach-Object{[string]$_})}

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
      $fields=@('query','reason','candidate_paths','admitted_paths','rejected_paths','dependency_edges','trust_boundaries','tests','context_gaps','stop_reason')
      Assert-ExactProperties $record $fields 'RETRIEVAL_RECORD_SCHEMA_INVALID'
      if(@($record.admitted_paths).Count-gt[int]$budget.max_admitted_paths){throw 'CONTEXT_PATH_BUDGET_EXCEEDED'}
      $path=Join-Path (Get-TaskDir $Root $TaskId) 'CONTEXT_RETRIEVAL.jsonl'
      $existing=if(Test-Path $path){@((Get-Content $path|Where-Object{$_})|ForEach-Object{$_|ConvertFrom-Json})}else{@()}
      if($Cycle-ne$existing.Count+1){throw 'RETRIEVAL_CYCLE_SEQUENCE_INVALID'}
      $result=[ordered]@{schema='CONTEXT_RETRIEVAL_CYCLE_V1';task_id=$TaskId;cycle=$Cycle;recorded_at=(Get-Now);query=$record.query;reason=$record.reason;candidate_paths=@($record.candidate_paths);admitted_paths=@($record.admitted_paths);rejected_paths=@($record.rejected_paths);dependency_edges=@($record.dependency_edges);trust_boundaries=@($record.trust_boundaries);tests=@($record.tests);context_gaps=@($record.context_gaps);stop_reason=$record.stop_reason}
      Write-JsonLine $path $result
    }
    'SelectSkills'{
      $budget=Get-Budget $Root $TaskId
      $catalog=@(Read-JsonFile $CatalogPath);$criteria=Read-JsonFile $InputJsonPath
      Assert-ExactProperties $criteria @('triggers','languages','frameworks','required_sections','available_tools') 'SKILL_SELECTION_CRITERIA_INVALID'
      $available=Convert-ToStringArray $criteria.available_tools
      $candidates=@();$rejected=@()
      foreach($skill in $catalog){
        Assert-ExactProperties $skill @('schema','skill_id','version','content_sha256','source','trust_class','triggers','supported_work_classes','languages','frameworks','required_tools','external_dependencies','conflicts_with','overlaps_with','estimated_context_tokens','sections') 'SKILL_MANIFEST_FIELDS_INVALID'
        if($skill.schema-ne'SKILL_CAPABILITY_MANIFEST_V1'){throw 'SKILL_MANIFEST_SCHEMA_INVALID'}
        if(-not$TrustRank.ContainsKey([string]$skill.trust_class)){throw 'SKILL_TRUST_CLASS_INVALID'}
        $id=[string]$skill.skill_id;$reason=$null
        if(@($skill.supported_work_classes).Count-and([string]$budget.work_class-notin(Convert-ToStringArray $skill.supported_work_classes))){$reason='WORK_CLASS_NOT_APPLICABLE'}
        elseif(@($skill.triggers).Count-and-not(@(Convert-ToStringArray $skill.triggers|Where-Object{$_-in(Convert-ToStringArray $criteria.triggers)}).Count)){$reason='TRIGGER_NOT_APPLICABLE'}
        elseif(@($skill.languages).Count-and-not(@(Convert-ToStringArray $skill.languages|Where-Object{$_-in(Convert-ToStringArray $criteria.languages)}).Count)){$reason='LANGUAGE_NOT_APPLICABLE'}
        elseif(@($skill.frameworks).Count-and-not(@(Convert-ToStringArray $skill.frameworks|Where-Object{$_-in(Convert-ToStringArray $criteria.frameworks)}).Count)){$reason='FRAMEWORK_NOT_APPLICABLE'}
        elseif(@($skill.external_dependencies).Count){$reason='EXTERNAL_DEPENDENCY_UNAVAILABLE'}
        elseif(@(Convert-ToStringArray $skill.required_tools|Where-Object{$_-notin$available}).Count){$reason='REQUIRED_TOOL_UNAVAILABLE'}
        if($reason){$rejected+=[ordered]@{skill_id=$id;reason=$reason}}else{$candidates+=$skill}
      }
      $candidates=@($candidates|Sort-Object @{Expression={-$TrustRank[[string]$_.trust_class]}},@{Expression={[int]$_.estimated_context_tokens}},@{Expression={[string]$_.skill_id}})
      $selected=@()
      foreach($skill in $candidates){
        $id=[string]$skill.skill_id
        if($selected.Count-ge[int]$budget.max_loaded_skills){$rejected+=[ordered]@{skill_id=$id;reason='SKILL_BUDGET_EXCEEDED'};continue}
        $selectedIds=@($selected.skill_id)
        $conflict=@($selectedIds|Where-Object{$_-in(Convert-ToStringArray $skill.conflicts_with)}).Count-or@($selected|Where-Object{$id-in(Convert-ToStringArray $_.conflicts_with)}).Count
        $overlap=@($selectedIds|Where-Object{$_-in(Convert-ToStringArray $skill.overlaps_with)}).Count-or@($selected|Where-Object{$id-in(Convert-ToStringArray $_.overlaps_with)}).Count
        if($conflict){$rejected+=[ordered]@{skill_id=$id;reason='SKILL_CONFLICT'};continue}
        if($overlap){$rejected+=[ordered]@{skill_id=$id;reason='OVERLAP_DEDUPLICATED'};continue}
        $sectionIds=@($skill.sections|ForEach-Object{[string]$_.id})
        $sections=if($sectionIds.Count){@(Convert-ToStringArray $criteria.required_sections|Where-Object{$_-in$sectionIds})}else{@('FULL')}
        $selected+=[ordered]@{skill_id=$id;version=[string]$skill.version;content_sha256=([string]$skill.content_sha256).ToLowerInvariant();source=[string]$skill.source;trust_class=[string]$skill.trust_class;estimated_context_tokens=[int]$skill.estimated_context_tokens;sections=$sections;selection_reason='HIGHEST_TRUST_NARROW_APPLICABLE_CAPABILITY';overlaps_with=@($skill.overlaps_with);conflicts_with=@($skill.conflicts_with)}
      }
      $publicSelected=@($selected|ForEach-Object{[ordered]@{skill_id=$_.skill_id;version=$_.version;content_sha256=$_.content_sha256;source=$_.source;trust_class=$_.trust_class;estimated_context_tokens=$_.estimated_context_tokens;sections=$_.sections;selection_reason=$_.selection_reason}})
      $result=[ordered]@{schema='SKILL_SELECTION_V1';task_id=$TaskId;work_class=[string]$budget.work_class;max_loaded_skills=[int]$budget.max_loaded_skills;selected=$publicSelected;rejected=@($rejected|Sort-Object skill_id);selected_at=(Get-Now)}
      Write-JsonFile (Join-Path (Get-TaskDir $Root $TaskId) 'SKILL_SELECTION.json') $result
    }
    'CachePut'{
      $info=Get-CacheInfo $Root;$summary=Read-JsonFile $InputJsonPath
      Assert-ExactProperties $summary $SummaryFields 'CONTENT_SUMMARY_FIELDS_INVALID'
      $result=[ordered]@{schema='CONTENT_SUMMARY_CACHE_ENTRY_V1';file_sha256=$info.FileHash;relative_path_hash=$info.RelativeHash;parser_version=$ParserVersion;skill_context_hash=$info.SkillHash;summary=$summary;stored_at=(Get-Now)}
      Write-JsonFile $info.Path $result
      $result=[ordered]@{schema='CONTENT_SUMMARY_CACHE_RESULT_V1';status='PUT';cache_key=$info.Key;file_sha256=$info.FileHash}
    }
    'CacheGet'{
      $info=Get-CacheInfo $Root
      if(-not(Test-Path -LiteralPath $info.Path -PathType Leaf)){$result=[ordered]@{schema='CONTENT_SUMMARY_CACHE_RESULT_V1';status='MISS';file_sha256=$info.FileHash}}
      else{
        try{$entry=Read-JsonFile $info.Path;Assert-ExactProperties $entry.summary $SummaryFields 'CACHE_ENTRY_INVALID';if($entry.schema-ne'CONTENT_SUMMARY_CACHE_ENTRY_V1'-or$entry.file_sha256-ne$info.FileHash){throw 'CACHE_ENTRY_INVALID'};$result=[ordered]@{schema='CONTENT_SUMMARY_CACHE_RESULT_V1';status='HIT';file_sha256=$info.FileHash;summary=$entry.summary}}
        catch{$result=[ordered]@{schema='CONTENT_SUMMARY_CACHE_RESULT_V1';status='MISS';file_sha256=$info.FileHash;reason='CACHE_INVALID'}}
      }
    }
    'RecordMetrics'{
      Assert-TaskId $TaskId;$metrics=Read-JsonFile $InputJsonPath
      Assert-ExactProperties $metrics $MetricFields 'CONTEXT_METRICS_FIELDS_INVALID'
      foreach($field in $MetricFields){$value=$metrics.$field;if($field-like'*tokens'-and$value-eq'UNAVAILABLE'){continue};if($value-isnot[int]-and$value-isnot[long]){throw "CONTEXT_METRIC_INVALID: $field"};if([long]$value-lt0){throw "CONTEXT_METRIC_INVALID: $field"}}
      $result=[ordered]@{schema='CONTEXT_METRICS_V1';task_id=$TaskId;recorded_at=(Get-Now)};foreach($field in $MetricFields){$result[$field]=$metrics.$field}
      Write-JsonLine (Join-Path $Root '.ai/metrics/CONTEXT_METRICS.jsonl') $result
      Write-JsonLine (Join-Path (Get-TaskDir $Root $TaskId) 'CONTEXT_METRICS.jsonl') $result
    }
    'ValidateTask'{
      $budget=Get-Budget $Root $TaskId;$task=Get-TaskDir $Root $TaskId;$errors=@();$path=Join-Path $task 'CONTEXT_RETRIEVAL.jsonl';$cycles=@()
      if(Test-Path $path){try{$cycles=@((Get-Content $path|Where-Object{$_})|ForEach-Object{$_|ConvertFrom-Json})}catch{$errors+='CONTEXT_RETRIEVAL_INVALID'}}
      if($cycles.Count-gt[Math]::Min(3,[int]$budget.max_retrieval_cycles)){$errors+='RETRIEVAL_CYCLE_LIMIT'}
      for($i=0;$i-lt$cycles.Count;$i++){if([int]$cycles[$i].cycle-ne$i+1){$errors+='RETRIEVAL_CYCLE_SEQUENCE_INVALID';break}}
      $selectionPath=Join-Path $task 'SKILL_SELECTION.json';if(Test-Path $selectionPath){$selection=Read-JsonFile $selectionPath;if(@($selection.selected).Count-gt[int]$budget.max_loaded_skills){$errors+='SKILL_BUDGET_EXCEEDED'}}
      $result=[ordered]@{schema='CONTEXT_TASK_VALIDATION_V1';task_id=$TaskId;valid=($errors.Count-eq0);errors=$errors}
    }
  }
  $result|ConvertTo-Json -Depth 40 -Compress
  $global:LASTEXITCODE=0
  exit 0
}catch{
  [Console]::Error.WriteLine($_.Exception.Message)
  $global:LASTEXITCODE=2
  exit 2
}
