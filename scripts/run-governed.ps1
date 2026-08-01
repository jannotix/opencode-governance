param(
    [Parameter(Mandatory=$true)][string]$ProjectDir,
    [Parameter(Mandatory=$true)][ValidateSet('ai-init','ai-audit','ai-discover','ai-plan','ai-resume')][string]$Command,
    [string]$Arguments = '',
    [string]$ArgumentsFile,
    [string]$TaskId,
    [string]$RoutingConfigPath,
    [string]$ConfigDir,
    [string]$OpenCodeCommand = 'opencode',
    [string[]]$OpenCodePrefixArguments = @(),
    [int]$TimeoutSeconds = 3600,
    [switch]$KeepAttemptLogs
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
    [Console]::Error.WriteLine('POWERSHELL_7_REQUIRED: The Architect transactional runner requires PowerShell 7 or newer.')
    exit 64
}

$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $ProjectDir -PathType Container)){throw 'Project directory does not exist.'}
$ProjectDir=(Resolve-Path -LiteralPath $ProjectDir).Path
if(-not $ConfigDir){$ConfigDir=if($env:OPENCODE_CONFIG_DIR){$env:OPENCODE_CONFIG_DIR}else{Join-Path $HOME '.config/opencode'}}
if(-not $RoutingConfigPath){$RoutingConfigPath=Join-Path $ConfigDir 'opencode-governance-routing.json'}
if(-not(Test-Path -LiteralPath $RoutingConfigPath -PathType Leaf)){throw "Routing profile/manifest not found: $RoutingConfigPath"}
if($TimeoutSeconds -lt 30){throw 'TimeoutSeconds must be at least 30.'}

function Get-TextHash([string]$Text){
  $bytes=[Text.Encoding]::UTF8.GetBytes($Text);$sha=[Security.Cryptography.SHA256]::Create()
  try{([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Get-FileHashHex([string]$Path){
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return 'ABSENT'}
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Assert-SafeLeaf([string]$Path,[string]$Label){
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "$Label not found: $Path"}
  $item=Get-Item -LiteralPath $Path -Force
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne0){throw "$Label may not be a symlink, junction or reparse point: $Path"}
}

if($ArgumentsFile){
  Assert-SafeLeaf $ArgumentsFile 'Arguments file'
  $ArgumentsFile=(Resolve-Path -LiteralPath $ArgumentsFile).Path
  $Arguments=[IO.File]::ReadAllText($ArgumentsFile,[Text.Encoding]::UTF8)
}
$ArgumentsHash=Get-TextHash $Arguments
$Marker='[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
$env:OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE='1'
$RoutedArguments=if($Arguments -like "*$Marker*"){$Arguments}elseif([string]::IsNullOrWhiteSpace($Arguments)){$Marker}else{"$Arguments`n`n$Marker"}

if($Command-eq'ai-resume'){
  if([string]::IsNullOrWhiteSpace($TaskId)){
    $match=[regex]::Match($Arguments,'(?m)^\s*([A-Za-z0-9][A-Za-z0-9._-]{2,})\b')
    if($match.Success){$TaskId=$match.Groups[1].Value}
  }
  if([string]::IsNullOrWhiteSpace($TaskId)){throw 'RESUME_TASK_ID_REQUIRED: ai-resume requires -TaskId or a task ID as the first argument token.'}
  if($TaskId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]+$'){throw 'RESUME_TASK_ID_INVALID'}
}

try{$Routing=Get-Content -LiteralPath $RoutingConfigPath -Raw|ConvertFrom-Json}catch{throw 'Routing profile is invalid JSON.'}
if([string]$Routing.schema_version -ne '1.0'){throw 'Routing schema_version must be 1.0.'}
if($null-eq$Routing.settings-or$null-eq$Routing.roles){throw 'Routing profile is missing settings or roles.'}
$AllowedFailures=@('PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT','TOOL_EXECUTION_ABORTED')
$AllowedOnlyOn=$AllowedFailures+@('MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS')
$PostSideEffectPhases=@(
  'IMPLEMENTING','IMPLEMENTATION','DOCUMENTATION_SYNC','EVIDENCE_VALIDATION','OPERATIONAL_VALIDATION',
  'EVIDENCE_AND_OPERATIONAL_VALIDATION','TASK_VALIDATED','DUAL_REVIEW','DUAL_REVIEW_COMPLETE','TASK_DUAL_REVIEW',
  'FINAL_ADJUDICATION','FINAL_ADJUDICATION_PASS','TASK_FINAL_ADJUDICATION','PASS','IMPLEMENTATION_DEFECT','PLAN_DEFECT',
  'PRODUCT_COMPLETENESS_RECONCILIATION','PRODUCT_COMPLETE','PRODUCT_DEFECT','PRODUCT_INCOMPLETE','MILESTONE_VALIDATED',
  'RELEASE_READINESS','RELEASE_READY','READY_FOR_PRODUCTION','NOT_READY_FOR_PRODUCTION','VALIDATED_LEARNING','LOCAL_COMMITTED'
)
function Get-JsonArray([object]$Owner,[string]$Name,[string]$Context,[bool]$Required=$true){
  $Property=$Owner.PSObject.Properties[$Name]
  if($null-eq$Property){if($Required){throw "$Context must be an array."};return}
  $Value=$Property.Value
  if($Value-is[string]-or$Value-isnot[System.Collections.IEnumerable]){throw "$Context must be an array."}
  @($Value)
}
function Test-JsonInteger([object]$Value){($Value-is[int])-or($Value-is[long])}
$Enabled=@(Get-JsonArray $Routing.settings 'enabled_roles' 'settings.enabled_roles')
if('architect'-notin@($Enabled|ForEach-Object{[string]$_})){throw 'Architect failover is not enabled in the routing profile.'}
$Eligible=@(Get-JsonArray $Routing.settings 'eligible_failures' 'settings.eligible_failures')
if(@($Eligible|Where-Object{$_-isnot[string]-or[string]::IsNullOrWhiteSpace([string]$_)-or([string]$_-notin$AllowedFailures)}).Count-gt0){throw 'Routing profile contains an unsupported eligible failure.'}
if($Routing.settings.allow_degraded_independence-isnot[bool]-or$Routing.settings.allow_degraded_independence-ne$false){throw 'Routing must fail closed on degraded model independence.'}
$CooldownValue=$Routing.settings.default_cooldown_seconds
if(-not(Test-JsonInteger $CooldownValue)-or[long]$CooldownValue-lt60-or[long]$CooldownValue-gt86400){throw 'default cooldown must be an integer between 60 and 86400 seconds.'}
$DefaultCooldown=[long]$CooldownValue
$Architect=$Routing.roles.architect
if($null-eq$Architect){throw 'Architect role is missing from the routing profile.'}
$Fallbacks=@(Get-JsonArray $Architect 'fallbacks' 'architect fallbacks' $false)
if($Fallbacks.Count-eq0){throw 'Architect failover requires at least one fallback.'}
function Get-OnlyOn([object]$Candidate){
  $OnlyOn=@(Get-JsonArray $Candidate 'only_on' 'Every route candidate only_on')
  if(@($OnlyOn|Where-Object{$_-isnot[string]-or[string]::IsNullOrWhiteSpace([string]$_)-or([string]$_-notin$AllowedOnlyOn)}).Count-gt0){throw 'Every route candidate only_on contains an unsupported value.'}
  @($OnlyOn|ForEach-Object{[string]$_})
}
function Get-RoutePriority([object]$Route){
  if(-not(Test-JsonInteger $Route.priority)-or[long]$Route.priority-lt1){throw 'Architect fallback priority must be a positive integer.'}
  [long]$Route.priority
}
function Validate-Route([object]$Route,[bool]$NeedsPriority){
  if($null-eq$Route-or[string]$Route.model-notmatch'^[^/\s]+/\S+$'){throw "Invalid Architect route model: $($Route.model)"}
  if([string]::IsNullOrWhiteSpace([string]$Route.model_family)){throw 'Architect route model_family is required.'}
  $policy=[string]$Route.variant_policy
  if($policy-notin@('explicit','provider_default','highest_supported')){throw 'Architect route variant_policy is invalid.'}
  if($policy-eq'explicit'-and[string]::IsNullOrWhiteSpace([string]$Route.variant)){throw 'Explicit Architect variant is required.'}
  if($policy-eq'provider_default'-and-not[string]::IsNullOrWhiteSpace([string]$Route.variant)){throw 'provider_default must use a blank variant.'}
  if($policy-eq'highest_supported'-and[string]::IsNullOrWhiteSpace([string]$Route.variant)){throw 'highest_supported must resolve to a concrete variant.'}
  if([string]$Route.variant-eq'highest_supported'){throw 'highest_supported cannot be a literal variant.'}
  Get-OnlyOn $Route|Out-Null
  if($NeedsPriority){Get-RoutePriority $Route|Out-Null}
}
Validate-Route $Architect.primary $false
$Priorities=@()
foreach($route in $Fallbacks){Validate-Route $route $true;$p=Get-RoutePriority $route;if($p-in$Priorities){throw 'Architect fallback priorities must be unique.'};$Priorities+=$p}
$Routes=@([pscustomobject]@{candidate=$Architect.primary;priority=0;route='architect-primary'})+@($Fallbacks|Sort-Object{Get-RoutePriority $_}|ForEach-Object{[pscustomobject]@{candidate=$_;priority=(Get-RoutePriority $_);route="architect-fallback-$(Get-RoutePriority $_)"}})

function Resolve-OpenCodeLaunch(){
  $command=$OpenCodeCommand;$prefix=@($OpenCodePrefixArguments)
  if($command-eq'opencode'){
    $resolved=(Get-Command opencode -ErrorAction SilentlyContinue|Select-Object -First 1 -ExpandProperty Source)
    $candidates=@($resolved,"$env:USERPROFILE\.opencode\bin\opencode.exe","$env:LOCALAPPDATA\Microsoft\WinGet\Links\opencode.exe","$env:APPDATA\npm\opencode.ps1","$env:APPDATA\npm\opencode.cmd","$env:USERPROFILE\scoop\shims\opencode.exe","$env:USERPROFILE\scoop\shims\opencode.cmd","C:\ProgramData\chocolatey\bin\opencode.exe")|Where-Object{$_-and(Test-Path -LiteralPath $_ -PathType Leaf)}|Select-Object -Unique
    if(-not$candidates){throw 'OPENCODE_CLI_NOT_FOUND'}
    $command=$candidates[0]
  }
  if($command -match '\.ps1$'){$prefix=@('-NoProfile','-File',$command)+$prefix;$command=(Get-Command pwsh -ErrorAction Stop).Source}
  elseif($command -match '\.(cmd|bat)$'){$prefix=@('/d','/s','/c',$command)+$prefix;$command=$env:ComSpec}
  else{
    $found=Get-Command $command -ErrorAction SilentlyContinue
    if($found){$command=$found.Source}elseif(-not(Test-Path -LiteralPath $command -PathType Leaf)){throw "OPENCODE_CLI_NOT_FOUND: $command"}
  }
  [pscustomobject]@{command=$command;prefix=@($prefix)}
}
$Launch=Resolve-OpenCodeLaunch
Write-Host "OPENCODE_CLI_RESOLVED type=$([IO.Path]::GetExtension([string]$Launch.command)) command=$($Launch.command)"

$StatePath=Join-Path $ConfigDir 'opencode-governance-routing-state.tsv'
New-Item -ItemType Directory -Force -Path $ConfigDir|Out-Null
function Get-Epoch(){[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}
function Load-Cooldowns(){
  $map=@{};if(Test-Path -LiteralPath $StatePath -PathType Leaf){foreach($line in Get-Content -LiteralPath $StatePath){if([string]::IsNullOrWhiteSpace($line)){continue};$parts=$line-split"`t",2;$until=0L;if($parts.Count-eq2-and[long]::TryParse($parts[1],[ref]$until)-and$until-gt(Get-Epoch)){$map[$parts[0]]=$until}}};$map
}
function Save-Cooldowns([hashtable]$Map){$lines=@();foreach($key in($Map.Keys|Sort-Object)){$lines+="$key`t$($Map[$key])"};$tmp="$StatePath.tmp.$PID";[IO.File]::WriteAllLines($tmp,$lines,(New-Object Text.UTF8Encoding($false)));Move-Item -LiteralPath $tmp -Destination $StatePath -Force}
$Cooldowns=Load-Cooldowns

function Get-FileTreeHash([string]$Path){
  if(-not(Test-Path -LiteralPath $Path)){return 'ABSENT'}
  $rows=@();foreach($item in Get-ChildItem -LiteralPath $Path -Force -Recurse|Sort-Object FullName){$relative=[IO.Path]::GetRelativePath($Path,$item.FullName).Replace('\','/');if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){$rows+="$relative`tSYMLINK:$($item.Target -join ';')";continue};if(-not$item.PSIsContainer){$rows+="$relative`t$((Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant())"}};Get-TextHash($rows-join"`n")
}
function Encode-StateField([string]$Value){[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))}
function Get-ProjectTreeHash([string]$Root){
  $rows=[Collections.Generic.List[string]]::new();$stack=[Collections.Generic.Stack[string]]::new();$stack.Push($Root)
  while($stack.Count){$directory=$stack.Pop();foreach($item in Get-ChildItem -LiteralPath $directory -Force){$relative=[IO.Path]::GetRelativePath($Root,$item.FullName).Replace('\','/');if($item.Name-ieq'.git'){continue};if($relative-ieq'.ai'-or$relative.StartsWith('.ai/',[StringComparison]::OrdinalIgnoreCase)){continue};$p=Encode-StateField $relative;$a=[int]$item.Attributes;if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){$rows.Add("L|$p|$a|$(Encode-StateField ([string]$item.LinkTarget))");continue};if($item.PSIsContainer){$rows.Add("D|$p|$a");$stack.Push($item.FullName);continue};$rows.Add("F|$p|$a|$($item.Length)|$((Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant())")}}
  Get-TextHash(($rows|Sort-Object)-join"`n")
}
function Invoke-GitProbe([string[]]$GitArguments){$output=& git -C $ProjectDir @GitArguments 2>$null;[pscustomobject]@{code=$LASTEXITCODE;text=(($output|ForEach-Object{[string]$_})-join"`n")}}
function Get-ProjectStateFingerprint(){
  $tree=Get-ProjectTreeHash $ProjectDir;$mode='NON_GIT';$head='N/A';$index='N/A';$subs='N/A';$git=Get-Command git -ErrorAction SilentlyContinue
  if($git){$inside=Invoke-GitProbe @('rev-parse','--is-inside-work-tree');if($inside.code-eq0-and$inside.text.Trim()-eq'true'){$mode='GIT';$h=Invoke-GitProbe @('rev-parse','--verify','HEAD');$head=if($h.code-eq0){$h.text.Trim()}else{'UNBORN'};$i=Invoke-GitProbe @('rev-parse','--git-path','index');if($i.code-ne0){throw 'Unable to resolve Git index.'};$ip=$i.text.Trim();if(-not[IO.Path]::IsPathRooted($ip)){$ip=[IO.Path]::GetFullPath((Join-Path $ProjectDir $ip))};$index=if(Test-Path $ip){Get-FileHashHex $ip}else{'ABSENT'};$s=Invoke-GitProbe @('submodule','status','--recursive');if($s.code-ne0){throw 'Unable to read submodule state.'};$subs=Get-TextHash $s.text}}
  Get-TextHash "PROJECT_STATE_FINGERPRINT_V1`nMODE=$mode`nTREE=$tree`nHEAD=$head`nINDEX=$index`nSUBMODULES=$subs"
}
function Restore-Ai([string]$AiPath,[string]$Backup,[bool]$Existed,[string]$ExpectedHash){if(Test-Path $AiPath){Remove-Item $AiPath -Recurse -Force};if($Existed){Copy-Item $Backup $AiPath -Recurse -Force};$actual=Get-FileTreeHash $AiPath;if($actual-ne$ExpectedHash){throw "ARCHITECT_FAILOVER_BLOCKED: .ai restore hash mismatch ($actual != $ExpectedHash). HUMAN_RECOVERY_REQUIRED"}}
function Get-TransactionDir([string]$Path){ Join-Path $ConfigDir ("opencode-governance-architect-tx/" + (Get-TextHash $Path.ToLowerInvariant())) }
function Test-PidAlive([int]$Id){try{$null=Get-Process -Id $Id -ErrorAction Stop;$true}catch{$false}}
function Get-TaskSnapshot(){
  if($Command-ne'ai-resume'){return $null}
  $path=Join-Path $ProjectDir ".ai/tasks/$TaskId/RUN_STATE.json"
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "RESUME_TASK_NOT_FOUND: $TaskId"}
  try{$state=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json}catch{throw "INVALID_RUN_STATE: $path"}
  if($state.PSObject.Properties['task_id']-and[string]$state.task_id-ne$TaskId){throw 'RESUME_TASK_ID_MISMATCH'}
  $phase = if ($state.current_phase) { [string]$state.current_phase } else { [string]$state.phase }
  $action = if ($state.next_action) { $state.next_action | ConvertTo-Json -Depth 20 -Compress } else { '' }
  [pscustomobject]@{path=$path;hash=(Get-FileHashHex $path);state=[string]$state.state;phase=$phase;next=[string]$state.next_required_phase;action=$action}
}
function Get-ResumeMode(){
  $snap=Get-TaskSnapshot;$state=Get-Content -LiteralPath $snap.path -Raw|ConvertFrom-Json;$phases=@();foreach($field in @('current_phase','state','last_safe_transition')){$v=[string]$state.$field;if(-not[string]::IsNullOrWhiteSpace($v)){$phases+=$v.Trim()}}
  if(-not$phases){return 'PRE_SIDE_EFFECT'};foreach($phase in$phases){if($phase-in$PostSideEffectPhases){return 'POST_SIDE_EFFECT'}};'PRE_SIDE_EFFECT'
}
function Recover-Orphan([string]$Tx,[string]$Ai){
  $metaPath = Join-Path $Tx 'meta.json'
  if(-not(Test-Path -LiteralPath $metaPath -PathType Leaf)){return}
  $meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
  if(Test-PidAlive ([int]$meta.pid)){throw 'ARCHITECT_TRANSACTION_ACTIVE'}
  if((Get-ProjectStateFingerprint) -ne [string]$meta.project_state_fingerprint){throw 'ARCHITECT_ORPHAN_RECOVERY_BLOCKED: PROJECT_STATE_CHANGED. HUMAN_RECOVERY_REQUIRED'}
  $backup = Join-Path $Tx 'ai-snapshot'
  Restore-Ai $Ai $backup ([bool]$meta.ai_existed) ([string]$meta.ai_hash)
  Remove-Item -LiteralPath $Tx -Recurse -Force
  Write-Warning 'ARCHITECT_ORPHAN_RECOVERED'
}
function Open-Transaction([string]$Tx,[string]$Ai,[string]$AiHash,[bool]$Existed,[string]$ProjectState,[object]$Task){
  if(Test-Path -LiteralPath $Tx){Remove-Item -LiteralPath $Tx -Recurse -Force}
  New-Item -ItemType Directory -Force -Path $Tx | Out-Null
  $backup = Join-Path $Tx 'ai-snapshot'
  if($Existed){Copy-Item -LiteralPath $Ai -Destination $backup -Recurse -Force}
  $checkpointHash = if($Task){[string]$Task.hash}else{$null}
  $meta=[ordered]@{
    schema='ARCHITECT_TRANSACTION_V2'
    command=$Command
    task_id=$TaskId
    arguments_sha256=$ArgumentsHash
    checkpoint_sha256=$checkpointHash
    project_dir=$ProjectDir
    pid=$PID
    started_at_utc=[DateTime]::UtcNow.ToString('o')
    ai_existed=$Existed
    ai_hash=$AiHash
    project_state_fingerprint=$ProjectState
  }
  $meta | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Tx 'meta.json') -Encoding utf8
  $backup
}
function Close-Transaction([string]$Tx){if(Test-Path $Tx){Remove-Item $Tx -Recurse -Force}}
function Classify-Failure([string]$Text,[bool]$TimedOut,[int]$ExitCode=1){
  if($TimedOut){ return 'BOUNDED_TIMEOUT' }
  $value=$Text.ToLowerInvariant()
  if($value -match 'tool[_\s-]?execution[_\s-]?aborted|execution aborted|tool aborted'){ return 'TOOL_EXECUTION_ABORTED' }
  if($value -match 'quota.*(exhausted|exceeded)|plan limit'){ return 'PLAN_QUOTA_EXHAUSTED' }
  if($value -match 'rate.?limit|http\s*429'){ return 'RATE_LIMIT' }
  if($value -match 'retired|deprecated'){ return 'MODEL_RETIRED' }
  if($value -match 'temporarily unavailable|model overloaded'){ return 'MODEL_TEMPORARILY_UNAVAILABLE' }
  if($value -match 'connection refused|network error|http\s*5\d\d|service unavailable'){ return 'PROVIDER_UNAVAILABLE' }
  if($ExitCode -lt 0 -or $ExitCode -ge 128){ return 'TOOL_EXECUTION_ABORTED' }
  'UNCLASSIFIED_FAILURE'
}
function Candidate-Allowed([object]$Route,[string]$Failure,[string]$Family,[hashtable]$Attempted){
  if($Attempted.ContainsKey($Route.route)){ return $false }
  if($Cooldowns.ContainsKey([string]$Route.candidate.model) -and $Cooldowns[[string]$Route.candidate.model] -gt (Get-Epoch)){ return $false }
  $scope=Get-OnlyOn $Route.candidate
  if($scope.Count -gt 0 -and $Failure -notin $scope){
    $same=@($Routes | Where-Object { [string]$_.candidate.model_family -eq $Family -and -not $Attempted.ContainsKey($_.route) })
    if(-not($scope -contains 'MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS' -and $same.Count -eq 0)){ return $false }
  }
  if($Failure -eq 'MODEL_RETIRED' -and [string]$Route.candidate.model_family -eq $Family){ return $false }
  $true
}
function Invoke-Route([object]$Route,[int]$Attempt,[string]$Logs){
  $stdout = Join-Path $Logs "attempt-$Attempt.stdout.log"
  $stderr = Join-Path $Logs "attempt-$Attempt.stderr.log"
  $info = [Diagnostics.ProcessStartInfo]::new()
  $info.FileName = [string]$Launch.command
  $info.WorkingDirectory = $ProjectDir
  $info.UseShellExecute = $false
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.CreateNoWindow = $true
  $info.Environment['OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE'] = '1'
  foreach($v in @($Launch.prefix)){ $null = $info.ArgumentList.Add([string]$v) }
  foreach($v in @('run','--dir',$ProjectDir,'--agent','architect','--model',[string]$Route.candidate.model)){ $null = $info.ArgumentList.Add([string]$v) }
  if(-not [string]::IsNullOrWhiteSpace([string]$Route.candidate.variant)){
    $null = $info.ArgumentList.Add('--variant')
    $null = $info.ArgumentList.Add([string]$Route.candidate.variant)
  }
  foreach($v in @('--command',$Command,'--format','json',$RoutedArguments)){ $null = $info.ArgumentList.Add([string]$v) }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $info
  if(-not $process.Start()){ throw 'Unable to start OpenCode.' }
  $outTask = $process.StandardOutput.ReadToEndAsync()
  $errTask = $process.StandardError.ReadToEndAsync()
  $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
  if($timedOut){ try{$process.Kill($true)}catch{}; $process.WaitForExit() }
  $out = $outTask.GetAwaiter().GetResult()
  $err = $errTask.GetAwaiter().GetResult()
  [IO.File]::WriteAllText($stdout,$out)
  [IO.File]::WriteAllText($stderr,$err)
  [pscustomobject]@{exit=$process.ExitCode;timed_out=$timedOut;text=($out+"`n"+$err);stdout=$out;stderr=$err}
}
function Validate-ResumePostcondition([object]$Before,[string]$BeforeAi,[object]$Result){
  $After=Get-TaskSnapshot
  $AfterAi=Get-FileTreeHash (Join-Path $ProjectDir '.ai')
  if($After.hash -eq $Before.hash -and $AfterAi -eq $BeforeAi){ throw 'ARCHITECT_NO_PROGRESS: child exited zero but task checkpoint and .ai/** are byte-identical.' }
  if($Result.text -notmatch 'GOVERNANCE_RESULT'){ throw 'ARCHITECT_CHILD_RESULT_MISSING: child exited zero without GOVERNANCE_RESULT.' }
  if([string]::IsNullOrWhiteSpace($After.state) -and [string]::IsNullOrWhiteSpace($After.phase)){ throw 'ARCHITECT_CHILD_RESULT_MISMATCH: resulting checkpoint has no state/phase.' }
  [pscustomobject]@{after=$After;ai_hash=$AfterAi}
}

$AiPath=Join-Path $ProjectDir '.ai'
$TxDir=Get-TransactionDir $ProjectDir
Recover-Orphan $TxDir $AiPath
$BeforeTask=Get-TaskSnapshot
if($Command-eq'ai-resume'){
  $mode=Get-ResumeMode
  Write-Host "ARCHITECT_RESUME_MODE $mode task=$TaskId"
  if($mode-eq'POST_SIDE_EFFECT'){throw 'RESUME_POST_SIDE_EFFECT'}
}
$Temp=Join-Path ([IO.Path]::GetTempPath()) ("opencode-governance-"+[guid]::NewGuid().ToString('N'))
$Logs=Join-Path $Temp 'logs'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
$AiExisted=Test-Path $AiPath;$AiHash=Get-FileTreeHash $AiPath;$ProjectState=Get-ProjectStateFingerprint;$Backup=Open-Transaction $TxDir $AiPath $AiHash $AiExisted $ProjectState $BeforeTask
$Attempted=@{};$Failure=$null;$FailedFamily='';$attempt=0
try{
  while($true){
    $selectionFailure = if($Failure){$Failure}else{'PROVIDER_UNAVAILABLE'}
    $ordered=@($Routes | Where-Object { Candidate-Allowed $_ $selectionFailure $FailedFamily $Attempted } | Sort-Object priority)
    if(-not$ordered){throw "ARCHITECT_FAILOVER_BLOCKED: no eligible Architect route remains after $Failure"}
    $route=$ordered[0];$Attempted[$route.route]=$true;$attempt++;Write-Host "ARCHITECT_ROUTE_ATTEMPT $attempt $($route.route) $($route.candidate.model)"
    $result=Invoke-Route $route $attempt $Logs
    if((Get-ProjectStateFingerprint) -ne $ProjectState){ throw 'ARCHITECT_FAILOVER_BLOCKED: PROJECT_STATE_CHANGED. HUMAN_RECOVERY_REQUIRED' }
    if($result.exit -eq 0 -and -not $result.timed_out){
      $post=$null
      if($Command -eq 'ai-resume'){ $post=Validate-ResumePostcondition $BeforeTask $AiHash $result }
      $Cooldowns.Remove([string]$route.candidate.model);Save-Cooldowns $Cooldowns
      Write-Host "ARCHITECT_FAILOVER_COMPLETE route=$($route.route) attempts=$attempt task=$TaskId ai_tree=$(Get-FileTreeHash $AiPath) postcondition=PASS"
      if($result.stdout){ Write-Output $result.stdout.TrimEnd() }
      if($result.stderr){ Write-Warning $result.stderr.TrimEnd() }
      Close-Transaction $TxDir
      if(-not $KeepAttemptLogs){ Remove-Item -LiteralPath $Temp -Recurse -Force }
      exit 0
    }
    $Failure=Classify-Failure $result.text $result.timed_out ([int]$result.exit);$FailedFamily=[string]$route.candidate.model_family;Write-Warning "Architect route failed: $Failure ($($route.route))"
    if($Failure-notin$Eligible){throw "ARCHITECT_FAILOVER_BLOCKED: ineligible failure $Failure. Logs: $Logs"}
    $Cooldowns[[string]$route.candidate.model]=(Get-Epoch)+$DefaultCooldown;Save-Cooldowns $Cooldowns;Restore-Ai $AiPath $Backup $AiExisted $AiHash
  }
}catch{
  $restored=$false;try{if((Get-ProjectStateFingerprint)-eq$ProjectState){Restore-Ai $AiPath $Backup $AiExisted $AiHash;$restored=$true}}catch{}
  if($restored){Close-Transaction $TxDir}else{Write-Warning "ARCHITECT_TRANSACTION_ORPHANED: $TxDir"}
  Write-Host "ATTEMPT_LOGS $Logs";Write-Error $_;exit 1
}
