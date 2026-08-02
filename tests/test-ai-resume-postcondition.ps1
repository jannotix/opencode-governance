$ErrorActionPreference='Stop'
$RootDir=Split-Path -Parent $PSScriptRoot
$Runner=Join-Path $RootDir 'scripts/run-governed.ps1'
$TempRoot=Join-Path ([IO.Path]::GetTempPath()) ('opencode-v373-postcondition-'+[guid]::NewGuid().ToString('N'))
$Config=Join-Path $TempRoot 'config'
$Project=Join-Path $TempRoot 'project'
New-Item -ItemType Directory -Force -Path $Config,(Join-Path $Project '.ai/tasks/TASK-001'),(Join-Path $Project '.ai/tasks/TASK-002')|Out-Null

@'
{"schema_version":"1.0","settings":{"enabled_roles":["architect"],"eligible_failures":["PROVIDER_UNAVAILABLE"],"allow_degraded_independence":false,"default_cooldown_seconds":60},"roles":{"architect":{"primary":{"model":"test/architect-primary","model_family":"primary","variant_policy":"explicit","variant":"test","only_on":[]},"fallbacks":[{"model":"test/architect-fallback","model_family":"fallback","variant_policy":"explicit","variant":"test","priority":1,"only_on":["PROVIDER_UNAVAILABLE"]}]}}}
'@ | Set-Content -LiteralPath (Join-Path $Config 'opencode-governance-routing.json') -Encoding utf8
@'
{"task_id":"TASK-001","state":"DISCOVERY_DEFECT_REPAIR_CYCLE_3","phase":"DISCOVERY_DEFECT_REPAIR_CYCLE_3","next_required_phase":"DISCOVERY_ADJUDICATION","next_action":{"kind":"execute","command":"/ai-resume","arguments":["TASK-001"]}}
'@ | Set-Content -LiteralPath (Join-Path $Project '.ai/tasks/TASK-001/RUN_STATE.json') -Encoding utf8
@'
{"task_id":"TASK-002","state":"IMPLEMENTING","current_phase":"IMPLEMENTING","next_required_phase":"TASK_VALIDATED"}
'@ | Set-Content -LiteralPath (Join-Path $Project '.ai/tasks/TASK-002/RUN_STATE.json') -Encoding utf8
'source'|Set-Content -LiteralPath (Join-Path $Project 'source.txt')

$PromptPath=Join-Path $TempRoot 'prompt.txt'
$Prompt="TASK-001`n$('x'*25000)`nUnicode: città — ✓`n```json`n{`"a`":`"``$&`"}`n```n"
[IO.File]::WriteAllText($PromptPath,$Prompt,(New-Object Text.UTF8Encoding($false)))
$ExpectedHash=(Get-FileHash -LiteralPath $PromptPath -Algorithm SHA256).Hash.ToLowerInvariant()

$Mock=Join-Path $TempRoot 'mock.ps1'
@'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
if($env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH){$d=Split-Path -Parent $env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH; if($d){New-Item -ItemType Directory -Force -Path $d|Out-Null}; $r=if($env:OPENCODE_GOVERNANCE_ROLE){$env:OPENCODE_GOVERNANCE_ROLE}else{'architect'}; (@{schema='EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1';role=$r;plugin_sha256='mock';policy_sha256='mock';process_id=$PID;nonce='mock-test'}|ConvertTo-Json -Compress)|Set-Content -LiteralPath $env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH -Encoding utf8}
$project=''
for($i=0;$i-lt$Args.Count;$i++){if($Args[$i]-eq'--dir'){$project=$Args[++$i]}}
# ARCHITECT_STDIN_PROMPT_TRANSPORT_V1: complete handoff arrives on stdin, never argv.
$ms=[IO.MemoryStream]::new(); [Console]::OpenStandardInput().CopyTo($ms); $rawBytes=$ms.ToArray()
$prompt=[Text.UTF8Encoding]::new($false).GetString($rawBytes)
$raw=($prompt -split "`n`n\[\[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1\]\]",2)[0]
$bytes=[Text.Encoding]::UTF8.GetBytes($raw)
$sha=[Security.Cryptography.SHA256]::Create()
try{$hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
if($hash-ne$env:EXPECTED_HASH){[Console]::Error.WriteLine('prompt hash mismatch');exit 42}
# Prompt must not appear as an argv element.
foreach($a in $Args){ if($a -ceq $prompt -or ($a.Length -gt 1000 -and $raw.Length -gt 1000 -and $a.Contains('x'*100))){ [Console]::Error.WriteLine('prompt leaked to argv'); exit 43 } }
if((Get-Location).Path-ne$project){[Console]::Error.WriteLine('wrong cwd');exit 41}
if($env:MOCK_MODE-eq'progress'){
  $path=Join-Path $project '.ai/tasks/TASK-001/RUN_STATE.json'
  $state=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
  $state.state='READY_FOR_EXECUTION';$state.phase='READY_FOR_EXECUTION';$state.next_required_phase='IMPLEMENTING'
  $state|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $path -Encoding utf8
  Write-Output "GOVERNANCE_RESULT`nTASK_ID: TASK-001`nSTATE: READY_FOR_EXECUTION"
}else{Write-Output 'ordinary successful response without progress'}
exit 0
'@ | Set-Content -LiteralPath $Mock -Encoding utf8

function Invoke-Runner([string]$Mode){
  $env:MOCK_MODE=$Mode
  $env:EXPECTED_HASH=$ExpectedHash
  $wrapper=Join-Path $TempRoot ('runner-wrapper-'+[guid]::NewGuid().ToString('N')+'.ps1')
  $escapedRunner=$Runner.Replace("'","''")
  $escapedProject=$Project.Replace("'","''")
  $escapedPrompt=$PromptPath.Replace("'","''")
  $escapedRouting=(Join-Path $Config 'opencode-governance-routing.json').Replace("'","''")
  $escapedConfig=$Config.Replace("'","''")
  $escapedMock=$Mock.Replace("'","''")
  @"
`$ErrorActionPreference='Stop'
& '$escapedRunner' ```
  -ProjectDir '$escapedProject' ```
  -Command ai-resume ```
  -TaskId 'TASK-001' ```
  -ArgumentsFile '$escapedPrompt' ```
  -RoutingConfigPath '$escapedRouting' ```
  -ConfigDir '$escapedConfig' ```
  -OpenCodeCommand (Get-Command pwsh -ErrorAction Stop).Source ```
  -OpenCodePrefixArguments @('-NoProfile','-File','$escapedMock')
exit `$LASTEXITCODE
"@ | Set-Content -LiteralPath $wrapper -Encoding utf8
  $output=& pwsh -NoProfile -File $wrapper 2>&1
  $code=$LASTEXITCODE
  Remove-Item -LiteralPath $wrapper -Force -ErrorAction SilentlyContinue
  [pscustomobject]@{code=$code;text=(($output|ForEach-Object{[string]$_})-join"`n")}
}

$before=(Get-FileHash -LiteralPath (Join-Path $Project '.ai/tasks/TASK-001/RUN_STATE.json') -Algorithm SHA256).Hash
$result=Invoke-Runner 'no-progress'
if($result.code-eq0){throw 'No-progress attempt was incorrectly accepted.'}
if($result.text-notmatch'ARCHITECT_NO_PROGRESS'){throw "Missing ARCHITECT_NO_PROGRESS: $($result.text)"}
$after=(Get-FileHash -LiteralPath (Join-Path $Project '.ai/tasks/TASK-001/RUN_STATE.json') -Algorithm SHA256).Hash
if($before-ne$after){throw 'Checkpoint was not restored after no-progress.'}

$result=Invoke-Runner 'progress'
if($result.code-ne0){throw "Valid progress failed: $($result.text)"}
if($result.text-notmatch'postcondition=PASS'){throw 'Missing postcondition PASS.'}
if($result.text-notmatch'GOVERNANCE_RESULT'){throw 'Validated child result was not surfaced.'}

Remove-Item -LiteralPath $TempRoot -Recurse -Force
$global:LASTEXITCODE=0
Write-Host 'PASS: Windows lossless resume handoff, explicit task binding and postcondition validation.'
