param([string]$ConfigDir)

$ErrorActionPreference = 'Stop'
if (-not $ConfigDir) {
    $ConfigDir = if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $HOME '.config\opencode' }
}

$Agents = @('architect','build','plan','executor','reviewer','reviewer-architecture','final-reviewer')
$Commands = @('ai-init','ai-audit','ai-docs','ai-discover','ai-plan','ai-execute','ai-review','ai-workflow','ai-status','ai-resume','ai-metrics','ai-release')
$ManifestPath = Join-Path $ConfigDir 'opencode-governance-routing.json'
$AllowedTools = @(
    (Join-Path $ConfigDir 'opencode-governance-tools\executor-attempt.ps1'),
    (Join-Path $ConfigDir 'opencode-governance-tools\executor-attempt.sh')
)

if (Test-Path $ManifestPath -PathType Leaf) {
    try {
        $Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
    } catch {
        throw 'Routing manifest is invalid; refusing to remove unknown managed files.'
    }
    foreach ($Alias in @($Manifest.managed_aliases)) {
        $AliasName = [string]$Alias
        if ($AliasName -notmatch '^(executor|reviewer|reviewer-architecture|final-reviewer)-fallback-[0-9]+$') {
            throw "Unsafe managed alias in routing manifest: $AliasName"
        }
        $Path = Join-Path $ConfigDir "agents\$AliasName.md"
        if (Test-Path $Path -PathType Leaf) { Remove-Item $Path -Force }
    }
    foreach ($Tool in @($Manifest.managed_tools)) {
        $ToolPath = [string]$Tool
        if ($ToolPath -notin $AllowedTools) { throw "Unsafe managed tool in routing manifest: $ToolPath" }
        if (Test-Path $ToolPath -PathType Leaf) { Remove-Item $ToolPath -Force }
    }
    $ToolsDir = Join-Path $ConfigDir 'opencode-governance-tools'
    if (Test-Path $ToolsDir -PathType Container) {
        $Remaining = @(Get-ChildItem $ToolsDir -Force)
        if ($Remaining.Count -eq 0) { Remove-Item $ToolsDir -Force }
    }
    Remove-Item $ManifestPath -Force
}

foreach ($Name in $Agents) {
    $Path = Join-Path $ConfigDir "agents\$Name.md"
    if (Test-Path $Path) { Remove-Item $Path -Force }
}
foreach ($Name in $Commands) {
    $Path = Join-Path $ConfigDir "commands\$Name.md"
    if (Test-Path $Path) { Remove-Item $Path -Force }
}

Write-Host 'Removed OpenCode Governance public agents, commands, managed hidden routes, managed Executor tools and routing manifest. Provider authentication, config, project .ai state, project documentation, backups and unrelated files were preserved.'
