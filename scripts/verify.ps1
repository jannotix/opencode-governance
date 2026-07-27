param([string]$ConfigDir = $(if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $HOME '.config\opencode' }))
$ErrorActionPreference = 'Stop'

$AgentNames = @('architect','build','plan','executor','reviewer','reviewer-architecture','final-reviewer')
$AgentText = @{}
foreach ($Name in $AgentNames) {
    $Path = Join-Path $ConfigDir "agents\$Name.md"
    if (-not (Test-Path $Path) -or (Get-Item $Path).Length -eq 0) { throw "Missing agent: $Name" }
    $Text = Get-Content $Path -Raw
    $AgentText[$Name] = $Text
    if ($Text -notmatch '(?m)^model:\s+([^/\s]+/\S+)\s*$') { throw "Missing provider-qualified model in $Path" }
    if ($Text -match '__[A-Z_]+__') { throw "Unrendered placeholder in $Path" }
    if ($Text -notmatch 'ADAPTIVE_OUTPUT_EFFICIENCY') { throw "$Name is missing adaptive output efficiency policy." }
    if ($Text -notmatch '(?m)^\s{2}skill:\s*$') { throw "$Name is missing governed skill permission block." }
}

$ArchitectModel = [regex]::Match($AgentText['architect'], '(?m)^model:\s+(\S+)\s*$').Groups[1].Value
foreach ($Alias in @('build','plan')) {
    $AliasModel = [regex]::Match($AgentText[$Alias], '(?m)^model:\s+(\S+)\s*$').Groups[1].Value
    if ($AliasModel -ne $ArchitectModel) { throw "$Alias must use the Architect model. Expected $ArchitectModel, found $AliasModel" }
}

foreach ($Name in @('architect','build')) {
    foreach ($Worker in @('explore','scout')) {
        if ($AgentText[$Name] -notmatch "(?m)^\s+${Worker}:\s+allow\s*$") { throw "$Name must explicitly allow read-only discovery worker $Worker." }
    }
    if ($AgentText[$Name] -match '(?m)^\s+general:\s+allow\s*$') { throw "$Name must not explicitly allow writable General as a governance discovery worker." }
}
foreach ($Rule in @('    executor: allow','    reviewer: allow','    reviewer-architecture: allow','    final-reviewer: allow')) {
    if ($AgentText['build'] -notmatch [regex]::Escape($Rule)) { throw "Governed Build is missing required delegation permission: $Rule" }
}
if ($AgentText['plan'] -notmatch '(?m)^\s+task:\s+deny\s*$') { throw 'Governed Plan must deny task delegation.' }
foreach ($Name in @('architect','build','plan')) {
    if ($AgentText[$Name] -notmatch '(?m)^\s*question:\s+allow\s*$') { throw "$Name must explicitly allow the OpenCode question tool." }
}

foreach ($Marker in @('BASELINE_VALIDATED','DOCUMENTATION_SCOPE','DOCUMENTATION_IMPACT','LICENSE_DECISION_REQUIRED','CONTEXT_INDEX.md','INSTRUCTION_INDEX.md','GOVERNANCE_MEMORY.md','CONTEXT_MANIFEST.md','RUN_STATE.json','MINIMUM_CHANGE_ASSESSMENT','STEERING.md')) {
    if ($AgentText['architect'] -notmatch [regex]::Escape($Marker)) { throw "Architect is missing governance marker $Marker." }
}
foreach ($Marker in @('ORIGINAL_USER_REQUEST.md','CLARIFICATION_TRANSCRIPT.md','APPROVED_REQUIREMENTS.md')) {
    if ($AgentText['architect'] -notmatch [regex]::Escape($Marker) -or $AgentText['final-reviewer'] -notmatch [regex]::Escape($Marker)) { throw "Missing canonical requirement artifact marker $Marker." }
}

$EvidenceMarkers = @('VERIFICATION_PROFILE.md','VERIFICATION_EVIDENCE.md','TASK_RISK_PROFILE','VALIDATION_PROFILE','BUGFIX_PROOF','TEST_IMPACT_MAP','CONTRACT_COMPATIBILITY','ENVIRONMENT_FINGERPRINT','DEPENDENCY_ADMISSION_GATE','DEPENDENCY_DELTA','GENERATED_ARTIFACT_GATE','PRE_CHANGE_SAFEPOINT','MIGRATION_PROOF','NON_FUNCTIONAL_BUDGETS','FLAKINESS_EVIDENCE','ADVERSARIAL_INPUT_VALIDATION','CODEOWNERS_HUMAN_GATE','CLOSED_LOOP_LEARNING','UNAVAILABLE')
foreach ($Marker in $EvidenceMarkers) {
    if ($AgentText['architect'] -notmatch [regex]::Escape($Marker)) { throw "Architect is missing Evidence-Driven Verification marker $Marker." }
}
foreach ($Name in @('build','plan','executor','reviewer','reviewer-architecture','final-reviewer')) {
    foreach ($Marker in @('VERIFICATION_PROFILE','TASK_RISK_PROFILE','DEPENDENCY_ADMISSION_GATE','PRE_CHANGE_SAFEPOINT','CLOSED_LOOP_LEARNING')) {
        if ($AgentText[$Name] -notmatch [regex]::Escape($Marker)) { throw "$Name is missing v2 evidence marker $Marker." }
    }
}
foreach ($Name in @('executor','reviewer','reviewer-architecture','final-reviewer')) {
    if ($AgentText[$Name] -notmatch 'VERIFICATION_EVIDENCE') { throw "$Name is missing verification evidence handling." }
}

$DiscoverySkillMemoryMarkers = @('GOVERNED_SKILL_ROUTING','GOVERNANCE_MEMORY')
foreach ($Name in $AgentNames) {
    foreach ($Marker in $DiscoverySkillMemoryMarkers) {
        if ($AgentText[$Name] -notmatch [regex]::Escape($Marker)) { throw "$Name is missing v2 routing/memory marker $Marker." }
    }
}
foreach ($Name in @('architect','build')) {
    if ($AgentText[$Name] -notmatch 'READ_ONLY_DISCOVERY_SWARM') { throw "$Name is missing bounded read-only discovery policy." }
}
if ($AgentText['plan'] -notmatch 'READ_ONLY_DISCOVERY_SWARM') { throw 'Plan is missing explicit read-only discovery-swarm boundary.' }
if ($AgentText['final-reviewer'] -notmatch 'MEMORY_DECISION' -or $AgentText['final-reviewer'] -notmatch 'APPROVE' -or $AgentText['final-reviewer'] -notmatch 'REJECT') { throw 'Final Reviewer is missing closed-loop Governance Memory adjudication.' }

$OperationalMarkers = @('OPERATIONAL_ASSURANCE','PREVIEW_ENVIRONMENT_GATE','USER_FLOW_VERIFICATION','VISUAL_BEHAVIOR_GATE','RELEASE_RECOVERY_PROOF','TOOL_CAPABILITY_PROFILE','MCP_CAPABILITY_ASSESSMENT','SAFE_EXPERIMENTATION')
foreach ($Name in $AgentNames) {
    foreach ($Marker in $OperationalMarkers) {
        if ($AgentText[$Name] -notmatch [regex]::Escape($Marker)) { throw "$Name is missing v2.0 Operational Assurance marker $Marker." }
    }
}
foreach ($Name in @('plan','executor','reviewer','reviewer-architecture','final-reviewer')) {
    foreach ($Risk in @('USER_FLOW','VISUAL_BEHAVIOR','EXTERNAL_TOOLING','RECOVERY','EXPERIMENTATION')) {
        if ($AgentText[$Name] -notmatch [regex]::Escape($Risk)) { throw "$Name is missing v2.0 risk dimension $Risk." }
    }
}
if ($AgentText['executor'] -notmatch 'external_directory:\s+deny') { throw 'Executor must preserve external_directory deny; v2 governance must not broaden permissions.' }

foreach ($Marker in @('EXECUTION_PACKET.md','CONTEXT_MANIFEST.md','RUN_STATE.json','MINIMUM_CHANGE_ASSESSMENT')) {
    if ($AgentText['executor'] -notmatch [regex]::Escape($Marker)) { throw "Executor is missing $Marker." }
}
if ($AgentText['reviewer'] -notmatch 'REVIEW_IMPLEMENTATION_PACKET.md') { throw 'Implementation Reviewer is missing fresh evidence packet policy.' }
if ($AgentText['reviewer-architecture'] -notmatch 'REVIEW_ARCHITECTURE_PACKET.md' -or $AgentText['reviewer-architecture'] -notmatch 'context-efficient') { throw 'Architecture Reviewer is missing targeted context policy.' }
if ($AgentText['final-reviewer'] -notmatch 'FINAL_PACKET.md' -or $AgentText['final-reviewer'] -notmatch 'perfect implementation') { throw 'Final Reviewer is missing final packet or Architect-plan challenge policy.' }
foreach ($Name in @('reviewer','reviewer-architecture')) {
    if ($AgentText[$Name] -notmatch 'F-###' -or $AgentText[$Name] -notmatch 'Evidence:' -or $AgentText[$Name] -notmatch 'Verify:') { throw "$Name is missing compact evidence-dense finding format." }
}
foreach ($Name in @('reviewer','reviewer-architecture')) {
    foreach ($Mode in @('TASK_REVIEW','BASELINE_AUDIT','RELEASE_REVIEW')) {
        if ($AgentText[$Name] -notmatch $Mode) { throw "$Name is missing $Mode mode." }
    }
}
foreach ($Mode in @('TASK_REVIEW','BASELINE_AUDIT','RELEASE_REVIEW')) {
    if ($AgentText['final-reviewer'] -notmatch $Mode) { throw "Final Reviewer is missing $Mode mode." }
}
if ($AgentText['final-reviewer'] -notmatch 'BASELINE_PASS' -or $AgentText['final-reviewer'] -notmatch 'BASELINE_DEFECT' -or $AgentText['final-reviewer'] -notmatch 'LICENSE_DECISION_REQUIRED') { throw 'Final Reviewer is missing baseline/license gates.' }

$RequiredCommands = @('ai-init','ai-audit','ai-docs','ai-plan','ai-execute','ai-review','ai-workflow','ai-status','ai-resume','ai-metrics','ai-release')
$CommandText = @{}
foreach ($Name in $RequiredCommands) {
    $Path = Join-Path $ConfigDir "commands\$Name.md"
    if (-not (Test-Path $Path) -or (Get-Item $Path).Length -eq 0) { throw "Missing command: $Name" }
    $CommandText[$Name] = Get-Content $Path -Raw
}

$DocsCommand = $CommandText['ai-docs']
$PlanCommand = $CommandText['ai-plan']
$WorkflowCommand = $CommandText['ai-workflow']
$ExecuteCommand = $CommandText['ai-execute']
$ReviewCommand = $CommandText['ai-review']
$StatusCommand = $CommandText['ai-status']
$ResumeCommand = $CommandText['ai-resume']
$ReleaseCommand = $CommandText['ai-release']
$MetricsCommand = $CommandText['ai-metrics']
$InitCommand = $CommandText['ai-init']
$AuditCommand = $CommandText['ai-audit']

if ($DocsCommand -notmatch 'docs/INSTALLATION.md' -or $DocsCommand -notmatch 'docs/USER_MANUAL.md' -or $DocsCommand -notmatch 'docs/wiki/README.md') { throw '/ai-docs is missing required documentation coverage.' }
foreach ($Marker in @('ORIGINAL_USER_REQUEST.md','CLARIFICATION_TRANSCRIPT.md','APPROVED_REQUIREMENTS.md','CONTEXT_MANIFEST.md','VERIFICATION_PROFILE.md','RUN_STATE.json','MINIMUM_CHANGE_ASSESSMENT','GOVERNANCE_MEMORY')) {
    if ($WorkflowCommand -notmatch [regex]::Escape($Marker)) { throw "/ai-workflow is missing $Marker." }
}
foreach ($Marker in @('READ_ONLY_DISCOVERY_SWARM','GOVERNED_SKILL_ROUTING','DEPENDENCY_ADMISSION_GATE','PRE_CHANGE_SAFEPOINT','CLOSED_LOOP_LEARNING')) {
    if ($PlanCommand -notmatch [regex]::Escape($Marker) -or $WorkflowCommand -notmatch [regex]::Escape($Marker)) { throw "v2 planning/workflow is missing $Marker." }
}
foreach ($Marker in @('TASK_RISK_PROFILE','VALIDATION_PROFILE','BUGFIX_PROOF','TEST_IMPACT_MAP','CONTRACT_COMPATIBILITY','ENVIRONMENT_FINGERPRINT','DEPENDENCY_ADMISSION_GATE','DEPENDENCY_DELTA','GENERATED_ARTIFACT_GATE','PRE_CHANGE_SAFEPOINT','MIGRATION_PROOF','NON_FUNCTIONAL_BUDGETS','FLAKINESS_EVIDENCE','ADVERSARIAL_INPUT_VALIDATION','CODEOWNERS_HUMAN_GATE','CLOSED_LOOP_LEARNING')) {
    if ($PlanCommand -notmatch [regex]::Escape($Marker) -and $WorkflowCommand -notmatch [regex]::Escape($Marker)) { throw "Evidence-driven workflow is missing $Marker." }
}
foreach ($Marker in $OperationalMarkers) {
    if ($PlanCommand -notmatch [regex]::Escape($Marker) -or $WorkflowCommand -notmatch [regex]::Escape($Marker)) { throw "Operational Assurance planning/workflow is missing $Marker." }
}
foreach ($Marker in @('GOVERNED_DISCOVERY','SKILL_ROUTING','OPERATIONAL_PLANNING','PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED','OPERATIONAL_VALIDATION','VALIDATED_LEARNING')) {
    if ($WorkflowCommand -notmatch [regex]::Escape($Marker)) { throw "/ai-workflow is missing v2 lifecycle marker $Marker." }
}
foreach ($Name in @('ai-execute','ai-review','ai-status','ai-resume','ai-release')) {
    $Text = $CommandText[$Name]
    if ($Text -notmatch 'VERIFICATION_(PROFILE|EVIDENCE)') { throw "/$Name is missing verification artifacts." }
    if ($Text -notmatch 'OPERATIONAL_ASSURANCE') { throw "/$Name is missing v2 Operational Assurance handling." }
    foreach ($Marker in @('DEPENDENCY_ADMISSION_GATE','PRE_CHANGE_SAFEPOINT')) {
        if ($Text -notmatch [regex]::Escape($Marker)) { throw "/$Name is missing v2 safety gate $Marker." }
    }
}
foreach ($Marker in $OperationalMarkers[1..7]) {
    foreach ($Name in @('ai-execute','ai-review','ai-status','ai-release')) {
        if ($CommandText[$Name] -notmatch [regex]::Escape($Marker)) { throw "/$Name is missing operational gate $Marker." }
    }
}
foreach ($Marker in @('GOVERNANCE_MEMORY.md','Explore','Scout','PROJECT_AUTHORITATIVE')) {
    if ($InitCommand -notmatch [regex]::Escape($Marker)) { throw "/ai-init is missing v2 initialization marker $Marker." }
}
if ($InitCommand -match '(?i)general:\s*allow') { throw '/ai-init must not authorize writable General for governance discovery.' }
foreach ($Marker in @('GOVERNANCE_MEMORY','skill','package/dependency admission','read-only')) {
    if ($AuditCommand -notmatch [regex]::Escape($Marker)) { throw "/ai-audit is missing v2 audit marker $Marker." }
}
foreach ($Marker in @('REVIEW_IMPLEMENTATION_PACKET.md','REVIEW_ARCHITECTURE_PACKET.md','FINAL_PACKET.md','MEMORY_DECISION')) {
    if ($ReviewCommand -notmatch [regex]::Escape($Marker)) { throw "/ai-review is missing $Marker." }
}
foreach ($Marker in @('GOVERNANCE_MEMORY','READ_ONLY_DISCOVERY_SWARM','GOVERNED_SKILL_ROUTING','DEPENDENCY_ADMISSION_GATE','PRE_CHANGE_SAFEPOINT','CLOSED_LOOP_LEARNING','MEMORY_DECISION')) {
    if ($StatusCommand -notmatch [regex]::Escape($Marker)) { throw "/ai-status is missing v2 marker $Marker." }
}
foreach ($Marker in @('RUN_STATE.json','STEERING.md','GOVERNANCE_RESULT','ENVIRONMENT_FINGERPRINT','STALE','OPERATIONAL_ASSURANCE','GOVERNANCE_MEMORY','DEPENDENCY_ADMISSION_GATE','PRE_CHANGE_SAFEPOINT','MEMORY_DECISION')) {
    if ($ResumeCommand -notmatch [regex]::Escape($Marker)) { throw "/ai-resume is missing $Marker." }
}
foreach ($Marker in @('DEPENDENCY_ADMISSION_GATE','PRE_CHANGE_SAFEPOINT','CLOSED_LOOP_LEARNING','MEMORY_DECISION')) {
    if ($ReleaseCommand -notmatch [regex]::Escape($Marker)) { throw "/ai-release is missing v2 release marker $Marker." }
}
foreach ($Marker in @('opencode stats','--models','opencode session list','opencode export','--sanitize','GOVERNANCE_METRICS','ESTIMATED_VALUES: NONE','UNAVAILABLE')) {
    if ($MetricsCommand -notmatch [regex]::Escape($Marker)) { throw "/ai-metrics is missing $Marker." }
}
if ($WorkflowCommand -notmatch 'EVIDENCE_STATUS' -or $StatusCommand -notmatch 'EVIDENCE_STATUS' -or $ResumeCommand -notmatch 'EVIDENCE_STATUS') { throw 'Machine-readable EVIDENCE_STATUS is missing.' }

$JsoncPath = Join-Path $ConfigDir 'opencode.jsonc'
$JsonPath = Join-Path $ConfigDir 'opencode.json'
$Target = if (Test-Path $JsoncPath) { $JsoncPath } elseif (Test-Path $JsonPath) { $JsonPath } else { $null }
if (-not $Target) { throw 'Missing OpenCode config file.' }
$Raw = Get-Content $Target -Raw
$Stripped = [regex]::Replace($Raw, '/\*.*?\*/', '', 'Singleline')
$Stripped = [regex]::Replace($Stripped, '(?m)^\s*//.*$', '')
$Stripped = [regex]::Replace($Stripped, ',\s*([}\]])', '$1')
try { $Obj = $Stripped | ConvertFrom-Json } catch { throw "Cannot parse $Target for verification." }
if ($Obj.default_agent -ne 'architect') { throw 'default_agent must be architect.' }
if (Get-Command opencode -ErrorAction SilentlyContinue) { & opencode debug config | Out-Null }
Write-Host 'Verification PASS'