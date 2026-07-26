param([string]$ConfigDir = $(if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $HOME '.config\opencode' }))
$ErrorActionPreference = 'Stop'

$AgentNames = @('architect','build','plan','executor','reviewer','reviewer-architecture','final-reviewer')
$AgentText = @{}
foreach ($Name in $AgentNames) {
    $Path = Join-Path $ConfigDir "agents\$Name.md"
    if (-not (Test-Path $Path) -or (Get-Item $Path).Length -eq 0) { throw "Missing agent: $Name" }
    $Text = Get-Content $Path -Raw; $AgentText[$Name] = $Text
    if ($Text -notmatch '(?m)^model:\s+([^/\s]+/\S+)\s*$') { throw "Missing provider-qualified model in $Path" }
    if ($Text -match '__[A-Z_]+__') { throw "Unrendered placeholder in $Path" }
}

$ArchitectModel = [regex]::Match($AgentText['architect'], '(?m)^model:\s+(\S+)\s*$').Groups[1].Value
foreach ($Alias in @('build','plan')) {
    $AliasModel = [regex]::Match($AgentText[$Alias], '(?m)^model:\s+(\S+)\s*$').Groups[1].Value
    if ($AliasModel -ne $ArchitectModel) { throw "$Alias must use the Architect model. Expected $ArchitectModel, found $AliasModel" }
}
if ($AgentText['build'] -notmatch '(?m)^\s+executor:\s+allow\s*$' -or $AgentText['build'] -notmatch '(?m)^\s+reviewer:\s+allow\s*$' -or $AgentText['build'] -notmatch '(?m)^\s+reviewer-architecture:\s+allow\s*$' -or $AgentText['build'] -notmatch '(?m)^\s+final-reviewer:\s+allow\s*$') { throw 'Governed Build is missing required subagent delegation permissions.' }
if ($AgentText['plan'] -notmatch '(?m)^\s+task:\s+deny\s*$') { throw 'Governed Plan must deny task delegation.' }
foreach ($Name in @('architect','build','plan')) { if ($AgentText[$Name] -notmatch '(?m)^\s*question:\s+allow\s*$') { throw "$Name must explicitly allow the OpenCode question tool." } }

foreach ($Marker in @('BASELINE_VALIDATED','DOCUMENTATION_SCOPE','DOCUMENTATION_IMPACT','LICENSE_DECISION_REQUIRED','CONTEXT_INDEX.md','CONTEXT_MANIFEST.md','RUN_STATE.json','MINIMUM_CHANGE_ASSESSMENT','STEERING.md')) { if ($AgentText['architect'] -notmatch [regex]::Escape($Marker)) { throw "Architect is missing v1.6 governance marker $Marker." } }
foreach ($Marker in @('ORIGINAL_USER_REQUEST.md','CLARIFICATION_TRANSCRIPT.md','APPROVED_REQUIREMENTS.md')) { if ($AgentText['architect'] -notmatch [regex]::Escape($Marker) -or $AgentText['final-reviewer'] -notmatch [regex]::Escape($Marker)) { throw "Missing canonical requirement artifact marker $Marker." } }
foreach ($Marker in @('EXECUTION_PACKET.md','CONTEXT_MANIFEST.md','RUN_STATE.json','MINIMUM_CHANGE_ASSESSMENT')) { if ($AgentText['executor'] -notmatch [regex]::Escape($Marker)) { throw "Executor is missing $Marker." } }
if ($AgentText['reviewer'] -notmatch 'REVIEW_IMPLEMENTATION_PACKET.md') { throw 'Implementation Reviewer is missing fresh evidence packet policy.' }
if ($AgentText['reviewer-architecture'] -notmatch 'REVIEW_ARCHITECTURE_PACKET.md' -or $AgentText['reviewer-architecture'] -notmatch 'context-efficient') { throw 'Architecture Reviewer is missing targeted context policy.' }
if ($AgentText['final-reviewer'] -notmatch 'FINAL_PACKET.md' -or $AgentText['final-reviewer'] -notmatch 'perfect implementation') { throw 'Final Reviewer is missing final packet or Architect-plan challenge policy.' }

foreach ($Name in @('reviewer','reviewer-architecture')) { foreach ($Mode in @('TASK_REVIEW','BASELINE_AUDIT','RELEASE_REVIEW')) { if ($AgentText[$Name] -notmatch $Mode) { throw "$Name is missing $Mode mode." } } }
foreach ($Mode in @('TASK_REVIEW','BASELINE_AUDIT','RELEASE_REVIEW')) { if ($AgentText['final-reviewer'] -notmatch $Mode) { throw "Final Reviewer is missing $Mode mode." } }
if ($AgentText['final-reviewer'] -notmatch 'BASELINE_PASS' -or $AgentText['final-reviewer'] -notmatch 'BASELINE_DEFECT' -or $AgentText['final-reviewer'] -notmatch 'LICENSE_DECISION_REQUIRED') { throw 'Final Reviewer is missing baseline/license gates.' }

$RequiredCommands = @('ai-init','ai-audit','ai-docs','ai-plan','ai-execute','ai-review','ai-workflow','ai-status','ai-resume','ai-release')
foreach ($Name in $RequiredCommands) { $Path = Join-Path $ConfigDir "commands\$Name.md"; if (-not (Test-Path $Path) -or (Get-Item $Path).Length -eq 0) { throw "Missing command: $Name" } }

$DocsCommand = Get-Content (Join-Path $ConfigDir 'commands\ai-docs.md') -Raw
if ($DocsCommand -notmatch 'docs/INSTALLATION.md' -or $DocsCommand -notmatch 'docs/USER_MANUAL.md' -or $DocsCommand -notmatch 'docs/wiki/README.md') { throw '/ai-docs is missing required documentation coverage.' }
$WorkflowCommand = Get-Content (Join-Path $ConfigDir 'commands\ai-workflow.md') -Raw
$ReviewCommand = Get-Content (Join-Path $ConfigDir 'commands\ai-review.md') -Raw
$ResumeCommand = Get-Content (Join-Path $ConfigDir 'commands\ai-resume.md') -Raw
foreach ($Marker in @('ORIGINAL_USER_REQUEST.md','CLARIFICATION_TRANSCRIPT.md','APPROVED_REQUIREMENTS.md','CONTEXT_MANIFEST.md','RUN_STATE.json','MINIMUM_CHANGE_ASSESSMENT')) { if ($WorkflowCommand -notmatch [regex]::Escape($Marker)) { throw "/ai-workflow is missing $Marker." } }
foreach ($Marker in @('REVIEW_IMPLEMENTATION_PACKET.md','REVIEW_ARCHITECTURE_PACKET.md','FINAL_PACKET.md')) { if ($ReviewCommand -notmatch [regex]::Escape($Marker)) { throw "/ai-review is missing $Marker." } }
foreach ($Marker in @('RUN_STATE.json','STEERING.md','GOVERNANCE_RESULT')) { if ($ResumeCommand -notmatch [regex]::Escape($Marker)) { throw "/ai-resume is missing $Marker." } }

$JsoncPath = Join-Path $ConfigDir 'opencode.jsonc'; $JsonPath = Join-Path $ConfigDir 'opencode.json'
$Target = if (Test-Path $JsoncPath) { $JsoncPath } elseif (Test-Path $JsonPath) { $JsonPath } else { $null }
if (-not $Target) { throw 'Missing OpenCode config file.' }
$Raw = Get-Content $Target -Raw; $Stripped = [regex]::Replace($Raw, '/\*.*?\*/', '', 'Singleline'); $Stripped = [regex]::Replace($Stripped, '(?m)^\s*//.*$', ''); $Stripped = [regex]::Replace($Stripped, ',\s*([}\]])', '$1')
try { $Obj = $Stripped | ConvertFrom-Json } catch { throw "Cannot parse $Target for verification." }
if ($Obj.default_agent -ne 'architect') { throw 'default_agent must be architect.' }
if (Get-Command opencode -ErrorAction SilentlyContinue) { & opencode debug config | Out-Null }
Write-Host 'Verification PASS'
