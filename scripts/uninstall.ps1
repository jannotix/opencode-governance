$ErrorActionPreference = 'Stop'
$ConfigDir = if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $HOME '.config\opencode' }
@(
  'agents\architect.md','agents\executor.md','agents\reviewer.md',
  'commands\ai-init.md','commands\ai-plan.md','commands\ai-execute.md','commands\ai-review.md','commands\ai-workflow.md','commands\ai-status.md','commands\ai-release.md'
) | ForEach-Object {
    $Path = Join-Path $ConfigDir $_
    if (Test-Path $Path) { Remove-Item $Path -Force }
}
Write-Host 'Governance agents and commands removed. Existing provider authentication, project .ai state and backups were left untouched.'
Write-Host 'Review default_agent in your OpenCode config if you want to change it from architect.'
