param([string]$ConfigDir = $(if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $HOME '.config\opencode' }))
$ErrorActionPreference = 'Stop'
foreach ($Name in @('architect','executor','reviewer')) {
    $Path = Join-Path $ConfigDir "agents\$Name.md"
    if (-not (Test-Path $Path) -or (Get-Item $Path).Length -eq 0) { throw "Missing agent: $Name" }
    $Text = Get-Content $Path -Raw
    if ($Text -notmatch '(?m)^model:\s+\S+') { throw "Missing model in $Path" }
    if ($Text -match '__[A-Z_]+__') { throw "Unrendered placeholder in $Path" }
}
foreach ($Name in @('ai-init','ai-plan','ai-execute','ai-review','ai-workflow','ai-status','ai-release')) {
    $Path = Join-Path $ConfigDir "commands\$Name.md"
    if (-not (Test-Path $Path) -or (Get-Item $Path).Length -eq 0) { throw "Missing command: $Name" }
}
if (Get-Command opencode -ErrorAction SilentlyContinue) { & opencode debug config | Out-Null }
Write-Host 'Verification PASS'
