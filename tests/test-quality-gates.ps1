$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Tool=Join-Path $Root 'scripts/quality-gates.ps1'
$Temp=Join-Path ([IO.Path]::GetTempPath()) ('opencode-v350-'+[guid]::NewGuid().ToString('N'))
$Project=Join-Path $Temp 'project'
New-Item -ItemType Directory -Force -Path (Join-Path $Project '.ai')|Out-Null
'MEMORY_SENTINEL'|Set-Content (Join-Path $Project '.ai/GOVERNANCE_MEMORY.md')

function Invoke-Gate([hashtable]$Parameters){
  $output=& $Tool @Parameters
  if($LASTEXITCODE-ne0){throw "Quality gate failed: $($output-join"`n")"}
  return ($output-join"`n")|ConvertFrom-Json
}
function Invoke-GateFailure([string[]]$Arguments){
  $output=& pwsh -NoProfile -File $Tool @Arguments 2>&1
  [pscustomobject]@{Code=$LASTEXITCODE;Value=(($output-join"`n")|ConvertFrom-Json)}
}
function Write-Json([string]$Path,[object]$Value){$Value|ConvertTo-Json -Depth 30|Set-Content $Path -Encoding utf8NoBOM}

try{
  $bug=Invoke-Gate @{Action='InitializeProfile';ProjectDir=$Project;TaskId='BUG-1';WorkClass='PATCH';TaskKind='BUGFIX';Risks=''}
  if(-not$bug.debug_first_required-or-not$bug.tdd_required-or$bug.eval_required){throw 'Bugfix profile mismatch'}
  $ai=Invoke-Gate @{Action='InitializeProfile';ProjectDir=$Project;TaskId='AI-1';WorkClass='HIGH_RISK_CHANGE';TaskKind='FEATURE';Risks='AI_SYSTEM,SECURITY'}
  if(-not$ai.tdd_required-or-not$ai.eval_required-or$ai.required_reliability_mode-ne'PASS_K'){throw 'AI profile mismatch'}
  Invoke-Gate @{Action='InitializeProfile';ProjectDir=$Project;TaskId='EXC-1';WorkClass='BOUNDED_FEATURE';TaskKind='FEATURE';Risks=''}|Out-Null

  $badDebug=Join-Path $Temp 'debug-bad.json'
  Write-Json $badDebug ([ordered]@{symptom='wrong result';reproduction_status='REPRODUCED';root_cause_status='HYPOTHESIS';root_cause_evidence=@();hypothesis='maybe parser';minimal_experiment='isolate parser';disproving_condition='parser correct';hypothesis_attempts=3;defect_class='APPLICATION_DEFECT'})
  $blocked=Invoke-GateFailure @('-Action','ValidateDebug','-ProjectDir',$Project,'-TaskId','BUG-1','-InputJsonPath',$badDebug)
  if($blocked.Code-ne3-or$blocked.Value.status-ne'ARCHITECTURE_REVIEW_REQUIRED'){throw 'Debug escalation failed'}

  $goodDebug=Join-Path $Temp 'debug-good.json'
  Write-Json $goodDebug ([ordered]@{symptom='wrong result';reproduction_status='REPRODUCED';root_cause_status='CONFIRMED';root_cause_evidence=@('repro.log');hypothesis='parser drops zero';minimal_experiment='direct fixture';disproving_condition='zero preserved';hypothesis_attempts=1;defect_class='APPLICATION_DEFECT'})
  if((Invoke-Gate @{Action='ValidateDebug';ProjectDir=$Project;TaskId='BUG-1';InputJsonPath=$goodDebug}).status-ne'PASS'){throw 'Debug proof failed'}

  $badTdd=Join-Path $Temp 'tdd-bad.json'
  Write-Json $badTdd ([ordered]@{red_command='Invoke-Pester';red_exit_code=0;red_expected_failure='wrong value';red_observed_failure='none';red_evidence_refs=@('red.log');green_command='Invoke-Pester';green_exit_code=0;green_evidence_refs=@('green.log');regression_command='Invoke-Pester';regression_exit_code=0;regression_evidence_refs=@('suite.log');exception_class=$null;exception_reason=$null;equivalent_verification=$null})
  $tddBlocked=Invoke-GateFailure @('-Action','ValidateTdd','-ProjectDir',$Project,'-TaskId','BUG-1','-InputJsonPath',$badTdd)
  if($tddBlocked.Code-ne3-or'RED_MUST_FAIL'-notin@($tddBlocked.Value.errors)){throw 'TDD red gate failed'}

  $goodTdd=Join-Path $Temp 'tdd-good.json';$tdd=Get-Content $badTdd -Raw|ConvertFrom-Json;$tdd.red_exit_code=1;$tdd.red_observed_failure='assertion failed';Write-Json $goodTdd $tdd
  if((Invoke-Gate @{Action='ValidateTdd';ProjectDir=$Project;TaskId='BUG-1';InputJsonPath=$goodTdd}).status-ne'PASS'){throw 'TDD proof failed'}

  $exceptionTdd=Join-Path $Temp 'tdd-exception.json'
  Write-Json $exceptionTdd ([ordered]@{red_command=$null;red_exit_code=0;red_expected_failure=$null;red_observed_failure=$null;red_evidence_refs=@();green_command=$null;green_exit_code=0;green_evidence_refs=@();regression_command=$null;regression_exit_code=0;regression_evidence_refs=@();exception_class='NO_EXECUTABLE_HARNESS';exception_reason='No executable harness exists for the generated host configuration.';equivalent_verification='Validate generated schema and runtime diagnostic output.'})
  $exceptionGate=Invoke-GateFailure @('-Action','ValidateTdd','-ProjectDir',$Project,'-TaskId','EXC-1','-InputJsonPath',$exceptionTdd)
  if($exceptionGate.Code-ne3-or$exceptionGate.Value.status-ne'EXCEPTION_REQUIRES_FINAL_REVIEW'){throw 'TDD exception gate failed'}

  $badEval=Join-Path $Temp 'eval-bad.json'
  Write-Json $badEval ([ordered]@{capability_evals=@('routing');regression_evals=@('legacy');negative_cases=@('unsafe');forbidden_behaviors=@('source write');grader_type='HYBRID';success_threshold=1.0;reliability_mode='PASS_AT_K';run_count=3;observed_successes=3;evidence_refs=@('eval.json');exploratory_reason=$null})
  $evalBlocked=Invoke-GateFailure @('-Action','ValidateEval','-ProjectDir',$Project,'-TaskId','AI-1','-InputJsonPath',$badEval)
  if($evalBlocked.Code-ne3-or'PASS_K_REQUIRED'-notin@($evalBlocked.Value.errors)){throw 'Eval reliability gate failed'}
  $goodEval=Join-Path $Temp 'eval-good.json';$eval=Get-Content $badEval -Raw|ConvertFrom-Json;$eval.reliability_mode='PASS_K';Write-Json $goodEval $eval
  if((Invoke-Gate @{Action='ValidateEval';ProjectDir=$Project;TaskId='AI-1';InputJsonPath=$goodEval}).status-ne'PASS'){throw 'Eval proof failed'}

  $badCheck=Join-Path $Temp 'check-bad.json'
  Write-Json $badCheck ([ordered]@{plan_compliance=$true;scope_compliance=$true;tests_pass=$true;lint_pass=$true;typecheck_pass=$true;format_pass=$true;security_invariants_checked=$false;dependency_delta_checked=$true;migration_delta_checked=$true;documentation_impact_checked=$true;dead_code_checked=$true;temporary_files_checked=$true;external_action_compliance=$true;unresolved_assumptions=@('authorization unknown');evidence_refs=@('check.log')})
  $notReady=Invoke-GateFailure @('-Action','RecordSelfCheck','-ProjectDir',$Project,'-TaskId','BUG-1','-InputJsonPath',$badCheck)
  if($notReady.Code-ne3-or$notReady.Value.status-ne'NOT_READY_FOR_REVIEW'-or$notReady.Value.approval_authority){throw 'Self-check gate failed'}
  $goodCheck=Join-Path $Temp 'check-good.json';$check=Get-Content $badCheck -Raw|ConvertFrom-Json;$check.security_invariants_checked=$true;$check.unresolved_assumptions=@();Write-Json $goodCheck $check
  $ready=Invoke-Gate @{Action='RecordSelfCheck';ProjectDir=$Project;TaskId='BUG-1';InputJsonPath=$goodCheck}
  if($ready.status-ne'READY_FOR_REVIEW'-or$ready.approval_authority){throw 'Self-check readiness failed'}
  Invoke-Gate @{Action='RecordSelfCheck';ProjectDir=$Project;TaskId='EXC-1';InputJsonPath=$goodCheck}|Out-Null

  $badException=Join-Path $Temp 'exception-bad.json'
  Write-Json $badException ([ordered]@{exception_id='QEX-001';gate='TDD';exception_class='NO_EXECUTABLE_HARNESS';approved_by='IMPLEMENTATION_REVIEWER';approval_verdict='APPROVED';reason='Equivalent verification is sufficient.';evidence_refs=@('equivalent-verification.log');approved_scope=@('generated host configuration');stale_when=@('executable harness becomes available')})
  $deniedException=Invoke-GateFailure @('-Action','ApproveException','-ProjectDir',$Project,'-TaskId','EXC-1','-InputJsonPath',$badException)
  if($deniedException.Code-ne3-or$deniedException.Value.status-ne'FINAL_REVIEWER_APPROVAL_REQUIRED'){throw 'Exception approval authority failed'}
  $stillBlocked=Invoke-GateFailure @('-Action','ValidateTask','-ProjectDir',$Project,'-TaskId','EXC-1')
  if($stillBlocked.Code-ne3-or'TDD_PROOF.json_NOT_PASSING'-notin@($stillBlocked.Value.errors)){throw 'Unapproved exception did not remain blocked'}

  $goodException=Join-Path $Temp 'exception-good.json';$approval=Get-Content $badException -Raw|ConvertFrom-Json;$approval.approved_by='FINAL_REVIEWER';Write-Json $goodException $approval
  $approved=Invoke-Gate @{Action='ApproveException';ProjectDir=$Project;TaskId='EXC-1';InputJsonPath=$goodException}
  if($approved.status-ne'APPROVED_EXCEPTION'-or$approved.implementation_approved){throw 'Approved exception contract failed'}
  if(-not(Invoke-Gate @{Action='ValidateTask';ProjectDir=$Project;TaskId='EXC-1'}).valid){throw 'Approved exception did not unblock task validation'}

  $candidate=Join-Path $Temp 'candidate.json'
  Write-Json $candidate ([ordered]@{candidate_id='LRN-001';source='REVIEW_FINDING';scope=@('parser');statement='Preserve zero values.';evidence_refs=@('review.md');confidence=0.95;dedup_key='parser-zero';privacy_class='PROJECT_INTERNAL';stale_when=@('parser replaced')})
  if((Invoke-Gate @{Action='AddLearning';ProjectDir=$Project;InputJsonPath=$candidate}).promotion_status-ne'PENDING'){throw 'Learning add failed'}
  $duplicate=Invoke-GateFailure @('-Action','AddLearning','-ProjectDir',$Project,'-InputJsonPath',$candidate)
  if($duplicate.Code-ne3-or$duplicate.Value.status-ne'DUPLICATE_LEARNING_CANDIDATE'){throw 'Learning dedup failed'}

  $badPromotion=Join-Path $Temp 'promotion-bad.json'
  Write-Json $badPromotion ([ordered]@{candidate_id='LRN-001';dedup_key='parser-zero';approved_by='IMPLEMENTATION_REVIEWER';approval_verdict='APPROVED';evidence_refs=@('review.md');approved_scope=@('parser');stale_when=@('parser replaced');privacy_class='PROJECT_INTERNAL'})
  $denied=Invoke-GateFailure @('-Action','PromoteLearning','-ProjectDir',$Project,'-InputJsonPath',$badPromotion)
  if($denied.Code-ne3-or$denied.Value.status-ne'FINAL_REVIEWER_APPROVAL_REQUIRED'){throw 'Promotion authority gate failed'}
  $goodPromotion=Join-Path $Temp 'promotion-good.json';$promotion=Get-Content $badPromotion -Raw|ConvertFrom-Json;$promotion.approved_by='FINAL_REVIEWER';Write-Json $goodPromotion $promotion
  $promoted=Invoke-Gate @{Action='PromoteLearning';ProjectDir=$Project;InputJsonPath=$goodPromotion}
  if($promoted.status-ne'PROMOTED'-or$promoted.memory_updated){throw 'Promotion record failed'}
  if((Get-Content (Join-Path $Project '.ai/GOVERNANCE_MEMORY.md') -Raw).Trim()-ne'MEMORY_SENTINEL'){throw 'Governance Memory was modified automatically'}

  if(-not(Invoke-Gate @{Action='ValidateTask';ProjectDir=$Project;TaskId='BUG-1'}).valid){throw 'Task quality validation failed'}
  Write-Host 'PASS: quality gates PowerShell regressions'
}finally{Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue;$global:LASTEXITCODE=0}
