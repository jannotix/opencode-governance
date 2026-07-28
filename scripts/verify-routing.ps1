param([string]$ConfigDir)
$ErrorActionPreference='Stop'
if(-not $ConfigDir){$ConfigDir=if($env:OPENCODE_CONFIG_DIR){$env:OPENCODE_CONFIG_DIR}else{Join-Path $HOME '.config\opencode'}}
$ManifestPath=Join-Path $ConfigDir 'opencode-governance-routing.json'
if(-not(Test-Path $ManifestPath -PathType Leaf)){Write-Host 'PASS: model failover routing is not configured.';exit 0}
try{$Manifest=Get-Content $ManifestPath -Raw|ConvertFrom-Json}catch{throw 'Routing manifest is invalid JSON.'}
if([string]$Manifest.schema_version -ne '1.0'){throw 'Routing manifest schema_version must be 1.0.'}
if([string]$Manifest.governance_version -ne '3.2.0'){throw 'Routing manifest governance_version must be 3.2.0.'}
$EnabledRoles=@('architect','reviewer','reviewer-architecture','final-reviewer')
$AliasRoles=@('reviewer','reviewer-architecture','final-reviewer')
$AllowedFailures=@('PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT')
$Expected=@{}
function Require-Line([string]$Text,[string]$Line,[string]$Context){if(($Text -split "`r?`n") -cnotcontains $Line){throw "$Context missing exact line: $Line"}}
function Get-RoleConfig([string]$Role){$p=$Manifest.roles.PSObject.Properties[$Role];if(-not $p){throw "Routing manifest missing role: $Role"};return $p.Value}
function Get-OnlyOn([object]$Candidate,[string]$Context){if(-not $Candidate.PSObject.Properties['only_on']){throw "$Context missing only_on"};return @($Candidate.only_on|Where-Object{-not[string]::IsNullOrWhiteSpace([string]$_)})}
function Verify-RenderedCandidate([string]$Agent,[string]$Role,[object]$Candidate,[int]$Priority,[bool]$Hidden){
 $Path=Join-Path $ConfigDir "agents\$Agent.md";if(-not(Test-Path $Path -PathType Leaf)){throw "Missing routed agent: $Agent"};$Text=Get-Content $Path -Raw
 $Variant=if([string]::IsNullOrWhiteSpace([string]$Candidate.variant)){'PROVIDER_DEFAULT'}else{[string]$Candidate.variant};$OnlyValues=Get-OnlyOn $Candidate "$Agent route";$Only=if($OnlyValues.Count -eq 0){'ANY_ELIGIBLE_FAILURE'}else{$OnlyValues -join '|'};$Rebalance=if($Candidate.requires_role_rebalance -eq $true){'YES'}else{'NO'}
 Require-Line $Text "model: $($Candidate.model)" $Agent
 if([string]::IsNullOrWhiteSpace([string]$Candidate.variant)){if($Text -match '(?m)^variant:\s*\S+'){throw "$Agent rendered an unconfigured variant."}}else{Require-Line $Text "variant: $($Candidate.variant)" $Agent}
 foreach($Line in @('## MODEL_ROUTE_METADATA',"AUTHORITATIVE_ROLE: $Role","ROUTE_AGENT: $Agent","SELECTED_MODEL: $($Candidate.model)","SELECTED_VARIANT: $Variant","MODEL_FAMILY: $($Candidate.model_family)","ROUTE_PRIORITY: $Priority","ROUTE_ONLY_ON: $Only","REQUIRES_ROLE_REBALANCE: $Rebalance")){Require-Line $Text $Line $Agent}
 foreach($Marker in @('ROLE_ATTEMPT_ID','PACKET_SHA256','FROZEN_TARGET_SHA','REPORT_COMPLETE: YES')){if($Text -notlike "*$Marker*"){throw "$Agent missing route marker: $Marker"}}
 if($Hidden){Require-Line $Text 'mode: subagent' $Agent;Require-Line $Text 'hidden: true' $Agent;Require-Line $Text '  task: deny' $Agent}
}
foreach($Role in @($Manifest.settings.enabled_roles)){if([string]$Role -notin $EnabledRoles){throw "Unsupported enabled failover role: $Role"}}
foreach($Failure in @($Manifest.settings.eligible_failures)){if([string]$Failure -notin $AllowedFailures){throw "Unsupported eligible failure: $Failure"}}
if($Manifest.settings.allow_degraded_independence -ne $false){throw 'Default routing must fail closed on degraded independence.'}
foreach($Role in $AliasRoles){
 $cfg=Get-RoleConfig $Role;Verify-RenderedCandidate $Role $Role $cfg.primary 0 $false;$Priorities=@()
 foreach($c in @($cfg.fallbacks)){$p=[int]$c.priority;if($p -lt 1 -or $Priorities -contains $p){throw "$Role fallback priorities must be unique positive integers."};$Priorities+=$p;if($Role -in @($Manifest.settings.enabled_roles)){$Alias="$Role-fallback-$p";$Expected[$Alias]=$true;Verify-RenderedCandidate $Alias $Role $c $p $true}}
}
$PublicMap=@{'architect'=@('architect',(Get-RoleConfig 'architect').primary);'build'=@('architect',(Get-RoleConfig 'architect').primary);'plan'=@('architect',(Get-RoleConfig 'architect').primary);'executor'=@('executor',(Get-RoleConfig 'executor').primary)}
foreach($Name in $PublicMap.Keys){Verify-RenderedCandidate $Name $PublicMap[$Name][0] $PublicMap[$Name][1] 0 $false}
$ArchitectConfig=Get-RoleConfig 'architect';foreach($c in @($ArchitectConfig.fallbacks)){if(-not $c.PSObject.Properties['only_on']){throw 'Architect fallback missing only_on'};if([string]$c.model -notmatch '^[^/\s]+/\S+$'){throw 'Architect fallback has invalid model'};if([string]::IsNullOrWhiteSpace([string]$c.model_family)){throw 'Architect fallback missing model_family'}}
if('architect' -in @($Manifest.settings.enabled_roles)){
 if(@($ArchitectConfig.fallbacks).Count -eq 0){throw 'Architect routing enabled without fallbacks'}
 foreach($Name in @('architect','build')){$Text=Get-Content (Join-Path $ConfigDir "agents\$Name.md") -Raw;foreach($m in @('run-governed.ps1|sh','ai-init|ai-audit|ai-discover|ai-plan','never self-delegate','execution boundary')){if($Text -notlike "*$m*"){throw "$Name missing Architect runner policy: $m"}}}
}
$Managed=@($Manifest.managed_aliases);if($Managed.Count -ne $Expected.Count){throw 'Managed alias count does not match reviewer/final fallback candidates.'}
foreach($Alias in $Managed){if([string]$Alias -notmatch '^(reviewer|reviewer-architecture|final-reviewer)-fallback-[0-9]+$'){throw "Unsafe managed alias name: $Alias"};if(-not $Expected.ContainsKey([string]$Alias)){throw "Unexpected managed alias: $Alias"}}
$Rendered=@(Get-ChildItem (Join-Path $ConfigDir 'agents') -Filter '*-fallback-*.md'|ForEach-Object BaseName);foreach($Alias in $Rendered){if($Alias -notin $Managed){throw "Unmanaged fallback alias present: $Alias"};if($Alias -like 'architect-fallback-*'){throw 'Architect fallback aliases are forbidden in v3.2'}}
foreach($Name in @('architect','build')){$Text=Get-Content (Join-Path $ConfigDir "agents\$Name.md") -Raw;foreach($m in @('ROLE_FAILOVER_POLICY','MODEL_INDEPENDENCE_STATUS','MODEL_INDEPENDENCE_CONFLICT','Never retry the same candidate','"reviewer-fallback-*": allow','"reviewer-architecture-fallback-*": allow','"final-reviewer-fallback-*": allow')){if($Text -notlike "*$m*"){throw "$Name missing failover policy marker: $m"}}}
Write-Host "PASS: OpenCode Governance v3.2 routing verified ($($Managed.Count) hidden reviewer/final routes; Architect external runner policy verified)."
