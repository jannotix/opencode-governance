$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Temp=Join-Path ([IO.Path]::GetTempPath()) ('opencode-jsonc-readable-windows-'+[guid]::NewGuid().ToString('N'))
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

  & (Join-Path $Root 'scripts/normalize-jsonc.ps1') -Path $Target -SetDefaultAgent
  $Raw=Get-Content -LiteralPath $Target -Raw
  if($Raw-notlike'*https://opencode.ai/config.json*'){throw 'Schema URL was escaped during normalization.'}
  if($Raw-notlike'*https://example.test/a//b*'){throw 'Nested URL was escaped during normalization.'}
  if($Raw-like'*\u002f*'){throw 'JSONC contains unnecessary escaped slash sequences.'}
  $Value=$Raw|ConvertFrom-Json
  if($Value.default_agent-ne'architect'){throw 'default_agent was not configured.'}
  Write-Host 'PASS: Windows JSONC remains readable'
}finally{
  Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
  $global:LASTEXITCODE=0
}
