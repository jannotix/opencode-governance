param(
    [Parameter(Mandatory=$true)][string]$RunStatePath,
    [Parameter(Mandatory=$true)][ValidateSet('ai-workflow','ai-resume')][string]$ExpectedCommand
)

$ErrorActionPreference='Stop'
$Schema='WORKFLOW_CONTINUATION_GATE_V1'
$NonTerminal=@(
    'IDEA_INTAKE','PRODUCT_CLASSIFICATION','ADAPTIVE_PRODUCT_DISCOVERY','ADAPTIVE_DISCOVERY',
    'GOVERNED_DOMAIN_RESEARCH','CONSTRUCTIVE_CHALLENGE','PRODUCT_DEFINITION',
    'DISCOVERY_DUAL_REVIEW','DISCOVERY_ADJUDICATION','DISCOVERY_PASS','DISCOVERY_DEFECT',
    'PRODUCT_SCOPE_APPROVAL','PRODUCT_SCOPE_APPROVED','CONTEXT_ROUTING','CONTEXT_SUFFICIENT',
    'DELIVERY_ARCHITECTURE','VERTICAL_MILESTONE_PLANNING','EVIDENCE_PLANNING','OPERATIONAL_PLANNING',
    'READY_FOR_EXECUTION','PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED','IMPLEMENTING','IMPLEMENTATION',
    'DOCUMENTATION_SYNC','EVIDENCE_VALIDATION','OPERATIONAL_VALIDATION','EVIDENCE_AND_OPERATIONAL_VALIDATION',
    'TASK_VALIDATED','DUAL_REVIEW','DUAL_REVIEW_COMPLETE','TASK_DUAL_REVIEW','FINAL_ADJUDICATION',
    'FINAL_ADJUDICATION_PASS','TASK_FINAL_ADJUDICATION','PASS','IMPLEMENTATION_DEFECT','PLAN_DEFECT',
    'PRODUCT_COMPLETENESS_RECONCILIATION','PRODUCT_COMPLETE','PRODUCT_DEFECT','PRODUCT_INCOMPLETE',
    'MILESTONE_VALIDATED','RELEASE_READINESS','RELEASE_READY','READY_FOR_PRODUCTION',
    'NOT_READY_FOR_PRODUCTION','VALIDATED_LEARNING','AUDIT_PASS','BASELINE_PASS','BASELINE_DEFECT',
    'BASELINE_VALIDATED'
)
$TerminalSuccess=@('LOCAL_COMMITTED')
$TerminalBlockers=@(
    'BLOCKED','HUMAN_INPUT_REQUIRED','LICENSE_DECISION_REQUIRED','GOVERNANCE_PERMISSION_BLOCKED',
    'EXECUTOR_FAILOVER_BLOCKED','BASELINE_BLOCKED','DISCOVERY_BLOCKED','PRODUCT_BLOCKED',
    'RELEASE_BLOCKED','CONTEXT_BLOCKED','PLAN_BLOCKED','PERMISSION_BLOCKED','SAFETY_BLOCKED',
    'EXTERNAL_TOOL_BLOCKED'
)

function Emit([int]$Code,[hashtable]$Payload){
    $Body=[ordered]@{schema=$Schema}
    foreach($Key in $Payload.Keys){$Body[$Key]=$Payload[$Key]}
    [Console]::Out.WriteLine(($Body|ConvertTo-Json -Depth 10 -Compress))
    exit $Code
}

if(-not(Test-Path -LiteralPath $RunStatePath -PathType Leaf)){
    Emit 2 @{decision='INVALID_RUN_STATE';error='RUN_STATE_NOT_FOUND'}
}
try{$State=Get-Content -LiteralPath $RunStatePath -Raw|ConvertFrom-Json}catch{
    Emit 2 @{decision='INVALID_RUN_STATE';error='RUN_STATE_INVALID_JSON'}
}
$Required=@('top_level_command','current_phase','next_required_phase','terminal_reason')
$Missing=@($Required|Where-Object{$null-eq$State.PSObject.Properties[$_]})
if($Missing.Count){Emit 2 @{decision='INVALID_RUN_STATE';error='REQUIRED_FIELDS_MISSING';missing_fields=$Missing}}

$Command=[string]$State.top_level_command
$Phase=[string]$State.current_phase
$Next=$State.next_required_phase
$Reason=$State.terminal_reason
if($ExpectedCommand-eq'ai-workflow'-and$Command-ne'ai-workflow'){Emit 2 @{decision='INVALID_RUN_STATE';error='TOP_LEVEL_COMMAND_MISMATCH'}}
if($ExpectedCommand-eq'ai-resume'-and$Command-ne'ai-workflow'){Emit 2 @{decision='INVALID_RUN_STATE';error='ORIGINAL_TOP_LEVEL_COMMAND_REQUIRED'}}
if([string]::IsNullOrWhiteSpace($Phase)){Emit 2 @{decision='INVALID_RUN_STATE';error='CURRENT_PHASE_REQUIRED'}}

if($Phase-in$TerminalSuccess){
    if($null-ne$Next-and-not[string]::IsNullOrWhiteSpace([string]$Next)){Emit 2 @{decision='INVALID_RUN_STATE';error='SUCCESS_TERMINAL_FIELDS_INVALID'}}
    if($null-ne$Reason-and-not[string]::IsNullOrWhiteSpace([string]$Reason)){Emit 2 @{decision='INVALID_RUN_STATE';error='SUCCESS_TERMINAL_FIELDS_INVALID'}}
    Emit 0 @{decision='TERMINAL_ALLOWED';terminal_class='SUCCESS';top_level_command=$Command;current_phase=$Phase;next_required_phase=$null;terminal_reason=$null}
}
if($Phase-in$TerminalBlockers){
    if($null-ne$Next-and-not[string]::IsNullOrWhiteSpace([string]$Next)){Emit 2 @{decision='INVALID_RUN_STATE';error='BLOCKER_NEXT_PHASE_FORBIDDEN'}}
    if($null-eq$Reason-or[string]::IsNullOrWhiteSpace([string]$Reason)){Emit 2 @{decision='INVALID_RUN_STATE';error='TERMINAL_REASON_REQUIRED'}}
    Emit 0 @{decision='TERMINAL_ALLOWED';terminal_class='BLOCKER';top_level_command=$Command;current_phase=$Phase;next_required_phase=$null;terminal_reason=([string]$Reason).Trim()}
}
if($Phase-in$NonTerminal){
    if($null-eq$Next-or[string]::IsNullOrWhiteSpace([string]$Next)){Emit 2 @{decision='INVALID_RUN_STATE';error='NEXT_REQUIRED_PHASE_REQUIRED'}}
    if($null-ne$Reason-and-not[string]::IsNullOrWhiteSpace([string]$Reason)){Emit 2 @{decision='INVALID_RUN_STATE';error='NON_TERMINAL_REASON_FORBIDDEN'}}
    Emit 3 @{decision='CONTINUE_REQUIRED';terminal_class=$null;top_level_command=$Command;current_phase=$Phase;next_required_phase=([string]$Next).Trim();terminal_reason=$null}
}
Emit 2 @{decision='INVALID_RUN_STATE';error='UNKNOWN_WORKFLOW_PHASE';current_phase=$Phase}
