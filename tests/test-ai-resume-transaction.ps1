# 3.7.2 incident regressions: transactional /ai-resume, TOOL_EXECUTION_ABORTED, orphan recovery.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$RootDir = Split-Path -Parent $PSScriptRoot
$TempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { Join-Path ([IO.Path]::GetTempPath()) ('opencode-v372-tests-' + [guid]::NewGuid().ToString('N')) }
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
$Config = Join-Path $TempRoot 'opencode-v372-windows'
& (Join-Path $RootDir 'scripts/install.ps1') -ConfigDir $Config -NonInteractive -RoutingConfigPath (Join-Path $RootDir 'tests/fixtures/routing/architect-failover.valid.json')
$Runner = Join-Path $Config 'opencode-governance-tools/architect-attempt.ps1'
$Manifest = Join-Path $Config 'opencode-governance-routing.json'

function Invoke-ResumeRunner([string]$Project, [string]$Label, [string]$Mock) {
    $wrapper = Join-Path $TempRoot ('v372-wrapper-' + [guid]::NewGuid().ToString('N') + '.ps1')
    @"
& '$Runner' -ProjectDir '$Project' -Command ai-resume -Arguments '$Label' -RoutingConfigPath '$Manifest' -ConfigDir '$Config' -OpenCodeCommand pwsh -OpenCodePrefixArguments @('-NoProfile','-File','$Mock')
"@ | Set-Content -LiteralPath $wrapper
    $output = & pwsh -NoProfile -File $wrapper 2>&1
    $code = $LASTEXITCODE
    Remove-Item -LiteralPath $wrapper -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Code = $code; Text = (($output | ForEach-Object { [string]$_ }) -join "`n") }
}

function Get-TextHash([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-FileTreeHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 'ABSENT' }
    $rows = @()
    foreach ($item in Get-ChildItem -LiteralPath $Path -Force -Recurse | Sort-Object FullName) {
        $relative = [IO.Path]::GetRelativePath($Path, $item.FullName).Replace('\', '/')
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if (-not $item.PSIsContainer) {
            $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $rows += "$relative`t$hash"
        }
    }
    Get-TextHash ($rows -join "`n")
}

function Encode-StateField([string]$Value) { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value)) }

function Get-ProjectTreeHash([string]$Root) {
    $rows = [Collections.Generic.List[string]]::new()
    $stack = [Collections.Generic.Stack[string]]::new()
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $directory = $stack.Pop()
        foreach ($item in Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop) {
            $relative = [IO.Path]::GetRelativePath($Root, $item.FullName).Replace('\', '/')
            if ($item.Name -ieq '.git') { continue }
            if ($relative -ieq '.ai' -or $relative.StartsWith('.ai/', [StringComparison]::OrdinalIgnoreCase)) { continue }
            $pathField = Encode-StateField $relative
            $attributes = [int]$item.Attributes
            $isLink = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
            if ($isLink) {
                $target = if ($null -ne $item.LinkTarget) { [string]$item.LinkTarget } else { '' }
                $rows.Add("L|$pathField|$attributes|$(Encode-StateField $target)")
                continue
            }
            if ($item.PSIsContainer) {
                $rows.Add("D|$pathField|$attributes")
                $stack.Push($item.FullName)
                continue
            }
            $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $rows.Add("F|$pathField|$attributes|$($item.Length)|$hash")
        }
    }
    Get-TextHash (($rows | Sort-Object) -join "`n")
}

function Get-ProjectStateFingerprint([string]$Root) {
    $treeHash = Get-ProjectTreeHash $Root
    Get-TextHash "PROJECT_STATE_FINGERPRINT_V1`nMODE=NON_GIT`nTREE=$treeHash`nHEAD=N/A`nINDEX=N/A`nSUBMODULES=N/A"
}

function New-PreSideEffectProject([string]$Name) {
    $project = Join-Path $TempRoot $Name
    New-Item -ItemType Directory -Force -Path (Join-Path $project '.ai/tasks/TASK-001') | Out-Null
    'baseline' | Set-Content (Join-Path $project '.ai/BASELINE.md')
    'source' | Set-Content (Join-Path $project 'source.txt')
    $runState = [ordered]@{
        top_level_command   = 'ai-workflow'
        current_phase       = 'READY_FOR_EXECUTION'
        next_required_phase = 'IMPLEMENTING'
        terminal_reason     = $null
        next_action         = [ordered]@{
            kind                   = 'execute'
            command                = '/ai-execute'
            arguments              = @('TASK-001')
            expected_postcondition = 'TASK_VALIDATED'
        }
    }
    ($runState | ConvertTo-Json -Depth 6) | Set-Content (Join-Path $project '.ai/tasks/TASK-001/RUN_STATE.json') -Encoding utf8
    return $project
}

# --- 1) Incident reproduction: abort mid-resume → TOOL_EXECUTION_ABORTED → .ai/** restored → failover ---
$project = New-PreSideEffectProject 'v372-windows-abort'
$mock = Join-Path $TempRoot 'v372-windows-abort-mock.ps1'
$state = Join-Path $TempRoot 'v372-windows-abort-count'
@'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
$project='';$model=''
for($i=0;$i-lt$Args.Count;$i++){if($Args[$i]-eq'--dir'){$project=$Args[++$i]}elseif($Args[$i]-eq'--model'){$model=$Args[++$i]}}
$count=if(Test-Path $env:MOCK_STATE){[int](Get-Content $env:MOCK_STATE)}else{0};($count+1)|Set-Content $env:MOCK_STATE
if($model-eq'test/architect-primary'){
  'partial-architect'|Set-Content (Join-Path $project '.ai/PARTIAL_RESUME.md')
  [Console]::Error.WriteLine('tool execution aborted')
  exit 1
}
if(Test-Path (Join-Path $project '.ai/PARTIAL_RESUME.md')){exit 23}
if((Get-Content (Join-Path $project '.ai/BASELINE.md') -Raw).Trim()-ne'baseline'){exit 24}
'success'|Set-Content (Join-Path $project '.ai/RESUME_OK.md')
$runStatePath=Join-Path $project '.ai/tasks/TASK-001/RUN_STATE.json'
$runState=Get-Content -LiteralPath $runStatePath -Raw|ConvertFrom-Json
$runState|Add-Member NoteProperty state 'READY_FOR_EXECUTION' -Force
$runState.current_phase='READY_FOR_EXECUTION'
$runState.next_required_phase='IMPLEMENTING'
$runState|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $runStatePath -Encoding utf8
Write-Output "GOVERNANCE_RESULT`nTASK_ID: TASK-001`nSTATE: READY_FOR_EXECUTION"
exit 0
'@ | Set-Content -LiteralPath $mock
$env:MOCK_STATE = $state
$result = Invoke-ResumeRunner $project 'abort-resume-incident' $mock
if ($result.Code -ne 0) { throw "Abort-during-resume failover failed: $($result.Text)" }
if ($result.Text -notmatch 'TOOL_EXECUTION_ABORTED') { throw "Abort was not classified as TOOL_EXECUTION_ABORTED. Output: $($result.Text)" }
if ([int](Get-Content $state) -ne 2) { throw 'Abort-during-resume did not use fallback route' }
if (Test-Path (Join-Path $project '.ai/PARTIAL_RESUME.md')) { throw 'Partial .ai/** write survived after TOOL_EXECUTION_ABORTED' }
if (-not (Test-Path (Join-Path $project '.ai/RESUME_OK.md'))) { throw 'Fallback resume did not complete' }
if ((Get-Content (Join-Path $project 'source.txt') -Raw).Trim() -ne 'source') { throw 'Source changed during resume transaction' }

# --- 2) Post-side-effect resume refused ---
$post = New-PreSideEffectProject 'v372-windows-post'
$postState = Get-Content (Join-Path $post '.ai/tasks/TASK-001/RUN_STATE.json') -Raw | ConvertFrom-Json
$postState.current_phase = 'IMPLEMENTING'
$postState.next_required_phase = 'DOCUMENTATION_SYNC'
($postState | ConvertTo-Json -Depth 6) | Set-Content (Join-Path $post '.ai/tasks/TASK-001/RUN_STATE.json') -Encoding utf8
'keep-me' | Set-Content (Join-Path $post '.ai/IMPLEMENTATION_NOTE.md')
$postMock = Join-Path $TempRoot 'v372-windows-post-mock.ps1'
'param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args); exit 0' | Set-Content -LiteralPath $postMock
$result = Invoke-ResumeRunner $post 'post-side-effect' $postMock
if ($result.Code -eq 0) { throw 'Post-side-effect resume was incorrectly accepted' }
if ($result.Text -notmatch 'RESUME_POST_SIDE_EFFECT') { throw "Post-side-effect resume missing RESUME_POST_SIDE_EFFECT. Output: $($result.Text)" }
if (-not (Test-Path (Join-Path $post '.ai/IMPLEMENTATION_NOTE.md'))) { throw 'Post-side-effect refusal must not wipe .ai/**' }

# --- 3) Orphan Architect transaction recovery ---
$orphanProject = New-PreSideEffectProject 'v372-windows-orphan'
$cleanAi = Join-Path $TempRoot 'v372-orphan-clean-ai'
Copy-Item (Join-Path $orphanProject '.ai') $cleanAi -Recurse -Force
$projectFp = Get-ProjectStateFingerprint $orphanProject
$aiHash = Get-FileTreeHash $cleanAi
$txKey = Get-TextHash $orphanProject.ToLowerInvariant()
$txDir = Join-Path $Config "opencode-governance-architect-tx/$txKey"
New-Item -ItemType Directory -Force -Path $txDir | Out-Null
Copy-Item $cleanAi (Join-Path $txDir 'ai-snapshot') -Recurse -Force
$meta = [ordered]@{
    schema                    = 'ARCHITECT_TRANSACTION_V1'
    command                   = 'ai-resume'
    project_dir               = $orphanProject
    pid                       = 1
    started_at_utc            = [DateTime]::UtcNow.ToString('o')
    ai_existed                = $true
    ai_hash                   = $aiHash
    project_state_fingerprint = $projectFp
}
($meta | ConvertTo-Json -Depth 5) | Set-Content (Join-Path $txDir 'meta.json') -Encoding utf8
'orphaned-partial' | Set-Content (Join-Path $orphanProject '.ai/ORPHAN_PARTIAL.md')

$orphanMock = Join-Path $TempRoot 'v372-windows-orphan-mock.ps1'
@'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
$project=''
for($i=0;$i-lt$Args.Count;$i++){if($Args[$i]-eq'--dir'){$project=$Args[++$i]}}
if(Test-Path (Join-Path $project '.ai/ORPHAN_PARTIAL.md')){exit 25}
'recovered'|Set-Content (Join-Path $project '.ai/RECOVERED.md')
$runStatePath=Join-Path $project '.ai/tasks/TASK-001/RUN_STATE.json'
$runState=Get-Content -LiteralPath $runStatePath -Raw|ConvertFrom-Json
$runState|Add-Member NoteProperty state 'READY_FOR_EXECUTION' -Force
$runState.current_phase='READY_FOR_EXECUTION'
$runState.next_required_phase='IMPLEMENTING'
$runState|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $runStatePath -Encoding utf8
Write-Output "GOVERNANCE_RESULT`nTASK_ID: TASK-001`nSTATE: READY_FOR_EXECUTION"
exit 0
'@ | Set-Content -LiteralPath $orphanMock
$result = Invoke-ResumeRunner $orphanProject 'orphan-recovery' $orphanMock
if ($result.Code -ne 0) { throw "Orphan recovery resume failed: $($result.Text)" }
if ($result.Text -notmatch 'ARCHITECT_ORPHAN_RECOVERED') { throw "Missing ARCHITECT_ORPHAN_RECOVERED. Output: $($result.Text)" }
if (Test-Path (Join-Path $orphanProject '.ai/ORPHAN_PARTIAL.md')) { throw 'Orphan partial .ai/** was not rolled back' }
if (-not (Test-Path (Join-Path $orphanProject '.ai/RECOVERED.md'))) { throw 'Resume after orphan recovery did not complete' }

$global:LASTEXITCODE = 0
Write-Host 'PASS: Windows /ai-resume transactional reliability regressions (3.7.2).'
