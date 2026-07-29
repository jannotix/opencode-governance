$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$RootDir=Split-Path -Parent $PSScriptRoot
$TempRoot=if($env:RUNNER_TEMP){$env:RUNNER_TEMP}else{Join-Path ([IO.Path]::GetTempPath()) ('opencode-v334-tests-'+[guid]::NewGuid().ToString('N'))}
$Config=Join-Path $TempRoot 'opencode-v334-windows'
& (Join-Path $RootDir 'scripts/install.ps1') -ConfigDir $Config -NonInteractive -RoutingConfigPath (Join-Path $RootDir 'tests/fixtures/routing/architect-failover.valid.json')
$Runner=Join-Path $Config 'opencode-governance-tools/architect-attempt.ps1'
$Manifest=Join-Path $Config 'opencode-governance-routing.json'

function Invoke-RunnerProcess([string]$Project,[string]$Label,[string]$Mock){
    $wrapper=Join-Path $TempRoot ('v334-wrapper-'+[guid]::NewGuid().ToString('N')+'.ps1')
    @"
& '$Runner' -ProjectDir '$Project' -Command ai-init -Arguments '$Label' -RoutingConfigPath '$Manifest' -ConfigDir '$Config' -OpenCodeCommand pwsh -OpenCodePrefixArguments @('-NoProfile','-File','$Mock')
"@ | Set-Content -LiteralPath $wrapper
    $output=& pwsh -NoProfile -File $wrapper 2>&1
    $code=$LASTEXITCODE
    Remove-Item -LiteralPath $wrapper -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{Code=$code;Text=(($output|ForEach-Object{[string]$_})-join"`n")}
}

foreach($mode in 'dirty','untracked','staged'){
    $project=Join-Path $TempRoot "v334-windows-$mode"
    $mock=Join-Path $TempRoot "v334-windows-$mode-mock.ps1"
    New-Item -ItemType Directory -Force -Path (Join-Path $project '.ai')|Out-Null
    git -C $project init -q
    if($mode-ne'untracked'){
        git -C $project config user.email test@example.invalid
        git -C $project config user.name Test
        'base'|Set-Content (Join-Path $project 'source.txt')
        git -C $project add source.txt
        git -C $project commit -qm base
    }
    if($mode-eq'dirty'){'dirty-before'|Set-Content (Join-Path $project 'source.txt')}
    elseif($mode-eq'untracked'){'untracked-before'|Set-Content (Join-Path $project 'source.txt')}
    else{'staged-before'|Set-Content (Join-Path $project 'source.txt');git -C $project add source.txt}
    $before=(git -C $project status --porcelain=v1 --untracked-files=all)-join"`n"
@'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
$project=''
for($i=0;$i-lt$Args.Count;$i++){if($Args[$i]-eq'--dir'){$project=$Args[++$i]}}
if($env:TEST_MODE-eq'dirty'){'dirty-after'|Set-Content (Join-Path $project 'source.txt')}
elseif($env:TEST_MODE-eq'untracked'){'untracked-after'|Set-Content (Join-Path $project 'source.txt')}
else{'staged-after'|Set-Content (Join-Path $project 'source.txt');git -C $project add source.txt}
exit 0
'@ | Set-Content -LiteralPath $mock
    $env:TEST_MODE=$mode
    $result=Invoke-RunnerProcess $project "$mode-content-test" $mock
    $after=(git -C $project status --porcelain=v1 --untracked-files=all)-join"`n"
    if($before-ne$after){throw "$mode test did not preserve the same porcelain classification"}
    if($result.Code-eq 0){throw "$mode content mutation escaped detection"}
    if($result.Text-notmatch'PROJECT_STATE_CHANGED'){throw "$mode did not return PROJECT_STATE_CHANGED. Output: $($result.Text)"}
}

$safe=Join-Path $TempRoot 'v334-windows-nongit-safe'
$safeMock=Join-Path $TempRoot 'v334-windows-nongit-safe-mock.ps1'
$state=Join-Path $TempRoot 'v334-windows-nongit-count'
New-Item -ItemType Directory -Force -Path (Join-Path $safe '.ai')|Out-Null
'original'|Set-Content (Join-Path $safe '.ai/BASELINE.md')
'source'|Set-Content (Join-Path $safe 'source.txt')
@'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
$project='';$model=''
for($i=0;$i-lt$Args.Count;$i++){if($Args[$i]-eq'--dir'){$project=$Args[++$i]}elseif($Args[$i]-eq'--model'){$model=$Args[++$i]}}
$count=if(Test-Path $env:MOCK_STATE){[int](Get-Content $env:MOCK_STATE)}else{0};($count+1)|Set-Content $env:MOCK_STATE
if($model-eq'test/architect-primary'){'partial'|Set-Content (Join-Path $project '.ai/partial.txt');[Console]::Error.WriteLine('rate limit 429');exit 1}
if(Test-Path (Join-Path $project '.ai/partial.txt')){exit 23}
if((Get-Content (Join-Path $project '.ai/BASELINE.md'))-ne'original'){exit 24}
'success'|Set-Content (Join-Path $project '.ai/success.txt')
exit 0
'@ | Set-Content -LiteralPath $safeMock
$env:MOCK_STATE=$state
$result=Invoke-RunnerProcess $safe nongit-safe-test $safeMock
if($result.Code-ne 0){throw "Safe non-Git retry failed: $($result.Text)"}
if([int](Get-Content $state)-ne 2){throw 'Safe non-Git retry did not use fallback'}
if((Get-Content (Join-Path $safe 'source.txt'))-ne'source'){throw 'Safe non-Git source changed'}
if(-not(Test-Path (Join-Path $safe '.ai/success.txt'))){throw 'Safe non-Git fallback did not complete'}

$mutate=Join-Path $TempRoot 'v334-windows-nongit-mutate'
$mutateMock=Join-Path $TempRoot 'v334-windows-nongit-mutate-mock.ps1'
New-Item -ItemType Directory -Force -Path (Join-Path $mutate '.ai')|Out-Null
'source-before'|Set-Content (Join-Path $mutate 'source.txt')
@'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
$project=''
for($i=0;$i-lt$Args.Count;$i++){if($Args[$i]-eq'--dir'){$project=$Args[++$i]}}
'source-after'|Set-Content (Join-Path $project 'source.txt')
exit 0
'@ | Set-Content -LiteralPath $mutateMock
$result=Invoke-RunnerProcess $mutate nongit-mutation-test $mutateMock
if($result.Code-eq 0){throw 'Non-Git source mutation escaped detection'}
if($result.Text-notmatch'PROJECT_STATE_CHANGED'){throw "Non-Git source mutation did not return PROJECT_STATE_CHANGED. Output: $($result.Text)"}
$global:LASTEXITCODE=0
Write-Host 'PASS: Windows project-state integrity regressions.'
