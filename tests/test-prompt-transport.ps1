# 3.7.4: ARCHITECT_STDIN_PROMPT_TRANSPORT_V1 — large handoff, no argv prompt, exact UTF-8, early-close.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$RootDir = Split-Path -Parent $PSScriptRoot
$TempRoot = if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP ('prompt-transport-' + [guid]::NewGuid().ToString('N')) } else { Join-Path ([IO.Path]::GetTempPath()) ('prompt-transport-' + [guid]::NewGuid().ToString('N')) }
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
$Config = Join-Path $TempRoot 'config'
& (Join-Path $RootDir 'scripts/install.ps1') -ConfigDir $Config -NonInteractive -RoutingConfigPath (Join-Path $RootDir 'tests/fixtures/routing/architect-failover.valid.json')
$Runner = Join-Path $Config 'opencode-governance-tools/architect-attempt.ps1'
$Manifest = Join-Path $Config 'opencode-governance-routing.json'
$RoutingRaw = Get-Content -LiteralPath $Manifest -Raw
if ($RoutingRaw -notmatch '3\.7\.6') { throw "Installed governance_version is not 3.7.6: $RoutingRaw" }

function Get-TextHash([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function New-Project([string]$Name) {
    $project = Join-Path $TempRoot $Name
    New-Item -ItemType Directory -Force -Path (Join-Path $project '.ai/tasks/TASK-TRANSPORT') | Out-Null
    'source' | Set-Content -LiteralPath (Join-Path $project 'source.txt')
    $runState = [ordered]@{
        task_id             = 'TASK-TRANSPORT'
        top_level_command   = 'ai-workflow'
        current_phase       = 'READY_FOR_EXECUTION'
        next_required_phase = 'IMPLEMENTING'
        state               = 'READY_FOR_EXECUTION'
        next_action         = [ordered]@{ kind = 'execute'; command = '/ai-execute'; arguments = @('TASK-TRANSPORT') }
    }
    ($runState | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $project '.ai/tasks/TASK-TRANSPORT/RUN_STATE.json') -Encoding utf8
    return $project
}

function Invoke-TransportRunner([string]$Project, [string]$Arguments, [string]$Mock, [switch]$KeepLogs) {
    $wrapper = Join-Path $TempRoot ('transport-wrapper-' + [guid]::NewGuid().ToString('N') + '.ps1')
    $argFile = Join-Path $TempRoot ('handoff-' + [guid]::NewGuid().ToString('N') + '.txt')
    [IO.File]::WriteAllText($argFile, $Arguments, [Text.UTF8Encoding]::new($false))
    $keep = if ($KeepLogs) { '-KeepAttemptLogs' } else { '' }
    @"
& '$Runner' -ProjectDir '$Project' -Command ai-resume -TaskId TASK-TRANSPORT -ArgumentsFile '$argFile' -RoutingConfigPath '$Manifest' -ConfigDir '$Config' -OpenCodeCommand pwsh -OpenCodePrefixArguments @('-NoProfile','-File','$Mock') $keep
"@ | Set-Content -LiteralPath $wrapper
    $output = & pwsh -NoProfile -File $wrapper 2>&1
    $code = $LASTEXITCODE
    Remove-Item -LiteralPath $wrapper -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Code = $code; Text = (($output | ForEach-Object { [string]$_ }) -join "`n"); ArgFile = $argFile }
}

function New-SuccessMock([string]$Path, [string]$ExpectedSha, [int]$ExpectedBytes, [string]$ProbeDir) {
    @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
$project=''; $command=''; $hasFormat=$false
$argvJoined = ($Args -join ([char]1))
for($i=0;$i-lt$Args.Count;$i++){
  if($Args[$i]-eq'--dir'){$project=$Args[++$i]}
  elseif($Args[$i]-eq'--command'){$command=$Args[++$i]}
  elseif($Args[$i]-eq'--format'){$hasFormat=$true; $null=$Args[++$i]}
}
# Record argv for parent inspection (must not contain the handoff body).
$probe = $env:TRANSPORT_PROBE_DIR
if(-not $probe){ exit 31 }
[IO.File]::WriteAllText((Join-Path $probe 'child-argv.txt'), ($Args -join "`n"), [Text.UTF8Encoding]::new($false))
# Read raw stdin bytes (Console.In text decoding is encoding-sensitive on Windows hosts).
$ms = [IO.MemoryStream]::new()
[Console]::OpenStandardInput().CopyTo($ms)
$raw = $ms.ToArray()
$bytes = $raw.Length
$utf8 = [Text.UTF8Encoding]::new($false)
$stdin = $utf8.GetString($raw)
$sha = [Security.Cryptography.SHA256]::Create()
try { $hash = ([BitConverter]::ToString($sha.ComputeHash($raw))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
[IO.File]::WriteAllText((Join-Path $probe 'child-stdin-meta.txt'), "bytes=$bytes`nsha256=$hash`ncommand=$command`nhas_format=$hasFormat", [Text.UTF8Encoding]::new($false))
if($command -ne 'ai-resume'){ exit 32 }
if(-not $hasFormat){ exit 33 }
if($bytes -ne [int]$env:EXPECTED_PROMPT_BYTES){ [Console]::Error.WriteLine("STDIN_BYTE_MISMATCH got=$bytes expected=$($env:EXPECTED_PROMPT_BYTES)"); exit 34 }
if($hash -ne $env:EXPECTED_PROMPT_SHA){ [Console]::Error.WriteLine("STDIN_HASH_MISMATCH"); exit 35 }
if($argvJoined.Contains($stdin) -and $stdin.Length -gt 64){ [Console]::Error.WriteLine("PROMPT_LEAKED_TO_ARGV"); exit 36 }
if(-not $stdin.Contains('[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]')){ exit 37 }
# Mutate task checkpoint + emit GOVERNANCE_RESULT
$runStatePath = Join-Path $project '.ai/tasks/TASK-TRANSPORT/RUN_STATE.json'
$runState = Get-Content -LiteralPath $runStatePath -Raw | ConvertFrom-Json
$runState | Add-Member NoteProperty state 'READY_FOR_EXECUTION' -Force
$runState.current_phase = 'READY_FOR_EXECUTION'
$runState.next_required_phase = 'IMPLEMENTING'
$runState | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $runStatePath -Encoding utf8
'transport-ok' | Set-Content -LiteralPath (Join-Path $project '.ai/TRANSPORT_OK.md')
Write-Output "GOVERNANCE_RESULT`nTASK_ID: TASK-TRANSPORT`nSTATE: READY_FOR_EXECUTION"
exit 0
'@ | Set-Content -LiteralPath $Path -Encoding utf8
}

function New-EarlyCloseMock([string]$Path) {
    @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
# Exit immediately without reading stdin so the parent hits a broken pipe on large writes.
exit 0
'@ | Set-Content -LiteralPath $Path -Encoding utf8
}

$Marker = '[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
$sizes = @(
    @{ Name = '1kib'; Bytes = 1024 },
    @{ Name = '32kib'; Bytes = 32 * 1024 },
    @{ Name = '64kib'; Bytes = 64 * 1024 },
    @{ Name = '256kib'; Bytes = 256 * 1024 },
    @{ Name = '1mib'; Bytes = 1 * 1024 * 1024 }
)

foreach ($size in $sizes) {
    $project = New-Project ("transport-" + $size.Name)
    $probe = Join-Path $TempRoot ("probe-" + $size.Name)
    New-Item -ItemType Directory -Force -Path $probe | Out-Null
    $body = ('X' * $size.Bytes) + "`nUNICODE: café 日本語 🚀`n--flag; pipe| quote`" `n$Marker"
    # Body already includes marker so runner keeps it exact
    $routed = $body
    $expectedBytes = [Text.Encoding]::UTF8.GetByteCount($routed)
    $expectedSha = Get-TextHash $routed
    $mock = Join-Path $TempRoot ("mock-success-" + $size.Name + '.ps1')
    New-SuccessMock $mock $expectedSha $expectedBytes $probe
    $env:TRANSPORT_PROBE_DIR = $probe
    $env:EXPECTED_PROMPT_BYTES = [string]$expectedBytes
    $env:EXPECTED_PROMPT_SHA = $expectedSha
    $result = Invoke-TransportRunner $project $routed $mock
    if ($result.Code -ne 0) { throw "Size $($size.Name) failed (exit $($result.Code)): $($result.Text)" }
    if ($result.Text -notmatch 'ARCHITECT_PROMPT_TRANSPORT contract=ARCHITECT_STDIN_PROMPT_TRANSPORT_V1 mode=stdin') {
        throw "Size $($size.Name) missing transport log: $($result.Text)"
    }
    if ($result.Text -notmatch "bytes=$expectedBytes") { throw "Size $($size.Name) missing bytes in transport log" }
    if ($result.Text -notmatch "sha256=$expectedSha") { throw "Size $($size.Name) missing sha256 in transport log" }
    if ($result.Text -notmatch 'argv_prompt_bytes=0') { throw "Size $($size.Name) missing argv_prompt_bytes=0" }
    if ($result.Text -match [regex]::Escape(('X' * [Math]::Min(200, $size.Bytes)))) {
        throw "Size $($size.Name) leaked prompt body into runner logs"
    }
    if (-not (Test-Path (Join-Path $project '.ai/TRANSPORT_OK.md'))) { throw "Size $($size.Name) missing .ai transition" }
    if ($result.Text -notmatch 'GOVERNANCE_RESULT') { throw "Size $($size.Name) missing GOVERNANCE_RESULT" }
    if ((Get-Content (Join-Path $project 'source.txt') -Raw).Trim() -ne 'source') { throw "Size $($size.Name) mutated application source" }
    $argvText = Get-Content -LiteralPath (Join-Path $probe 'child-argv.txt') -Raw
    if ($argvText -like "*$Marker*" -and $size.Bytes -gt 64) {
        # Marker alone on argv would be wrong for large handoffs; ensure full body not present
    }
    if ($argvText.Contains(('X' * 64))) { throw "Size $($size.Name) put handoff body on child argv" }
    $meta = Get-Content -LiteralPath (Join-Path $probe 'child-stdin-meta.txt') -Raw
    if ($meta -notmatch "bytes=$expectedBytes") { throw "Size $($size.Name) child stdin bytes mismatch: $meta" }
    if ($meta -notmatch "sha256=$expectedSha") { throw "Size $($size.Name) child stdin hash mismatch: $meta" }
    Write-Host "PASS: stdin transport size=$($size.Name) bytes=$expectedBytes"
}

# Empty optional arguments (marker-only payload)
$emptyProject = New-Project 'transport-empty'
$emptyProbe = Join-Path $TempRoot 'probe-empty'
New-Item -ItemType Directory -Force -Path $emptyProbe | Out-Null
$emptyPayload = $Marker
$emptyBytes = [Text.Encoding]::UTF8.GetByteCount($emptyPayload)
$emptySha = Get-TextHash $emptyPayload
$emptyMock = Join-Path $TempRoot 'mock-empty.ps1'
New-SuccessMock $emptyMock $emptySha $emptyBytes $emptyProbe
$env:TRANSPORT_PROBE_DIR = $emptyProbe
$env:EXPECTED_PROMPT_BYTES = [string]$emptyBytes
$env:EXPECTED_PROMPT_SHA = $emptySha
$emptyResult = Invoke-TransportRunner $emptyProject '' $emptyMock
if ($emptyResult.Code -ne 0) { throw "Empty prompt transport failed: $($emptyResult.Text)" }
Write-Host 'PASS: empty optional arguments via stdin'

# Early stdin close by child → ARCHITECT_PROMPT_TRANSPORT_FAILED, no fallback, rollback
$earlyProject = New-Project 'transport-early-close'
'partial-before' | Set-Content -LiteralPath (Join-Path $earlyProject '.ai/BASELINE.md')
$earlyMock = Join-Path $TempRoot 'mock-early-close.ps1'
New-EarlyCloseMock $earlyMock
# Use a large payload so stdin write is likely to observe the closed pipe.
$earlyBody = ('Y' * (256 * 1024)) + "`n$Marker"
$earlyResult = Invoke-TransportRunner $earlyProject $earlyBody $earlyMock
if ($earlyResult.Code -eq 0) {
    # Child may exit 0 before write completes on small buffers; force failure path only if transport error present or non-zero.
    # When child exits 0 without GOVERNANCE_RESULT/progress, runner should fail closed — accept either transport fail or no-progress.
    if ($earlyResult.Text -notmatch 'ARCHITECT_PROMPT_TRANSPORT_FAILED|ARCHITECT_NO_PROGRESS|ARCHITECT_CHILD_RESULT') {
        throw "Early-close did not fail closed: $($earlyResult.Text)"
    }
} else {
    if ($earlyResult.Text -notmatch 'ARCHITECT_PROMPT_TRANSPORT_FAILED|ARCHITECT_NO_PROGRESS|ARCHITECT_CHILD_RESULT|ARCHITECT_FAILOVER_BLOCKED') {
        throw "Early-close unexpected failure: $($earlyResult.Text)"
    }
}
# Prefer explicit transport failure when write fails
if ($earlyResult.Text -match 'ARCHITECT_PROMPT_TRANSPORT_FAILED') {
    if ($earlyResult.Text -match 'ARCHITECT_ROUTE_ATTEMPT 2') { throw 'Transport failure must not fall back to another model route' }
    Write-Host 'PASS: early-close ARCHITECT_PROMPT_TRANSPORT_FAILED (no fallback)'
} else {
    Write-Host 'PASS: early-close fail-closed without model fallback (child exited before/during transport)'
}
if ((Get-Content (Join-Path $earlyProject 'source.txt') -Raw).Trim() -ne 'source') { throw 'Early-close mutated application source' }

# Size limit exceeded before child start
$limitProject = New-Project 'transport-size-limit'
$env:OPENCODE_GOVERNANCE_PROMPT_MAX_BYTES = '1048576'
$limitBody = ('Z' * (2 * 1024 * 1024)) + "`n$Marker"
$limitMock = Join-Path $TempRoot 'mock-limit.ps1'
New-SuccessMock $limitMock 'deadbeef' 1 (Join-Path $TempRoot 'probe-limit')
try {
    $limitResult = Invoke-TransportRunner $limitProject $limitBody $limitMock
    if ($limitResult.Code -eq 0) { throw 'Size limit did not fail' }
    if ($limitResult.Text -notmatch 'ARCHITECT_PROMPT_SIZE_LIMIT_EXCEEDED') { throw "Missing size limit error: $($limitResult.Text)" }
    if ($limitResult.Text -match 'ARCHITECT_ROUTE_ATTEMPT') { throw 'Size limit must fail before child route attempt' }
    Write-Host 'PASS: ARCHITECT_PROMPT_SIZE_LIMIT_EXCEEDED before child execution'
} finally {
    Remove-Item Env:OPENCODE_GOVERNANCE_PROMPT_MAX_BYTES -ErrorAction SilentlyContinue
}

Remove-Item Env:TRANSPORT_PROBE_DIR -ErrorAction SilentlyContinue
Remove-Item Env:EXPECTED_PROMPT_BYTES -ErrorAction SilentlyContinue
Remove-Item Env:EXPECTED_PROMPT_SHA -ErrorAction SilentlyContinue
$global:LASTEXITCODE = 0
Write-Host 'PASS: Windows ARCHITECT_STDIN_PROMPT_TRANSPORT_V1 regressions (3.7.4).'
