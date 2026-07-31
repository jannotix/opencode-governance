param([string]$ConfigDir)

$ErrorActionPreference='Stop'
if(-not$ConfigDir){$ConfigDir=if($env:OPENCODE_CONFIG_DIR){$env:OPENCODE_CONFIG_DIR}else{Join-Path $HOME '.config/opencode'}}
$ManifestPath=Join-Path $ConfigDir 'opencode-governance-routing.json'
if(-not(Test-Path -LiteralPath $ManifestPath -PathType Leaf)){Write-Host 'PASS: model failover routing is not configured.';return}
try{$Manifest=Get-Content -LiteralPath $ManifestPath -Raw|ConvertFrom-Json}catch{throw 'Routing manifest is invalid JSON.'}
$Version=[string]$Manifest.governance_version
if($Version-eq'3.3.0'){& (Join-Path $PSScriptRoot 'verify-routing-core.ps1') -ConfigDir $ConfigDir;return}
$Supported=@('3.3.2','3.3.3','3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4','3.6.0','3.7.0','3.7.1')
if($Version-notin$Supported){throw "Unsupported routing manifest governance_version: $Version"}

$ToolsDir=Join-Path $ConfigDir 'opencode-governance-tools'
$BaseTools=@((Join-Path $ToolsDir 'architect-attempt.ps1'),(Join-Path $ToolsDir 'architect-attempt.sh'),(Join-Path $ToolsDir 'executor-attempt.ps1'),(Join-Path $ToolsDir 'executor-attempt.sh'))
$ExpectedTools=@($BaseTools)
$ContextVersions=@('3.4.0','3.4.1','3.4.2','3.4.3','3.4.4','3.6.0','3.7.0','3.7.1')
$HardenedVersions=@('3.4.1','3.4.2','3.4.3','3.4.4','3.6.0','3.7.0','3.7.1')
$FingerprintVersions=@('3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4','3.6.0','3.7.0','3.7.1')
$PowerShell7Versions=@('3.3.3','3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4','3.6.0','3.7.0','3.7.1')
if($Version-in$ContextVersions){
    $ExpectedRunner=if($Version-eq'3.4.0'){'3.3.4'}else{$Version}
    if([string]$Manifest.architect_runner_version-ne$ExpectedRunner){throw "architect_runner_version must be $ExpectedRunner for Governance $Version."}
    if([string]$Manifest.context_intelligence_version-ne$Version){throw "context_intelligence_version must be $Version for Governance $Version."}
    $ExpectedTools+=@((Join-Path $ToolsDir 'context-intelligence.ps1'),(Join-Path $ToolsDir 'context-intelligence.sh'),(Join-Path $ToolsDir 'context-intelligence.py'))
    if($Version-in@('3.4.4','3.6.0','3.7.0','3.7.1')){
        if([string]$Manifest.workflow_continuation_version-ne$Version){throw "workflow_continuation_version must be $Version."}
        $ExpectedTools+=@((Join-Path $ToolsDir 'workflow-continuation.ps1'),(Join-Path $ToolsDir 'workflow-continuation.py'))
    }
    if($Version-in@('3.6.0','3.7.0','3.7.1')){
        $ExpectedTools+=@(
            (Join-Path $ToolsDir 'governance-authority.py'),
            (Join-Path $ToolsDir 'governance-memory.py'),
            (Join-Path $ToolsDir 'governance-evidence.py'),
            (Join-Path $ToolsDir 'governance-simulation.py'),
            (Join-Path $ToolsDir 'governance-pre-commit.py')
        )
    }
}else{
    if([string]$Manifest.architect_runner_version-ne$Version){throw "architect_runner_version must be $Version."}
    if($Manifest.PSObject.Properties.Name-contains'context_intelligence_version'){throw "context_intelligence_version is not valid for Governance $Version."}
    if($Manifest.PSObject.Properties.Name-contains'workflow_continuation_version'){throw "workflow_continuation_version is not valid for Governance $Version."}
}
$ManagedTools=@($Manifest.managed_tools|ForEach-Object{[string]$_})
if($ManagedTools.Count-ne$ExpectedTools.Count){throw "Managed tool count does not match the v$Version contract."}
foreach($Tool in $ExpectedTools){if($Tool-notin$ManagedTools){throw "Managed tool missing from manifest: $Tool"};if(-not(Test-Path -LiteralPath $Tool -PathType Leaf)){throw "Managed tool missing from disk: $Tool"}}

$Marker='[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
$PolicyMarkers=@('ARCHITECT_RUNNER_INTEGRATION','ARCHITECT_RUNNER_REQUIRED',$Marker,$BaseTools[0],$BaseTools[1],'Never invoke the Architect runner from inside the active OpenCode process.')
if($Version-in$PowerShell7Versions){$PolicyMarkers+=@('POWERSHELL_7_REQUIRED','pwsh -NoProfile -File')}
if($Version-in$FingerprintVersions){$PolicyMarkers+=@('PROJECT_STATE_FINGERPRINT_V1','NON_GIT_PROJECT_SUPPORTED','PROJECT_STATE_CHANGED')}
if($Version-in$ContextVersions){$PolicyMarkers+=@('CONTEXT_INTELLIGENCE_V1','CONTEXT_BUDGET.json','SKILL_CAPABILITY_MANIFEST_V1','CONTEXT_SUFFICIENT','BLOCKED_CONTEXT_GAP',$ExpectedTools[4],$ExpectedTools[5],$ExpectedTools[6])}
if($Version-in$HardenedVersions){$PolicyMarkers+='Governance state paths may not traverse symbolic links or reparse points.'}
foreach($Name in @('architect','build','plan')){$Text=Get-Content -LiteralPath (Join-Path $ConfigDir "agents/$Name.md") -Raw;foreach($Value in $PolicyMarkers){if($Text-notlike"*$Value*"){throw "$Name missing Governance v$Version marker: $Value"}}}

$GateMarkers=@('ARCHITECT_RUNNER_ENTRY_GATE','ARCHITECT_RUNNER_REQUIRED',$Marker,$BaseTools[0],$BaseTools[1])
if($Version-in$PowerShell7Versions){$GateMarkers+='pwsh -NoProfile -File'}
if($Version-in$FingerprintVersions){$GateMarkers+='PROJECT_STATE_CHANGED'}
if($Version-in@('3.4.4','3.6.0','3.7.0','3.7.1')){$GateMarkers+=@('WINDOWS_COMMAND:','UNIX_COMMAND:','-ProjectDir','--project-dir','<ORIGINAL_ARGUMENTS>')}
foreach($Command in @('ai-init','ai-audit','ai-discover','ai-plan')){$Text=Get-Content -LiteralPath (Join-Path $ConfigDir "commands/$Command.md") -Raw;foreach($Value in $GateMarkers){if($Text-notlike"*$Value*"){throw "$Command missing Architect entry gate marker: $Value"}}}
if($Version-in$ContextVersions){foreach($Command in @('ai-workflow','ai-resume','ai-metrics')){$Text=Get-Content -LiteralPath (Join-Path $ConfigDir "commands/$Command.md") -Raw;foreach($Value in @('CONTEXT_INTELLIGENCE_ENTRY','BLOCKED_CONTEXT_GAP',$ExpectedTools[4],$ExpectedTools[5])){if($Text-notlike"*$Value*"){throw "$Command missing Context Intelligence marker: $Value"}}}}

if($Version-in$FingerprintVersions){
    $PowerShellRunner=Get-Content -LiteralPath $BaseTools[0] -Raw;$UnixRunner=Get-Content -LiteralPath $BaseTools[1] -Raw
    foreach($Value in @('PROJECT_STATE_FINGERPRINT_V1','PROJECT_STATE_CHANGED','Get-ProjectStateFingerprint')){if($PowerShellRunner-notlike"*$Value*"){throw "PowerShell Architect runner missing project-state marker: $Value"}}
    foreach($Value in @('PROJECT_STATE_FINGERPRINT_V1','PROJECT_STATE_CHANGED','project_state_fingerprint')){if($UnixRunner-notlike"*$Value*"){throw "Unix Architect runner missing project-state marker: $Value"}}
    if($Version-in$HardenedVersions-and$PowerShellRunner-notlike'*default cooldown must be an integer between 60 and 86400 seconds.*'){throw 'PowerShell Architect runner missing cooldown validation.'}
}
if($Version-in$ContextVersions){
    $PsContext=Get-Content -LiteralPath $ExpectedTools[4] -Raw;$ShContext=Get-Content -LiteralPath $ExpectedTools[5] -Raw;$PyContext=Get-Content -LiteralPath $ExpectedTools[6] -Raw
    foreach($Value in @('CONTEXT_BUDGET_V1','SKILL_SELECTION_V1','CONTENT_SUMMARY_CACHE_ENTRY_V1','CONTEXT_METRICS_V1')){if($PsContext-notlike"*$Value*"-or$PyContext-notlike"*$Value*"){throw "Context tool missing marker: $Value"}}
    if($ShContext-notlike'*context-intelligence.py*'){throw 'Unix context wrapper does not invoke the managed Python core.'}
    if($Version-in$HardenedVersions){foreach($Value in @('GOVERNANCE_STATE_LINK_FORBIDDEN','REQUIRED_SECTION_UNAVAILABLE','TERMINAL_STATE_REQUIRED')){if($PsContext-notlike"*$Value*"-or$PyContext-notlike"*$Value*"){throw "Context hardening marker missing: $Value"}}}
}
if($Version-in@('3.4.4','3.6.0','3.7.0','3.7.1')){
    $PsWorkflow=Get-Content -LiteralPath $ExpectedTools[7] -Raw;$PyWorkflow=Get-Content -LiteralPath $ExpectedTools[8] -Raw
    foreach($Value in @('WORKFLOW_CONTINUATION_GATE_V1','CONTINUE_REQUIRED','TERMINAL_ALLOWED','INVALID_RUN_STATE','AUDIT_PASS','LOCAL_COMMITTED')){if($PsWorkflow-notlike"*$Value*"-or$PyWorkflow-notlike"*$Value*"){throw "Workflow continuation helper missing marker: $Value"}}
    foreach($Command in @('ai-workflow','ai-resume')){$Text=Get-Content -LiteralPath (Join-Path $ConfigDir "commands/$Command.md") -Raw;foreach($Value in @('WORKFLOW_CONTINUATION_GATE_V1','WINDOWS_WORKFLOW_CONTINUATION_CORE','UNIX_WORKFLOW_CONTINUATION_CORE',$ExpectedTools[7],$ExpectedTools[8],'CONTINUE_REQUIRED','TERMINAL_ALLOWED')){if($Text-notlike"*$Value*"){throw "$Command missing workflow continuation marker: $Value"}}}
}
if($Version-in@('3.6.0','3.7.0','3.7.1')){
    $Capabilities=Join-Path $PSScriptRoot 'governance-capabilities.py'
    if(-not(Test-Path -LiteralPath $Capabilities -PathType Leaf)){throw "Capability verifier not found: $Capabilities"}
    $Process=Start-Process -FilePath 'python' -ArgumentList @($Capabilities,'verify','--config-dir',$ConfigDir) -NoNewWindow -Wait -PassThru
    if($Process.ExitCode-ne0){throw "Governance capability verification failed with exit code $($Process.ExitCode)."}
}
$Temp=Join-Path ([IO.Path]::GetTempPath()) ('opencode-routing-compat-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Force -Path (Join-Path $Temp 'agents'),(Join-Path $Temp 'opencode-governance-tools')|Out-Null
    Copy-Item (Join-Path $ConfigDir 'agents/*.md') (Join-Path $Temp 'agents') -Force
    Copy-Item $BaseTools[2] (Join-Path $Temp 'opencode-governance-tools/executor-attempt.ps1') -Force;Copy-Item $BaseTools[3] (Join-Path $Temp 'opencode-governance-tools/executor-attempt.sh') -Force
    $Normalized=Get-Content -LiteralPath $ManifestPath -Raw|ConvertFrom-Json;$Normalized.governance_version='3.3.0';$Normalized.PSObject.Properties.Remove('architect_runner_version');$Normalized.PSObject.Properties.Remove('context_intelligence_version');$Normalized.PSObject.Properties.Remove('workflow_continuation_version')
    foreach($Field in @('candidate_authority_version','governed_memory_version','evidence_reuse_version','simulation_harness_version','pre_commit_receipt_gate_version','actionable_continuation_version','capability_tool_hashes','capability_section_hashes','memory_store','capabilities_installed_at')){$Normalized.PSObject.Properties.Remove($Field)}
    $Normalized.managed_tools=@((Join-Path $Temp 'opencode-governance-tools/executor-attempt.ps1'),(Join-Path $Temp 'opencode-governance-tools/executor-attempt.sh'))
    [IO.File]::WriteAllText((Join-Path $Temp 'opencode-governance-routing.json'),(($Normalized|ConvertTo-Json -Depth 30)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
    & (Join-Path $PSScriptRoot 'verify-routing-core.ps1') -ConfigDir $Temp
}finally{Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host "PASS: OpenCode Governance v$Version routing verified ($(@($Manifest.managed_aliases).Count) hidden routes; $($ExpectedTools.Count) managed tools verified)."
