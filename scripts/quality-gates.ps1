param(
  [Parameter(Mandatory)][ValidateSet('InitializeProfile','ValidateDebug','ValidateTdd','ValidateEval','RecordSelfCheck','AddLearning','PromoteLearning','ValidateTask')][string]$Action,
  [Parameter(Mandatory)][string]$ProjectDir,
  [string]$TaskId,
  [ValidateSet('PATCH','BOUNDED_FEATURE','MAJOR_FEATURE','EXISTING_PRODUCT_EVOLUTION','NEW_PRODUCT','HIGH_RISK_CHANGE')][string]$WorkClass,
  [ValidateSet('BUGFIX','FEATURE','REFACTOR','DOCS','CONFIG','GENERATED','SPIKE')][string]$TaskKind,
  [string]$Risks='',
  [string]$InputJsonPath
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major-lt7){[Console]::Error.WriteLine('POWERSHELL_7_REQUIRED');exit 64}

$MandatoryTdd=@('SECURITY','AUTHORIZATION','ROUTING','PARSER','DATA_MIGRATION','PUBLIC_CONTRACT','HIGH_RISK')
$Exceptions=@('DOCUMENTATION_ONLY','GENERATED_ARTIFACT','ENVIRONMENT_CONFIGURATION_ONLY','NO_EXECUTABLE_HARNESS','NON_PROMOTABLE_SPIKE')
$LearningSources=@('USER_CORRECTION','FAILED_TASK','REVIEW_FINDING','SUCCESSFUL_PATTERN')
$DefectClasses=@('APPLICATION_DEFECT','ENVIRONMENT_DEFECT','GOVERNANCE_DEFECT')
$Graders=@('CODE_BASED','MODEL_BASED','HUMAN','HYBRID')

function Now {[DateTime]::UtcNow.ToString('o')}
function Root {
  if(-not(Test-Path -LiteralPath $ProjectDir -PathType Container)){throw 'INVALID_PROJECT_DIR'}
  [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectDir).Path)
}
function Assert-Id([string]$Value,[string]$Error='INVALID_TASK_ID'){
  if([string]::IsNullOrWhiteSpace($Value)-or$Value-notmatch'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'){throw $Error}
}
function TaskDir([string]$Root,[string]$Id){
  Assert-Id $Id
  $base=[IO.Path]::GetFullPath((Join-Path $Root '.ai/tasks'));$target=[IO.Path]::GetFullPath((Join-Path $base $Id))
  if([IO.Path]::GetDirectoryName($target)-ne$base){throw 'TASK_PATH_ESCAPE'}
  $target
}
function Read-Json([string]$Path){
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'INVALID_JSON_PATH'}
  try{Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}catch{throw "INVALID_JSON: $($_.Exception.Message)"}
}
function Write-Json([string]$Path,[object]$Value){
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)|Out-Null
  [IO.File]::WriteAllText($Path,(($Value|ConvertTo-Json -Depth 40)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
}
function Append-Json([string]$Path,[object]$Value){
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)|Out-Null
  [IO.File]::AppendAllText($Path,(($Value|ConvertTo-Json -Depth 40 -Compress)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
}
function Assert-Fields([object]$Value,[string[]]$Expected,[string]$Error){
  $actual=@($Value.PSObject.Properties.Name|Sort-Object);$wanted=@($Expected|Sort-Object)
  if(($actual-join'|')-ne($wanted-join'|')){throw $Error}
}
function Strings([object]$Value,[string]$Field,[bool]$AllowEmpty=$true){
  $items=@($Value);if((-not$AllowEmpty-and$items.Count-eq0)-or@($items|Where-Object{$_-isnot[string]-or[string]::IsNullOrWhiteSpace([string]$_)}).Count){throw "INVALID_STRING_LIST: $Field"};$items
}
function Profile([string]$Root,[string]$Id){
  $path=Join-Path (TaskDir $Root $Id) 'QUALITY_PROFILE.json';if(-not(Test-Path $path)){throw 'QUALITY_PROFILE_MISSING'}
  $value=Read-Json $path;if($value.schema-ne'QUALITY_PROFILE_V1'){throw 'QUALITY_PROFILE_INVALID'};$value
}
function Emit([object]$Value,[int]$Code=0){$Value|ConvertTo-Json -Depth 40 -Compress;$global:LASTEXITCODE=$Code;exit $Code}
function Save-Gate([string]$Root,[string]$Id,[string]$Name,[object]$Value){
  Write-Json (Join-Path (TaskDir $Root $Id) $Name) $Value
  $blocked=@('BLOCKED','ARCHITECTURE_REVIEW_REQUIRED','EVAL_GATE_FAILED','NOT_READY_FOR_REVIEW','EXCEPTION_REQUIRES_FINAL_REVIEW')
  Emit $Value $(if($Value.status-in$blocked){3}else{0})
}
function LearningPaths([string]$Root){[pscustomobject]@{Candidates=(Join-Path $Root '.ai/learning/CANDIDATES.jsonl');Promotions=(Join-Path $Root '.ai/learning/PROMOTIONS.jsonl')}}
function JsonLines([string]$Path){if(-not(Test-Path $Path)){return @()};try{@(Get-Content $Path|Where-Object{$_}|ForEach-Object{$_|ConvertFrom-Json})}catch{throw "INVALID_JSONL: $([IO.Path]::GetFileName($Path))"}}

try{
  $R=Root
  switch($Action){
    'InitializeProfile'{
      Assert-Id $TaskId
      $risk=@($Risks.Split(',',[StringSplitOptions]::RemoveEmptyEntries)|ForEach-Object{$_.Trim().ToUpperInvariant()}|Sort-Object -Unique)
      $debug=$TaskKind-eq'BUGFIX'
      $tdd=$TaskKind-in@('BUGFIX','FEATURE','REFACTOR')-or$WorkClass-eq'HIGH_RISK_CHANGE'-or@($risk|Where-Object{$_-in$MandatoryTdd}).Count-gt0
      $eval='AI_SYSTEM'-in$risk
      $result=[ordered]@{schema='QUALITY_PROFILE_V1';task_id=$TaskId;work_class=$WorkClass;task_kind=$TaskKind;risks=$risk;debug_first_required=$debug;tdd_required=$tdd;eval_required=$eval;self_check_required=$true;learning_capture_enabled=($TaskKind-ne'SPIKE');required_reliability_mode=$(if($eval){'PASS_K'}else{'NOT_APPLICABLE'});allowed_exception_classes=$Exceptions;created_at=(Now)}
      Write-Json (Join-Path (TaskDir $R $TaskId) 'QUALITY_PROFILE.json') $result;Emit $result
    }
    'ValidateDebug'{
      $profile=Profile $R $TaskId;$v=Read-Json $InputJsonPath
      Assert-Fields $v @('symptom','reproduction_status','root_cause_status','root_cause_evidence','hypothesis','minimal_experiment','disproving_condition','hypothesis_attempts','defect_class') 'DEBUG_PROOF_FIELDS_INVALID'
      if($v.reproduction_status-notin@('REPRODUCED','EQUIVALENT_PROOF','BLOCKED')-or$v.root_cause_status-notin@('CONFIRMED','HYPOTHESIS','BLOCKED')-or$v.defect_class-notin$DefectClasses){throw 'DEBUG_PROOF_ENUM_INVALID'}
      Strings $v.root_cause_evidence 'root_cause_evidence'|Out-Null;$errors=@()
      if($profile.debug_first_required){
        if($v.reproduction_status-notin@('REPRODUCED','EQUIVALENT_PROOF')){$errors+='REPRODUCTION_REQUIRED'}
        if($v.root_cause_status-ne'CONFIRMED'){$errors+='ROOT_CAUSE_CONFIRMATION_REQUIRED'}
        if(@($v.root_cause_evidence).Count-eq0){$errors+='ROOT_CAUSE_EVIDENCE_REQUIRED'}
        foreach($field in 'symptom','hypothesis','minimal_experiment','disproving_condition'){if([string]::IsNullOrWhiteSpace([string]$v.$field)){$errors+=$field.ToUpperInvariant()+'_REQUIRED'}}
      }
      $architecture=[int]$v.hypothesis_attempts-ge3-and$v.root_cause_status-ne'CONFIRMED'
      $status=if($architecture){'ARCHITECTURE_REVIEW_REQUIRED'}elseif($errors.Count){'BLOCKED'}elseif($profile.debug_first_required){'PASS'}else{'NOT_REQUIRED'}
      $result=[ordered]@{schema='DEBUG_PROOF_V1';task_id=$TaskId;symptom=$v.symptom;reproduction_status=$v.reproduction_status;root_cause_status=$v.root_cause_status;root_cause_evidence=@($v.root_cause_evidence);hypothesis=$v.hypothesis;minimal_experiment=$v.minimal_experiment;disproving_condition=$v.disproving_condition;hypothesis_attempts=[int]$v.hypothesis_attempts;defect_class=$v.defect_class;architecture_review_required=$architecture;errors=@($errors|Sort-Object -Unique);status=$status;validated_at=(Now)}
      Save-Gate $R $TaskId 'DEBUG_PROOF.json' $result
    }
    'ValidateTdd'{
      $profile=Profile $R $TaskId;$v=Read-Json $InputJsonPath
      $fields=@('red_command','red_exit_code','red_expected_failure','red_observed_failure','red_evidence_refs','green_command','green_exit_code','green_evidence_refs','regression_command','regression_exit_code','regression_evidence_refs','exception_class','exception_reason','equivalent_verification')
      Assert-Fields $v $fields 'TDD_PROOF_FIELDS_INVALID';$errors=@();$exception=$v.exception_class
      if($null-ne$exception){
        if($exception-notin$Exceptions){$errors+='TDD_EXCEPTION_INVALID'}
        if([string]::IsNullOrWhiteSpace([string]$v.exception_reason)-or[string]::IsNullOrWhiteSpace([string]$v.equivalent_verification)){$errors+='TDD_EXCEPTION_EVIDENCE_REQUIRED'}
        $status=if($errors.Count){'BLOCKED'}elseif($profile.tdd_required){'EXCEPTION_REQUIRES_FINAL_REVIEW'}else{'NOT_REQUIRED'}
      }else{
        foreach($field in 'red_command','red_expected_failure','red_observed_failure','green_command','regression_command'){if([string]::IsNullOrWhiteSpace([string]$v.$field)){$errors+=$field.ToUpperInvariant()+'_REQUIRED'}}
        foreach($field in 'red_evidence_refs','green_evidence_refs','regression_evidence_refs'){try{Strings $v.$field $field $false|Out-Null}catch{$errors+=$field.ToUpperInvariant()+'_REQUIRED'}}
        if([int]$v.red_exit_code-eq0){$errors+='RED_MUST_FAIL'};if([int]$v.green_exit_code-ne0){$errors+='GREEN_MUST_PASS'};if([int]$v.regression_exit_code-ne0){$errors+='REGRESSION_MUST_PASS'}
        $status=if($profile.tdd_required-and$errors.Count){'BLOCKED'}elseif($profile.tdd_required){'PASS'}else{'NOT_REQUIRED'}
      }
      $result=[ordered]@{schema='TDD_PROOF_V1';task_id=$TaskId;red_command=$v.red_command;red_exit_code=[int]$v.red_exit_code;red_expected_failure=$v.red_expected_failure;red_observed_failure=$v.red_observed_failure;red_evidence_refs=@($v.red_evidence_refs);green_command=$v.green_command;green_exit_code=[int]$v.green_exit_code;green_evidence_refs=@($v.green_evidence_refs);regression_command=$v.regression_command;regression_exit_code=[int]$v.regression_exit_code;regression_evidence_refs=@($v.regression_evidence_refs);exception_class=$v.exception_class;exception_reason=$v.exception_reason;equivalent_verification=$v.equivalent_verification;errors=@($errors|Sort-Object -Unique);status=$status;validated_at=(Now)}
      Save-Gate $R $TaskId 'TDD_PROOF.json' $result
    }
    'ValidateEval'{
      $profile=Profile $R $TaskId;$v=Read-Json $InputJsonPath
      $fields=@('capability_evals','regression_evals','negative_cases','forbidden_behaviors','grader_type','success_threshold','reliability_mode','run_count','observed_successes','evidence_refs','exploratory_reason')
      Assert-Fields $v $fields 'EVAL_PLAN_FIELDS_INVALID';$errors=@()
      foreach($field in 'capability_evals','regression_evals','negative_cases','forbidden_behaviors','evidence_refs'){try{Strings $v.$field $field $false|Out-Null}catch{$errors+=$field.ToUpperInvariant()+'_REQUIRED'}}
      if($v.grader_type-notin$Graders){$errors+='GRADER_TYPE_INVALID'};if($v.reliability_mode-notin@('PASS_K','PASS_AT_K')){$errors+='RELIABILITY_MODE_INVALID'}
      $runs=[int]$v.run_count;$success=[int]$v.observed_successes;$threshold=[double]$v.success_threshold
      if($runs-lt1-or$success-lt0-or$success-gt$runs-or$threshold-le0-or$threshold-gt1){$errors+='EVAL_COUNTS_INVALID'}
      if($profile.eval_required-and$v.reliability_mode-ne$profile.required_reliability_mode){$errors+='PASS_K_REQUIRED'}
      if($v.reliability_mode-eq'PASS_K'-and$success-ne$runs){$errors+='PASS_K_NOT_MET'}
      if($runs-gt0-and($success/$runs)-lt$threshold){$errors+='SUCCESS_THRESHOLD_NOT_MET'}
      if($v.reliability_mode-eq'PASS_AT_K'-and[string]::IsNullOrWhiteSpace([string]$v.exploratory_reason)){$errors+='EXPLORATORY_REASON_REQUIRED'}
      $status=if($profile.eval_required-and$errors.Count){'EVAL_GATE_FAILED'}elseif($profile.eval_required){'PASS'}else{'NOT_REQUIRED'}
      $result=[ordered]@{schema='EVAL_PLAN_V1';task_id=$TaskId;capability_evals=@($v.capability_evals);regression_evals=@($v.regression_evals);negative_cases=@($v.negative_cases);forbidden_behaviors=@($v.forbidden_behaviors);grader_type=$v.grader_type;success_threshold=$threshold;reliability_mode=$v.reliability_mode;run_count=$runs;observed_successes=$success;evidence_refs=@($v.evidence_refs);exploratory_reason=$v.exploratory_reason;errors=@($errors|Sort-Object -Unique);status=$status;validated_at=(Now)}
      Save-Gate $R $TaskId 'EVAL_PLAN.json' $result
    }
    'RecordSelfCheck'{
      $profile=Profile $R $TaskId;$v=Read-Json $InputJsonPath
      $bools=@('plan_compliance','scope_compliance','tests_pass','lint_pass','typecheck_pass','format_pass','security_invariants_checked','dependency_delta_checked','migration_delta_checked','documentation_impact_checked','dead_code_checked','temporary_files_checked','external_action_compliance')
      Assert-Fields $v ($bools+@('unresolved_assumptions','evidence_refs')) 'SELF_CHECK_FIELDS_INVALID';$errors=@()
      foreach($field in $bools){if($v.$field-ne$true){$errors+=$field.ToUpperInvariant()}}
      try{Strings $v.unresolved_assumptions 'unresolved_assumptions'|Out-Null}catch{$errors+='UNRESOLVED_ASSUMPTIONS_INVALID'}
      try{Strings $v.evidence_refs 'evidence_refs' $false|Out-Null}catch{$errors+='SELF_CHECK_EVIDENCE_REQUIRED'}
      if(@($v.unresolved_assumptions).Count){$errors+='UNRESOLVED_ASSUMPTIONS'}
      $status=if($profile.self_check_required-and$errors.Count){'NOT_READY_FOR_REVIEW'}else{'READY_FOR_REVIEW'}
      $result=[ordered]@{schema='IMPLEMENTATION_SELF_CHECK_V1';task_id=$TaskId};foreach($field in $bools){$result[$field]=[bool]$v.$field};$result.unresolved_assumptions=@($v.unresolved_assumptions);$result.evidence_refs=@($v.evidence_refs);$result.errors=@($errors|Sort-Object -Unique);$result.status=$status;$result.approval_authority=$false;$result.recorded_at=Now
      Save-Gate $R $TaskId 'IMPLEMENTATION_SELF_CHECK.json' $result
    }
    'AddLearning'{
      $v=Read-Json $InputJsonPath;Assert-Fields $v @('candidate_id','source','scope','statement','evidence_refs','confidence','dedup_key','privacy_class','stale_when') 'LEARNING_CANDIDATE_FIELDS_INVALID'
      Assert-Id ([string]$v.candidate_id) 'LEARNING_CANDIDATE_IDENTITY_INVALID';if($v.source-notin$LearningSources-or[string]$v.dedup_key-notmatch'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,191}$'){throw 'LEARNING_CANDIDATE_IDENTITY_INVALID'}
      foreach($field in 'scope','evidence_refs','stale_when'){Strings $v.$field $field $false|Out-Null};if([string]::IsNullOrWhiteSpace([string]$v.statement)-or[string]::IsNullOrWhiteSpace([string]$v.privacy_class)-or[double]$v.confidence-lt0-or[double]$v.confidence-gt1){throw 'LEARNING_CANDIDATE_VALUE_INVALID'}
      $paths=LearningPaths $R;if(@(JsonLines $paths.Candidates|Where-Object{$_.dedup_key-eq$v.dedup_key}).Count){Emit ([ordered]@{schema='LEARNING_CANDIDATE_RESULT_V1';status='DUPLICATE_LEARNING_CANDIDATE';dedup_key=$v.dedup_key}) 3}
      $result=[ordered]@{schema='LEARNING_CANDIDATE_V1';candidate_id=$v.candidate_id;source=$v.source;scope=@($v.scope);statement=$v.statement;evidence_refs=@($v.evidence_refs);confidence=[double]$v.confidence;dedup_key=$v.dedup_key;privacy_class=$v.privacy_class;stale_when=@($v.stale_when);promotion_status='PENDING';created_at=(Now)}
      Append-Json $paths.Candidates $result;Emit $result
    }
    'PromoteLearning'{
      $v=Read-Json $InputJsonPath;Assert-Fields $v @('candidate_id','dedup_key','approved_by','approval_verdict','evidence_refs','approved_scope','stale_when','privacy_class') 'LEARNING_PROMOTION_FIELDS_INVALID'
      $paths=LearningPaths $R;$candidate=@(JsonLines $paths.Candidates|Where-Object{$_.candidate_id-eq$v.candidate_id-and$_.dedup_key-eq$v.dedup_key})
      if(-not$candidate.Count){throw 'LEARNING_CANDIDATE_NOT_FOUND'}
      if($v.approved_by-ne'FINAL_REVIEWER'-or$v.approval_verdict-ne'APPROVED'){Emit ([ordered]@{schema='LEARNING_PROMOTION_RESULT_V1';status='FINAL_REVIEWER_APPROVAL_REQUIRED';candidate_id=$v.candidate_id}) 3}
      foreach($field in 'evidence_refs','approved_scope','stale_when'){Strings $v.$field $field $false|Out-Null}
      if(@(JsonLines $paths.Promotions|Where-Object{$_.candidate_id-eq$v.candidate_id}).Count){Emit ([ordered]@{schema='LEARNING_PROMOTION_RESULT_V1';status='DUPLICATE_PROMOTION';candidate_id=$v.candidate_id}) 3}
      $result=[ordered]@{schema='LEARNING_PROMOTION_V1';candidate_id=$v.candidate_id;dedup_key=$v.dedup_key;approved_by=$v.approved_by;approval_verdict=$v.approval_verdict;evidence_refs=@($v.evidence_refs);approved_scope=@($v.approved_scope);stale_when=@($v.stale_when);privacy_class=$v.privacy_class;status='PROMOTED';memory_updated=$false;promoted_at=(Now)}
      Append-Json $paths.Promotions $result;Emit $result
    }
    'ValidateTask'{
      $profile=Profile $R $TaskId;$dir=TaskDir $R $TaskId;$errors=@()
      $requirements=@(@('debug_first_required','DEBUG_PROOF.json','PASS'),@('tdd_required','TDD_PROOF.json','PASS'),@('eval_required','EVAL_PLAN.json','PASS'),@('self_check_required','IMPLEMENTATION_SELF_CHECK.json','READY_FOR_REVIEW'))
      foreach($rule in $requirements){if(-not$profile.($rule[0])){continue};$path=Join-Path $dir $rule[1];if(-not(Test-Path $path)){$errors+=$rule[1]+'_MISSING';continue};$value=Read-Json $path;if($value.status-ne$rule[2]){$errors+=$rule[1]+'_NOT_PASSING'}}
      $result=[ordered]@{schema='QUALITY_VALIDATION_V1';task_id=$TaskId;valid=($errors.Count-eq0);errors=$errors;validated_at=(Now)};Write-Json (Join-Path $dir 'QUALITY_VALIDATION.json') $result
      if($errors.Count){$result.status='BLOCKED';Emit $result 3};Emit $result
    }
  }
}catch{[Console]::Error.WriteLine($_.Exception.Message);$global:LASTEXITCODE=2;exit 2}
