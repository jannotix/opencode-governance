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
$ProjectDir=(Resolve-Path $ProjectDir).Path
if(-not $ConfigDir){$ConfigDir=if($env:OPENCODE_CONFIG_DIR){$env:OPENCODE_CONFIG_DIR}else{Join-Path $HOME '.config\opencode'}}
if(-not $RoutingConfigPath){$RoutingConfigPath=Join-Path $ConfigDir 'opencode-governance-routing.json'}
if(-not(Test-Path $RoutingConfigPath -PathType Leaf)){throw "Routing profile/manifest not found: $RoutingConfigPath"}
if($TimeoutSeconds -lt 30){throw 'TimeoutSeconds must be at least 30.'}
try{$Routing=Get-Content $RoutingConfigPath -Raw|ConvertFrom-Json}catch{throw 'Routing profile is invalid JSON.'}
if([string]$Routing.schema_version -ne '1.0'){throw 'Routing schema_version must be 1.0.'}
if('architect' -notin @($Routing.settings.enabled_roles)){throw 'Architect failover is not enabled in the routing profile.'}
$Architect=$Routing.roles.architect
if(-not $Architect -or @($Architect.fallbacks).Count -eq 0){throw 'Architect failover requires at least one fallback.'}
$Eligible=@($Routing.settings.eligible_failures)
$DefaultCooldown=[int]$Routing.settings.default_cooldown_seconds
$StatePath=Join-Path $ConfigDir 'opencode-governance-routing-state.tsv'
New-Item -ItemType Directory -Force -Path $ConfigDir|Out-Null
$Marker='[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
$env:OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE='1'
$RoutedArguments=if($Arguments -like "*$Marker*"){$Arguments}elseif([string]::IsNullOrWhiteSpace($Arguments)){$Marker}else{"$Arguments`n`n$Marker"}

function Get-OnlyOn([object]$Candidate){if(-not $Candidate.PSObject.Properties['only_on']){throw 'Every route candidate must define only_on.'};return @($Candidate.only_on|Where-Object{-not[string]::IsNullOrWhiteSpace([string]$_)})}
function Validate-Route([object]$Route,[bool]$Priority){
 if([string]$Route.model -notmatch '^[^/\s]+/\S+$'){throw "Invalid Architect route model: $($Route.model)"}
 if([string]::IsNullOrWhiteSpace([string]$Route.model_family)){throw 'Architect route model_family is required.'}
 if([string]$Route.variant_policy -eq 'highest_supported' -and [string]::IsNullOrWhiteSpace([string]$Route.variant)){throw 'highest_supported must be resolved to a concrete variant before running.'}
 if([string]$Route.variant -eq 'highest_supported'){throw 'highest_supported cannot be used as a literal variant.'}
 Get-OnlyOn $Route|Out-Null
 if($Priority -and [int]$Route.priority -lt 1){throw 'Architect fallback priority must be positive.'}
}
Validate-Route $Architect.primary $false
foreach($r in @($Architect.fallbacks)){Validate-Route $r $true}
$Routes=@([pscustomobject]@{candidate=$Architect.primary;priority=0;route='architect-primary'})+@($Architect.fallbacks|Sort-Object{[int]$_.priority}|ForEach-Object{[pscustomobject]@{candidate=$_;priority=[int]$_.priority;route="architect-fallback-$([int]$_.priority)"}})

function Get-Epoch(){return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}
function Load-Cooldowns(){
 $map=@{};if(Test-Path $StatePath){foreach($line in Get-Content $StatePath){if([string]::IsNullOrWhiteSpace($line)){continue};$p=$line -split "`t",2;if($p.Count -eq 2){$until=0;if([long]::TryParse($p[1],[ref]$until)-and $until -gt(Get-Epoch)){$map[$p[0]]=$until}}}};return $map
}
function Save-Cooldowns([hashtable]$Map){$lines=@();foreach($key in ($Map.Keys|Sort-Object)){$lines+="$key`t$($Map[$key])"};[IO.File]::WriteAllLines($StatePath,$lines,(New-Object Text.UTF8Encoding($false)))}
$Cooldowns=Load-Cooldowns

function Get-TextHash([string]$Text){
 $bytes=[Text.Encoding]::UTF8.GetBytes($Text);$sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Encode-StateField([string]$Value){return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))}
function Get-FileTreeHash([string]$Path){
 if(-not(Test-Path $Path)){return 'ABSENT'}
 $rows=@();foreach($file in Get-ChildItem $Path -File -Recurse|Sort-Object FullName){$rel=[IO.Path]::GetRelativePath($Path,$file.FullName).Replace('\','/');$hash=(Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant();$rows+="$rel`t$hash"}
 return Get-TextHash ($rows -join "`n")
}
function Test-GitMetadataAbove([string]$Path){
 $current=[IO.DirectoryInfo]::new($Path)
 while($null-ne$current){if(Test-Path -LiteralPath (Join-Path $current.FullName '.git')){return $true};$current=$current.Parent}
 return $false
}
function Get-ProjectTreeHash([string]$Root){
 $rows=[Collections.Generic.List[string]]::new();$stack=[Collections.Generic.Stack[string]]::new();$stack.Push($Root)
 while($stack.Count -gt 0){
  $directory=$stack.Pop()
  foreach($item in Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop){
   $rel=[IO.Path]::GetRelativePath($Root,$item.FullName).Replace('\','/')
   if($item.Name -ieq '.git'){continue}
   if($rel -ieq '.ai' -or $rel.StartsWith('.ai/',[StringComparison]::OrdinalIgnoreCase)){continue}
   $pathField=Encode-StateField $rel;$attributes=[int]$item.Attributes;$isLink=($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne 0
   if($isLink){$target=if($null-ne$item.LinkTarget){[string]$item.LinkTarget}else{''};$rows.Add("L|$pathField|$attributes|$(Encode-StateField $target)");continue}
   if($item.PSIsContainer){$rows.Add("D|$pathField|$attributes");$stack.Push($item.FullName);continue}
   $hash=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant();$rows.Add("F|$pathField|$attributes|$($item.Length)|$hash")
  }
 }
 return Get-TextHash (($rows|Sort-Object)-join"`n")
}
function Invoke-GitProbe([string[]]$GitArguments){
 $output=& git -C $ProjectDir @GitArguments 2>$null;$code=$LASTEXITCODE
 return [pscustomobject]@{code=$code;text=(($output|ForEach-Object{[string]$_})-join"`n")}
}
function Get-ProjectStateFingerprint(){
 $treeHash=Get-ProjectTreeHash $ProjectDir;$mode='NON_GIT';$head='N/A';$indexHash='N/A';$submoduleHash='N/A'
 $gitCommand=Get-Command git -ErrorAction SilentlyContinue
 if($gitCommand){
  $inside=Invoke-GitProbe @('rev-parse','--is-inside-work-tree')
  if($inside.code-eq 0 -and $inside.text.Trim()-eq'true'){
   $mode='GIT';$headProbe=Invoke-GitProbe @('rev-parse','--verify','HEAD');$head=if($headProbe.code-eq 0){$headProbe.text.Trim()}else{'UNBORN'}
   $indexProbe=Invoke-GitProbe @('rev-parse','--git-path','index');if($indexProbe.code-ne 0){throw 'Unable to resolve Git index for project-state fingerprinting.'}
   $indexPath=$indexProbe.text.Trim();if(-not[IO.Path]::IsPathRooted($indexPath)){$indexPath=[IO.Path]::GetFullPath((Join-Path $ProjectDir $indexPath))}
   $indexHash=if(Test-Path -LiteralPath $indexPath -PathType Leaf){(Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).Hash.ToLowerInvariant()}else{'ABSENT'}
   $submoduleProbe=Invoke-GitProbe @('submodule','status','--recursive');if($submoduleProbe.code-ne 0){throw 'Unable to read recursive submodule state for project-state fingerprinting.'};$submoduleHash=Get-TextHash $submoduleProbe.text
  }
 }elseif(Test-GitMetadataAbove $ProjectDir){throw 'Git metadata exists but the git executable is unavailable; project state cannot be fingerprinted safely.'}
 $manifest="PROJECT_STATE_FINGERPRINT_V1`nMODE=$mode`nTREE=$treeHash`nHEAD=$head`nINDEX=$indexHash`nSUBMODULES=$submoduleHash"
 return Get-TextHash $manifest
}
function Restore-Ai([string]$AiPath,[string]$Backup,[bool]$Existed,[string]$ExpectedHash){
 if(Test-Path $AiPath){Remove-Item $AiPath -Recurse -Force}
 if($Existed){Copy-Item $Backup $AiPath -Recurse -Force}
 $actual=Get-FileTreeHash $AiPath;if($actual -ne $ExpectedHash){throw "ARCHITECT_FAILOVER_BLOCKED: .ai restore hash mismatch ($actual != $ExpectedHash). HUMAN_RECOVERY_REQUIRED"}
}
function Classify-Failure([string]$Text,[bool]$TimedOut){
 if($TimedOut){return 'BOUNDED_TIMEOUT'}
 $t=$Text.ToLowerInvariant()
 if($t -match 'authentication failed|unauthorized|invalid api key|token expired|provider auth'){return 'AUTHENTICATION_FAILED'}
 if($t -match 'retired|deprecated|no longer available'){return 'MODEL_RETIRED'}
 if($t -match 'model not found|configured model.*not valid|providermodelnotfound|invalid model'){return 'INVALID_MODEL_CONFIGURATION'}
 if($t -match 'context.*(too long|overflow|length)|maximum context'){return 'CONTEXT_OVERFLOW'}
 if($t -match 'permission denied|tool permission|deniederror'){return 'TOOL_PERMISSION_DENIED'}
 if($t -match 'safety refusal|content policy|refused for safety'){return 'SAFETY_REFUSAL'}
 if($t -match 'malformed request|invalid request body|bad request'){return 'MALFORMED_REQUEST'}
 if($t -match 'quota.*(exhausted|exceeded)|credits.*(exhausted|insufficient)|plan limit'){return 'PLAN_QUOTA_EXHAUSTED'}
 if($t -match 'rate.?limit|http\s*429|concurrency limit'){return 'RATE_LIMIT'}
 if($t -match 'temporarily unavailable|model overloaded|try again later'){return 'MODEL_TEMPORARILY_UNAVAILABLE'}
 if($t -match 'connection refused|unable to connect|network error|http\s*5\d\d|service unavailable|gateway timeout'){return 'PROVIDER_UNAVAILABLE'}
 return 'UNCLASSIFIED_FAILURE'
}
function Invoke-Route([object]$Route,[int]$Attempt,[string]$LogDir){
 $stdout=Join-Path $LogDir "attempt-$Attempt.stdout.log";$stderr=Join-Path $LogDir "attempt-$Attempt.stderr.log"
 $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$OpenCodeCommand;$psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.CreateNoWindow=$true
 $psi.Environment['OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE']='1'
 foreach($x in $OpenCodePrefixArguments){$null=$psi.ArgumentList.Add($x)}
 foreach($x in @('run','--dir',$ProjectDir,'--agent','architect','--model',[string]$Route.candidate.model)){ $null=$psi.ArgumentList.Add($x) }
 if(-not[string]::IsNullOrWhiteSpace([string]$Route.candidate.variant)){$null=$psi.ArgumentList.Add('--variant');$null=$psi.ArgumentList.Add([string]$Route.candidate.variant)}
 foreach($x in @('--command',$Command,'--format','json',$RoutedArguments)){$null=$psi.ArgumentList.Add($x)}
 $p=[Diagnostics.Process]::new();$p.StartInfo=$psi;if(-not $p.Start()){throw 'Unable to start OpenCode.'}
 $outTask=$p.StandardOutput.ReadToEndAsync();$errTask=$p.StandardError.ReadToEndAsync();$timedOut=-not $p.WaitForExit($TimeoutSeconds*1000)
 if($timedOut){try{$p.Kill($true)}catch{};$p.WaitForExit()}
 $out=$outTask.GetAwaiter().GetResult();$err=$errTask.GetAwaiter().GetResult();[IO.File]::WriteAllText($stdout,$out);[IO.File]::WriteAllText($stderr,$err)
 return [pscustomobject]@{exit=$p.ExitCode;timed_out=$timedOut;text=($out+"`n"+$err);stdout=$stdout;stderr=$stderr}
}
function Candidate-Allowed([object]$Route,[string]$Failure,[string]$FailedFamily,[hashtable]$Attempted){
 if($Attempted.ContainsKey($Route.route)){return $false}
 if($Cooldowns.ContainsKey([string]$Route.candidate.model)-and $Cooldowns[[string]$Route.candidate.model] -gt(Get-Epoch)){return $false}
 $scope=Get-OnlyOn $Route.candidate
 if($scope.Count -gt 0 -and $Failure -notin $scope){
  $sameLeft=@($Routes|Where-Object{[string]$_.candidate.model_family -eq $FailedFamily -and -not $Attempted.ContainsKey($_.route)})
  if(-not($scope -contains 'MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS' -and $sameLeft.Count -eq 0)){return $false}
 }
 if($Failure -eq 'MODEL_RETIRED' -and [string]$Route.candidate.model_family -eq $FailedFamily){return $false}
 return $true
}

$AiPath=Join-Path $ProjectDir '.ai';$Temp=Join-Path ([IO.Path]::GetTempPath()) ("opencode-governance-"+[guid]::NewGuid().ToString('N'));$Backup=Join-Path $Temp 'ai-snapshot';$Logs=Join-Path $Temp 'logs';New-Item -ItemType Directory -Force -Path $Logs|Out-Null
$AiExisted=Test-Path $AiPath;if($AiExisted){Copy-Item $AiPath $Backup -Recurse -Force};$AiHash=Get-FileTreeHash $AiPath;$ProjectState=Get-ProjectStateFingerprint
$Attempted=@{};$Failure=$null;$FailedFamily=$null;$attempt=0
try{
 while($true){
  $SelectionFailure=if([string]::IsNullOrWhiteSpace([string]$Failure)){'PROVIDER_UNAVAILABLE'}else{[string]$Failure}
  $SelectionFamily=if([string]::IsNullOrWhiteSpace([string]$FailedFamily)){''}else{[string]$FailedFamily}
  $ordered=@($Routes|Where-Object{Candidate-Allowed $_ $SelectionFailure $SelectionFamily $Attempted}|Sort-Object @{Expression={if($Failure -and [string]$_.candidate.model_family -eq $FailedFamily){0}else{1}}},priority)
  if($ordered.Count -eq 0){throw "ARCHITECT_FAILOVER_BLOCKED: no eligible Architect route remains after $Failure. HUMAN_RECOVERY_REQUIRED"}
  $route=$ordered[0];$Attempted[$route.route]=$true;$attempt++
  Write-Host "ARCHITECT_ROUTE_ATTEMPT $attempt $($route.route) $($route.candidate.model)"
  $result=Invoke-Route $route $attempt $Logs
  $afterState=Get-ProjectStateFingerprint
  if($afterState -ne $ProjectState){throw 'ARCHITECT_FAILOVER_BLOCKED: PROJECT_STATE_CHANGED: source or project-documentation content changed during a pre-execution command. HUMAN_RECOVERY_REQUIRED'}
  if($result.exit -eq 0 -and -not $result.timed_out){
   $Cooldowns.Remove([string]$route.candidate.model);Save-Cooldowns $Cooldowns
   Write-Host "ARCHITECT_FAILOVER_COMPLETE route=$($route.route) attempts=$attempt ai_tree=$(Get-FileTreeHash $AiPath)"
   if(-not $KeepAttemptLogs){Remove-Item $Temp -Recurse -Force}
   exit 0
  }
  $Failure=Classify-Failure $result.text $result.timed_out;$FailedFamily=[string]$route.candidate.model_family
  Write-Warning "Architect route failed: $Failure ($($route.route))"
  if($Failure -notin $Eligible){throw "ARCHITECT_FAILOVER_BLOCKED: ineligible failure $Failure. Logs: $Logs"}
  $Cooldowns[[string]$route.candidate.model]=(Get-Epoch)+$DefaultCooldown;Save-Cooldowns $Cooldowns
  Restore-Ai $AiPath $Backup $AiExisted $AiHash
 }
}catch{
 try{if((Get-ProjectStateFingerprint)-eq $ProjectState){Restore-Ai $AiPath $Backup $AiExisted $AiHash}}catch{}
 Write-Error $_
 Write-Host "ATTEMPT_LOGS $Logs"
 exit 1
}
