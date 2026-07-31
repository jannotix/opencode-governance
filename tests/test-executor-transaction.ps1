param(
    [string]$Helper = (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\executor-attempt.ps1')
)

$ErrorActionPreference = 'Stop'
$Root = Join-Path ([System.IO.Path]::GetTempPath()) ('opencode-executor-' + [Guid]::NewGuid().ToString('N'))
$Config = Join-Path $Root 'config'
$Project = Join-Path $Root 'project'

function Get-Sha256Text([string]$Text) {
    $Algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($Algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    } finally {
        $Algorithm.Dispose()
    }
}

try {
    New-Item -ItemType Directory -Force -Path $Config, $Project | Out-Null
    @'
{
  "schema_version": "1.0",
  "settings": {
    "enabled_roles": ["executor"],
    "default_cooldown_seconds": 60
  },
  "roles": {
    "executor": {
      "primary": {
        "model": "test/primary",
        "variant": "high",
        "model_family": "family-a",
        "only_on": [],
        "work_classes": ["PATCH", "HIGH_RISK_CHANGE"]
      },
      "fallbacks": [
        {
          "priority": 1,
          "model": "test/fallback-one",
          "variant": "high",
          "model_family": "family-a",
          "only_on": ["RATE_LIMIT", "PROVIDER_UNAVAILABLE"],
          "work_classes": ["PATCH"]
        },
        {
          "priority": 2,
          "model": "test/fallback-two",
          "variant": "high",
          "model_family": "family-b",
          "only_on": ["MODEL_RETIRED", "MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS"],
          "work_classes": ["PATCH", "HIGH_RISK_CHANGE"]
        }
      ]
    }
  }
}
'@ | Set-Content (Join-Path $Config 'opencode-governance-routing.json') -Encoding utf8

    $Primary = & $Helper -Operation select -ConfigDir $Config -WorkClass PATCH | ConvertFrom-Json
    $RateLimit = & $Helper -Operation select -ConfigDir $Config -WorkClass PATCH -FailureClass RATE_LIMIT -FailedRoute executor -AttemptedRoute executor | ConvertFrom-Json
    $Retired = & $Helper -Operation select -ConfigDir $Config -WorkClass PATCH -FailureClass MODEL_RETIRED -FailedRoute executor -AttemptedRoute executor | ConvertFrom-Json
    if ($Primary.route_agent -ne 'executor') { throw 'Primary Executor route not selected.' }
    if ($RateLimit.route_agent -ne 'executor-fallback-1') { throw 'Same-family fallback not selected.' }
    if ($Retired.route_agent -ne 'executor-fallback-2') { throw 'Cross-family fallback not selected.' }

    git -C $Project init -q
    git -C $Project config user.name Test
    git -C $Project config user.email test@example.invalid
    'base' | Set-Content (Join-Path $Project 'app.txt')
    'unrelated' | Set-Content (Join-Path $Project 'unrelated.txt')
    git -C $Project add .
    git -C $Project commit -qm base
    $Frozen = (git -C $Project rev-parse HEAD).Trim()
    $Packet = Get-Sha256Text 'packet'

    $Prepare = & $Helper -Operation prepare -ProjectDir $Project -ConfigDir $Config -TaskId TASK -AttemptId locked -FrozenTarget $Frozen -WorkClass PATCH -RouteAgent executor -PacketSha256 $Packet | ConvertFrom-Json
    $Worktree = [string]$Prepare.execution_root
    'promoted' | Set-Content (Join-Path $Worktree 'app.txt')
    $Report = Join-Path $Project '.ai\tasks\TASK\evidence\executor-attempts\report.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $Report -Parent) | Out-Null
    [ordered]@{
        EXECUTOR_ATTEMPT_ID = 'locked'
        PACKET_SHA256 = $Packet
        FROZEN_TARGET_SHA = $Frozen
        REPORT_COMPLETE = 'YES'
    } | ConvertTo-Json | Set-Content $Report -Encoding utf8

    & $Helper -Operation finalize -ProjectDir $Project -ConfigDir $Config -TaskId TASK -AttemptId locked -ReportPath $Report | Out-Null
    git -C $Project worktree lock $Worktree --reason transaction-test
    $Result = & $Helper -Operation promote -ProjectDir $Project -ConfigDir $Config -TaskId TASK -AttemptId locked | ConvertFrom-Json
    if ($Result.state -ne 'PROMOTED') { throw 'Promotion state was not persisted.' }
    if ($Result.cleanup_status -ne 'WARNING') { throw 'Locked worktree cleanup did not produce a warning.' }
    if ((Get-Content (Join-Path $Project 'app.txt') -Raw).Trim() -ne 'promoted') { throw 'Promoted patch is missing.' }

    $Manifest = Get-Content (Join-Path $Project '.ai\tasks\TASK\evidence\executor-attempts\locked.json') -Raw | ConvertFrom-Json
    if ($Manifest.state -ne 'PROMOTED') { throw 'Durable manifest is not PROMOTED.' }

    $DiscardFailed = $false
    try {
        & $Helper -Operation discard -ProjectDir $Project -ConfigDir $Config -TaskId TASK -AttemptId locked | Out-Null
    } catch {
        $DiscardFailed = $_.Exception.Message -match 'cannot be discarded'
    }
    if (-not $DiscardFailed) { throw 'Promoted attempt was incorrectly discardable.' }

    git -C $Project worktree unlock $Worktree
    git -C $Project worktree remove --force $Worktree
    Write-Host 'PASS: Windows Executor routing and transactional promotion'
} finally {
    if (Test-Path $Root) { Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue }
}
