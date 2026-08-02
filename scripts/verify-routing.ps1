param([string]$ConfigDir)

$ErrorActionPreference='Stop'
if(-not$ConfigDir){$ConfigDir=if($env:OPENCODE_CONFIG_DIR){$env:OPENCODE_CONFIG_DIR}else{Join-Path $HOME '.config/opencode'}}
$ManifestPath=Join-Path $ConfigDir 'opencode-governance-routing.json'
if(-not(Test-Path -LiteralPath $ManifestPath -PathType Leaf)){Write-Host 'PASS: model failover routing is not configured.';return}
try{$Manifest=Get-Content -LiteralPath $ManifestPath -Raw|ConvertFrom-Json}catch{throw 'Routing manifest is invalid JSON.'}
$Version=[string]$Manifest.governance_version
if($Version-eq'3.3.0'){& (Join-Path $PSScriptRoot 'verify-routing-core.ps1') -ConfigDir $ConfigDir;return}
$Supported=@('3.3.2','3.3.3','3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4','3.6.0','3.7.0','3.7.1','3.7.2','3.7.3','3.7.4','3.7.5','3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')
if($Version-notin$Supported){throw "Unsupported routing manifest governance_version: $Version"}

$ToolsDir=Join-Path $ConfigDir 'opencode-governance-tools'
$BaseTools=@((Join-Path $ToolsDir 'architect-attempt.ps1'),(Join-Path $ToolsDir 'architect-attempt.sh'),(Join-Path $ToolsDir 'executor-attempt.ps1'),(Join-Path $ToolsDir 'executor-attempt.sh'))
$ExpectedTools=@($BaseTools)
if($Version-in@('3.4.4','3.6.0','3.7.0','3.7.1','3.7.2','3.7.3','3.7.4','3.7.5','3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')){
    # Insert headless contract after architect runners for base+ layers that install it.
    $ExpectedTools=@($BaseTools[0],$BaseTools[1],(Join-Path $ToolsDir 'architect-headless-contract.py'),$BaseTools[2],$BaseTools[3])
    if($Version-in@('3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')){
        # Insert evidence-bound recovery module after headless contract.
        $ExpectedTools=@($BaseTools[0],$BaseTools[1],(Join-Path $ToolsDir 'architect-headless-contract.py'),(Join-Path $ToolsDir 'legacy-architect-orphan-recovery.py'),$BaseTools[2],$BaseTools[3])
    }
}
$ContextVersions=@('3.4.0','3.4.1','3.4.2','3.4.3','3.4.4','3.6.0','3.7.0','3.7.1','3.7.2','3.7.3','3.7.4','3.7.5','3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')
$HardenedVersions=@('3.4.1','3.4.2','3.4.3','3.4.4','3.6.0','3.7.0','3.7.1','3.7.2','3.7.3','3.7.4','3.7.5','3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')
$FingerprintVersions=@('3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4','3.6.0','3.7.0','3.7.1','3.7.2','3.7.3','3.7.4','3.7.5','3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')
$PowerShell7Versions=@('3.3.3','3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4','3.6.0','3.7.0','3.7.1','3.7.2','3.7.3','3.7.4','3.7.5','3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')
if($Version-in$ContextVersions){
    $ExpectedRunner=if($Version-eq'3.4.0'){'3.3.4'}else{$Version}
    if([string]$Manifest.architect_runner_version-ne$ExpectedRunner){throw "architect_runner_version must be $ExpectedRunner for Governance $Version."}
    if([string]$Manifest.context_intelligence_version-ne$Version){throw "context_intelligence_version must be $Version for Governance $Version."}
    $ExpectedTools+=@((Join-Path $ToolsDir 'context-intelligence.ps1'),(Join-Path $ToolsDir 'context-intelligence.sh'),(Join-Path $ToolsDir 'context-intelligence.py'))
    if($Version-in@('3.4.4','3.6.0','3.7.0','3.7.1','3.7.2','3.7.3','3.7.4','3.7.5','3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')){
        if([string]$Manifest.workflow_continuation_version-ne$Version){throw "workflow_continuation_version must be $Version."}
        $ExpectedTools+=@((Join-Path $ToolsDir 'workflow-continuation.ps1'),(Join-Path $ToolsDir 'workflow-continuation.py'))
    }
    if($Version-in@('3.8.0','4.0.0','4.0.1','4.0.2')){
        $ExpectedTools+=@(
            (Join-Path $ToolsDir 'governance-semantic.py'),
            (Join-Path $ToolsDir 'opencode-compatibility.py'),
            (Join-Path $ToolsDir 'governance-metrics.py'),
            (Join-Path $ToolsDir 'role-report-ingest.py')
        )
        if($Version-in@('4.0.1','4.0.2')){
            $ExpectedTools+=@(
                (Join-Path $ToolsDir 'install-effect-plugin.py'),
                (Join-Path $ToolsDir 'governed-role-launch.py')
            )
            if($Version-eq'4.0.2'){
                $ExpectedTools+=@(
                    (Join-Path $ToolsDir 'governed-role-attempt.py'),
                    (Join-Path $ToolsDir 'governance-read-git.py')
                )
            }
        }
    }
    if($Version-in@('3.6.0','3.7.0','3.7.1','3.7.2','3.7.3','3.7.4','3.7.5','3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')){
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
$ContextPs=Join-Path $ToolsDir 'context-intelligence.ps1'
$ContextSh=Join-Path $ToolsDir 'context-intelligence.sh'
$ContextPy=Join-Path $ToolsDir 'context-intelligence.py'
$WorkflowPs=Join-Path $ToolsDir 'workflow-continuation.ps1'
$WorkflowPy=Join-Path $ToolsDir 'workflow-continuation.py'
$HeadlessContractTool=Join-Path $ToolsDir 'architect-headless-contract.py'
if($Version-in$ContextVersions){$PolicyMarkers+=@('CONTEXT_INTELLIGENCE_V1','CONTEXT_BUDGET.json','SKILL_CAPABILITY_MANIFEST_V1','CONTEXT_SUFFICIENT','BLOCKED_CONTEXT_GAP',$ContextPs,$ContextSh,$ContextPy)}
if($Version-in$HardenedVersions){$PolicyMarkers+='Governance state paths may not traverse symbolic links or reparse points.'}
foreach($Name in @('architect','build','plan')){$Text=Get-Content -LiteralPath (Join-Path $ConfigDir "agents/$Name.md") -Raw;foreach($Value in $PolicyMarkers){if($Text-notlike"*$Value*"){throw "$Name missing Governance v$Version marker: $Value"}}}

$GateMarkers=@('ARCHITECT_RUNNER_ENTRY_GATE','ARCHITECT_RUNNER_REQUIRED',$Marker,$BaseTools[0],$BaseTools[1])
if($Version-in$PowerShell7Versions){$GateMarkers+='pwsh -NoProfile -File'}
if($Version-in$FingerprintVersions){$GateMarkers+='PROJECT_STATE_CHANGED'}
if($Version-in@('3.4.4','3.6.0','3.7.0','3.7.1','3.7.2','3.7.3','3.7.4','3.7.5','3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')){$GateMarkers+=@('WINDOWS_COMMAND:','UNIX_COMMAND:','-ProjectDir','--project-dir','<ORIGINAL_ARGUMENTS>')}
foreach($Command in @('ai-init','ai-audit','ai-discover','ai-plan')){$Text=Get-Content -LiteralPath (Join-Path $ConfigDir "commands/$Command.md") -Raw;foreach($Value in $GateMarkers){if($Text-notlike"*$Value*"){throw "$Command missing Architect entry gate marker: $Value"}}}
if($Version-in@('3.7.2','3.7.3','3.7.4','3.7.5','3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')){
    $ResumeMarkers=$GateMarkers+@('RESUME_MODE_V1','PRE_SIDE_EFFECT','POST_SIDE_EFFECT','TOOL_EXECUTION_ABORTED')
    $ResumeText=Get-Content -LiteralPath (Join-Path $ConfigDir 'commands/ai-resume.md') -Raw
    foreach($Value in $ResumeMarkers){if($ResumeText-notlike"*$Value*"){throw "ai-resume missing Architect entry gate marker: $Value"}}
}
if($Version-in$ContextVersions){foreach($Command in @('ai-workflow','ai-resume','ai-metrics')){$Text=Get-Content -LiteralPath (Join-Path $ConfigDir "commands/$Command.md") -Raw;foreach($Value in @('CONTEXT_INTELLIGENCE_ENTRY','BLOCKED_CONTEXT_GAP',$ContextPs,$ContextSh)){if($Text-notlike"*$Value*"){throw "$Command missing Context Intelligence marker: $Value"}}}}

if($Version-in$FingerprintVersions){
    $PowerShellRunner=Get-Content -LiteralPath $BaseTools[0] -Raw;$UnixRunner=Get-Content -LiteralPath $BaseTools[1] -Raw
    foreach($Value in @('PROJECT_STATE_FINGERPRINT_V1','PROJECT_STATE_CHANGED','Get-ProjectStateFingerprint')){if($PowerShellRunner-notlike"*$Value*"){throw "PowerShell Architect runner missing project-state marker: $Value"}}
    foreach($Value in @('PROJECT_STATE_FINGERPRINT_V1','PROJECT_STATE_CHANGED','project_state_fingerprint')){if($UnixRunner-notlike"*$Value*"){throw "Unix Architect runner missing project-state marker: $Value"}}
    if($Version-in@('3.7.2','3.7.3','3.7.4','3.7.5','3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')){foreach($Value in @('ai-resume','TOOL_EXECUTION_ABORTED','ARCHITECT_ORPHAN_RECOVERED','RESUME_POST_SIDE_EFFECT','ARCHITECT_TRANSACTION_V1','PRE_SIDE_EFFECT','POST_SIDE_EFFECT')){if($PowerShellRunner-notlike"*$Value*"-or$UnixRunner-notlike"*$Value*"){throw "Architect runner missing 3.7.2 reliability marker: $Value"}}}
    if($Version-in@('3.7.3','3.7.4','3.7.5','3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')){
        foreach($Value in @('ARCHITECT_HEADLESS_PERMISSION_CONTRACT_V1','OPENCODE_CONFIG_CONTENT','ARCHITECT_PERMISSION_BLOCKED','HEADLESS_PERMISSION_CONTRACT','auto=disabled','ROUTING_MANIFEST_HASHES')){if($PowerShellRunner-notlike"*$Value*"-or$UnixRunner-notlike"*$Value*"){throw "Architect runner missing 3.7.3 headless permission marker: $Value"}}
        if(-not(Test-Path -LiteralPath $HeadlessContractTool -PathType Leaf)){throw "Managed headless contract tool missing: $HeadlessContractTool"}
    }
    if($Version-in@('3.7.4','3.7.5','3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')){
        foreach($Value in @('ARCHITECT_STDIN_PROMPT_TRANSPORT_V1','ARCHITECT_PROMPT_TRANSPORT','ARCHITECT_PROMPT_TRANSPORT_FAILED','argv_prompt_bytes','prompt_transport')){if($PowerShellRunner-notlike"*$Value*"-or$UnixRunner-notlike"*$Value*"){throw "Architect runner missing 3.7.4 stdin transport marker: $Value"}}
        if($PowerShellRunner-notlike"*RedirectStandardInput*"){throw "PowerShell Architect runner missing RedirectStandardInput"}
        if($UnixRunner-notlike"*input=prompt_utf8*"){throw "Unix Architect runner missing input=prompt_utf8 stdin transport"}
    }
    if($Version-in@('3.7.5','3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')){
        foreach($Value in @('WORKSPACE_REPOSITORY_ROOT_CONTRACT_V1','MULTI_GOVERNANCE_ROOT_TRANSACTION_V1','PROJECT_STATE_CHANGESET_DIAGNOSTIC_V1','REPOSITORY_ROOT_AMBIGUOUS','managed_governance_roots','ARCHITECT_PHASE_ADVANCED','WorkspaceDir','RepositoryDir')){
            if($PowerShellRunner-notlike"*$Value*"-or$UnixRunner-notlike"*$Value*"){throw "Architect runner missing 3.7.5 nested-root marker: $Value"}
        }
    }
    if($Version-in@('3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')){
        foreach($Value in @('LEGACY_ARCHITECT_ORPHAN_RECOVERY_CONTRACT_V1','EVIDENCE_BOUND_RECOVERY_RECEIPT_V2','validate-governance-only','legacy-architect-orphan-recovery')){
            if($PowerShellRunner-notlike"*$Value*"-or$UnixRunner-notlike"*$Value*"){throw "Architect runner missing 3.7.6 legacy recovery marker: $Value"}
        }
        if($PowerShellRunner-notlike'*EvidenceBundlePath*'){throw 'PowerShell runner missing EvidenceBundlePath'}
        if($UnixRunner-notlike'*evidence-bundle-path*' -and $UnixRunner-notlike'*evidence_bundle*'){throw 'Unix runner missing evidence-bundle-path'}
        $LegacyRecoveryTool=Join-Path $ToolsDir 'legacy-architect-orphan-recovery.py'
        if(-not(Test-Path -LiteralPath $LegacyRecoveryTool -PathType Leaf)){throw "Managed legacy recovery tool missing: $LegacyRecoveryTool"}
        if($Version-in@('3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')){
            $RecoveryRaw=Get-Content -LiteralPath $LegacyRecoveryTool -Raw
            foreach($Value in @('LEGACY_FORENSIC_BUNDLE_V1_ADAPTER','LEGACY_PROJECT_STATE_FORENSICS_V1','CANONICAL_RECOVERY_EVIDENCE_V2')){
                if($RecoveryRaw-notlike"*$Value*"){throw "legacy recovery module missing 3.7.7 adapter marker: $Value"}
            }
        }
    }
    if($Version-in@('3.8.0','4.0.0','4.0.1','4.0.2')){
        $Sem=Join-Path $ToolsDir 'governance-semantic.py'
        if(-not(Test-Path -LiteralPath $Sem -PathType Leaf)){throw "Managed semantic tool missing: $Sem"}
        $SemRaw=Get-Content -LiteralPath $Sem -Raw
        foreach($Value in @('SEMANTIC_WORKFLOW_STATE_MACHINE_V1','TRANSITION_NOT_DEFINED')){
            if($SemRaw-notlike"*$Value*"){throw "semantic module missing 3.8.0 marker: $Value"}
        }
    }
    if($Version-in@('4.0.1','4.0.2')){
        $EffectInstaller=Join-Path $ToolsDir 'install-effect-plugin.py'
        if(-not(Test-Path -LiteralPath $EffectInstaller -PathType Leaf)){throw "Managed effect plugin installer missing: $EffectInstaller"}
        $EffectRaw=Get-Content -LiteralPath $EffectInstaller -Raw
        foreach($Value in @('EFFECT_PLUGIN_INSTALLATION_CONTRACT_V1','EFFECT_PLUGIN_RUNTIME_SELF_TEST_V1')){
            if($EffectRaw-notlike"*$Value*"){throw "effect plugin installer missing marker: $Value"}
        }
        foreach($Value in @('OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE','OPENCODE_GOVERNANCE_ROLE','GOVERNED_ROLE_LAUNCH_CONTRACT_V2')){
            if($PowerShellRunner-notlike"*$Value*" -and $Value -ne 'GOVERNED_ROLE_LAUNCH_CONTRACT_V2'){throw "Architect runner missing role-launch marker: $Value"}
        }
        if($PowerShellRunner-notlike'*GOVERNED_ROLE_LAUNCH_CONTRACT_V2*'-and$PowerShellRunner-notlike'*GOVERNED_ROLE_LAUNCH_CONTRACT_V1*'){throw 'Architect runner missing launch contract marker'}
        if($UnixRunner-notlike'*OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE*'-or$UnixRunner-notlike'*OPENCODE_GOVERNANCE_ROLE*'){throw 'Unix Architect runner missing role-launch markers'}
        # Ban live heal invocation, not documentation comments about the ban.
        if($PowerShellRunner-match 'install[^\n]*--skip-self-test'){throw 'Architect runner must not invoke install --skip-self-test'}
        if($UnixRunner-match 'install[^\n]*--skip-self-test'){throw 'Unix Architect runner must not invoke install --skip-self-test'}
        $Ingest=Join-Path $ToolsDir 'role-report-ingest.py'
        $IngestRaw=Get-Content -LiteralPath $Ingest -Raw
        if($Version-eq'4.0.2'){
            foreach($Value in @('DETERMINISTIC_ROLE_REPORT_INGESTION_V3','REVIEW_CHAIN_ATTESTATION_V3')){
                if($IngestRaw-notlike"*$Value*"){throw "role-report-ingest missing 4.0.2 marker: $Value"}
            }
            foreach($Name in @('governed-role-attempt.py','governance-read-git.py')){
                if(-not(Test-Path -LiteralPath (Join-Path $ToolsDir $Name) -PathType Leaf)){throw "Managed 4.0.2 tool missing: $Name"}
            }
        }else{
            foreach($Value in @('DETERMINISTIC_ROLE_REPORT_INGESTION_V2','REVIEW_CHAIN_ATTESTATION_V2')){
                if($IngestRaw-notlike"*$Value*"){throw "role-report-ingest missing 4.0.1 marker: $Value"}
            }
        }
        if(-not $Manifest.effect_plugin_sha256 -or -not $Manifest.effect_policy_sha256){throw 'Routing manifest missing effect plugin hash bindings'}
    }

    if($Version-in$HardenedVersions-and$PowerShellRunner-notlike'*default cooldown must be an integer between 60 and 86400 seconds.*'){throw 'PowerShell Architect runner missing cooldown validation.'}
}
if($Version-in$ContextVersions){
    $PsContext=Get-Content -LiteralPath $ContextPs -Raw;$ShContext=Get-Content -LiteralPath $ContextSh -Raw;$PyContext=Get-Content -LiteralPath $ContextPy -Raw
    foreach($Value in @('CONTEXT_BUDGET_V1','SKILL_SELECTION_V1','CONTENT_SUMMARY_CACHE_ENTRY_V1','CONTEXT_METRICS_V1')){if($PsContext-notlike"*$Value*"-or$PyContext-notlike"*$Value*"){throw "Context tool missing marker: $Value"}}
    if($ShContext-notlike'*context-intelligence.py*'){throw 'Unix context wrapper does not invoke the managed Python core.'}
    if($Version-in$HardenedVersions){foreach($Value in @('GOVERNANCE_STATE_LINK_FORBIDDEN','REQUIRED_SECTION_UNAVAILABLE','TERMINAL_STATE_REQUIRED')){if($PsContext-notlike"*$Value*"-or$PyContext-notlike"*$Value*"){throw "Context hardening marker missing: $Value"}}}
}
if($Version-in@('3.4.4','3.6.0','3.7.0','3.7.1','3.7.2','3.7.3','3.7.4','3.7.5','3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')){
    $PsWorkflow=Get-Content -LiteralPath $WorkflowPs -Raw;$PyWorkflow=Get-Content -LiteralPath $WorkflowPy -Raw
    foreach($Value in @('WORKFLOW_CONTINUATION_GATE_V1','CONTINUE_REQUIRED','TERMINAL_ALLOWED','INVALID_RUN_STATE','AUDIT_PASS','LOCAL_COMMITTED')){if($PsWorkflow-notlike"*$Value*"-or$PyWorkflow-notlike"*$Value*"){throw "Workflow continuation helper missing marker: $Value"}}
    foreach($Command in @('ai-workflow','ai-resume')){$Text=Get-Content -LiteralPath (Join-Path $ConfigDir "commands/$Command.md") -Raw;foreach($Value in @('WORKFLOW_CONTINUATION_GATE_V1','WINDOWS_WORKFLOW_CONTINUATION_CORE','UNIX_WORKFLOW_CONTINUATION_CORE',$WorkflowPs,$WorkflowPy,'CONTINUE_REQUIRED','TERMINAL_ALLOWED')){if($Text-notlike"*$Value*"){throw "$Command missing workflow continuation marker: $Value"}}}
}
if($Version-in@('3.6.0','3.7.0','3.7.1','3.7.2','3.7.3','3.7.4','3.7.5','3.7.6','3.7.7','3.8.0','4.0.0','4.0.1','4.0.2')){
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
