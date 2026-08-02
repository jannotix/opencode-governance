param(
    [string]$ProjectDir,
    [string]$WorkspaceDir,
    [string]$RepositoryDir,
    [Parameter(Mandatory=$true)][ValidateSet('ai-init','ai-audit','ai-discover','ai-plan','ai-resume')][string]$Command,
    [string]$Arguments = '',
    [string]$ArgumentsFile,
    [string]$TaskId,
    [string]$RoutingConfigPath,
    [string]$ConfigDir,
    [string]$OpenCodeCommand = 'opencode',
    [string[]]$OpenCodePrefixArguments = @(),
    [int]$TimeoutSeconds = 3600,
    [switch]$KeepAttemptLogs,
    [switch]$RecoverTransaction,
    [ValidateSet('validate-governance-only','adopt-governance-only','rollback')]$RecoveryDecision,
    [string]$ExpectedTransactionHash,
    [string]$EvidenceBundlePath,
    [string]$ExpectedEvidenceBundleHash,
    [string]$ExpectedRepositoryHead,
    [string]$ExpectedPlanHash,
    [string]$ExpectedExecutionPacketHash,
    [string]$ExpectedCheckpointHash,
    [string]$ExpectedArgumentsHash,
    [string]$ExpectedStdoutHash,
    [string]$ExpectedStderrHash
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
    [Console]::Error.WriteLine('POWERSHELL_7_REQUIRED: The Architect transactional runner requires PowerShell 7 or newer.')
    exit 64
}

$ErrorActionPreference='Stop'
# WORKSPACE_REPOSITORY_ROOT_CONTRACT_V1: -ProjectDir remains a compatibility alias for workspace root.
if([string]::IsNullOrWhiteSpace($WorkspaceDir)){$WorkspaceDir=$ProjectDir}
if([string]::IsNullOrWhiteSpace($WorkspaceDir)){throw 'WORKSPACE_ROOT_REQUIRED: Provide -WorkspaceDir or -ProjectDir.'}
if(-not(Test-Path -LiteralPath $WorkspaceDir -PathType Container)){throw 'Project directory does not exist.'}
$WorkspaceDir=(Resolve-Path -LiteralPath $WorkspaceDir).Path
$ProjectDir=$WorkspaceDir
if(-not $ConfigDir){$ConfigDir=if($env:OPENCODE_CONFIG_DIR){$env:OPENCODE_CONFIG_DIR}else{Join-Path $HOME '.config/opencode'}}
if(-not $RoutingConfigPath){$RoutingConfigPath=Join-Path $ConfigDir 'opencode-governance-routing.json'}
if(-not(Test-Path -LiteralPath $RoutingConfigPath -PathType Leaf)){throw "Routing profile/manifest not found: $RoutingConfigPath"}
if($TimeoutSeconds -lt 30){throw 'TimeoutSeconds must be at least 30.'}
$script:WorkspaceRootContract='WORKSPACE_REPOSITORY_ROOT_CONTRACT_V1'
$script:MultiGovernanceTx='MULTI_GOVERNANCE_ROOT_TRANSACTION_V1'
$script:ChangesetDiagnostic='PROJECT_STATE_CHANGESET_DIAGNOSTIC_V1'
# Capture explicit -RepositoryDir before any later script-scope assignment reuses the name.
$script:ExplicitRepositoryDir = $RepositoryDir
$script:ManagedGovernanceRoots=@()
$script:ManagedRootRecords=@()
$script:FingerprintManifestBefore=@()

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
function Assert-SafeDirectory([string]$Path,[string]$Label){
  if(-not(Test-Path -LiteralPath $Path -PathType Container)){throw "$Label not found: $Path"}
  $item=Get-Item -LiteralPath $Path -Force
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne0){throw "$Label may not be a symlink, junction or reparse point: $Path"}
}
function Test-RecognizedGovernanceRoot([string]$AiPath){
  if(-not(Test-Path -LiteralPath $AiPath -PathType Container)){return $false}
  foreach($name in @('STATUS.md','PROJECT_HISTORY.md','RUN_STATE.json','tasks','product','CONTEXT_INDEX.md','INSTRUCTION_INDEX.md','GOVERNANCE_MEMORY.md')){
    if(Test-Path -LiteralPath (Join-Path $AiPath $name)){return $true}
  }
  $false
}
function Test-IsGitWorktree([string]$Path){
  $git=Get-Command git -ErrorAction SilentlyContinue
  if(-not$git){return $false}
  $output=& git -C $Path rev-parse --is-inside-work-tree 2>$null
  $LASTEXITCODE-eq0 -and ([string]$output).Trim()-eq'true'
}
function Find-NestedGitRoots([string]$Workspace){
  $found=[System.Collections.Generic.List[string]]::new()
  $stack=[Collections.Generic.Stack[object]]::new();$stack.Push([pscustomobject]@{Path=$Workspace;Depth=0})
  $skipNames=@('.git','.ai','node_modules','vendor','.venv','dist','build')
  while($stack.Count){
    $frame=$stack.Pop()
    if($frame.Depth -gt 6){continue}
    try{
      foreach($item in Get-ChildItem -LiteralPath $frame.Path -Force -ErrorAction Stop){
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
        if($item.Name -ieq '.git'){
          if($frame.Path -ne $Workspace -and (Test-IsGitWorktree $frame.Path)){
            $resolved=(Resolve-Path -LiteralPath $frame.Path).Path
            if($resolved -notin $found){$found.Add($resolved)}
          }
          continue
        }
        if(-not $item.PSIsContainer){continue}
        if($item.Name -in $skipNames){continue}
        $gitMarker=Join-Path $item.FullName '.git'
        if(Test-Path -LiteralPath $gitMarker){
          if(Test-IsGitWorktree $item.FullName){
            $resolved=(Resolve-Path -LiteralPath $item.FullName).Path
            if($resolved -notin $found){$found.Add($resolved)}
          }
          continue
        }
        $stack.Push([pscustomobject]@{Path=$item.FullName;Depth=($frame.Depth+1)})
      }
    }catch{}
  }
  @($found | Sort-Object)
}
function Resolve-WorkspaceRepositoryRoots(){
  # WORKSPACE_REPOSITORY_ROOT_CONTRACT_V1
  Assert-SafeDirectory $WorkspaceDir 'workspace_root'
  $workspace=(Resolve-Path -LiteralPath $WorkspaceDir).Path
  $repository=$null
  $source=''
  $explicitRepo = if(-not [string]::IsNullOrWhiteSpace($script:ExplicitRepositoryDir)){$script:ExplicitRepositoryDir}elseif(-not [string]::IsNullOrWhiteSpace($RepositoryDir)){$RepositoryDir}else{''}
  if(-not [string]::IsNullOrWhiteSpace($explicitRepo)){
    if(-not(Test-Path -LiteralPath $explicitRepo -PathType Container)){throw "REPOSITORY_ROOT_NOT_FOUND: $explicitRepo"}
    Assert-SafeDirectory $explicitRepo 'repository_root'
    $repository=(Resolve-Path -LiteralPath $explicitRepo).Path
    $source='explicit_repository_dir'
  }else{
    if(Test-IsGitWorktree $workspace){
      $top=& git -C $workspace rev-parse --show-toplevel 2>$null
      if($LASTEXITCODE-eq0 -and -not [string]::IsNullOrWhiteSpace([string]$top)){$repository=(Resolve-Path -LiteralPath ([string]$top).Trim()).Path}
      else{$repository=$workspace}
      $source='workspace_is_git'
    }else{
      $nested=@(Find-NestedGitRoots $workspace)
      if($nested.Count -gt 1){throw "REPOSITORY_ROOT_AMBIGUOUS: $($nested -join '; ')"}
      if($nested.Count -eq 1){
        $repository=$nested[0]
        $source='unique_nested_git'
      }else{
        # NON_GIT_PROJECT_SUPPORTED: workspace is the application root when no Git repository exists.
        $repository=$workspace
        $source='workspace_non_git'
      }
    }
  }
  $workspaceFull=[IO.Path]::GetFullPath($workspace)
  $repositoryFull=[IO.Path]::GetFullPath($repository)
  if(-not ($repositoryFull.Equals($workspaceFull,[StringComparison]::OrdinalIgnoreCase) -or $repositoryFull.StartsWith($workspaceFull.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){
    throw "REPOSITORY_ROOT_OUTSIDE_WORKSPACE: repository=$repositoryFull workspace=$workspaceFull"
  }
  # Bind exact canonical Governance roots the runner owns (even if not yet created).
  # Unrelated nested .ai directories elsewhere remain inside the project fingerprint.
  # Fail closed if an existing .ai is a symlink/junction/reparse or resolves outside the workspace.
  function Bind-ManagedAiRoot([string]$AiPath,[string]$Role,[string]$WorkspaceFull){
    $literal=[IO.Path]::GetFullPath($AiPath)
    if(Test-Path -LiteralPath $AiPath){
      $item=Get-Item -LiteralPath $AiPath -Force
      if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne0){
        throw "MANAGED_GOVERNANCE_ROOT_REPARSE_FORBIDDEN: $AiPath may not be a symlink, junction or reparse point."
      }
      if(-not $item.PSIsContainer){throw "MANAGED_GOVERNANCE_ROOT_NOT_DIRECTORY: $AiPath"}
      # Identity for snapshot/restore is the literal path under the workspace, never a followed outside target.
      $resolved=(Resolve-Path -LiteralPath $AiPath).Path
      if(-not ($resolved.Equals($literal,[StringComparison]::OrdinalIgnoreCase))){
        # Resolve-Path followed a reparse that Get-Item missed — still fail closed if target left workspace.
        if(-not ($resolved.Equals($WorkspaceFull,[StringComparison]::OrdinalIgnoreCase) -or $resolved.StartsWith($WorkspaceFull.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){
          throw "MANAGED_GOVERNANCE_ROOT_OUTSIDE_WORKSPACE: $AiPath -> $resolved"
        }
      }
      if(-not ($literal.Equals($WorkspaceFull,[StringComparison]::OrdinalIgnoreCase) -or $literal.StartsWith($WorkspaceFull.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){
        throw "MANAGED_GOVERNANCE_ROOT_OUTSIDE_WORKSPACE: $literal"
      }
    }else{
      if(-not ($literal.Equals($WorkspaceFull,[StringComparison]::OrdinalIgnoreCase) -or $literal.StartsWith($WorkspaceFull.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){
        throw "MANAGED_GOVERNANCE_ROOT_OUTSIDE_WORKSPACE: $literal"
      }
    }
    [pscustomobject]@{canonical_path=$literal;role=$Role;recognized=(Test-RecognizedGovernanceRoot $AiPath)}
  }
  $managed=[System.Collections.Generic.List[object]]::new()
  $wsAi=Join-Path $workspace '.ai'
  $repoAi=Join-Path $repository '.ai'
  $managed.Add((Bind-ManagedAiRoot $wsAi 'workspace_governance' $workspaceFull))
  if(-not $repositoryFull.Equals($workspaceFull,[StringComparison]::OrdinalIgnoreCase)){
    $managed.Add((Bind-ManagedAiRoot $repoAi 'repository_governance' $workspaceFull))
  }
  $script:RepositoryDir=$repository
  $script:ManagedGovernanceRoots=@($managed)
  $script:WorkspaceDir=$workspace
  Write-Host "WORKSPACE_REPOSITORY_ROOT_CONTRACT contract=$($script:WorkspaceRootContract) workspace=$workspace repository=$repository source=$source managed_roots=$($managed.Count)"
  [pscustomobject]@{workspace=$workspace;repository=$repository;source=$source;managed=@($managed)}
}
# Resolve roots before task discovery so nested repository .ai/** is visible.
$null=Resolve-WorkspaceRepositoryRoots
$ProjectDir=$script:WorkspaceDir
$WorkspaceDir=$script:WorkspaceDir

# JSONC normalization (in-memory only; never mutates the installed routing source).
function Remove-JsoncComments([string]$Text){
  $builder=[Text.StringBuilder]::new();$index=0;$inString=$false;$escaped=$false;$lineComment=$false;$blockComment=$false
  while($index-lt$Text.Length){
    $char=$Text[$index];$next=if($index+1-lt$Text.Length){$Text[$index+1]}else{[char]0}
    if($lineComment){if($char-eq"`r"-or$char-eq"`n"){$lineComment=$false;$null=$builder.Append($char)};$index++;continue}
    if($blockComment){if($char-eq'*'-and$next-eq'/'){$blockComment=$false;$index+=2;continue};if($char-eq"`r"-or$char-eq"`n"){$null=$builder.Append($char)};$index++;continue}
    if($inString){
      $null=$builder.Append($char)
      if($escaped){$escaped=$false}elseif($char-eq'\'){$escaped=$true}elseif($char-eq'"'){$inString=$false}
      $index++;continue
    }
    if($char-eq'"'){$inString=$true;$null=$builder.Append($char);$index++;continue}
    if($char-eq'/'-and$next-eq'/'){$lineComment=$true;$index+=2;continue}
    if($char-eq'/'-and$next-eq'*'){$blockComment=$true;$index+=2;continue}
    $null=$builder.Append($char);$index++
  }
  if($inString-or$blockComment){throw 'ROUTING_JSONC_INVALID: unterminated string or block comment.'}
  $builder.ToString()
}
function Remove-TrailingCommas([string]$Text){
  $builder=[Text.StringBuilder]::new();$index=0;$inString=$false;$escaped=$false
  while($index-lt$Text.Length){
    $char=$Text[$index]
    if($inString){
      $null=$builder.Append($char)
      if($escaped){$escaped=$false}elseif($char-eq'\'){$escaped=$true}elseif($char-eq'"'){$inString=$false}
      $index++;continue
    }
    if($char-eq'"'){$inString=$true;$null=$builder.Append($char);$index++;continue}
    if($char-eq','){
      $lookahead=$index+1
      while($lookahead-lt$Text.Length-and[char]::IsWhiteSpace($Text[$lookahead])){$lookahead++}
      if($lookahead-lt$Text.Length-and($Text[$lookahead]-eq'}'-or$Text[$lookahead]-eq']')){$index++;continue}
    }
    $null=$builder.Append($char);$index++
  }
  $builder.ToString()
}
function Read-RoutingProfile([string]$Path){
  Assert-SafeLeaf $Path 'Routing profile'
  $raw=[IO.File]::ReadAllText($Path)
  $sourceHash=Get-TextHash $raw
  try{
    $clean=Remove-TrailingCommas (Remove-JsoncComments $raw)
    $obj=$clean|ConvertFrom-Json
  }catch{throw "Routing profile is invalid JSON/JSONC: $($_.Exception.Message)"}
  if($null-eq$obj){throw 'Routing profile is invalid JSON/JSONC.'}
  $semantic=Get-TextHash (($obj|ConvertTo-Json -Depth 50 -Compress))
  Write-Host "ROUTING_MANIFEST_HASHES source_sha256=$sourceHash semantic_sha256=$semantic"
  $obj
}

if($ArgumentsFile){
  Assert-SafeLeaf $ArgumentsFile 'Arguments file'
  $ArgumentsFile=(Resolve-Path -LiteralPath $ArgumentsFile).Path
  $Arguments=[IO.File]::ReadAllText($ArgumentsFile,[Text.Encoding]::UTF8)
}
$ArgumentsHash=Get-TextHash $Arguments
$Marker='[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
$env:OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE='1'
$script:PromptTransportContract='ARCHITECT_STDIN_PROMPT_TRANSPORT_V1'
# Use Contains (not -like): the marker includes '[' which is a wildcard metacharacter for -like.
$RoutedArguments=if($Arguments.Contains($Marker)){$Arguments}elseif([string]::IsNullOrWhiteSpace($Arguments)){$Marker}else{"$Arguments`n`n$Marker"}
# Exact stdin payload metrics (authoritative arguments_sha256 remains the pre-marker hash).
$script:PromptUtf8Bytes=[Text.Encoding]::UTF8.GetByteCount($RoutedArguments)
$script:PromptTransportSha256=Get-TextHash $RoutedArguments
$script:PromptMaxBytes=67108864L
$envMax=$env:OPENCODE_GOVERNANCE_PROMPT_MAX_BYTES
if(-not [string]::IsNullOrWhiteSpace($envMax)){
  $parsed=0L
  if([long]::TryParse($envMax,[ref]$parsed) -and $parsed -ge 1048576L){ $script:PromptMaxBytes=$parsed }
}
if($script:PromptUtf8Bytes -gt $script:PromptMaxBytes){
  throw "ARCHITECT_PROMPT_SIZE_LIMIT_EXCEEDED: prompt_bytes=$($script:PromptUtf8Bytes) max_bytes=$($script:PromptMaxBytes) sha256=$($script:PromptTransportSha256) contract=$($script:PromptTransportContract)"
}

function Get-TaskStateSearchRoots(){
  $roots=[System.Collections.Generic.List[string]]::new()
  $roots.Add($ProjectDir)
  if($script:RepositoryDir -and $script:RepositoryDir -ne $ProjectDir){$roots.Add($script:RepositoryDir)}
  @($roots)
}
function Find-TaskStatePath([string]$Id){
  foreach($root in Get-TaskStateSearchRoots){
    $candidate=Join-Path $root ".ai/tasks/$Id/RUN_STATE.json"
    if(Test-Path -LiteralPath $candidate -PathType Leaf){return $candidate}
  }
  $null
}
if($Command -eq 'ai-resume') {
  if([string]::IsNullOrWhiteSpace($TaskId)) {
    $match = [regex]::Match($Arguments, '(?m)^\s*([A-Za-z0-9][A-Za-z0-9._-]{2,})\b')
    if($match.Success) {
      $candidate = $match.Groups[1].Value
      if(Find-TaskStatePath $candidate) { $TaskId = $candidate }
    }
  }
  if([string]::IsNullOrWhiteSpace($TaskId)) {
    $states = [System.Collections.Generic.List[string]]::new()
    foreach($root in Get-TaskStateSearchRoots){
      $taskRoot = Join-Path $root '.ai/tasks'
      if(Test-Path -LiteralPath $taskRoot -PathType Container) {
        Get-ChildItem -LiteralPath $taskRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
          $statePath = Join-Path $_.FullName 'RUN_STATE.json'
          if(Test-Path -LiteralPath $statePath -PathType Leaf) { $states.Add($statePath) }
        }
      }
    }
    if($states.Count -eq 1) { $TaskId = Split-Path -Leaf (Split-Path -Parent $states[0]) }
  }
  if([string]::IsNullOrWhiteSpace($TaskId)) { throw 'RESUME_TASK_ID_REQUIRED: ai-resume requires -TaskId when more than one task checkpoint exists.' }
  if($TaskId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]+$') { throw 'RESUME_TASK_ID_INVALID' }
}

$Routing=Read-RoutingProfile $RoutingConfigPath
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
  if($null-eq$OpenCodePrefixArguments){throw 'OPENCODE_PREFIX_MALFORMED: OpenCodePrefixArguments must be a string array.'}
  if($OpenCodePrefixArguments -is [string]){throw 'OPENCODE_PREFIX_MALFORMED: OpenCodePrefixArguments must not be a scalar string; pass a string array.'}
  $prefix=@($OpenCodePrefixArguments|ForEach-Object{[string]$_})
  $explicit=([string]$OpenCodeCommand).Trim()
  if([string]::IsNullOrWhiteSpace($explicit)){throw 'OPENCODE_CLI_NOT_FOUND: empty OpenCodeCommand.'}
  $launcherPath=$null
  $launcherType='unknown'
  $hostExe=$null
  if($explicit -eq 'opencode'){
    $discovered=[System.Collections.Generic.List[string]]::new()
    $resolved=@(Get-Command opencode -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
    foreach($item in $resolved){if($item -and (Test-Path -LiteralPath $item -PathType Leaf) -and -not $discovered.Contains($item)){$discovered.Add($item)}}
    foreach($candidate in @(
      "$env:USERPROFILE\.opencode\bin\opencode.exe",
      "$env:LOCALAPPDATA\Microsoft\WinGet\Links\opencode.exe",
      "$env:APPDATA\npm\opencode.ps1",
      "$env:APPDATA\npm\opencode.cmd",
      "$env:USERPROFILE\scoop\shims\opencode.exe",
      "$env:USERPROFILE\scoop\shims\opencode.cmd",
      'C:\ProgramData\chocolatey\bin\opencode.exe'
    )){
      if($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf) -and -not $discovered.Contains($candidate)){$discovered.Add($candidate)}
    }
    if($discovered.Count -eq 0){throw 'OPENCODE_CLI_NOT_FOUND'}
    if($discovered.Count -gt 1){Write-Host "OPENCODE_CLI_CANDIDATES count=$($discovered.Count) selected_index=0"}
    $launcherPath=[string]$discovered[0]
  }else{
    if($explicit -match '[\r\n]'){throw 'OPENCODE_CLI_NOT_FOUND: multi-line OpenCodeCommand is not allowed.'}
    if(Test-Path -LiteralPath $explicit -PathType Leaf){$launcherPath=(Resolve-Path -LiteralPath $explicit).Path}
    else{
      $found=Get-Command $explicit -ErrorAction SilentlyContinue | Select-Object -First 1
      if($found -and $found.Source){$launcherPath=[string]$found.Source}
      else{throw "OPENCODE_CLI_NOT_FOUND: $explicit"}
    }
  }
  if($launcherPath -is [array]){throw 'OPENCODE_CLI_AMBIGUOUS: launcher resolved to multiple paths.'}
  $launcherPath=[string]$launcherPath
  if([string]::IsNullOrWhiteSpace($launcherPath)){throw 'OPENCODE_CLI_NOT_FOUND'}
  if($launcherPath -match '\.ps1$'){
    $launcherType='npm-ps1'
    $hostExe=(Get-Command pwsh -ErrorAction Stop).Source
    $prefix=@('-NoProfile','-File',$launcherPath)+$prefix
  }elseif($launcherPath -match '\.(cmd|bat)$'){
    $launcherType='npm-cmd'
    $hostExe=$env:ComSpec
    if([string]::IsNullOrWhiteSpace($hostExe)){throw 'OPENCODE_CLI_NOT_FOUND: ComSpec missing for .cmd launcher.'}
    $prefix=@('/d','/s','/c',$launcherPath)+$prefix
  }else{
    $launcherType=if($launcherPath -match '\.exe$'){'exe'}else{'unix-or-other'}
    $hostExe=$launcherPath
    $launcherPath=$hostExe
  }
  [pscustomobject]@{
    host=$hostExe
    launcher=$launcherPath
    launcher_type=$launcherType
    prefix=@($prefix)
    command=$hostExe
  }
}
$Launch=Resolve-OpenCodeLaunch
Write-Host "OPENCODE_CLI_RESOLVED host=$($Launch.host) launcher_type=$($Launch.launcher_type) launcher=$($Launch.launcher) prefix_count=$(@($Launch.prefix).Count)"

# ARCHITECT_HEADLESS_PERMISSION_CONTRACT_V1 — temporary OPENCODE_CONFIG_CONTENT overlay (deny-by-default bash).
# Canonical builder: architect-headless-contract.py (installed next to this runner).
$script:HeadlessContractVersion='ARCHITECT_HEADLESS_PERMISSION_CONTRACT_V1'
$script:HeadlessPolicyHash=$null
$script:HeadlessConfigContent=$null
function Resolve-HeadlessContractPath(){
  $candidates=@(
    (Join-Path $PSScriptRoot 'architect-headless-contract.py'),
    (Join-Path (Split-Path -Parent $PSCommandPath) 'architect-headless-contract.py'),
    (Join-Path $ConfigDir 'opencode-governance-tools/architect-headless-contract.py')
  )
  foreach($path in $candidates){if($path-and(Test-Path -LiteralPath $path -PathType Leaf)){return $path}}
  throw 'HEADLESS_CONTRACT_MISSING: architect-headless-contract.py is not installed next to the Architect runner.'
}
function New-HeadlessPermissionOverlay([string]$Model,[string]$Variant,[string[]]$ExternalRoots){
  $contract=Resolve-HeadlessContractPath
  $py=Get-Command python -ErrorAction SilentlyContinue
  if(-not$py){$py=Get-Command python3 -ErrorAction SilentlyContinue}
  if(-not$py){throw 'HEADLESS_CONTRACT_PYTHON_MISSING: python is required to emit the headless permission overlay.'}
  $args=@($contract,'emit-config')
  if(-not[string]::IsNullOrWhiteSpace($Model)){$args+='--model';$args+=$Model}
  if(-not[string]::IsNullOrWhiteSpace($Variant)){$args+='--variant';$args+=$Variant}
  foreach($root in @($ExternalRoots|Where-Object{$_})){$args+=[string]$root}
  $stderrFile=Join-Path ([IO.Path]::GetTempPath()) ("headless-policy-"+[guid]::NewGuid().ToString('N')+".err")
  try{
    $json=& $py.Source @args 2>$stderrFile
    if($LASTEXITCODE-ne0){throw "HEADLESS_CONTRACT_EMIT_FAILED: exit $LASTEXITCODE"}
    $json=(($json|ForEach-Object{[string]$_})-join'').Trim()
    if([string]::IsNullOrWhiteSpace($json)-or-not$json.StartsWith('{')){throw 'HEADLESS_CONTRACT_EMIT_FAILED: empty or non-JSON overlay.'}
    $hash=Get-TextHash $json
    if(Test-Path -LiteralPath $stderrFile -PathType Leaf){
      $errText=(Get-Content -LiteralPath $stderrFile -Raw).Trim()
      if($errText-match'^[a-f0-9]{64}$'){$hash=$errText.ToLowerInvariant()}
    }
    [pscustomobject]@{json=$json;sha256=$hash;version=$script:HeadlessContractVersion}
  }finally{Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue}
}
function Test-PermissionBlocked([string]$Text){
  $value=$Text.ToLowerInvariant()
  ($value -match 'permission requested') -or ($value -match 'auto-rejecting') -or ($value -match 'the user rejected permission') -or ($value -match 'user rejected permission to use this specific tool call')
}
function Get-DeniedToolName([string]$Text){
  $m=[regex]::Match($Text,'permission requested:\s*([A-Za-z0-9_-]+)',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if($m.Success){return $m.Groups[1].Value.ToLowerInvariant()}
  if($Text -match '(?i)\bbash\b'){return 'bash'}
  'unknown'
}
function New-PermissionBlockedError([string]$Text,[string]$Route,[int]$Attempt,[string]$Logs){
  $tool=Get-DeniedToolName $Text
  "ARCHITECT_PERMISSION_BLOCKED: HEADLESS_PERMISSION_CONTRACT_VIOLATION denied_tool=$tool command_class=sanitized route=$Route attempt=$Attempt permission_contract=$($script:HeadlessContractVersion) logs=$Logs"
}

$StatePath=Join-Path $ConfigDir 'opencode-governance-routing-state.tsv'
New-Item -ItemType Directory -Force -Path $ConfigDir|Out-Null
function Get-Epoch(){[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}
function Load-Cooldowns(){
  $map=@{};if(Test-Path -LiteralPath $StatePath -PathType Leaf){foreach($line in Get-Content -LiteralPath $StatePath){if([string]::IsNullOrWhiteSpace($line)){continue};$parts=$line-split"`t",2;$until=0L;if($parts.Count-eq2-and[long]::TryParse($parts[1],[ref]$until)-and$until-gt(Get-Epoch)){$map[$parts[0]]=$until}}};$map
}
function Save-Cooldowns([hashtable]$Map){$lines=@();foreach($key in ($Map.Keys | Sort-Object)){$lines+="$key`t$($Map[$key])"};$tmp="$StatePath.tmp.$PID";[IO.File]::WriteAllLines($tmp,$lines,(New-Object Text.UTF8Encoding($false)));Move-Item -LiteralPath $tmp -Destination $StatePath -Force}
$Cooldowns=Load-Cooldowns

function Get-FileTreeHash([string]$Path){
  if(-not(Test-Path -LiteralPath $Path)){return 'ABSENT'}
  $rows=@();foreach($item in Get-ChildItem -LiteralPath $Path -Force -Recurse|Sort-Object FullName){$relative=[IO.Path]::GetRelativePath($Path,$item.FullName).Replace('\','/');if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){$rows+="$relative`tSYMLINK:$($item.Target -join ';')";continue};if(-not$item.PSIsContainer){$rows+="$relative`t$((Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant())"}};Get-TextHash($rows-join"`n")
}
function Encode-StateField([string]$Value){[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))}
function Get-ManagedRelativePrefixes([string]$Root){
  # Exact managed Governance roots only (workspace .ai + repository .ai when nested).
  $set=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  [void]$set.Add('.ai')
  if($script:RepositoryDir -and -not [string]::Equals($script:RepositoryDir,$Root,[StringComparison]::OrdinalIgnoreCase)){
    try{
      $repoRel=[IO.Path]::GetRelativePath($Root,$script:RepositoryDir).Replace('\','/').TrimEnd('/')
      if($repoRel -and $repoRel -ne '.' -and -not $repoRel.StartsWith('..')){
        [void]$set.Add("$repoRel/.ai")
      }
    }catch{}
  }
  foreach($m in @($script:ManagedGovernanceRoots)){
    $path=[string]$m.canonical_path
    if([string]::IsNullOrWhiteSpace($path)){continue}
    try{
      $full=[IO.Path]::GetFullPath($path)
      $rootFull=[IO.Path]::GetFullPath($Root)
      $rel=[IO.Path]::GetRelativePath($rootFull,$full).Replace('\','/').TrimEnd('/')
      if(-not $rel -or $rel -eq '.' -or $rel.StartsWith('..')){continue}
      [void]$set.Add($rel)
    }catch{}
  }
  @($set)
}
function Normalize-RelativePath([string]$Relative){
  # Do not use TrimStart('./') — .NET TrimStart treats the argument as a char set and would turn ".ai" into "ai".
  $norm=$Relative.Replace('\','/')
  while($norm.StartsWith('./')){ $norm=$norm.Substring(2) }
  $norm.TrimStart('/')
}
function Test-IsManagedRelative([string]$Relative,[string[]]$Prefixes){
  $norm=Normalize-RelativePath $Relative
  if($norm -eq '.git' -or $norm.StartsWith('.git/',[StringComparison]::OrdinalIgnoreCase) -or $norm.Contains('/.git/')){return $true}
  foreach($p in @($Prefixes)){
    if([string]::IsNullOrWhiteSpace($p)){continue}
    $pref=Normalize-RelativePath $p
    if($norm.Equals($pref,[StringComparison]::OrdinalIgnoreCase)){return $true}
    if($norm.StartsWith("$pref/",[StringComparison]::OrdinalIgnoreCase)){return $true}
  }
  $false
}
function Get-ProjectTreeManifest([string]$Root){
  # Root-aware fingerprint rows; excludes .git/** and exact managed Governance roots only.
  $rows=[Collections.Generic.List[string]]::new();$stack=[Collections.Generic.Stack[string]]::new();$stack.Push($Root)
  $prefixes=@(Get-ManagedRelativePrefixes $Root)
  while($stack.Count){
    $directory=$stack.Pop()
    foreach($item in Get-ChildItem -LiteralPath $directory -Force -ErrorAction SilentlyContinue){
      $relative=[IO.Path]::GetRelativePath($Root,$item.FullName).Replace('\','/')
      if($item.Name-ieq'.git'){continue}
      if(Test-IsManagedRelative $relative $prefixes){continue}
      $p=Encode-StateField $relative;$a=[int]$item.Attributes
      if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){$rows.Add("L|$p|$a|$(Encode-StateField ([string]$item.LinkTarget))");continue}
      if($item.PSIsContainer){$rows.Add("D|$p|$a");$stack.Push($item.FullName);continue}
      $rows.Add("F|$p|$a|$($item.Length)|$((Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant())")
    }
  }
  @($rows|Sort-Object)
}
function Get-ProjectTreeHash([string]$Root){
  Get-TextHash((Get-ProjectTreeManifest $Root)-join"`n")
}
function Invoke-GitProbe([string[]]$GitArguments){
  $repo=if($script:RepositoryDir){$script:RepositoryDir}else{$ProjectDir}
  $output=& git -C $repo @GitArguments 2>$null
  [pscustomobject]@{code=$LASTEXITCODE;text=(($output|ForEach-Object{[string]$_})-join"`n")}
}
function Get-ProjectStateFingerprintCore(){
  # Core PROJECT_STATE_FINGERPRINT_V1 fields (compatible with 3.7.4 journals for orphan recovery).
  $tree=Get-ProjectTreeHash $ProjectDir;$mode='NON_GIT';$head='N/A';$index='N/A';$subs='N/A';$git=Get-Command git -ErrorAction SilentlyContinue
  $repo=if($script:RepositoryDir){$script:RepositoryDir}else{$ProjectDir}
  if($git -and (Test-IsGitWorktree $repo)){
    $mode='GIT'
    $h=Invoke-GitProbe @('rev-parse','--verify','HEAD');$head=if($h.code-eq0){$h.text.Trim()}else{'UNBORN'}
    $i=Invoke-GitProbe @('rev-parse','--git-path','index');if($i.code-ne0){throw 'Unable to resolve Git index.'}
    $ip=$i.text.Trim();if(-not[IO.Path]::IsPathRooted($ip)){$ip=[IO.Path]::GetFullPath((Join-Path $repo $ip))}
    $index=if(Test-Path $ip){Get-FileHashHex $ip}else{'ABSENT'}
    $s=Invoke-GitProbe @('submodule','status','--recursive');if($s.code-ne0){throw 'Unable to read submodule state.'};$subs=Get-TextHash $s.text
  }
  [pscustomobject]@{tree=$tree;mode=$mode;head=$head;index=$index;subs=$subs;repo=$repo}
}
function Get-ProjectStateFingerprint([switch]$Legacy){
  # NON_GIT_PROJECT_SUPPORTED + PROJECT_STATE_FINGERPRINT_V1 with multi-root exclusions
  $core=Get-ProjectStateFingerprintCore
  $base="PROJECT_STATE_FINGERPRINT_V1`nMODE=$($core.mode)`nTREE=$($core.tree)`nHEAD=$($core.head)`nINDEX=$($core.index)`nSUBMODULES=$($core.subs)"
  if($Legacy){ return (Get-TextHash $base) }
  $managedKeys=((@($script:ManagedGovernanceRoots)|ForEach-Object{[string]$_.canonical_path.ToLowerInvariant()})|Sort-Object)-join','
  Get-TextHash "$base`nWORKSPACE=$($ProjectDir.ToLowerInvariant())`nREPOSITORY=$($core.repo.ToLowerInvariant())`nMANAGED=$managedKeys"
}
function Get-PathClass([string]$Relative,[string[]]$Prefixes){
  $norm=Normalize-RelativePath $Relative
  if(Test-IsManagedRelative $norm $Prefixes){
    return 'GOVERNANCE_ONLY_CHANGE'
  }
  if($norm -eq '.git' -or $norm.StartsWith('.git/') -or $norm.Contains('/.git/')){return 'GIT_METADATA_CHANGE'}
  $base=[IO.Path]::GetFileName($norm)
  if($base -in @('package.json','package-lock.json','pnpm-lock.yaml','yarn.lock','composer.json','composer.lock','requirements.txt','pyproject.toml','go.mod','Cargo.toml','Gemfile','pom.xml')){return 'DEPENDENCY_CHANGE'}
  foreach($hint in @('node_modules/','vendor/','dist/','build/','__pycache__/')){if($norm.StartsWith($hint) -or $norm.Contains("/$hint")){return 'GENERATED_ARTIFACT_CHANGE'}}
  if($norm -match '\.(php|py|ts|tsx|js|jsx|go|rs|java|cs|c|cpp|h|rb)$'){return 'APPLICATION_SOURCE_CHANGE'}
  foreach($seg in @('src','app','lib','Source_Code','source')){if($norm -eq $seg -or $norm.StartsWith("$seg/") -or $norm.Contains("/$seg/")){return 'APPLICATION_SOURCE_CHANGE'}}
  'UNKNOWN_CHANGE'
}
function Get-ProjectStateChangesetDiagnostic([string[]]$BeforeRows,[string[]]$AfterRows){
  # PROJECT_STATE_CHANGESET_DIAGNOSTIC_V1
  $prefixes=@(Get-ManagedRelativePrefixes $ProjectDir)
  function Parse-Rows([string[]]$Rows){
    $map=@{}
    foreach($row in $Rows){
      $parts=$row -split '\|',3
      if($parts.Count -lt 2){continue}
      try{$rel=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($parts[1]))}catch{continue}
      $map[$rel]=$row
    }
    $map
  }
  $before=Parse-Rows $BeforeRows;$after=Parse-Rows $AfterRows
  $keys=@($before.Keys+$after.Keys|Select-Object -Unique|Sort-Object)
  $changes=[System.Collections.Generic.List[object]]::new();$classes=[System.Collections.Generic.HashSet[string]]::new()
  foreach($key in $keys){
    if($before[$key] -eq $after[$key]){continue}
    $cls=Get-PathClass $key $prefixes
    [void]$classes.Add($cls)
    $inside=$false;foreach($p in $prefixes){if($key -eq $p -or $key.StartsWith("$p/")){$inside=$true;break}}
    $changes.Add([pscustomobject]@{relative_path=$key;path_class=$cls;inside_managed_root=$inside})
  }
  $overall='NO_CHANGE'
  if($changes.Count -gt 0){
    if(($classes|Where-Object{$_ -ne 'GOVERNANCE_ONLY_CHANGE'}).Count -eq 0){$overall='GOVERNANCE_ONLY_CHANGE'}
    elseif($classes.Contains('APPLICATION_SOURCE_CHANGE')){$overall='APPLICATION_SOURCE_CHANGE'}
    elseif($classes.Contains('GIT_METADATA_CHANGE')){$overall='GIT_METADATA_CHANGE'}
    elseif($classes.Contains('DEPENDENCY_CHANGE')){$overall='DEPENDENCY_CHANGE'}
    elseif($classes.Contains('GENERATED_ARTIFACT_CHANGE')){$overall='GENERATED_ARTIFACT_CHANGE'}
    else{$overall='UNKNOWN_CHANGE'}
  }
  [pscustomobject]@{diagnostic=$script:ChangesetDiagnostic;overall_class=$overall;change_count=$changes.Count;classes=@($classes);changes=@($changes|Select-Object -First 200)}
}
function Assert-ProjectStateUnchanged([string]$Expected,[string[]]$BeforeRows){
  $actual=Get-ProjectStateFingerprint
  if($actual -eq $Expected){return}
  $afterRows=@(Get-ProjectTreeManifest $ProjectDir)
  $diag=Get-ProjectStateChangesetDiagnostic $BeforeRows $afterRows
  $summary=($diag.changes|ForEach-Object{"$($_.path_class):$($_.relative_path)"}) -join '; '
  if($diag.overall_class -eq 'GOVERNANCE_ONLY_CHANGE'){
    # Should not happen when managed roots are registered; treat as fingerprint contract defect but do not mislabel.
    throw "ARCHITECT_FAILOVER_BLOCKED: PROJECT_STATE_CHANGED. diagnostic=$($script:ChangesetDiagnostic) overall=$($diag.overall_class) changes=$($diag.change_count) detail=$summary HUMAN_RECOVERY_REQUIRED"
  }
  throw "ARCHITECT_FAILOVER_BLOCKED: PROJECT_STATE_CHANGED. diagnostic=$($script:ChangesetDiagnostic) overall=$($diag.overall_class) changes=$($diag.change_count) detail=$summary HUMAN_RECOVERY_REQUIRED"
}
function Restore-Ai([string]$AiPath,[string]$Backup,[bool]$Existed,[string]$ExpectedHash){if(Test-Path $AiPath){Remove-Item $AiPath -Recurse -Force};if($Existed){Copy-Item $Backup $AiPath -Recurse -Force};$actual=Get-FileTreeHash $AiPath;if($actual-ne$ExpectedHash){throw "ARCHITECT_FAILOVER_BLOCKED: .ai restore hash mismatch ($actual != $ExpectedHash). HUMAN_RECOVERY_REQUIRED"}}
function Restore-ManagedGovernanceRoots([object[]]$Records){
  # MULTI_GOVERNANCE_ROOT_TRANSACTION_V1 atomic multi-root restore
  $errors=[System.Collections.Generic.List[string]]::new()
  foreach($rec in @($Records)){
    $path=[string]$rec.canonical_path
    $snap=[string]$rec.snapshot_path
    $expected=[string]$rec.tree_hash_before
    $existed=[bool]$rec.existed_before
    try{
      if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Recurse -Force}
      if($existed){
        if(-not(Test-Path -LiteralPath $snap)){throw "SNAPSHOT_MISSING: $snap"}
        Copy-Item -LiteralPath $snap -Destination $path -Recurse -Force
      }
      $actual=if(Test-Path -LiteralPath $path){Get-FileTreeHash $path}else{'ABSENT'}
      if($actual -ne $expected){throw "hash mismatch $actual != $expected"}
    }catch{$errors.Add("$path :: $($_.Exception.Message)")}
  }
  if($errors.Count){throw "MULTI_ROOT_RESTORE_INCOMPLETE: $($errors -join ' | '). HUMAN_RECOVERY_REQUIRED"}
}
function Get-TransactionDir([string]$Path){ Join-Path $ConfigDir ("opencode-governance-architect-tx/" + (Get-TextHash $Path.ToLowerInvariant())) }
function Test-PidAlive([int]$Id){try{$null=Get-Process -Id $Id -ErrorAction Stop;$true}catch{$false}}
function Get-TaskSnapshot(){
  if($Command-ne'ai-resume' -and -not $RecoverTransaction){return $null}
  if([string]::IsNullOrWhiteSpace($TaskId)){return $null}
  $path=Find-TaskStatePath $TaskId
  if(-not$path){throw "RESUME_TASK_NOT_FOUND: $TaskId"}
  try{$state=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json}catch{throw "INVALID_RUN_STATE: $path"}
  if($state.PSObject.Properties['task_id']-and[string]$state.task_id-ne$TaskId){throw 'RESUME_TASK_ID_MISMATCH'}
  $phase = if ($state.current_phase) { [string]$state.current_phase } else { [string]$state.phase }
  $action = if ($state.next_action) { $state.next_action | ConvertTo-Json -Depth 20 -Compress } else { '' }
  [pscustomobject]@{path=$path;hash=(Get-FileHashHex $path);state=[string]$state.state;phase=$phase;next=[string]$state.next_required_phase;action=$action}
}
function Get-ResumeMode(){
  $snap=Get-TaskSnapshot;$state=Get-Content -LiteralPath $snap.path -Raw|ConvertFrom-Json;$phases=@();foreach($field in @('current_phase','state','last_safe_transition')){$v=[string]$state.$field;if(-not[string]::IsNullOrWhiteSpace($v)){$phases+=$v.Trim()}}
  if(-not$phases){return 'PRE_SIDE_EFFECT'};foreach($phase in $phases){if($phase-in$PostSideEffectPhases){return 'POST_SIDE_EFFECT'}};'PRE_SIDE_EFFECT'
}
function Recover-Orphan([string]$Tx){
  $metaPath = Join-Path $Tx 'meta.json'
  if(-not(Test-Path -LiteralPath $metaPath -PathType Leaf)){return}
  $meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
  if(Test-PidAlive ([int]$meta.pid)){throw 'ARCHITECT_TRANSACTION_ACTIVE'}
  $expected=[string]$meta.project_state_fingerprint
  $hasMulti = $null -ne $meta.PSObject.Properties['managed_governance_roots'] -and $meta.managed_governance_roots
  $current = if($hasMulti){ Get-ProjectStateFingerprint } else { Get-ProjectStateFingerprint -Legacy }
  if($current -ne $expected){
    # Retry alternate formula for transitional journals
    $alt = if($hasMulti){ Get-ProjectStateFingerprint -Legacy } else { Get-ProjectStateFingerprint }
    if($alt -ne $expected){throw 'ARCHITECT_ORPHAN_RECOVERY_BLOCKED: PROJECT_STATE_CHANGED. HUMAN_RECOVERY_REQUIRED'}
  }
  if($hasMulti){
    Restore-ManagedGovernanceRoots @($meta.managed_governance_roots)
  }else{
    $ai=Join-Path $ProjectDir '.ai'
    $backup=Join-Path $Tx 'ai-snapshot'
    Restore-Ai $ai $backup ([bool]$meta.ai_existed) ([string]$meta.ai_hash)
  }
  Remove-Item -LiteralPath $Tx -Recurse -Force
  Write-Warning 'ARCHITECT_ORPHAN_RECOVERED'
}
function Open-Transaction([string]$Tx,[string]$ProjectState,[object]$Task){
  # MULTI_GOVERNANCE_ROOT_TRANSACTION_V1 (compatible with ARCHITECT_TRANSACTION_V2)
  if(Test-Path -LiteralPath $Tx){Remove-Item -LiteralPath $Tx -Recurse -Force}
  New-Item -ItemType Directory -Force -Path $Tx | Out-Null
  $records=[System.Collections.Generic.List[object]]::new()
  $snapRoot=Join-Path $Tx 'managed-governance-roots'
  New-Item -ItemType Directory -Force -Path $snapRoot | Out-Null
  foreach($m in @($script:ManagedGovernanceRoots)){
    $path=[string]$m.canonical_path
    $key=(Get-TextHash $path.ToLowerInvariant()).Substring(0,16)
    $dest=Join-Path $snapRoot $key
    $existed=Test-Path -LiteralPath $path
    $hash=if($existed){Get-FileTreeHash $path}else{'ABSENT'}
    if($existed){Copy-Item -LiteralPath $path -Destination $dest -Recurse -Force}
    $records.Add([pscustomobject]@{
      canonical_path=$path
      existed_before=$existed
      tree_hash_before=$hash
      snapshot_path=$dest
      snapshot_key=$key
      role=[string]$m.role
    })
  }
  # Compatibility single-root snapshot: prefer repository_governance else first managed root else workspace .ai
  $primary= @($records | Where-Object { $_.role -eq 'repository_governance' } | Select-Object -First 1)
  if(-not $primary){$primary=@($records | Select-Object -First 1)}
  $legacyBackup=Join-Path $Tx 'ai-snapshot'
  if($primary -and $primary.existed_before -and (Test-Path -LiteralPath $primary.snapshot_path)){
    Copy-Item -LiteralPath $primary.snapshot_path -Destination $legacyBackup -Recurse -Force
  }
  $script:ManagedRootRecords=@($records)
  $checkpointHash = if($Task){[string]$Task.hash}else{$null}
  $hashMap=[ordered]@{}
  foreach($r in $records){$hashMap[[string]$r.canonical_path]=[string]$r.tree_hash_before}
  $meta=[ordered]@{
    schema='ARCHITECT_TRANSACTION_V2'
    compatibility='ARCHITECT_TRANSACTION_V1'
    extensions=[ordered]@{
      workspace_repository_root_contract=$script:WorkspaceRootContract
      multi_governance_root_transaction=$script:MultiGovernanceTx
    }
    command=$Command
    task_id=$TaskId
    arguments_sha256=$ArgumentsHash
    prompt_transport='stdin'
    prompt_transport_contract=$script:PromptTransportContract
    arguments_utf8_bytes=$script:PromptUtf8Bytes
    argv_prompt_bytes=0
    checkpoint_sha256=$checkpointHash
    project_dir=$ProjectDir
    workspace_root=$ProjectDir
    repository_root=$script:RepositoryDir
    pid=$PID
    started_at_utc=[DateTime]::UtcNow.ToString('o')
    ai_existed=if($primary){[bool]$primary.existed_before}else{$false}
    ai_hash=if($primary){[string]$primary.tree_hash_before}else{'ABSENT'}
    managed_governance_roots=@($records)
    managed_governance_root_hashes_before=$hashMap
    executor_worktree_roots=@()
    project_state_fingerprint=$ProjectState
    permission_contract=$script:HeadlessContractVersion
    runtime_policy_sha256=$script:HeadlessPolicyHash
  }
  $meta | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Tx 'meta.json') -Encoding utf8
  $legacyBackup
}
function Close-Transaction([string]$Tx){if(Test-Path $Tx){Remove-Item $Tx -Recurse -Force}}
function Resolve-LegacyRecoveryModule(){
  # LEGACY_ARCHITECT_ORPHAN_RECOVERY_CONTRACT_V1 + EVIDENCE_BOUND_RECOVERY_RECEIPT_V2
  # validate-governance-only | adopt-governance-only | rollback via EvidenceBundlePath binding.
  $candidates=@(
    (Join-Path $PSScriptRoot 'legacy-architect-orphan-recovery.py'),
    (Join-Path (Split-Path -Parent $PSCommandPath) 'legacy-architect-orphan-recovery.py'),
    (Join-Path $ConfigDir 'opencode-governance-tools/legacy-architect-orphan-recovery.py')
  )
  foreach($path in $candidates){if($path-and(Test-Path -LiteralPath $path -PathType Leaf)){return $path}}
  throw 'LEGACY_RECOVERY_MODULE_MISSING: legacy-architect-orphan-recovery.py is not installed next to the Architect runner.'
}
function Invoke-ExplicitTransactionRecovery(){
  if(-not $RecoverTransaction){return $false}
  if([string]::IsNullOrWhiteSpace($RecoveryDecision)){throw 'RECOVERY_DECISION_REQUIRED: use -RecoveryDecision validate-governance-only|adopt-governance-only|rollback'}
  if([string]::IsNullOrWhiteSpace($TaskId)){throw 'RECOVERY_TASK_ID_REQUIRED'}
  $tx=Get-TransactionDir $ProjectDir
  if(-not(Test-Path -LiteralPath $tx -PathType Container)){throw "RECOVERY_TRANSACTION_NOT_FOUND: $tx"}
  $module=Resolve-LegacyRecoveryModule
  $py=Get-Command python -ErrorAction SilentlyContinue
  if(-not$py){$py=Get-Command python3 -ErrorAction SilentlyContinue}
  if(-not$py){throw 'LEGACY_RECOVERY_PYTHON_MISSING: python is required for evidence-bound recovery.'}
  $repo=if($script:RepositoryDir){$script:RepositoryDir}else{$ProjectDir}
  $argv=[System.Collections.Generic.List[string]]::new()
  foreach($v in @($module,'--decision',$RecoveryDecision,'--workspace',$ProjectDir,'--repository',$repo,'--task-id',$TaskId,'--transaction-dir',$tx,'--config-dir',$ConfigDir)){ $argv.Add([string]$v) }
  if(-not [string]::IsNullOrWhiteSpace($EvidenceBundlePath)){ $argv.Add('--evidence-bundle'); $argv.Add($EvidenceBundlePath) }
  if(-not [string]::IsNullOrWhiteSpace($ExpectedTransactionHash)){ $argv.Add('--expected-transaction-hash'); $argv.Add($ExpectedTransactionHash) }
  if(-not [string]::IsNullOrWhiteSpace($ExpectedEvidenceBundleHash)){ $argv.Add('--expected-evidence-bundle-hash'); $argv.Add($ExpectedEvidenceBundleHash) }
  if(-not [string]::IsNullOrWhiteSpace($ExpectedRepositoryHead)){ $argv.Add('--expected-repository-head'); $argv.Add($ExpectedRepositoryHead) }
  if(-not [string]::IsNullOrWhiteSpace($ExpectedPlanHash)){ $argv.Add('--expected-plan-hash'); $argv.Add($ExpectedPlanHash) }
  if(-not [string]::IsNullOrWhiteSpace($ExpectedExecutionPacketHash)){ $argv.Add('--expected-execution-packet-hash'); $argv.Add($ExpectedExecutionPacketHash) }
  if(-not [string]::IsNullOrWhiteSpace($ExpectedCheckpointHash)){ $argv.Add('--expected-checkpoint-hash'); $argv.Add($ExpectedCheckpointHash) }
  if(-not [string]::IsNullOrWhiteSpace($ExpectedArgumentsHash)){ $argv.Add('--expected-arguments-hash'); $argv.Add($ExpectedArgumentsHash) }
  if(-not [string]::IsNullOrWhiteSpace($ExpectedStdoutHash)){ $argv.Add('--expected-stdout-hash'); $argv.Add($ExpectedStdoutHash) }
  if(-not [string]::IsNullOrWhiteSpace($ExpectedStderrHash)){ $argv.Add('--expected-stderr-hash'); $argv.Add($ExpectedStderrHash) }
  $output=& $py.Source @($argv) 2>&1
  $code=$LASTEXITCODE
  $text=(($output|ForEach-Object{[string]$_})-join"`n")
  if($code -ne 0){ throw $text }
  if($text){ Write-Host $text }
  return $true
}
function Classify-Failure([string]$Text,[bool]$TimedOut,[int]$ExitCode=1){
  if($TimedOut){ return 'BOUNDED_TIMEOUT' }
  if(Test-PermissionBlocked $Text){ return 'ARCHITECT_PERMISSION_BLOCKED' }
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
function New-PromptTransportError([string]$Detail,[string]$Route,[int]$Attempt,[string]$Logs){
  "ARCHITECT_PROMPT_TRANSPORT_FAILED: contract=$($script:PromptTransportContract) mode=stdin host=$($Launch.host) launcher_type=$($Launch.launcher_type) route=$Route attempt=$Attempt bytes=$($script:PromptUtf8Bytes) sha256=$($script:PromptTransportSha256) argv_prompt_bytes=0 logs=$Logs detail=$Detail"
}
function Invoke-Route([object]$Route,[int]$Attempt,[string]$Logs){
  $stdout = Join-Path $Logs "attempt-$Attempt.stdout.log"
  $stderr = Join-Path $Logs "attempt-$Attempt.stderr.log"
  $roots = [System.Collections.Generic.List[string]]::new()
  $roots.Add($ConfigDir)
  $toolsDir = Join-Path $ConfigDir 'opencode-governance-tools'
  if(Test-Path -LiteralPath $toolsDir -PathType Container){ $roots.Add($toolsDir) }
  if($ArgumentsFile){ $roots.Add([IO.Path]::GetDirectoryName($ArgumentsFile)) }
  $overlay = New-HeadlessPermissionOverlay ([string]$Route.candidate.model) ([string]$Route.candidate.variant) @($roots)
  $script:HeadlessConfigContent = $overlay.json
  $script:HeadlessPolicyHash = $overlay.sha256
  Write-Host "HEADLESS_PERMISSION_CONTRACT version=$($overlay.version) runtime_policy_sha256=$($overlay.sha256) auto=disabled"
  # ARCHITECT_STDIN_PROMPT_TRANSPORT_V1: control argv only; complete handoff on redirected stdin (UTF-8 no BOM).
  Write-Host "ARCHITECT_PROMPT_TRANSPORT contract=$($script:PromptTransportContract) mode=stdin bytes=$($script:PromptUtf8Bytes) sha256=$($script:PromptTransportSha256) argv_prompt_bytes=0"
  $utf8NoBom = [Text.UTF8Encoding]::new($false)
  $info = [Diagnostics.ProcessStartInfo]::new()
  $info.FileName = [string]$Launch.command
  $info.WorkingDirectory = $ProjectDir
  $info.UseShellExecute = $false
  $info.RedirectStandardInput = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.StandardInputEncoding = $utf8NoBom
  $info.StandardOutputEncoding = $utf8NoBom
  $info.StandardErrorEncoding = $utf8NoBom
  $info.CreateNoWindow = $true
  $info.Environment['OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE'] = '1'
  $info.Environment['OPENCODE_GOVERNANCE_HEADLESS_CONTRACT'] = $script:HeadlessContractVersion
  $info.Environment['OPENCODE_CONFIG_CONTENT'] = $overlay.json
  # GOVERNED_ROLE_LAUNCH_CONTRACT_V1 — fail closed if effect plugin is not installed/hash-bound.
  $launchHelper = Join-Path $ConfigDir 'opencode-governance-tools\governed-role-launch.py'
  if(-not (Test-Path -LiteralPath $launchHelper -PathType Leaf)){
    $launchHelper = Join-Path $PSScriptRoot 'governed-role-launch.py'
  }
  if(-not (Test-Path -LiteralPath $launchHelper -PathType Leaf)){
    throw 'EFFECT_PLUGIN_NOT_ACTIVE: governed-role-launch.py missing (install 4.0.1 capabilities).'
  }
  $pre = & python $launchHelper preflight-plugin --config-dir $ConfigDir 2>&1
  if($LASTEXITCODE -ne 0){ throw "EFFECT_PLUGIN_NOT_ACTIVE: $pre" }
  $repoRoot = if($script:RepositoryDir){ [string]$script:RepositoryDir } elseif($RepositoryDir){ [string]$RepositoryDir } else { [string]$ProjectDir }
  $effectPolicy = Join-Path $ConfigDir 'plugins\opencode-governance-effect-enforcement\role-effect-policy.json'
  $effectSha = ''
  if(Test-Path -LiteralPath $effectPolicy){
    $effectSha = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([IO.File]::ReadAllBytes($effectPolicy))).Replace('-','').ToLowerInvariant()
  } else {
    throw 'EFFECT_PLUGIN_NOT_ACTIVE: effect policy missing under plugins/'
  }
  $launchPath = Join-Path $Logs "governed-role-launch-architect-$Attempt.json"
  $writeArgs = @(
    $launchHelper,'write','--out',$launchPath,'--role','architect','--expected-agent','architect',
    '--workspace',[string]$ProjectDir,'--repository',$repoRoot,'--phase',[string]$Command,
    '--effect-policy',$effectPolicy,'--effect-policy-sha256',$effectSha,'--config-dir',$ConfigDir,'--require-plugin'
  )
  if($TaskId){ $writeArgs += @('--task-id',[string]$TaskId) }
  if($script:HeadlessPolicyHash){ $writeArgs += @('--permission-policy-sha256',[string]$script:HeadlessPolicyHash) }
  $written = & python @writeArgs 2>&1
  if($LASTEXITCODE -ne 0){ throw "GOVERNED_ROLE_LAUNCH_REQUIRED: $written" }
  $info.Environment['OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE'] = '1'
  $info.Environment['OPENCODE_GOVERNANCE_ROLE'] = 'architect'
  $info.Environment['OPENCODE_GOVERNANCE_EXPECTED_AGENT'] = 'architect'
  $info.Environment['OPENCODE_GOVERNANCE_PHASE'] = [string]$Command
  $info.Environment['OPENCODE_GOVERNANCE_WORKSPACE'] = [string]$ProjectDir
  $info.Environment['OPENCODE_GOVERNANCE_REPOSITORY'] = $repoRoot
  $info.Environment['OPENCODE_GOVERNANCE_LAUNCH_FILE'] = $launchPath
  $info.Environment['OPENCODE_GOVERNANCE_EFFECT_POLICY'] = $effectPolicy
  $info.Environment['OPENCODE_GOVERNANCE_EFFECT_POLICY_SHA256'] = $effectSha
  if($TaskId){ $info.Environment['OPENCODE_GOVERNANCE_TASK_ID'] = [string]$TaskId }
  if($script:HeadlessPolicyHash){ $info.Environment['OPENCODE_GOVERNANCE_PERMISSION_POLICY_SHA256'] = [string]$script:HeadlessPolicyHash }
  # Never place the governed prompt on argv, in environment variables, or via shell interpolation.
  # Never pass blanket --auto. Deny-by-default bash eliminates ask; residual asks fail closed.
  foreach($v in @($Launch.prefix)){ $null = $info.ArgumentList.Add([string]$v) }
  foreach($v in @('run','--dir',$ProjectDir,'--agent','architect','--model',[string]$Route.candidate.model)){ $null = $info.ArgumentList.Add([string]$v) }
  if(-not [string]::IsNullOrWhiteSpace([string]$Route.candidate.variant)){
    $null = $info.ArgumentList.Add('--variant')
    $null = $info.ArgumentList.Add([string]$Route.candidate.variant)
  }
  foreach($v in @('--command',$Command,'--format','json')){ $null = $info.ArgumentList.Add([string]$v) }
  # Fail closed if the governed handoff ever reappears on argv (no silent CLI transport).
  foreach($arg in $info.ArgumentList){
    if([string]$arg -ceq $RoutedArguments){
      throw (New-PromptTransportError 'argv contained complete prompt payload (refusing silent CLI transport)' $Route.route $Attempt $Logs)
    }
  }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $info
  try{
    if(-not $process.Start()){ throw (New-PromptTransportError 'Process.Start returned false' $Route.route $Attempt $Logs) }
  }catch{
    $msg = [string]$_.Exception.Message
    if($msg -match '(?i)filename or extension is too long|command line.*too long|E2BIG|argument list too long'){
      throw (New-PromptTransportError "process start failed (command-line limit): $msg" $Route.route $Attempt $Logs)
    }
    if($_.Exception.Message -like 'ARCHITECT_PROMPT_TRANSPORT*'){ throw }
    throw (New-PromptTransportError "process start failed: $msg" $Route.route $Attempt $Logs)
  }
  # Start async stream readers before writing stdin to avoid stdout/stderr pipe deadlocks.
  $outTask = $process.StandardOutput.ReadToEndAsync()
  $errTask = $process.StandardError.ReadToEndAsync()
  try{
    $process.StandardInput.Write($RoutedArguments)
    $process.StandardInput.Close()
  }catch{
    try{ if(-not $process.HasExited){ $process.Kill($true) } }catch{}
    try{ $process.WaitForExit(5000) }catch{}
    throw (New-PromptTransportError "stdin write/close failed: $([string]$_.Exception.Message)" $Route.route $Attempt $Logs)
  }
  $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
  if($timedOut){ try{$process.Kill($true)}catch{}; $process.WaitForExit() }
  $out = $outTask.GetAwaiter().GetResult()
  $err = $errTask.GetAwaiter().GetResult()
  [IO.File]::WriteAllText($stdout,$out,$utf8NoBom)
  [IO.File]::WriteAllText($stderr,$err,$utf8NoBom)
  [pscustomobject]@{exit=$process.ExitCode;timed_out=$timedOut;text=($out+"`n"+$err);stdout=$out;stderr=$err;policy_sha256=$overlay.sha256}
}
function Get-CombinedGovernanceTreeHash(){
  $parts=[System.Collections.Generic.List[string]]::new()
  foreach($m in @($script:ManagedGovernanceRoots)){
    $path=[string]$m.canonical_path
    $hash=if(Test-Path -LiteralPath $path){Get-FileTreeHash $path}else{'ABSENT'}
    $parts.Add("$path=$hash")
  }
  if($parts.Count -eq 0){
    $ai=Join-Path $ProjectDir '.ai'
    return (Get-FileTreeHash $ai)
  }
  Get-TextHash (($parts|Sort-Object)-join"`n")
}
function Validate-ResumePostcondition([object]$Before,[string]$BeforeAi,[object]$Result){
  $After=Get-TaskSnapshot
  $AfterAi=Get-CombinedGovernanceTreeHash
  if($After.hash -eq $Before.hash -and $AfterAi -eq $BeforeAi){ throw 'ARCHITECT_NO_PROGRESS: child exited zero but task checkpoint and .ai/** are byte-identical.' }
  if($Result.text -notmatch 'GOVERNANCE_RESULT'){ throw 'ARCHITECT_CHILD_RESULT_MISSING: child exited zero without GOVERNANCE_RESULT.' }
  if([string]::IsNullOrWhiteSpace($After.state) -and [string]::IsNullOrWhiteSpace($After.phase)){ throw 'ARCHITECT_CHILD_RESULT_MISMATCH: resulting checkpoint has no state/phase.' }
  [pscustomobject]@{after=$After;ai_hash=$AfterAi}
}
function Write-PhaseContinuation([object]$After){
  if(-not $After){return}
  $state=[string]$After.state; if([string]::IsNullOrWhiteSpace($state)){$state=[string]$After.phase}
  if($state -eq 'READY_FOR_EXECUTION' -or [string]$After.next -eq 'IMPLEMENTING'){
    Write-Host "ARCHITECT_PHASE_ADVANCED STATE=$state NEXT_COMMAND=/ai-execute ATTEMPT_CONSUMED=false"
  }
}

$TxDir=Get-TransactionDir $ProjectDir
if($RecoverTransaction){
  if(Invoke-ExplicitTransactionRecovery){exit 0}
  throw 'RECOVERY_FAILED'
}
Recover-Orphan $TxDir
$BeforeTask=Get-TaskSnapshot
if($Command-eq'ai-resume'){
  $mode=Get-ResumeMode
  Write-Host "ARCHITECT_RESUME_MODE $mode task=$TaskId"
  if($mode-eq'POST_SIDE_EFFECT'){throw 'RESUME_POST_SIDE_EFFECT'}
}
$Temp=Join-Path ([IO.Path]::GetTempPath()) ("opencode-governance-"+[guid]::NewGuid().ToString('N'))
$Logs=Join-Path $Temp 'logs'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
$ExternalRoots=[System.Collections.Generic.List[string]]::new()
$ExternalRoots.Add($ConfigDir)
$ToolsRoot=Join-Path $ConfigDir 'opencode-governance-tools'
if(Test-Path -LiteralPath $ToolsRoot -PathType Container){$ExternalRoots.Add($ToolsRoot)}
if($ArgumentsFile){$ExternalRoots.Add([IO.Path]::GetDirectoryName($ArgumentsFile))}
if($script:RepositoryDir -and $script:RepositoryDir -ne $ProjectDir){$ExternalRoots.Add($script:RepositoryDir)}
$BaseOverlay=New-HeadlessPermissionOverlay ([string]$Architect.primary.model) ([string]$Architect.primary.variant) @($ExternalRoots)
$script:HeadlessConfigContent=$BaseOverlay.json
$script:HeadlessPolicyHash=$BaseOverlay.sha256
Write-Host "HEADLESS_PERMISSION_CONTRACT version=$($BaseOverlay.version) runtime_policy_sha256=$($BaseOverlay.sha256) auto=disabled"
$script:FingerprintManifestBefore=@(Get-ProjectTreeManifest $ProjectDir)
$ProjectState=Get-ProjectStateFingerprint
$BeforeCombined=Get-CombinedGovernanceTreeHash
$Backup=Open-Transaction $TxDir $ProjectState $BeforeTask
$Attempted=@{};$Failure=$null;$FailedFamily='';$attempt=0
try{
  while($true){
    $selectionFailure = if($Failure){$Failure}else{'PROVIDER_UNAVAILABLE'}
    $ordered=@($Routes | Where-Object { Candidate-Allowed $_ $selectionFailure $FailedFamily $Attempted } | Sort-Object priority)
    if(-not$ordered){throw "ARCHITECT_FAILOVER_BLOCKED: no eligible Architect route remains after $Failure"}
    $route=$ordered[0];$Attempted[$route.route]=$true;$attempt++;Write-Host "ARCHITECT_ROUTE_ATTEMPT $attempt $($route.route) $($route.candidate.model)"
    $result=Invoke-Route $route $attempt $Logs
    Assert-ProjectStateUnchanged $ProjectState $script:FingerprintManifestBefore
    # Permission blocks are ineligible for model fallback and never consume implementation/review cycles.
    if(Test-PermissionBlocked $result.text){
      throw (New-PermissionBlockedError $result.text $route.route $attempt $Logs)
    }
    if($result.exit -eq 0 -and -not $result.timed_out){
      $post=$null
      if($Command -eq 'ai-resume'){ $post=Validate-ResumePostcondition $BeforeTask $BeforeCombined $result }
      $Cooldowns.Remove([string]$route.candidate.model);Save-Cooldowns $Cooldowns
      Write-Host "ARCHITECT_FAILOVER_COMPLETE route=$($route.route) attempts=$attempt task=$TaskId ai_tree=$(Get-CombinedGovernanceTreeHash) postcondition=PASS permission_contract=$($script:HeadlessContractVersion) runtime_policy_sha256=$($script:HeadlessPolicyHash)"
      if($post){ Write-PhaseContinuation $post.after }
      elseif($Command -eq 'ai-resume'){ Write-PhaseContinuation (Get-TaskSnapshot) }
      if($result.stdout){ Write-Output $result.stdout.TrimEnd() }
      if($result.stderr){ Write-Warning $result.stderr.TrimEnd() }
      Close-Transaction $TxDir
      if(-not $KeepAttemptLogs){ Remove-Item -LiteralPath $Temp -Recurse -Force }
      exit 0
    }
    $Failure=Classify-Failure $result.text $result.timed_out ([int]$result.exit);$FailedFamily=[string]$route.candidate.model_family;Write-Warning "Architect route failed: $Failure ($($route.route))"
    if($Failure -eq 'ARCHITECT_PERMISSION_BLOCKED'){ throw (New-PermissionBlockedError $result.text $route.route $attempt $Logs) }
    if($Failure-notin$Eligible){throw "ARCHITECT_FAILOVER_BLOCKED: ineligible failure $Failure. Logs: $Logs"}
    $Cooldowns[[string]$route.candidate.model]=(Get-Epoch)+$DefaultCooldown;Save-Cooldowns $Cooldowns
    Restore-ManagedGovernanceRoots $script:ManagedRootRecords
  }
}catch{
  # MULTI_GOVERNANCE_ROOT_TRANSACTION_V1: always restore managed Governance roots on failure when possible.
  # Never rewrite application source. If multi-root restore is incomplete, retain the orphan journal.
  $restored=$false
  try{
    Restore-ManagedGovernanceRoots $script:ManagedRootRecords
    $restored=$true
  }catch{Write-Warning $_.Exception.Message}
  if($restored){Close-Transaction $TxDir}else{Write-Warning "ARCHITECT_TRANSACTION_ORPHANED: $TxDir"}
  $script:HeadlessConfigContent=$null
  Write-Host "ATTEMPT_LOGS $Logs";Write-Error $_;exit 1
}
