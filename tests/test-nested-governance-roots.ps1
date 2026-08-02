# 3.7.5: nested workspace + multi governance root transactions (Windows)
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$RootDir=Split-Path -Parent $PSScriptRoot
$TempRoot=Join-Path ([IO.Path]::GetTempPath()) ('opencode-v375-nested-'+[guid]::NewGuid().ToString('N'))
$Config=Join-Path $TempRoot 'config'
$Runner=Join-Path $RootDir 'scripts/run-governed.ps1'
$Routing=Join-Path $TempRoot 'routing.json'
New-Item -ItemType Directory -Force -Path $Config|Out-Null
[IO.File]::WriteAllText($Routing, '{"schema_version":"1.0","settings":{"enabled_roles":["architect"],"eligible_failures":["PROVIDER_UNAVAILABLE","RATE_LIMIT","TOOL_EXECUTION_ABORTED"],"allow_degraded_independence":false,"default_cooldown_seconds":60},"roles":{"architect":{"primary":{"model":"test/architect-primary","model_family":"primary","variant_policy":"explicit","variant":"test","only_on":[]},"fallbacks":[{"model":"test/architect-fallback","model_family":"fallback","variant_policy":"explicit","variant":"test","priority":1,"only_on":["PROVIDER_UNAVAILABLE","RATE_LIMIT","TOOL_EXECUTION_ABORTED"]}]}}}')

function Invoke-NestedRunner{
  param(
    [string]$Workspace,
    [string]$Repo,
    [string]$Mock,
    [string]$Command='ai-plan',
    [string]$TaskId='',
    [string]$ArgsText='nested-test'
  )
  $wrapper=Join-Path $TempRoot ('wrap-'+[guid]::NewGuid().ToString('N')+'.ps1')
  $lines = New-Object System.Collections.Generic.List[string]
  [void]$lines.Add("`$ErrorActionPreference='Stop'")
  [void]$lines.Add("& '$($Runner.Replace("'","''"))' ``")
  [void]$lines.Add("  -WorkspaceDir '$($Workspace.Replace("'","''"))' ``")
  [void]$lines.Add("  -RepositoryDir '$($Repo.Replace("'","''"))' ``")
  [void]$lines.Add("  -Command $Command ``")
  if($TaskId){ [void]$lines.Add("  -TaskId '$($TaskId.Replace("'","''"))' ``") }
  [void]$lines.Add("  -Arguments '$($ArgsText.Replace("'","''"))' ``")
  [void]$lines.Add("  -RoutingConfigPath '$($Routing.Replace("'","''"))' ``")
  [void]$lines.Add("  -ConfigDir '$($Config.Replace("'","''"))' ``")
  [void]$lines.Add("  -OpenCodeCommand (Get-Command pwsh -ErrorAction Stop).Source ``")
  [void]$lines.Add("  -OpenCodePrefixArguments @('-NoProfile','-File','$($Mock.Replace("'","''"))')")
  [void]$lines.Add('exit $LASTEXITCODE')
  [IO.File]::WriteAllLines($wrapper, $lines)
  $output=& pwsh -NoProfile -File $wrapper 2>&1
  $code=$LASTEXITCODE
  Remove-Item -LiteralPath $wrapper -Force -ErrorAction SilentlyContinue
  [pscustomobject]@{Code=$code;Text=(($output|ForEach-Object{[string]$_})-join"`n")}
}

function New-NestedFixture([string]$Name){
  $ws=Join-Path $TempRoot $Name
  $repo=Join-Path $ws 'Source_Code'
  New-Item -ItemType Directory -Force -Path (Join-Path $ws '.ai'),(Join-Path $repo '.ai/tasks/TASK-NEST'),(Join-Path $repo 'app')|Out-Null
  'workspace-status'|Set-Content (Join-Path $ws '.ai/STATUS.md')
  'repo-status'|Set-Content (Join-Path $repo '.ai/STATUS.md')
  'app'|Set-Content (Join-Path $repo 'app/file.php')
  git -C $repo init -q
  git -C $repo config user.email test@example.invalid
  git -C $repo config user.name Test
  git -C $repo add .
  git -C $repo commit -qm base
  [pscustomobject]@{Workspace=$ws;Repository=$repo}
}

function Write-Mock([string]$Path,[string]$Body){
  [IO.File]::WriteAllText($Path, $Body)
}

# --- Positive: governance-only writes under both managed roots succeed ---
$fx=New-NestedFixture 'gov-only'
$mock=Join-Path $TempRoot 'mock-gov-only.ps1'
Write-Mock $mock @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
if($env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH){$d=Split-Path -Parent $env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH; if($d){New-Item -ItemType Directory -Force -Path $d|Out-Null}; $r=if($env:OPENCODE_GOVERNANCE_ROLE){$env:OPENCODE_GOVERNANCE_ROLE}else{'architect'}; (@{schema='EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1';role=$r;plugin_sha256='mock';policy_sha256='mock';process_id=$PID;nonce='mock-test'}|ConvertTo-Json -Compress)|Set-Content -LiteralPath $env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH -Encoding utf8}
$project=''
for($i=0;$i-lt$Args.Count;$i++){if($Args[$i]-eq'--dir'){$project=$Args[++$i]}}
'success-ws'|Set-Content (Join-Path $project '.ai/STATUS.md')
$repoAi=Join-Path $project 'Source_Code/.ai'
New-Item -ItemType Directory -Force -Path (Join-Path $repoAi 'tasks/TASK-NEST')|Out-Null
$json='{"task_id":"TASK-NEST","state":"READY_FOR_EXECUTION","current_phase":"READY_FOR_EXECUTION","next_required_phase":"IMPLEMENTING","next_action":{"kind":"execute","command":"/ai-execute"}}'
[IO.File]::WriteAllText((Join-Path $repoAi 'tasks/TASK-NEST/RUN_STATE.json'), $json)
'repo-updated'|Set-Content (Join-Path $repoAi 'STATUS.md')
Write-Output "GOVERNANCE_RESULT"
Write-Output "STATE: READY_FOR_EXECUTION"
exit 0
'@
$result=Invoke-NestedRunner -Workspace $fx.Workspace -Repo $fx.Repository -Mock $mock -Command ai-plan
if($result.Code-ne0){throw "Governance-only nested run failed: $($result.Text)"}
if($result.Text-notmatch'WORKSPACE_REPOSITORY_ROOT_CONTRACT'){throw 'Missing root contract log'}
if((Get-Content (Join-Path $fx.Workspace '.ai/STATUS.md'))-ne'success-ws'){throw 'Workspace governance not updated'}
if((Get-Content (Join-Path $fx.Repository 'app/file.php'))-ne'app'){throw 'Application source was mutated'}
if((Get-Content (Join-Path $fx.Repository '.ai/STATUS.md'))-ne'repo-updated'){throw 'Repository governance not updated'}

# --- Positive resume phase advanced ---
$fx2=New-NestedFixture 'resume-phase'
$stateJson='{"task_id":"TASK-NEST","state":"DISCOVERY","current_phase":"DISCOVERY","next_required_phase":"PLANNING","next_action":{"kind":"resume","command":"/ai-resume"}}'
[IO.File]::WriteAllText((Join-Path $fx2.Repository '.ai/tasks/TASK-NEST/RUN_STATE.json'), $stateJson)
$mock2=Join-Path $TempRoot 'mock-resume.ps1'
Write-Mock $mock2 @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
if($env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH){$d=Split-Path -Parent $env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH; if($d){New-Item -ItemType Directory -Force -Path $d|Out-Null}; $r=if($env:OPENCODE_GOVERNANCE_ROLE){$env:OPENCODE_GOVERNANCE_ROLE}else{'architect'}; (@{schema='EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1';role=$r;plugin_sha256='mock';policy_sha256='mock';process_id=$PID;nonce='mock-test'}|ConvertTo-Json -Compress)|Set-Content -LiteralPath $env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH -Encoding utf8}
$project=''
for($i=0;$i-lt$Args.Count;$i++){if($Args[$i]-eq'--dir'){$project=$Args[++$i]}}
$path=Join-Path $project 'Source_Code/.ai/tasks/TASK-NEST/RUN_STATE.json'
$json='{"task_id":"TASK-NEST","state":"READY_FOR_EXECUTION","current_phase":"READY_FOR_EXECUTION","next_required_phase":"IMPLEMENTING","next_action":{"kind":"execute","command":"/ai-execute"}}'
[IO.File]::WriteAllText($path, $json)
'plan'|Set-Content (Join-Path $project 'Source_Code/.ai/tasks/TASK-NEST/PLAN.md')
Write-Output "GOVERNANCE_RESULT"
Write-Output "STATE: READY_FOR_EXECUTION"
exit 0
'@
$result=Invoke-NestedRunner -Workspace $fx2.Workspace -Repo $fx2.Repository -Mock $mock2 -Command ai-resume -TaskId 'TASK-NEST' -ArgsText 'TASK-NEST'
if($result.Code-ne0){throw "Resume nested failed: $($result.Text)"}
if($result.Text-notmatch'ARCHITECT_PHASE_ADVANCED'){throw "Missing ARCHITECT_PHASE_ADVANCED: $($result.Text)"}
if($result.Text-notmatch'NEXT_COMMAND=/ai-execute'){throw 'Missing next command'}

# --- Negative: application source mutation fails closed and restores governance ---
$fx3=New-NestedFixture 'app-mutate'
'before-ws'|Set-Content (Join-Path $fx3.Workspace '.ai/STATUS.md')
'before-repo'|Set-Content (Join-Path $fx3.Repository '.ai/STATUS.md')
$mock3=Join-Path $TempRoot 'mock-mutate.ps1'
Write-Mock $mock3 @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
if($env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH){$d=Split-Path -Parent $env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH; if($d){New-Item -ItemType Directory -Force -Path $d|Out-Null}; $r=if($env:OPENCODE_GOVERNANCE_ROLE){$env:OPENCODE_GOVERNANCE_ROLE}else{'architect'}; (@{schema='EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1';role=$r;plugin_sha256='mock';policy_sha256='mock';process_id=$PID;nonce='mock-test'}|ConvertTo-Json -Compress)|Set-Content -LiteralPath $env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH -Encoding utf8}
$project=''
for($i=0;$i-lt$Args.Count;$i++){if($Args[$i]-eq'--dir'){$project=$Args[++$i]}}
'partial'|Set-Content (Join-Path $project '.ai/STATUS.md')
'partial-repo'|Set-Content (Join-Path $project 'Source_Code/.ai/STATUS.md')
'mutated'|Set-Content (Join-Path $project 'Source_Code/app/file.php')
exit 0
'@
$result=Invoke-NestedRunner -Workspace $fx3.Workspace -Repo $fx3.Repository -Mock $mock3
if($result.Code-eq0){throw 'Source mutation was accepted'}
if($result.Text-notmatch'PROJECT_STATE_CHANGED'){throw "Missing PROJECT_STATE_CHANGED: $($result.Text)"}
if($result.Text-notmatch'APPLICATION_SOURCE_CHANGE'){throw "Missing APPLICATION_SOURCE_CHANGE diagnostic: $($result.Text)"}
if((Get-Content (Join-Path $fx3.Workspace '.ai/STATUS.md'))-ne'before-ws'){throw 'Workspace governance not restored'}
if((Get-Content (Join-Path $fx3.Repository '.ai/STATUS.md'))-ne'before-repo'){throw 'Repository governance not restored'}
if((Get-Content (Join-Path $fx3.Repository 'app/file.php'))-ne'mutated'){throw 'Runner must not overwrite application source on failure'}

# --- Negative: unregistered nested .ai is not excluded ---
$fx4=New-NestedFixture 'unreg-ai'
$extra=Join-Path $fx4.Workspace 'other/.ai'
New-Item -ItemType Directory -Force -Path $extra|Out-Null
'extra'|Set-Content (Join-Path $extra 'NOTE.md')
$mock4=Join-Path $TempRoot 'mock-unreg.ps1'
Write-Mock $mock4 @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
if($env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH){$d=Split-Path -Parent $env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH; if($d){New-Item -ItemType Directory -Force -Path $d|Out-Null}; $r=if($env:OPENCODE_GOVERNANCE_ROLE){$env:OPENCODE_GOVERNANCE_ROLE}else{'architect'}; (@{schema='EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1';role=$r;plugin_sha256='mock';policy_sha256='mock';process_id=$PID;nonce='mock-test'}|ConvertTo-Json -Compress)|Set-Content -LiteralPath $env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH -Encoding utf8}
$project=''
for($i=0;$i-lt$Args.Count;$i++){if($Args[$i]-eq'--dir'){$project=$Args[++$i]}}
'changed'|Set-Content (Join-Path $project 'other/.ai/NOTE.md')
exit 0
'@
$result=Invoke-NestedRunner -Workspace $fx4.Workspace -Repo $fx4.Repository -Mock $mock4
if($result.Code-eq0){throw 'Unregistered .ai mutation was accepted'}
if($result.Text-notmatch'PROJECT_STATE_CHANGED'){throw 'Unregistered .ai did not trip fingerprint'}

# --- Negative: multiple nested git roots ambiguous ---
$amb=Join-Path $TempRoot 'ambiguous'
New-Item -ItemType Directory -Force -Path (Join-Path $amb 'a'),(Join-Path $amb 'b')|Out-Null
git -C (Join-Path $amb 'a') init -q
git -C (Join-Path $amb 'b') init -q
$failed=$false
try{
  & $Runner -WorkspaceDir $amb -Command ai-plan -Arguments x -RoutingConfigPath $Routing -ConfigDir $Config -OpenCodeCommand pwsh -OpenCodePrefixArguments @('-NoProfile','-Command','exit 0') 2>&1|Out-Null
}catch{ $failed=$true; if("$_" -notmatch 'REPOSITORY_ROOT_AMBIGUOUS'){throw "Expected REPOSITORY_ROOT_AMBIGUOUS, got $_"} }
if(-not$failed){throw 'Ambiguous repos did not fail closed'}

# --- Negative: repository outside workspace ---
$outWs=Join-Path $TempRoot 'outside-ws'
$outRepo=Join-Path $TempRoot 'outside-repo'
New-Item -ItemType Directory -Force -Path $outWs,$outRepo|Out-Null
git -C $outRepo init -q
$failed=$false
try{
  & $Runner -WorkspaceDir $outWs -RepositoryDir $outRepo -Command ai-plan -Arguments x -RoutingConfigPath $Routing -ConfigDir $Config -OpenCodeCommand pwsh -OpenCodePrefixArguments @('-NoProfile','-Command','exit 0') 2>&1|Out-Null
}catch{ $failed=$true; if("$_" -notmatch 'REPOSITORY_ROOT_OUTSIDE_WORKSPACE'){throw "Expected REPOSITORY_ROOT_OUTSIDE_WORKSPACE, got $_"} }
if(-not$failed){throw 'Outside repository did not fail closed'}

# --- Compatibility: -ProjectDir still works for single-root git ---
$single=Join-Path $TempRoot 'single-git'
New-Item -ItemType Directory -Force -Path (Join-Path $single '.ai')|Out-Null
git -C $single init -q
's'|Set-Content (Join-Path $single 'source.txt')
$mockS=Join-Path $TempRoot 'mock-single.ps1'
Write-Mock $mockS @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
if($env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH){$d=Split-Path -Parent $env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH; if($d){New-Item -ItemType Directory -Force -Path $d|Out-Null}; $r=if($env:OPENCODE_GOVERNANCE_ROLE){$env:OPENCODE_GOVERNANCE_ROLE}else{'architect'}; (@{schema='EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1';role=$r;plugin_sha256='mock';policy_sha256='mock';process_id=$PID;nonce='mock-test'}|ConvertTo-Json -Compress)|Set-Content -LiteralPath $env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH -Encoding utf8}
$project=''
for($i=0;$i-lt$Args.Count;$i++){if($Args[$i]-eq'--dir'){$project=$Args[++$i]}}
'ok'|Set-Content (Join-Path $project '.ai/STATUS.md'); exit 0
'@
& $Runner -ProjectDir $single -Command ai-plan -Arguments compat -RoutingConfigPath $Routing -ConfigDir $Config -OpenCodeCommand pwsh -OpenCodePrefixArguments @('-NoProfile','-File',$mockS)
if($LASTEXITCODE-ne0){throw 'ProjectDir compatibility failed'}

Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
$global:LASTEXITCODE=0
Write-Host 'PASS: Windows nested governance root / multi-root transaction regressions (3.7.5).'
