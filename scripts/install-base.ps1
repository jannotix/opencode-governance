param(
    [string]$ConfigDir,
    [string]$ArchitectModel,
    [string]$ArchitectVariant,
    [string]$ExecutorModel,
    [string]$ExecutorVariant,
    [string]$ReviewerImplementationModel,
    [string]$ReviewerImplementationVariant,
    [string]$ReviewerArchitectureModel,
    [string]$ReviewerArchitectureVariant,
    [string]$FinalReviewerModel,
    [string]$FinalReviewerVariant,
    [string]$RoutingConfigPath,
    [switch]$NonInteractive
)

$ErrorActionPreference='Stop'
if(-not$ConfigDir){$ConfigDir=if($env:OPENCODE_CONFIG_DIR){$env:OPENCODE_CONFIG_DIR}else{Join-Path $HOME '.config/opencode'}}

function Test-RoutingProfile([string]$Path){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "Routing profile not found: $Path"}
    try{$Profile=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}catch{throw "Invalid routing profile JSON: $Path"}
    if([string]$Profile.schema_version-ne'1.0'){throw 'Routing schema_version must be 1.0.'}
    if($null-eq$Profile.settings-or$null-eq$Profile.roles){throw 'Routing profile must contain settings and roles objects.'}
    $RoleNames=@('architect','executor','reviewer','reviewer-architecture','final-reviewer')
    $Failures=@('PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT')
    $OnlyOnAllowed=$Failures+@('MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS')
    $WorkClasses=@('PATCH','BOUNDED_FEATURE','MAJOR_FEATURE','EXISTING_PRODUCT_EVOLUTION','NEW_PRODUCT','HIGH_RISK_CHANGE')

    function Get-JsonArray([object]$Owner,[string]$Name,[string]$Context,[bool]$Required=$true){
        $Property=$Owner.PSObject.Properties[$Name]
        if($null-eq$Property){if($Required){throw "$Context must be an array."};return}
        $Value=$Property.Value
        if($Value-is[string]-or$Value-isnot[System.Collections.IEnumerable]){throw "$Context must be an array."}
        @($Value)
    }
    function Test-JsonInteger([object]$Value){($Value-is[int])-or($Value-is[long])}

    $Enabled=@(Get-JsonArray $Profile.settings 'enabled_roles' 'settings.enabled_roles')
    $Eligible=@(Get-JsonArray $Profile.settings 'eligible_failures' 'settings.eligible_failures')
    if(@($Enabled|Where-Object{$_-isnot[string]-or[string]::IsNullOrWhiteSpace([string]$_)-or([string]$_-notin$RoleNames)}).Count-gt0){throw 'Routing profile contains an unsupported enabled role.'}
    if(@($Eligible|Where-Object{$_-isnot[string]-or[string]::IsNullOrWhiteSpace([string]$_)-or([string]$_-notin$Failures)}).Count-gt0){throw 'Routing profile contains an unsupported eligible failure.'}
    if($Profile.settings.allow_degraded_independence-isnot[bool]-or$Profile.settings.allow_degraded_independence-ne$false){throw 'Routing must fail closed on degraded model independence.'}
    $CooldownValue=$Profile.settings.default_cooldown_seconds
    if(-not(Test-JsonInteger $CooldownValue)-or[long]$CooldownValue-lt60-or[long]$CooldownValue-gt86400){throw 'default_cooldown_seconds must be an integer between 60 and 86400.'}

    function Test-Candidate([object]$Candidate,[string]$Role,[string]$Context,[bool]$NeedsPriority){
        if($null-eq$Candidate-or[string]$Candidate.model-notmatch'^[^/\s]+/\S+$'){throw "$Context model must use concrete provider/model format."}
        if([string]::IsNullOrWhiteSpace([string]$Candidate.model_family)){throw "$Context model_family is required."}
        $Policy=[string]$Candidate.variant_policy
        if($Policy-notin@('explicit','provider_default','highest_supported')){throw "$Context variant_policy is invalid."}
        if($Policy-eq'explicit'-and[string]::IsNullOrWhiteSpace([string]$Candidate.variant)){throw "$Context explicit variant is required."}
        if($Policy-eq'provider_default'-and-not[string]::IsNullOrWhiteSpace([string]$Candidate.variant)){throw "$Context provider_default must use a blank variant."}
        if($Policy-eq'highest_supported'-and[string]::IsNullOrWhiteSpace([string]$Candidate.variant)){throw "$Context highest_supported must be resolved locally before installation."}
        if([string]$Candidate.variant-eq'highest_supported'){throw "$Context cannot use highest_supported as a literal variant."}

        $OnlyOn=@(Get-JsonArray $Candidate 'only_on' "$Context only_on")
        if(@($OnlyOn|Where-Object{$_-isnot[string]-or[string]::IsNullOrWhiteSpace([string]$_)-or([string]$_-notin$OnlyOnAllowed)}).Count-gt0){throw "$Context contains an unsupported only_on value."}

        $Classes=@(Get-JsonArray $Candidate 'work_classes' "$Context work_classes" $false)
        if(@($Classes|Where-Object{$_-isnot[string]-or[string]::IsNullOrWhiteSpace([string]$_)-or([string]$_-notin$WorkClasses)}).Count-gt0){throw "$Context contains an invalid work class."}
        if($Role-ne'executor'-and$Classes.Count-gt0){throw "$Context work_classes is valid only for Executor routes."}

        if($NeedsPriority){
            $PriorityValue=$Candidate.priority
            if(-not(Test-JsonInteger $PriorityValue)-or[long]$PriorityValue-lt1){throw "$Context priority must be a positive integer."}
        }
        if($Candidate.PSObject.Properties['requires_role_rebalance']-and$Candidate.requires_role_rebalance-isnot[bool]){throw "$Context requires_role_rebalance must be boolean."}
    }

    foreach($Role in $RoleNames){
        $RoleConfig=$Profile.roles.$Role
        if($null-eq$RoleConfig){throw "Routing profile missing role: $Role"}
        Test-Candidate $RoleConfig.primary $Role "$Role primary" $false
        $Fallbacks=@(Get-JsonArray $RoleConfig 'fallbacks' "$Role fallbacks" $false)
        $Priorities=@()
        foreach($Candidate in $Fallbacks){
            Test-Candidate $Candidate $Role "$Role fallback" $true
            $Priority=[long]$Candidate.priority
            if($Priority-in$Priorities){throw "$Role fallback priorities must be unique."}
            $Priorities+=$Priority
        }
        if($Role-in$Enabled-and$Fallbacks.Count-eq0){throw "$Role failover is enabled but no fallback is configured."}
    }
}
if($RoutingConfigPath){Test-RoutingProfile $RoutingConfigPath}

$JsoncPath=Join-Path $ConfigDir 'opencode.jsonc'
$JsonPath=Join-Path $ConfigDir 'opencode.json'
$ConfigTarget=if((Test-Path -LiteralPath $JsoncPath)-or-not(Test-Path -LiteralPath $JsonPath)){$JsoncPath}else{$JsonPath}
$ConfigBackup=$null
$ConfigNormalized=$null
if(Test-Path -LiteralPath $ConfigTarget -PathType Leaf){
    $ConfigBackup=Join-Path ([IO.Path]::GetTempPath()) ('opencode-jsonc-backup-'+[guid]::NewGuid().ToString('N'))
    $ConfigNormalized=Join-Path ([IO.Path]::GetTempPath()) ('opencode-jsonc-normalized-'+[guid]::NewGuid().ToString('N'))
    Copy-Item -LiteralPath $ConfigTarget -Destination $ConfigBackup -Force
    & (Join-Path $PSScriptRoot 'normalize-jsonc.ps1') -Path $ConfigTarget
    Copy-Item -LiteralPath $ConfigTarget -Destination $ConfigNormalized -Force
    [IO.File]::WriteAllText($ConfigTarget,"{`n  `"`$schema`": `"https://opencode.ai/config.json`"`n}`n",(New-Object Text.UTF8Encoding($false)))
}

try{
    $CoreInstaller=Join-Path $PSScriptRoot 'install-core.ps1'
    if(-not(Test-Path -LiteralPath $CoreInstaller -PathType Leaf)){throw "Core installer not found: $CoreInstaller"}
    & $CoreInstaller @PSBoundParameters

    $BackupDir=Get-ChildItem -LiteralPath (Join-Path $ConfigDir 'backups') -Directory -Filter 'opencode-governance-*'|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
    if($null-eq$BackupDir){throw 'Installer backup directory was not created.'}
    if($ConfigBackup){Copy-Item -LiteralPath $ConfigBackup -Destination (Join-Path $BackupDir.FullName ([IO.Path]::GetFileName($ConfigTarget))) -Force}

    if($RoutingConfigPath){
        $ToolsDir=Join-Path $ConfigDir 'opencode-governance-tools'
        $ManifestPath=Join-Path $ConfigDir 'opencode-governance-routing.json'
        $ArchitectRunnerPs=Join-Path $ToolsDir 'architect-attempt.ps1'
        $ArchitectRunnerSh=Join-Path $ToolsDir 'architect-attempt.sh'
        $ContextToolPs=Join-Path $ToolsDir 'context-intelligence.ps1'
        $ContextToolSh=Join-Path $ToolsDir 'context-intelligence.sh'
        $ContextToolPy=Join-Path $ToolsDir 'context-intelligence.py'
        $WorkflowGatePs=Join-Path $ToolsDir 'workflow-continuation.ps1'
        $WorkflowGatePy=Join-Path $ToolsDir 'workflow-continuation.py'
        foreach($ManagedPath in @($ArchitectRunnerPs,$ArchitectRunnerSh,$ContextToolPs,$ContextToolSh,$ContextToolPy,$WorkflowGatePs,$WorkflowGatePy)){
            if(Test-Path -LiteralPath $ManagedPath -PathType Leaf){Copy-Item -LiteralPath $ManagedPath -Destination (Join-Path $BackupDir.FullName ([IO.Path]::GetFileName($ManagedPath)))-Force}
        }
        Copy-Item (Join-Path $PSScriptRoot 'run-governed.ps1') $ArchitectRunnerPs -Force
        Copy-Item (Join-Path $PSScriptRoot 'run-governed.sh') $ArchitectRunnerSh -Force
        Copy-Item (Join-Path $PSScriptRoot 'context-intelligence.ps1') $ContextToolPs -Force
        Copy-Item (Join-Path $PSScriptRoot 'context-intelligence.sh') $ContextToolSh -Force
        Copy-Item (Join-Path $PSScriptRoot 'context-intelligence.py') $ContextToolPy -Force
        Copy-Item (Join-Path $PSScriptRoot 'workflow-continuation.ps1') $WorkflowGatePs -Force
        Copy-Item (Join-Path $PSScriptRoot 'workflow-continuation.py') $WorkflowGatePy -Force

        try{$Manifest=Get-Content -LiteralPath $ManifestPath -Raw|ConvertFrom-Json}catch{throw 'Routing manifest is invalid after core installation.'}
        if([string]$Manifest.schema_version-ne'1.0'){throw 'Routing manifest schema_version must be 1.0.'}
        $Manifest|Add-Member NoteProperty governance_version '3.4.4' -Force
        $Manifest|Add-Member NoteProperty architect_runner_version '3.4.4' -Force
        $Manifest|Add-Member NoteProperty context_intelligence_version '3.4.4' -Force
        $Manifest|Add-Member NoteProperty workflow_continuation_version '3.4.4' -Force
        $Manifest|Add-Member NoteProperty managed_tools @(
            $ArchitectRunnerPs,$ArchitectRunnerSh,
            (Join-Path $ToolsDir 'executor-attempt.ps1'),(Join-Path $ToolsDir 'executor-attempt.sh'),
            $ContextToolPs,$ContextToolSh,$ContextToolPy,$WorkflowGatePs,$WorkflowGatePy
        ) -Force
        [IO.File]::WriteAllText($ManifestPath,(($Manifest|ConvertTo-Json -Depth 30)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))

        $Marker='[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
        $ArchitectPolicy=@"

## ARCHITECT_RUNNER_INTEGRATION

Architect pre-execution commands ``ai-init|ai-audit|ai-discover|ai-plan`` require the installed transactional runner.

WINDOWS_ARCHITECT_RUNNER: $ArchitectRunnerPs
WINDOWS_ARCHITECT_HOST: pwsh -NoProfile -File
UNIX_ARCHITECT_RUNNER: $ArchitectRunnerSh
ACTIVE_CHILD_MARKER: $Marker
PROJECT_STATE_FINGERPRINT: PROJECT_STATE_FINGERPRINT_V1
NON_GIT_PROJECTS: NON_GIT_PROJECT_SUPPORTED

The PowerShell runner requires PowerShell 7 or newer and fails before any project-state mutation with ``POWERSHELL_7_REQUIRED`` under Windows PowerShell 5.1. Invoke it through ``pwsh -NoProfile -File``.

Before and after every routed attempt, both runners fingerprint all project entries outside root ``.ai/**`` and Git metadata. Git projects also bind the fingerprint to HEAD, the Git index and recursive submodule state. Non-Git directories are supported with the same content-integrity contract. Any source or project-documentation change returns ``PROJECT_STATE_CHANGED`` and blocks fallback.

When the marker is absent, do not write ``.ai/**``; return ``ARCHITECT_RUNNER_REQUIRED`` with the exact installed runner path and command. Never invent ``architect-attempt`` at another path. Never invoke the Architect runner from inside the active OpenCode process. A routed child invocation containing the marker continues normally.
"@
        $ContextPolicy=@"

## CONTEXT_INTELLIGENCE_V1

WINDOWS_CONTEXT_TOOL: $ContextToolPs
WINDOWS_CONTEXT_HOST: pwsh -NoProfile -File
UNIX_CONTEXT_TOOL: $ContextToolSh
CONTEXT_CORE: $ContextToolPy

Before finalizing ``CONTEXT_MANIFEST.md``, initialize ``CONTEXT_BUDGET.json`` from the exact ``WORK_CLASS`` and use bounded ``DISPATCH -> EVALUATE -> REFINE`` retrieval. Never exceed three cycles. End with ``CONTEXT_SUFFICIENT`` or ``BLOCKED_CONTEXT_GAP``.

Use ``SKILL_CAPABILITY_MANIFEST_V1`` to deduplicate overlapping skills, prefer the highest-trust narrow applicable capability and load only selected sections within the skill budget. Record accepted and rejected candidates with reasons in ``SKILL_SELECTION.json``.

Governance state paths may not traverse symbolic links or reparse points. The external content summary cache is advisory, content-addressed and outside the project. A cache hit never replaces current primary evidence for a material claim. Cache failure is a recorded miss, not permission to fabricate context. Context-budget overrides require an evidence-backed reason and never waive security, migration, recovery, contract or operational evidence.
"@
        foreach($Name in @('architect','build','plan')){
            $AgentPath=Join-Path $ConfigDir "agents/$Name.md"
            $Text=Get-Content -LiteralPath $AgentPath -Raw
            $Text=[regex]::Replace($Text,'(?s)\r?\n## ARCHITECT_RUNNER_INTEGRATION\r?\n.*?(?=\r?\n## Core invariants|\z)','')
            $Text=[regex]::Replace($Text,'(?s)\r?\n## CONTEXT_INTELLIGENCE_V1\r?\n.*?(?=\r?\n## Core invariants|\z)','')
            $Insertion=$ArchitectPolicy.TrimEnd()+"`n"+$ContextPolicy.TrimEnd()
            if($Text-match'(?m)^## Core invariants\r?$'){$Text=[regex]::Replace($Text,'(?m)^## Core invariants\r?$',($Insertion+"`n`n## Core invariants"),1)}else{$Text+="`n"+$Insertion}
            [IO.File]::WriteAllText($AgentPath,$Text,(New-Object Text.UTF8Encoding($false)))
        }

        foreach($Command in @('ai-init','ai-audit','ai-discover','ai-plan')){
            $CommandPath=Join-Path $ConfigDir "commands/$Command.md"
            $Text=Get-Content -LiteralPath $CommandPath -Raw
            $Text=[regex]::Replace($Text,'(?s)\r?\n## ARCHITECT_RUNNER_ENTRY_GATE\r?\n.*?(?=\r?\n## |\z)','')
            $Gate=@"

## ARCHITECT_RUNNER_ENTRY_GATE

Before any ``.ai/**`` write, require the exact invocation marker ``$Marker`` in the command arguments.

When the marker is absent, stop immediately with:

``````text
ARCHITECT_RUNNER_REQUIRED
COMMAND: $Command
WINDOWS_HOST: pwsh -NoProfile -File
WINDOWS_RUNNER: $ArchitectRunnerPs
UNIX_RUNNER: $ArchitectRunnerSh
PROJECT_DIR: <CURRENT_PROJECT_ROOT>
WINDOWS_COMMAND: pwsh -NoProfile -File "$ArchitectRunnerPs" -ProjectDir "<CURRENT_PROJECT_ROOT>" -Command $Command -Arguments "<ORIGINAL_ARGUMENTS>"
UNIX_COMMAND: "$ArchitectRunnerSh" --project-dir "<CURRENT_PROJECT_ROOT>" --command $Command --arguments "<ORIGINAL_ARGUMENTS>"
``````

The external runner supports Git and non-Git project directories. It fingerprints all source and project-documentation content outside root ``.ai/**`` before and after each attempt and returns ``PROJECT_STATE_CHANGED`` on any delta.

Do not create, edit or delete ``.ai/**``. Do not invoke the runner from inside this OpenCode process. Return the complete ``WINDOWS_COMMAND`` and ``UNIX_COMMAND`` values with the actual current project root and original arguments substituted so the owner can copy and execute them. Do not invent another runner path.

When the exact marker is present, this is already a transactional child attempt; continue with the command contract below.
"@
            $FrontMatter=[regex]::Match($Text,'(?s)\A---\r?\n.*?\r?\n---\r?\n')
            if(-not$FrontMatter.Success){throw "Command front matter not found: $CommandPath"}
            $Text=$Text.Insert($FrontMatter.Length,$Gate)
            [IO.File]::WriteAllText($CommandPath,$Text,(New-Object Text.UTF8Encoding($false)))
        }

        $ContextEntry=@"

## CONTEXT_INTELLIGENCE_ENTRY

Use ``$ContextToolPs`` through ``pwsh -NoProfile -File`` on Windows or ``$ContextToolSh`` on Unix. Initialize the task budget from ``WORK_CLASS`` before context routing; record each retrieval cycle, skill selection and optional metrics. Maximum retrieval cycles: 3. A task must end with ``CONTEXT_SUFFICIENT`` or ``BLOCKED_CONTEXT_GAP``; unresolved material context blocks continuation.
"@
        foreach($Command in @('ai-workflow','ai-resume','ai-metrics')){
            $CommandPath=Join-Path $ConfigDir "commands/$Command.md"
            $Text=Get-Content -LiteralPath $CommandPath -Raw
            $Text=[regex]::Replace($Text,'(?s)\r?\n## CONTEXT_INTELLIGENCE_ENTRY\r?\n.*?(?=\r?\n## |\z)','')
            $FrontMatter=[regex]::Match($Text,'(?s)\A---\r?\n.*?\r?\n---\r?\n')
            if(-not$FrontMatter.Success){throw "Command front matter not found: $CommandPath"}
            $Text=$Text.Insert($FrontMatter.Length,$ContextEntry)
            [IO.File]::WriteAllText($CommandPath,$Text,(New-Object Text.UTF8Encoding($false)))
        }

        foreach($Command in @('ai-workflow','ai-resume')){
            $CommandPath=Join-Path $ConfigDir "commands/$Command.md"
            $Text=Get-Content -LiteralPath $CommandPath -Raw
            $Text=[regex]::Replace($Text,'(?s)\r?\n## WORKFLOW_CONTINUATION_GATE_V1\r?\n.*?(?=\r?\n## |\z)','')
            $ExpectedCommand=$Command
            $WorkflowEntry=@"

## WORKFLOW_CONTINUATION_GATE_V1

WINDOWS_WORKFLOW_CONTINUATION_CORE: $WorkflowGatePs
UNIX_WORKFLOW_CONTINUATION_CORE: $WorkflowGatePy

Persist ``top_level_command``, ``current_phase``, ``next_required_phase`` and ``terminal_reason`` in the authoritative task ``RUN_STATE.json``. Before a final response on Windows, invoke ``pwsh -NoProfile -File "$WorkflowGatePs" -RunStatePath "<AUTHORITATIVE_RUN_STATE_PATH>" -ExpectedCommand $ExpectedCommand``. On Unix, invoke ``python3 "$WorkflowGatePy" --run-state "<AUTHORITATIVE_RUN_STATE_PATH>" --expected-command $ExpectedCommand``. Exit 3/``CONTINUE_REQUIRED`` requires continuation at the recorded next phase. Exit 0/``TERMINAL_ALLOWED`` permits only ``LOCAL_COMMITTED`` or an explicit blocker. Exit 2/``INVALID_RUN_STATE`` blocks completion.
"@
            $FrontMatter=[regex]::Match($Text,'(?s)\A---\r?\n.*?\r?\n---\r?\n')
            if(-not$FrontMatter.Success){throw "Command front matter not found: $CommandPath"}
            $Text=$Text.Insert($FrontMatter.Length,$WorkflowEntry)
            [IO.File]::WriteAllText($CommandPath,$Text,(New-Object Text.UTF8Encoding($false)))
        }

        & (Join-Path $PSScriptRoot 'verify-routing.ps1') -ConfigDir $ConfigDir
        Write-Host 'Installed OpenCode Governance v3.4.4 — Deterministic Workflow Continuation.'
        Write-Host 'Routing preflight, complete managed-tool backup and hardened context paths are enabled without changing model selection.'
    }

    if($ConfigNormalized){
        & (Join-Path $PSScriptRoot 'normalize-jsonc.ps1') -Path $ConfigNormalized -SetDefaultAgent
        Copy-Item -LiteralPath $ConfigNormalized -Destination $ConfigTarget -Force
    }
}catch{
    if($ConfigBackup-and(Test-Path -LiteralPath $ConfigBackup -PathType Leaf)){Copy-Item -LiteralPath $ConfigBackup -Destination $ConfigTarget -Force}
    throw
}finally{
    if($ConfigBackup){Remove-Item -LiteralPath $ConfigBackup -Force -ErrorAction SilentlyContinue}
    if($ConfigNormalized){Remove-Item -LiteralPath $ConfigNormalized -Force -ErrorAction SilentlyContinue}
}
