param(
    [Parameter(Mandatory=$true)][string]$ProjectDir,
    [Parameter(Mandatory=$true)][ValidateSet('ai-init','ai-audit','ai-discover','ai-plan')][string]$Command,
    [string]$Arguments = '',
    [string]$RoutingConfigPath,
    [string]$ConfigDir,
    [string]$OpenCodeCommand = 'opencode',
    [string[]]$OpenCodePrefixArguments = @(),
    [int]$TimeoutSeconds = 3600,
    [switch]$KeepAttemptLogs
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
    [Console]::Error.WriteLine('POWERSHELL_7_REQUIRED: The Architect transactional runner requires PowerShell 7 or newer. Invoke it with: pwsh -NoProfile -File "<architect-attempt.ps1>" <arguments>')
    exit 64
}

$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $ProjectDir -PathType Container)){throw 'Project directory does not exist.'}
$ProjectDir=(Resolve-Path -LiteralPath $ProjectDir).Path
if(-not $ConfigDir){$ConfigDir=if($env:OPENCODE_CONFIG_DIR){$env:OPENCODE_CONFIG_DIR}else{Join-Path $HOME '.config/opencode'}}
if(-not $RoutingConfigPath){$RoutingConfigPath=Join-Path $ConfigDir 'opencode-governance-routing.json'}
if(-not(Test-Path -LiteralPath $RoutingConfigPath -PathType Leaf)){throw "Routing profile/manifest not found: $RoutingConfigPath"}
if($TimeoutSeconds -lt 30){throw 'TimeoutSeconds must be at least 30.'}
try{$Routing=Get-Content -LiteralPath $RoutingConfigPath -Raw|ConvertFrom-Json}catch{throw 'Routing profile is invalid JSON.'}
if([string]$Routing.schema_version -ne '1.0'){throw 'Routing schema_version must be 1.0.'}
if($null-eq$Routing.settings-or$null-eq$Routing.roles){throw 'Routing profile is missing settings or roles.'}
if('architect' -notin @($Routing.settings.enabled_roles)){throw 'Architect failover is not enabled in the routing profile.'}
if($Routing.settings.allow_degraded_independence-ne$false){throw 'Routing must fail closed on degraded model independence.'}
$Architect=$Routing.roles.architect
if(-not $Architect -or @($Architect.fallbacks).Count -eq 0){throw 'Architect failover requires at least one fallback.'}
$AllowedFailures=@('PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT')
$Eligible=@($Routing.settings.eligible_failures|ForEach-Object{[string]$_})
if(@($Eligible|Where-Object{$_-notin$AllowedFailures}).Count){throw 'Routing profile contains an unsupported eligible failure.'}
$DefaultCooldown=[int]$Routing.settings.default_cooldown_seconds
if($DefaultCooldown-lt60-or$DefaultCooldown-gt86400){throw 'default cooldown must be between 60 and 86400 seconds.'}
$StatePath=Join-Path $ConfigDir 'opencode-governance-routing-state.tsv'
New-Item -ItemType Directory -Force -Path $ConfigDir|Out-Null
$Marker='[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
$env:OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE='1'
$RoutedArguments=if($Arguments -like "*$Marker*"){$Arguments}elseif([string]::IsNullOrWhiteSpace($Arguments)){$Marker}else{"$Arguments`n`n$Marker"}

function Get-OnlyOn([object]$Candidate){
  if(-not $Candidate.PSObject.Properties['only_on']){throw 'Every route candidate must define only_on.'}
  @($Candidate.only_on|Where-Object{-not[string]::IsNullOrWhiteSpace([string]$_)}|ForEach-Object{[string]$_})
}
function Validate-Route([object]$Route,[bool]$NeedsPriority){
  if($null-eq$Route-or[string]$Route.model-notmatch'^[^/\s]+/\S+$'){throw "Invalid Architect route model: $($Route.model)"}
  if([string]::IsNullOrWhiteSpace([string]$Route.model_family)){throw 'Architect route model_family is required.'}
  $policy=[string]$Route.variant_policy
  if($policy-notin@('explicit','provider_default','highest_supported')){throw 'Architect route variant_policy is invalid.'}
  if($policy-eq'explicit'-and[string]::IsNullOrWhiteSpace([string]$Route.variant)){throw 'Explicit Architect variant is required.'}
  if($policy-eq'provider_default'-and-not[string]::IsNullOrWhiteSpace([string]$Route.variant)){throw 'provider_default must use a blank variant.'}
  if($policy-eq'highest_supported'-and[string]::IsNullOrWhiteSpace([string]$Route.variant)){throw 'highest_supported must be resolved to a concrete variant before running.'}
  if([string]$Route.variant-eq'highest_supported'){throw 'highest_supported cannot be used as a literal variant.'}
  Get-OnlyOn $Route|Out-Null
  if($NeedsPriority-and($Route.priority-isnot[int]-or[int]$Route.priority-lt1)){throw 'Architect fallback priority must be a positive integer.'}
}
Validate-Route $Architect.primary $false
$Priorities=@()
foreach($route in @($Architect.fallbacks)){
  Validate-Route $route $true
  if([int]$route.priority-in$Priorities){throw 'Architect fallback priorities must be unique.'}
  $Priorities+=[int]$route.priority
}
$Routes=@([pscustomobject]@{candidate=$Architect.primary;priority=0;route='architect-primary'})+@($Architect.fallbacks|Sort-Object{[int]$_.priority}|ForEach-Object{[pscustomobject]@{candidate=$_;priority=[int]$_.priority;route="architect-fallback-$([int]$_.priority)"}})

function Get-Epoch(){[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}
function Load-Cooldowns(){
  $map=@{}
  if(Test-Path -LiteralPath $StatePath -PathType Leaf){
    foreach($line in Get-Content -LiteralPath $StatePath){
      if([string]::IsNullOrWhiteSpace($line)){continue}
      $parts=$line -split "`t",2;$until=0L
      if($parts.Count-eq2-and[long]::TryParse($parts[1],[ref]$until)-and$until-gt(Get-Epoch)){$map[$parts[0]]=$until}
    }
  }
  $map
}
function Save-Cooldowns([hashtable]$Map){
  $lines=@();foreach($key in ($Map.Keys|Sort-Object)){$lines+="$key`t$($Map[$key])"}
  $temporary="$StatePath.tmp.$PID.$([guid]::NewGuid().ToString('N'))"
  [IO.File]::WriteAllLines($temporary,$lines,(New-Object Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $temporary -Destination $StatePath -Force
}
$Cooldowns=Load-Cooldowns

function Get-TextHash([string]$Text){
  $bytes=[Text.Encoding]::UTF8.GetBytes($Text);$sha=[Security.Cryptography.SHA256]::Create()
  try{([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Encode-StateField([string]$Value){[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))}
function Get-FileTreeHash([string]$Path){
  if(-not(Test-Path -LiteralPath $Path)){return 'ABSENT'}
  $rows=@()
  foreach($file in Get-ChildItem -LiteralPath $Path -File -Recurse|Sort-Object FullName){
    $relative=[IO.Path]::GetRelativePath($Path,$file.FullName).Replace('\','/');$hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant();$rows+="$relative`t$hash"
  }
  Get-TextHash ($rows-join"`n")
}
function Test-GitMetadataAbove([string]$Path){
  $current=[IO.DirectoryInfo]::new($Path)
  while($null-ne$current){if(Test-Path -LiteralPath (Join-Path $current.FullName '.git')){return $true};$current=$current.Parent}
  $false
}
function Get-ProjectTreeHash([string]$Root){
  $rows=[Collections.Generic.List[string]]::new();$stack=[Collections.Generic.Stack[string]]::new();$stack.Push($Root)
  while($stack.Count-gt0){
    $directory=$stack.Pop()
    foreach($item in Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop){
      $relative=[IO.Path]::GetRelativePath($Root,$item.FullName).Replace('\','/')
      if($item.Name-ieq'.git'){continue}
      if($relative-ieq'.ai'-or$relative.StartsWith('.ai/',[StringComparison]::OrdinalIgnoreCase)){continue}
      $pathField=Encode-StateField $relative;$attributes=[int]$item.Attributes;$isLink=($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0
      if($isLink){$target=if($null-ne$item.LinkTarget){[string]$item.LinkTarget}else{''};$rows.Add("L|$pathField|$attributes|$(Encode-StateField $target)");continue}
      if($item.PSIsContainer){$rows.Add("D|$pathField|$attributes");$stack.Push($item.FullName);continue}
      $hash=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant();$rows.Add("F|$pathField|$attributes|$($item.Length)|$hash")
    }
  }
  Get-TextHash (($rows|Sort-Object)-join"`n")
}
function Invoke-GitProbe([string[]]$GitArguments){
  $output=& git -C $ProjectDir @GitArguments 2>$null;$code=$LASTEXITCODE
  [pscustomobject]@{code=$code;text=(($output|ForEach-Object{[string]$_})-join"`n")}
}
function Get-ProjectStateFingerprint(){
  $treeHash=Get-ProjectTreeHash $ProjectDir;$mode='NON_GIT';$head='N/A';$indexHash='N/A';$submoduleHash='N/A'
  $gitCommand=Get-Command git -ErrorAction SilentlyContinue
  if($gitCommand){
    $inside=Invoke-GitProbe @('rev-parse','--is-inside-work-tree')
    if($inside.code-eq0-and$inside.text.Trim()-eq'true'){
      $mode='GIT';$headProbe=Invoke-GitProbe @('rev-parse','--verify','HEAD');$head=if($headProbe.code-eq0){$headProbe.text.Trim()}else{'UNBORN'}
      $indexProbe=Invoke-GitProbe @('rev-parse','--git-path','index');if($indexProbe.code-ne0){throw 'Unable to resolve Git index for project-state fingerprinting.'}
      $indexPath=$indexProbe.text.Trim();if(-not[IO.Path]::IsPathRooted($indexPath)){$indexPath=[IO.Path]::GetFullPath((Join-Path $ProjectDir $indexPath))}
      $indexHash=if(Test-Path -LiteralPath $indexPath -PathType Leaf){(Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).Hash.ToLowerInvariant()}else{'ABSENT'}
      $submoduleProbe=Invoke-GitProbe @('submodule','status','--recursive');if($submoduleProbe.code-ne0){throw 'Unable to read recursive submodule state for project-state fingerprinting.'};$submoduleHash=Get-TextHash $submoduleProbe.text
    }
  }elseif(Test-GitMetadataAbove $ProjectDir){throw 'Git metadata exists but the git executable is unavailable; project state cannot be fingerprinted safely.'}
  Get-TextHash "PROJECT_STATE_FINGERPRINT_V1`nMODE=$mode`nTREE=$treeHash`nHEAD=$head`nINDEX=$indexHash`nSUBMODULES=$submoduleHash"
}
function Restore-Ai([string]$AiPath,[string]$Backup,[bool]$Existed,[string]$ExpectedHash){
  if(Test-Path -LiteralPath $AiPath){Remove-Item -LiteralPath $AiPath -Recurse -Force}
  if($Existed){Copy-Item -LiteralPath $Backup -Destination $AiPath -Recurse -Force}
  $actual=Get-FileTreeHash $AiPath;if($actual-ne$ExpectedHash){throw "ARCHITECT_FAILOVER_BLOCKED: .ai restore hash mismatch ($actual != $ExpectedHash). HUMAN_RECOVERY_REQUIRED"}
}
function Classify-Failure([string]$Text,[bool]$TimedOut){
  if($TimedOut){return 'BOUNDED_TIMEOUT'}
  $value=$Text.ToLowerInvariant()
  if($value-match'authentication failed|unauthorized|invalid api key|token expired|provider auth'){return 'AUTHENTICATION_FAILED'}
  if($value-match'retired|deprecated|no longer available'){return 'MODEL_RETIRED'}
  if($value-match'model not found|configured model.*not valid|providermodelnotfound|invalid model'){return 'INVALID_MODEL_CONFIGURATION'}
  if($value-match'context.*(too long|overflow|length)|maximum context'){return 'CONTEXT_OVERFLOW'}
  if($value-match'permission denied|tool permission|deniederror'){return 'TOOL_PERMISSION_DENIED'}
  if($value-match'safety refusal|content policy|refused for safety'){return 'SAFETY_REFUSAL'}
  if($value-match'malformed request|invalid request body|bad request'){return 'MALFORMED_REQUEST'}
  if($value-match'quota.*(exhausted|exceeded)|credits.*(exhausted|insufficient)|plan limit'){return 'PLAN_QUOTA_EXHAUSTED'}
  if($value-match'rate.?limit|http\s*429|concurrency limit'){return 'RATE_LIMIT'}
  if($value-match'temporarily unavailable|model overloaded|try again later'){return 'MODEL_TEMPORARILY_UNAVAILABLE'}
  if($value-match'connection refused|unable to connect|network error|http\s*5\d\d|service unavailable|gateway timeout'){return 'PROVIDER_UNAVAILABLE'}
  'UNCLASSIFIED_FAILURE'
}
function Invoke-Route([object]$Route,[int]$Attempt,[string]$LogDir){
  $stdout=Join-Path $LogDir "attempt-$Attempt.stdout.log";$stderr=Join-Path $LogDir "attempt-$Attempt.stderr.log"
  $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$OpenCodeCommand;$info.UseShellExecute=$false;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.CreateNoWindow=$true;$info.Environment['OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE']='1'
  foreach($value in $OpenCodePrefixArguments){$null=$info.ArgumentList.Add($value)}
  foreach($value in @('run','--dir',$ProjectDir,'--agent','architect','--model',[string]$Route.candidate.model)){$null=$info.ArgumentList.Add($value)}
  if(-not[string]::IsNullOrWhiteSpace([string]$Route.candidate.variant)){$null=$info.ArgumentList.Add('--variant');$null=$info.ArgumentList.Add([string]$Route.candidate.variant)}
  foreach($value in @('--command',$Command,'--format','json',$RoutedArguments)){$null=$info.ArgumentList.Add($value)}
  $process=[Diagnostics.Process]::new();$process.StartInfo=$info;if(-not$process.Start()){throw 'Unable to start OpenCode.'}
  $outTask=$process.StandardOutput.ReadToEndAsync();$errTask=$process.StandardError.ReadToEndAsync();$timedOut=-not$process.WaitForExit($TimeoutSeconds*1000)
  if($timedOut){try{$process.Kill($true)}catch{};$process.WaitForExit()}
  $out=$outTask.GetAwaiter().GetResult();$err=$errTask.GetAwaiter().GetResult();[IO.File]::WriteAllText($stdout,$out);[IO.File]::WriteAllText($stderr,$err)
  [pscustomobject]@{exit=$process.ExitCode;timed_out=$timedOut;text=($out+"`n"+$err)}
}
function Candidate-Allowed([object]$Route,[string]$Failure,[string]$FailedFamily,[hashtable]$Attempted){
  if($Attempted.ContainsKey($Route.route)){return $false}
  if($Cooldowns.ContainsKey([string]$Route.candidate.model)-and$Cooldowns[[string]$Route.candidate.model]-gt(Get-Epoch)){return $false}
  $scope=Get-OnlyOn $Route.candidate
  if($scope.Count-gt0-and$Failure-notin$scope){
    $sameLeft=@($Routes|Where-Object{[string]$_.candidate.model_family-eq$FailedFamily-and-not$Attempted.ContainsKey($_.route)})
    if(-not($scope-contains'MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS'-and$sameLeft.Count-eq0)){return $false}
  }
  if($Failure-eq'MODEL_RETIRED'-and[string]$Route.candidate.model_family-eq$FailedFamily){return $false}
  $true
}
function Preserve-LogsOnly([string]$Temp,[string]$Backup){
  if($KeepAttemptLogs){if(Test-Path -LiteralPath $Backup){Remove-Item -LiteralPath $Backup -Recurse -Force}}elseif(Test-Path -LiteralPath $Temp){Remove-Item -LiteralPath $Temp -Recurse -Force}
}

$AiPath=Join-Path $ProjectDir '.ai';$Temp=Join-Path ([IO.Path]::GetTempPath()) ("opencode-governance-"+[guid]::NewGuid().ToString('N'));$Backup=Join-Path $Temp 'ai-snapshot';$Logs=Join-Path $Temp 'logs';New-Item -ItemType Directory -Force -Path $Logs|Out-Null
$AiExisted=Test-Path -LiteralPath $AiPath;if($AiExisted){Copy-Item -LiteralPath $AiPath -Destination $Backup -Recurse -Force};$AiHash=Get-FileTreeHash $AiPath;$ProjectState=Get-ProjectStateFingerprint
$Attempted=@{};$Failure=$null;$FailedFamily=$null;$attempt=0
try{
  while($true){
    $SelectionFailure=if([string]::IsNullOrWhiteSpace([string]$Failure)){'PROVIDER_UNAVAILABLE'}else{[string]$Failure};$SelectionFamily=if([string]::IsNullOrWhiteSpace([string]$FailedFamily)){''}else{[string]$FailedFamily}
    $ordered=@($Routes|Where-Object{Candidate-Allowed $_ $SelectionFailure $SelectionFamily $Attempted}|Sort-Object @{Expression={if($Failure-and[string]$_.candidate.model_family-eq$FailedFamily){0}else{1}}},priority)
    if($ordered.Count-eq0){throw "ARCHITECT_FAILOVER_BLOCKED: no eligible Architect route remains after $Failure. HUMAN_RECOVERY_REQUIRED"}
    $route=$ordered[0];$Attempted[$route.route]=$true;$attempt++;Write-Host "ARCHITECT_ROUTE_ATTEMPT $attempt $($route.route) $($route.candidate.model)"
    $result=Invoke-Route $route $attempt $Logs
    if((Get-ProjectStateFingerprint)-ne$ProjectState){throw 'ARCHITECT_FAILOVER_BLOCKED: PROJECT_STATE_CHANGED: source or project-documentation content changed during a pre-execution command. HUMAN_RECOVERY_REQUIRED'}
    if($result.exit-eq0-and-not$result.timed_out){
      $Cooldowns.Remove([string]$route.candidate.model);Save-Cooldowns $Cooldowns;Write-Host "ARCHITECT_FAILOVER_COMPLETE route=$($route.route) attempts=$attempt ai_tree=$(Get-FileTreeHash $AiPath)";Preserve-LogsOnly $Temp $Backup;exit 0
    }
    $Failure=Classify-Failure $result.text $result.timed_out;$FailedFamily=[string]$route.candidate.model_family;Write-Warning "Architect route failed: $Failure ($($route.route))"
    if($Failure-notin$Eligible){throw "ARCHITECT_FAILOVER_BLOCKED: ineligible failure $Failure. Logs: $Logs"}
    $Cooldowns[[string]$route.candidate.model]=(Get-Epoch)+$DefaultCooldown;Save-Cooldowns $Cooldowns;Restore-Ai $AiPath $Backup $AiExisted $AiHash
  }
}catch{
  try{if((Get-ProjectStateFingerprint)-eq$ProjectState){Restore-Ai $AiPath $Backup $AiExisted $AiHash}}catch{}
  Preserve-LogsOnly $Temp $Backup;Write-Error $_;if($KeepAttemptLogs){Write-Host "ATTEMPT_LOGS $Logs"};exit 1
}
