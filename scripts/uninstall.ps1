param([string]$ConfigDir)

$ErrorActionPreference = 'Stop'
if (-not $ConfigDir) {
    $ConfigDir = if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $HOME '.config\opencode' }
}
$ManifestPath = Join-Path $ConfigDir 'opencode-governance-routing.json'
if (Test-Path -LiteralPath $ManifestPath -PathType Leaf) {
    try { $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json } catch { throw 'Routing manifest is invalid; refusing to remove unknown managed files.' }
    if ([string]$Manifest.governance_version -in @('3.3.2','3.3.3')) {
        $ToolsDir = Join-Path $ConfigDir 'opencode-governance-tools'
        $Expected = @(
            (Join-Path $ToolsDir 'architect-attempt.ps1'),
            (Join-Path $ToolsDir 'architect-attempt.sh'),
            (Join-Path $ToolsDir 'executor-attempt.ps1'),
            (Join-Path $ToolsDir 'executor-attempt.sh')
        )
        $Managed = @($Manifest.managed_tools | ForEach-Object { [string]$_ })
        if ($Managed.Count -ne $Expected.Count) { throw "Unsafe managed tool count in v$($Manifest.governance_version) routing manifest." }
        foreach ($Tool in $Expected) { if ($Tool -notin $Managed) { throw "Unsafe managed tool set in v$($Manifest.governance_version) routing manifest: $Tool" } }
        Remove-Item -LiteralPath $Expected[0],$Expected[1] -Force -ErrorAction SilentlyContinue
        $Manifest | Add-Member -MemberType NoteProperty -Name governance_version -Value '3.3.0' -Force
        $Manifest.PSObject.Properties.Remove('architect_runner_version')
        $Manifest | Add-Member -MemberType NoteProperty -Name managed_tools -Value @($Expected[2],$Expected[3]) -Force
        [IO.File]::WriteAllText($ManifestPath, (($Manifest | ConvertTo-Json -Depth 30) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
    }
}
& (Join-Path $PSScriptRoot 'uninstall-core.ps1') -ConfigDir $ConfigDir
