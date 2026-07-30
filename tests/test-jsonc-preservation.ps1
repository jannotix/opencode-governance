$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Temp=Join-Path ([IO.Path]::GetTempPath()) ('opencode-jsonc-windows-'+[guid]::NewGuid().ToString('N'))
$Target=Join-Path $Temp 'opencode.jsonc'
try{
  New-Item -ItemType Directory -Force -Path $Temp|Out-Null
  @'
{
  // user comment
  "$schema": "https://opencode.ai/config.json",
  "literal": "keep /* inside string */ and // inside string",
  "nested": {"url": "https://example.test/a//b",},
}
'@|Set-Content -LiteralPath $Target -Encoding utf8NoBOM

  & (Join-Path $Root 'scripts/install.ps1') `
    -ConfigDir $Temp `
    -NonInteractive `
    -ArchitectModel 'test/architect' `
    -ArchitectVariant 'max' `
    -ExecutorModel 'test/executor' `
    -ReviewerImplementationModel 'test/reviewer' `
    -ReviewerImplementationVariant 'thinking' `
    -ReviewerArchitectureModel 'test/architecture' `
    -ReviewerArchitectureVariant 'high' `
    -FinalReviewerModel 'test/final' `
    -FinalReviewerVariant 'thinking'|Out-Null

  $Value=Get-Content -LiteralPath $Target -Raw|ConvertFrom-Json
  if($Value.literal-ne'keep /* inside string */ and // inside string'){throw 'JSONC string literal was corrupted.'}
  if($Value.nested.url-ne'https://example.test/a//b'){throw 'JSONC URL literal was corrupted.'}
  if($Value.default_agent-ne'architect'){throw 'default_agent was not configured.'}
  Write-Host 'PASS: Windows JSONC semantic preservation'
}finally{
  Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
  $global:LASTEXITCODE=0
}
