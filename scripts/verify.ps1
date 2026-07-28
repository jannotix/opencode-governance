param([string]$ConfigDir)

$ErrorActionPreference = 'Stop'
if (-not $ConfigDir) {
    $ConfigDir = if ($env:OPENCODE_CONFIG_DIR) {
        $env:OPENCODE_CONFIG_DIR
    } else {
        Join-Path $HOME '.config\opencode'
    }
}

$Agents = @(
    'architect', 'build', 'plan', 'executor',
    'reviewer', 'reviewer-architecture', 'final-reviewer'
)
$Commands = @(
    'ai-init', 'ai-audit', 'ai-docs', 'ai-discover',
    'ai-plan', 'ai-execute', 'ai-review', 'ai-workflow',
    'ai-status', 'ai-resume', 'ai-metrics', 'ai-release'
)
$ProductPaths = @(
    '.ai/product/PRODUCT_VISION.md',
    '.ai/product/USER_AND_ROLE_MODEL.md',
    '.ai/product/DOMAIN_AND_PROCESS_MODEL.md',
    '.ai/product/PRODUCT_COMPLETENESS_MATRIX.md',
    '.ai/product/PRODUCT_BLUEPRINT.md',
    '.ai/product/PRODUCT_DECISIONS.md'
)
$V2Markers = @(
    'VERIFICATION_PROFILE', 'TASK_RISK_PROFILE', 'VALIDATION_PROFILE',
    'BUGFIX_PROOF', 'TEST_IMPACT_MAP', 'CONTRACT_COMPATIBILITY',
    'ENVIRONMENT_FINGERPRINT', 'DEPENDENCY_ADMISSION_GATE',
    'DEPENDENCY_DELTA', 'GENERATED_ARTIFACT_GATE', 'PRE_CHANGE_SAFEPOINT',
    'MIGRATION_PROOF', 'NON_FUNCTIONAL_BUDGETS', 'FLAKINESS_EVIDENCE',
    'ADVERSARIAL_INPUT_VALIDATION', 'CODEOWNERS_HUMAN_GATE',
    'CLOSED_LOOP_LEARNING', 'OPERATIONAL_ASSURANCE',
    'PREVIEW_ENVIRONMENT_GATE', 'USER_FLOW_VERIFICATION',
    'VISUAL_BEHAVIOR_GATE', 'RELEASE_RECOVERY_PROOF',
    'TOOL_CAPABILITY_PROFILE', 'MCP_CAPABILITY_ASSESSMENT',
    'SAFE_EXPERIMENTATION', 'GOVERNED_SKILL_ROUTING',
    'GOVERNANCE_MEMORY', 'ADAPTIVE_OUTPUT_EFFICIENCY'
)
$V3Markers = @(
    'PRODUCT_LIFECYCLE_GOVERNANCE', 'WORK_CLASS',
    'DISCOVERY_DEPTH', 'ASSISTANCE_MODE',
    'ADAPTIVE_PRODUCT_DISCOVERY', 'CONSTRUCTIVE_CHALLENGE',
    'GUIDED_DECISION_POLICY', 'PRODUCT_COMPLETENESS_MATRIX.md',
    'PRODUCT_DECISIONS.md', 'PRODUCT_BLUEPRINT_VERSION',
    'MATERIAL_UNKNOWN_COUNT'
)

function Require-Text([string]$Path, [string]$Marker) {
    if (-not (Select-String -Path $Path -SimpleMatch $Marker -Quiet)) {
        throw "$Path missing $Marker"
    }
}

foreach ($Name in $Agents) {
    $Path = Join-Path $ConfigDir "agents\$Name.md"
    if (-not (Test-Path $Path -PathType Leaf)) { throw "Missing agent: $Name" }
    $Text = Get-Content $Path -Raw
    if ($Text -notmatch '(?m)^model: [^\s/]+/\S+\r?$') { throw "Missing provider-qualified model: $Name" }
    if ($Text -match '__[A-Z_]+__') { throw "Unrendered placeholder: $Name" }
    if ($Text -notmatch '(?m)^  skill:\s*$') { throw "$Name missing governed skill block" }
    foreach ($Marker in $V2Markers) { Require-Text $Path $Marker }
}

foreach ($Name in $Commands) {
    $Path = Join-Path $ConfigDir "commands\$Name.md"
    if (-not (Test-Path $Path -PathType Leaf)) { throw "Missing command: $Name" }
}

foreach ($Name in @('architect', 'build', 'plan')) {
    $Path = Join-Path $ConfigDir "agents\$Name.md"
    foreach ($Marker in $V3Markers) { Require-Text $Path $Marker }
}

foreach ($ProductPath in $ProductPaths) {
    foreach ($Name in @('architect', 'build', 'plan')) {
        Require-Text (Join-Path $ConfigDir "agents\$Name.md") $ProductPath
    }
    foreach ($Command in @('ai-init', 'ai-discover', 'ai-plan', 'ai-workflow', 'ai-status', 'ai-resume', 'ai-release')) {
        Require-Text (Join-Path $ConfigDir "commands\$Command.md") $ProductPath
    }
}

foreach ($Name in @('reviewer', 'reviewer-architecture', 'final-reviewer')) {
    Require-Text (Join-Path $ConfigDir "agents\$Name.md") 'DISCOVERY_REVIEW'
}
foreach ($Marker in @('DISCOVERY_PASS', 'DISCOVERY_DEFECT', 'DISCOVERY_BLOCKED')) {
    Require-Text (Join-Path $ConfigDir 'agents\final-reviewer.md') $Marker
}
foreach ($Marker in @(
    'PRODUCT_COMPLETENESS_VERDICT', 'PRODUCT_COMPLETE',
    'PRODUCT_DEFECT', 'PRODUCT_BLOCKED', 'RELEASE_VERDICT',
    'READY_FOR_PRODUCTION', 'NOT_READY_FOR_PRODUCTION'
)) {
    Require-Text (Join-Path $ConfigDir 'agents\final-reviewer.md') $Marker
    Require-Text (Join-Path $ConfigDir 'commands\ai-release.md') $Marker
}
foreach ($Marker in @(
    'ADAPTIVE_PRODUCT_DISCOVERY', 'WORK_CLASS', 'DISCOVERY_DEPTH',
    'CONSTRUCTIVE_CHALLENGE', 'PRODUCT_COMPLETENESS_MATRIX.md',
    'PRODUCT_DECISIONS.md', 'DISCOVERY_PASS', 'refresh', 'audit'
)) {
    Require-Text (Join-Path $ConfigDir 'commands\ai-discover.md') $Marker
}
foreach ($Marker in @(
    'PRODUCT_CAPABILITY_TRACEABILITY', 'VERTICAL_MILESTONE',
    'MILESTONE_VALIDATED', 'PRODUCT_INCOMPLETE'
)) {
    Require-Text (Join-Path $ConfigDir 'agents\executor.md') $Marker
}

foreach ($Name in @('architect', 'build')) {
    $Text = Get-Content (Join-Path $ConfigDir "agents\$Name.md") -Raw
    if ($Text -notmatch '(?m)^\s+explore:\s+allow\s*$') { throw "$Name must allow explore" }
    if ($Text -notmatch '(?m)^\s+scout:\s+allow\s*$') { throw "$Name must allow scout" }
    if ($Text -match '(?m)^\s+general:\s+allow\s*$') { throw "$Name must not allow General" }
}

$PlanText = Get-Content (Join-Path $ConfigDir 'agents\plan.md') -Raw
if ($PlanText -notmatch '(?m)^  task: deny\s*$') { throw 'Plan must deny task delegation' }
$ExecutorText = Get-Content (Join-Path $ConfigDir 'agents\executor.md') -Raw
if ($ExecutorText -notmatch 'external_directory:\s+deny') { throw 'Executor must deny external_directory' }

$SemanticCommon = @('EVIDENCE_FRESHNESS','REVIEW_FREEZE','BOUNDED_REPAIR','NO_AUTOMATIC_EXTERNAL_ACTION')
foreach ($Name in @('architect','build','reviewer','reviewer-architecture','final-reviewer')) {
    foreach ($Marker in $SemanticCommon) { Require-Text (Join-Path $ConfigDir "agents\$Name.md") $Marker }
}
foreach ($Marker in @('BASELINE_DUAL_AUDIT','REQUIREMENT_PROVENANCE')) { Require-Text (Join-Path $ConfigDir 'agents\architect.md') $Marker }
foreach ($Marker in @('REQUIREMENT_PROVENANCE','NO_AUTOMATIC_EXTERNAL_ACTION')) { Require-Text (Join-Path $ConfigDir 'agents\plan.md') $Marker }
foreach ($Marker in @('EVIDENCE_FRESHNESS','REVIEW_FREEZE','NO_AUTOMATIC_EXTERNAL_ACTION','PLAN_CONFLICT')) { Require-Text (Join-Path $ConfigDir 'agents\executor.md') $Marker }
foreach ($Command in @('ai-init','ai-discover','ai-plan','ai-workflow','ai-execute','ai-review','ai-release')) { Require-Text (Join-Path $ConfigDir "commands\$Command.md") 'NO_AUTOMATIC_EXTERNAL_ACTION' }
foreach ($Command in @('ai-workflow','ai-review','ai-resume')) { Require-Text (Join-Path $ConfigDir "commands\$Command.md") 'REVIEW_FREEZE' }

foreach ($Directory in @((Join-Path $ConfigDir 'agents'), (Join-Path $ConfigDir 'commands'))) {
    $Matches = Get-ChildItem $Directory -Filter '*.md' |
        Select-String -Pattern 'DISCOVERY_DEPTH[^\r\n]{0,30}NONE|NONE\s*\|\s*LIGHT'
    if ($Matches) { throw 'Discovery depth NONE is forbidden in v3' }
}

$JsoncPath = Join-Path $ConfigDir 'opencode.jsonc'
$JsonPath = Join-Path $ConfigDir 'opencode.json'
$Target = if (Test-Path $JsoncPath) { $JsoncPath } else { $JsonPath }
if (-not (Test-Path $Target)) { throw 'Missing OpenCode config file' }
$Raw = Get-Content $Target -Raw
$Stripped = [regex]::Replace($Raw, '/\*.*?\*/', '', 'Singleline')
$Stripped = [regex]::Replace($Stripped, '(?m)^\s*//.*$', '')
$Stripped = [regex]::Replace($Stripped, ',\s*([}\]])', '$1')
$Object = $Stripped | ConvertFrom-Json
if ($Object.default_agent -ne 'architect') { throw 'default_agent must be architect' }

Write-Host 'PASS: OpenCode Governance v3.0 rendered contract verified (7 agents, 12 commands).'
