# 3.7.3: headless Architect permission contract, permission blocker, JSONC routing, launcher selection.
$ErrorActionPreference='Stop'
$RootDir=Split-Path -Parent $PSScriptRoot
$Runner=Join-Path $RootDir 'scripts/run-governed.ps1'
$Contract=Join-Path $RootDir 'scripts/architect-headless-contract.py'
$TempRoot=Join-Path ([IO.Path]::GetTempPath()) ('opencode-v373-headless-'+[guid]::NewGuid().ToString('N'))
$Config=Join-Path $TempRoot 'config'
$Project=Join-Path $TempRoot 'project'
New-Item -ItemType Directory -Force -Path $Config,(Join-Path $Project '.ai/tasks/TASK-001')|Out-Null

# JSONC routing with comments + trailing commas (must load without mutating source).
$RoutingPath=Join-Path $Config 'routing.jsonc'
@'
{
  // headless contract fixture
  "schema_version": "1.0",
  "settings": {
    "enabled_roles": ["architect"],
    "eligible_failures": ["PROVIDER_UNAVAILABLE"],
    "allow_degraded_independence": false,
    "default_cooldown_seconds": 60,
  },
  "roles": {
    "architect": {
      "primary": {
        "model": "test/architect-primary",
        "model_family": "primary",
        "variant_policy": "explicit",
        "variant": "test",
        "only_on": [],
      },
      "fallbacks": [
        {
          "model": "test/architect-fallback",
          "model_family": "fallback",
          "variant_policy": "explicit",
          "variant": "test",
          "priority": 1,
          "only_on": ["PROVIDER_UNAVAILABLE"],
        },
      ],
    },
  },
}
'@ | Set-Content -LiteralPath $RoutingPath -Encoding utf8
$RoutingBytesBefore=[IO.File]::ReadAllBytes($RoutingPath)

@'
{"task_id":"TASK-001","state":"DISCOVERY_DEFECT_REPAIR_CYCLE_1","phase":"DISCOVERY_DEFECT_REPAIR_CYCLE_1","next_required_phase":"DISCOVERY_ADJUDICATION","next_action":{"kind":"execute","command":"/ai-resume","arguments":["TASK-001"]}}
'@ | Set-Content -LiteralPath (Join-Path $Project '.ai/tasks/TASK-001/RUN_STATE.json') -Encoding utf8
'source-keep'|Set-Content -LiteralPath (Join-Path $Project 'source.txt') -Encoding utf8

# Policy unit tests (Python contract module)
$pyOut = & python $Contract 2>&1
if(($pyOut -join "`n") -notmatch 'ARCHITECT_HEADLESS_PERMISSION_CONTRACT_V1'){throw 'Contract module missing version marker.'}
& python -c @"
import importlib.util, pathlib, sys
p=pathlib.Path(r'$($Contract.Replace('\','/'))')
spec=importlib.util.spec_from_file_location('ahc', p)
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
assert m.evaluate_bash_permission('Test-Path -LiteralPath .ai')=='allow'
assert m.evaluate_bash_permission('Get-ChildItem -LiteralPath .')=='allow'
assert m.evaluate_bash_permission('git status')=='allow'
assert m.evaluate_bash_permission('git remote -v')=='allow'
assert m.evaluate_bash_permission('git push origin main')=='deny'
assert m.evaluate_bash_permission('git status && git push')=='deny'
assert m.evaluate_bash_permission('Get-ChildItem | Remove-Item')=='deny'
assert m.evaluate_bash_permission('echo hi > file.txt')=='deny'
assert m.evaluate_bash_permission('pwsh -Command Get-ChildItem')=='deny'
assert m.evaluate_bash_permission('bash -c ls')=='deny'
assert m.evaluate_bash_permission('ls -la')=='allow'
assert m.evaluate_bash_permission('Set-Content foo bar')=='deny'
cfg=m.build_headless_config(external_roots=[r'C:/tmp/config'])
assert cfg['permission']['bash']['*']=='deny'
assert cfg['agent']['architect']['permission']['bash']['*']=='deny'
assert cfg['agent']['architect']['permission']['bash']['Test-Path *']=='allow'
assert 'ask' not in cfg['agent']['architect']['permission']['bash'].values()
assert m.permission_blocked_in_text('permission requested: bash (Test-Path); auto-rejecting')
print('python-policy-ok')
"@
if($LASTEXITCODE -ne 0){throw 'Python headless policy unit tests failed.'}

function Invoke-MockRunner([string]$Mode,[string]$OpenCodeCommand,[string[]]$Prefix){
  $Mock=Join-Path $TempRoot ("mock-$Mode.ps1")
  @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
$project=''; $agent=''; $model=''
for($i=0;$i-lt$Args.Count;$i++){
  if($Args[$i]-eq'--dir'){$project=$Args[++$i]}
  elseif($Args[$i]-eq'--agent'){$agent=$Args[++$i]}
  elseif($Args[$i]-eq'--model'){$model=$Args[++$i]}
}
if($env:OPENCODE_CONFIG_CONTENT -notmatch 'ARCHITECT_HEADLESS_PERMISSION_CONTRACT_V1' -and $env:OPENCODE_CONFIG_CONTENT -notmatch 'governance_headless_contract'){
  [Console]::Error.WriteLine('missing headless contract overlay'); exit 50
}
if($env:OPENCODE_CONFIG_CONTENT -match '"\*":\s*"ask"' -or $env:OPENCODE_CONFIG_CONTENT -match '"bash"\s*:\s*"ask"'){
  [Console]::Error.WriteLine('headless overlay still uses ask'); exit 51
}
if($env:OPENCODE_CONFIG_CONTENT -notmatch '"\*":"deny"' -and $env:OPENCODE_CONFIG_CONTENT -notmatch '"\*": "deny"'){
  # compressed JSON may use "*" : "deny"
  if($env:OPENCODE_CONFIG_CONTENT -notmatch '\*"\s*:\s*"deny"'){ [Console]::Error.WriteLine('deny-by-default missing'); exit 52 }
}
if($env:MOCK_MODE -eq 'permission-block'){
  Write-Output 'Architect started and created internal task list.'
  [Console]::Error.WriteLine('permission requested: bash (Test-Path -LiteralPath .ai); auto-rejecting')
  [Console]::Error.WriteLine('The user rejected permission to use this specific tool call.')
  exit 0
}
if($env:MOCK_MODE -eq 'progress'){
  $path=Join-Path $project '.ai/tasks/TASK-001/RUN_STATE.json'
  $state=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
  $state.state='READY_FOR_EXECUTION'; $state.phase='READY_FOR_EXECUTION'; $state.next_required_phase='IMPLEMENTING'
  $state|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $path -Encoding utf8
  Write-Output "GOVERNANCE_RESULT`nTASK_ID: TASK-001`nSTATE: READY_FOR_EXECUTION"
  exit 0
}
Write-Output 'ordinary successful response without progress'
exit 0
'@ | Set-Content -LiteralPath $Mock -Encoding utf8
  $env:MOCK_MODE=$Mode
  # Isolate the runner in a child script so its `exit` cannot terminate this test process,
  # and so string[] OpenCodePrefixArguments are bound correctly.
  $wrapper=Join-Path $TempRoot ("runner-wrapper-"+[guid]::NewGuid().ToString('N')+'.ps1')
  $esc=@{
    Runner=$Runner.Replace("'","''")
    Project=$Project.Replace("'","''")
    Routing=$RoutingPath.Replace("'","''")
    Config=$Config.Replace("'","''")
    Host=$OpenCodeCommand.Replace("'","''")
    Mock=$Prefix[-1].Replace("'","''")
  }
  @"
`$ErrorActionPreference='Stop'
& '$($esc.Runner)' ``
  -ProjectDir '$($esc.Project)' ``
  -Command ai-resume ``
  -TaskId 'TASK-001' ``
  -Arguments 'TASK-001 resume fixture' ``
  -RoutingConfigPath '$($esc.Routing)' ``
  -ConfigDir '$($esc.Config)' ``
  -OpenCodeCommand '$($esc.Host)' ``
  -OpenCodePrefixArguments @('-NoProfile','-File','$($esc.Mock)') ``
  -KeepAttemptLogs
exit `$LASTEXITCODE
"@ | Set-Content -LiteralPath $wrapper -Encoding utf8
  $output=& pwsh -NoProfile -File $wrapper 2>&1
  $code=$LASTEXITCODE
  Remove-Item -LiteralPath $wrapper -Force -ErrorAction SilentlyContinue
  [pscustomobject]@{code=$code;text=(($output|ForEach-Object{[string]$_})-join"`n")}
}

# Positive lifecycle: complete handoff → progress under headless policy
$hostExe=(Get-Command pwsh -ErrorAction Stop).Source
$progress=Invoke-MockRunner 'progress' $hostExe @('-NoProfile','-File',(Join-Path $TempRoot 'mock-progress.ps1'))
if($progress.code -ne 0){throw "Positive headless progress failed: $($progress.text)"}
if($progress.text -notmatch 'HEADLESS_PERMISSION_CONTRACT'){throw 'Missing headless contract log.'}
if($progress.text -notmatch 'auto=disabled'){throw 'Missing auto=disabled guarantee.'}
if($progress.text -notmatch 'postcondition=PASS'){throw 'Missing postcondition PASS.'}
if($progress.text -notmatch 'GOVERNANCE_RESULT'){throw 'Missing GOVERNANCE_RESULT surface.'}
if($progress.text -notmatch 'OPENCODE_CLI_RESOLVED host='){throw 'Missing launcher resolution log.'}
if($progress.text -notmatch 'ROUTING_MANIFEST_HASHES'){throw 'Missing JSONC routing hashes.'}

# Reset checkpoint for negative path
@'
{"task_id":"TASK-001","state":"DISCOVERY_DEFECT_REPAIR_CYCLE_1","phase":"DISCOVERY_DEFECT_REPAIR_CYCLE_1","next_required_phase":"DISCOVERY_ADJUDICATION","next_action":{"kind":"execute","command":"/ai-resume","arguments":["TASK-001"]}}
'@ | Set-Content -LiteralPath (Join-Path $Project '.ai/tasks/TASK-001/RUN_STATE.json') -Encoding utf8
$beforeAi=(Get-FileHash -LiteralPath (Join-Path $Project '.ai/tasks/TASK-001/RUN_STATE.json') -Algorithm SHA256).Hash
$beforeSource=Get-Content -LiteralPath (Join-Path $Project 'source.txt') -Raw

# Negative lifecycle: permission auto-reject → precise blocker, no fallback, rollback
$blocked=Invoke-MockRunner 'permission-block' $hostExe @('-NoProfile','-File',(Join-Path $TempRoot 'mock-permission-block.ps1'))
if($blocked.code -eq 0){throw 'Permission block was incorrectly accepted.'}
if($blocked.text -notmatch 'ARCHITECT_PERMISSION_BLOCKED'){throw "Missing ARCHITECT_PERMISSION_BLOCKED: $($blocked.text)"}
if($blocked.text -notmatch 'HEADLESS_PERMISSION_CONTRACT_VIOLATION'){throw 'Missing HEADLESS_PERMISSION_CONTRACT_VIOLATION.'}
if($blocked.text -match 'ARCHITECT_FAILOVER_COMPLETE'){throw 'Permission block incorrectly completed failover.'}
if($blocked.text -match 'architect-fallback'){throw 'Permission block incorrectly attempted model fallback.'}
$afterAi=(Get-FileHash -LiteralPath (Join-Path $Project '.ai/tasks/TASK-001/RUN_STATE.json') -Algorithm SHA256).Hash
if($beforeAi -ne $afterAi){throw 'Checkpoint was not restored after permission block.'}
if((Get-Content -LiteralPath (Join-Path $Project 'source.txt') -Raw) -ne $beforeSource){throw 'Application source changed after permission block.'}

# JSONC source must be byte-identical (never mutated merely to read)
$RoutingBytesAfter=[IO.File]::ReadAllBytes($RoutingPath)
if($RoutingBytesBefore.Length -ne $RoutingBytesAfter.Length){throw 'Routing JSONC was mutated.'}
for($i=0;$i -lt $RoutingBytesBefore.Length;$i++){if($RoutingBytesBefore[$i] -ne $RoutingBytesAfter[$i]){throw 'Routing JSONC byte drift.'}}

# Launcher: explicit .ps1 path (single candidate)
$ps1Launcher=Join-Path $TempRoot 'space dir'
New-Item -ItemType Directory -Force -Path $ps1Launcher|Out-Null
$ps1Path=Join-Path $ps1Launcher 'opencode mock.ps1'
@'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
Write-Output "GOVERNANCE_RESULT`nTASK_ID: TASK-001`nSTATE: READY_FOR_EXECUTION"
$path=Join-Path ($Args[[array]::IndexOf($Args,'--dir')+1]) '.ai/tasks/TASK-001/RUN_STATE.json'
$state=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
$state.state='READY_FOR_EXECUTION';$state.phase='READY_FOR_EXECUTION'
$state|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding utf8
exit 0
'@ | Set-Content -LiteralPath $ps1Path -Encoding utf8
@'
{"task_id":"TASK-001","state":"DISCOVERY_DEFECT_REPAIR_CYCLE_1","phase":"DISCOVERY_DEFECT_REPAIR_CYCLE_1","next_required_phase":"DISCOVERY_ADJUDICATION","next_action":{"kind":"execute","command":"/ai-resume","arguments":["TASK-001"]}}
'@ | Set-Content -LiteralPath (Join-Path $Project '.ai/tasks/TASK-001/RUN_STATE.json') -Encoding utf8
$launchPs1=& pwsh -NoProfile -File $Runner -ProjectDir $Project -Command ai-resume -TaskId TASK-001 -Arguments 'TASK-001' -RoutingConfigPath $RoutingPath -ConfigDir $Config -OpenCodeCommand $ps1Path 2>&1
if($LASTEXITCODE -ne 0){throw "ps1 launcher failed: $($launchPs1 -join "`n")"}
if(($launchPs1 -join "`n") -notmatch 'launcher_type=npm-ps1'){throw 'Expected npm-ps1 launcher type.'}

# Missing launcher
$missing=& pwsh -NoProfile -File $Runner -ProjectDir $Project -Command ai-plan -Arguments x -RoutingConfigPath $RoutingPath -ConfigDir $Config -OpenCodeCommand 'C:\definitely\missing\opencode-not-real.exe' 2>&1
if($LASTEXITCODE -eq 0){throw 'Missing launcher was accepted.'}
if(($missing -join "`n") -notmatch 'OPENCODE_CLI_NOT_FOUND'){throw 'Missing OPENCODE_CLI_NOT_FOUND.'}

# Malformed prefix (scalar string should be rejected when passed incorrectly via wrapper)
# Array is required by param type; exercise empty explicit command
$empty=& pwsh -NoProfile -File $Runner -ProjectDir $Project -Command ai-plan -Arguments x -RoutingConfigPath $RoutingPath -ConfigDir $Config -OpenCodeCommand '   ' 2>&1
if($LASTEXITCODE -eq 0){throw 'Empty OpenCodeCommand was accepted.'}

Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
$global:LASTEXITCODE=0
Write-Host 'PASS: Windows Architect headless permission contract, permission blocker, JSONC routing and launcher regressions.'
