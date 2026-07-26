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
}

$ArchitectModel = [regex]::Match($AgentText['architect'], '(?m)^model:\s+(\S+)\s*$').Groups[1].Value
foreach ($Alias in @('build','plan')) {
    $AliasModel = [regex]::Match($AgentText[$Alias], '(?m)^model:\s+(\S+)\s*$').Groups[1].Value
    if ($AliasModel -ne $ArchitectModel) { throw "$Alias must use the Architect model. Expected $ArchitectModel, found $AliasModel" }
}

if ($AgentText['build'] -notmatch '(?m)^\s+executor:\s+allow\s*$' -or
    $AgentText['build'] -notmatch '(?m)^\s+reviewer:\s+allow\s*$' -or
    $AgentText['build'] -notmatch '(?m)^\s+reviewer-architecture:\s+allow\s*$' -or
    $AgentText['build'] -notmatch '(?m)^\s+final-reviewer:\s+allow\s*$') {
    throw 'Governed Build is missing required subagent delegation permissions.'
}
if ($AgentText['plan'] -notmatch '(?m)^\s+task:\s+deny\s*$') { throw 'Governed Plan must deny task delegation.' }

foreach ($Name in @('architect','build','plan')) {
    if ($AgentText[$Name] -notmatch '(?m)^\s*question:\s+allow\s*$') { throw "$Name must explicitly allow the OpenCode question tool." }
}

if ($AgentText['architect'] -notmatch 'BASELINE_VALIDATED') { throw 'Architect is missing baseline validation gate.' }
if ($AgentText['architect'] -notmatch 'DOCUMENTATION_SCOPE') { throw 'Architect is missing project documentation governance.' }
if ($AgentText['architect'] -notmatch 'DOCUMENTATION_IMPACT') { throw 'Architect is missing documentation impact planning.' }
if ($AgentText['architect'] -notmatch 'LICENSE_DECISION_REQUIRED') { throw 'Architect is missing explicit license-decision gating.' }
if ($AgentText['executor'] -notmatch 'DOCUMENTATION_IMPACT') { throw 'Executor is missing documentation synchronization rules.' }

foreach ($Name in @('reviewer','reviewer-architecture')) {
    foreach ($Mode in @('TASK_REVIEW','BASELINE_AUDIT','RELEASE_REVIEW')) {
        if ($AgentText[$Name] -notmatch $Mode) { throw "$Name is missing $Mode mode." }
    }
    if ($AgentText[$Name] -notmatch 'documentation') { throw "$Name is missing documentation review coverage." }
}
foreach ($Mode in @('TASK_REVIEW','BASELINE_AUDIT','RELEASE_REVIEW')) {
    if ($AgentText['final-reviewer'] -notmatch $Mode) { throw "Final Reviewer is missing $Mode mode." }
}
if ($AgentText['final-reviewer'] -notmatch 'BASELINE_PASS' -or $AgentText['final-reviewer'] -notmatch 'BASELINE_DEFECT') { throw 'Final Reviewer is missing baseline adjudication verdicts.' }
if ($AgentText['final-reviewer'] -notmatch 'LICENSE_DECISION_REQUIRED') { throw 'Final Reviewer is missing license-readiness gating.' }

foreach ($Name in @('ai-init','ai-audit','ai-docs','ai-plan','ai-execute','ai-review','ai-workflow','ai-status','ai-release')) {
    $Path = Join-Path $ConfigDir "commands\$Name.md"
    if (-not (Test-Path $Path) -or (Get-Item $Path).Length -eq 0) { throw "Missing command: $Name" }
}

$DocsCommand = Get-Content (Join-Path $ConfigDir 'commands\ai-docs.md') -Raw
if ($DocsCommand -notmatch 'docs/INSTALLATION.md' -or $DocsCommand -notmatch 'docs/USER_MANUAL.md' -or $DocsCommand -notmatch 'docs/wiki/README.md') {
    throw '/ai-docs is missing required distributable-application documentation coverage.'
}

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