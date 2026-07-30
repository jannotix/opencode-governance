$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Install=Join-Path $Root 'scripts/install.ps1'
$Runner=Join-Path $Root 'scripts/run-governed.ps1'
$Context=Join-Path $Root 'scripts/context-intelligence.ps1'
$Fixture=Join-Path $Root 'tests/fixtures/routing/architect-failover.valid.json'
$Temp=Join-Path ([IO.Path]::GetTempPath()) ('opencode-v342-schema-'+[guid]::NewGuid().ToString('N'))

function Write-Json([string]$Path,[object]$Value){
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)|Out-Null
  [IO.File]::WriteAllText($Path,(($Value|ConvertTo-Json -Depth 40)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
}
function Invoke-Failure([string]$Script,[string[]]$Arguments,[string]$Expected){
  $Output=& pwsh -NoProfile -File $Script @Arguments 2>&1;$Code=$LASTEXITCODE;$Text=$Output-join"`n";$global:LASTEXITCODE=0
  if($Code-eq0){throw "Expected failure from $Script. Output: $Text"}
  if($Text-notlike"*$Expected*"){throw "Expected '$Expected'. Output: $Text"}
}
function Load-Profile{Get-Content -LiteralPath $Fixture -Raw|ConvertFrom-Json}

try{
  New-Item -ItemType Directory -Force -Path $Temp|Out-Null
  $InstallCases=@(
    @{Name='enabled-scalar';Expected='settings.enabled_roles must be an array.';Mutate={param($p)$p.settings.enabled_roles='architect'}},
    @{Name='eligible-scalar';Expected='settings.eligible_failures must be an array.';Mutate={param($p)$p.settings.eligible_failures='RATE_LIMIT'}},
    @{Name='only-on-scalar';Expected='architect primary only_on must be an array.';Mutate={param($p)$p.roles.architect.primary.only_on='RATE_LIMIT'}},
    @{Name='work-class-scalar';Expected='executor primary work_classes must be an array.';Mutate={param($p)$p.roles.executor.primary|Add-Member NoteProperty work_classes 'PATCH' -Force}},
    @{Name='priority-string';Expected='reviewer fallback priority must be a positive integer.';Mutate={param($p)$p.roles.reviewer.fallbacks[0].priority='1'}},
    @{Name='fallback-scalar';Expected='reviewer fallbacks must be an array.';Mutate={param($p)$p.roles.reviewer.fallbacks=$p.roles.reviewer.fallbacks[0]}}
  )
  foreach($Case in $InstallCases){
    $Profile=Load-Profile;& $Case.Mutate $Profile;$Path=Join-Path $Temp "$($Case.Name).json";Write-Json $Path $Profile
    Invoke-Failure $Install @('-ConfigDir',(Join-Path $Temp "config-$($Case.Name)"),'-NonInteractive','-RoutingConfigPath',$Path) $Case.Expected
  }

  $Project=Join-Path $Temp 'project';New-Item -ItemType Directory -Force -Path $Project|Out-Null
  $RunnerCases=@(
    @{Name='runner-enabled-scalar';Expected='settings.enabled_roles must be an array.';Mutate={param($p)$p.settings.enabled_roles='architect'}},
    @{Name='runner-eligible-scalar';Expected='settings.eligible_failures must be an array.';Mutate={param($p)$p.settings.eligible_failures='RATE_LIMIT'}},
    @{Name='runner-cooldown-string';Expected='default cooldown must be an integer';Mutate={param($p)$p.settings.default_cooldown_seconds='300'}},
    @{Name='runner-only-on-scalar';Expected='only_on must be an array.';Mutate={param($p)$p.roles.architect.fallbacks[0].only_on='RATE_LIMIT'}},
    @{Name='runner-priority-string';Expected='priority must be a positive integer.';Mutate={param($p)$p.roles.architect.fallbacks[0].priority='1'}},
    @{Name='runner-fallback-scalar';Expected='architect fallbacks must be an array.';Mutate={param($p)$p.roles.architect.fallbacks=$p.roles.architect.fallbacks[0]}}
  )
  foreach($Case in $RunnerCases){
    $Profile=Load-Profile;& $Case.Mutate $Profile;$Path=Join-Path $Temp "$($Case.Name).json";Write-Json $Path $Profile
    Invoke-Failure $Runner @('-ProjectDir',$Project,'-Command','ai-plan','-Arguments','test','-RoutingConfigPath',$Path,'-ConfigDir',(Join-Path $Temp 'runner-config'),'-OpenCodeCommand','definitely-not-opencode') $Case.Expected
  }

  & $Context -Action InitializeBudget -ProjectDir $Project -TaskId TOKEN-STRING -WorkClass PATCH -CacheRoot (Join-Path $Temp 'cache')|Out-Null
  $Catalog=Join-Path $Temp 'catalog.json';$Criteria=Join-Path $Temp 'criteria.json'
  Write-Json $Catalog @([ordered]@{schema='SKILL_CAPABILITY_MANIFEST_V1';skill_id='token-skill';version='1';content_sha256=('a'*64);source='project';trust_class='PROJECT_AUTHORITATIVE';triggers=@('test');supported_work_classes=@('PATCH');languages=@();frameworks=@();required_tools=@();external_dependencies=@();conflicts_with=@();overlaps_with=@();estimated_context_tokens='100';sections=@()})
  Write-Json $Criteria ([ordered]@{triggers=@('test');languages=@();frameworks=@();required_sections=@();available_tools=@()})
  Invoke-Failure $Context @('-Action','SelectSkills','-ProjectDir',$Project,'-TaskId','TOKEN-STRING','-CatalogPath',$Catalog,'-InputJsonPath',$Criteria,'-CacheRoot',(Join-Path $Temp 'cache')) 'SKILL_TOKEN_ESTIMATE_INVALID'
  Write-Host 'PASS: PowerShell routing schema parity regressions'
}finally{Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue;$global:LASTEXITCODE=0}
