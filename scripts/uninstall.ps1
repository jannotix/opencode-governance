param([string]$ConfigDir)

$ErrorActionPreference='Stop'
if(-not$ConfigDir){$ConfigDir=if($env:OPENCODE_CONFIG_DIR){$env:OPENCODE_CONFIG_DIR}else{Join-Path $HOME '.config/opencode'}}
$ManifestPath=Join-Path $ConfigDir 'opencode-governance-routing.json'
if(Test-Path -LiteralPath $ManifestPath -PathType Leaf){
    try{$Manifest=Get-Content -LiteralPath $ManifestPath -Raw|ConvertFrom-Json}catch{throw 'Routing manifest is invalid; refusing to remove unknown managed files.'}
    $Version=[string]$Manifest.governance_version
    if($Version-in@('3.3.2','3.3.3','3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4','3.4.4')){
        $ToolsDir=Join-Path $ConfigDir 'opencode-governance-tools'
        $Expected=@((Join-Path $ToolsDir 'architect-attempt.ps1'),(Join-Path $ToolsDir 'architect-attempt.sh'),(Join-Path $ToolsDir 'executor-attempt.ps1'),(Join-Path $ToolsDir 'executor-attempt.sh'))
        if($Version-in@('3.4.0','3.4.1','3.4.2','3.4.3','3.4.4')){$Expected+=@((Join-Path $ToolsDir 'context-intelligence.ps1'),(Join-Path $ToolsDir 'context-intelligence.sh'),(Join-Path $ToolsDir 'context-intelligence.py'))}
        if($Version-eq'3.4.4'){$Expected+=(Join-Path $ToolsDir 'workflow-continuation.py')}
        $Managed=@($Manifest.managed_tools|ForEach-Object{[string]$_})
        if($Managed.Count-ne$Expected.Count){throw "Unsafe managed tool count in v$Version routing manifest."}
        foreach($Tool in $Expected){if($Tool-notin$Managed){throw "Unsafe managed tool set in v$Version routing manifest: $Tool"}}
        $Remove=@($Expected[0],$Expected[1]);if($Version-in@('3.4.0','3.4.1','3.4.2','3.4.3','3.4.4')){$Remove+=$Expected[4..6]}
        if($Version-eq'3.4.4'){$Remove+=$Expected[7]}
        Remove-Item -LiteralPath $Remove -Force -ErrorAction SilentlyContinue
        $Manifest|Add-Member NoteProperty governance_version '3.3.0' -Force
        $Manifest.PSObject.Properties.Remove('architect_runner_version');$Manifest.PSObject.Properties.Remove('context_intelligence_version');$Manifest.PSObject.Properties.Remove('workflow_continuation_version')
        $Manifest|Add-Member NoteProperty managed_tools @($Expected[2],$Expected[3]) -Force
        [IO.File]::WriteAllText($ManifestPath,(($Manifest|ConvertTo-Json -Depth 30)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
    }
}
& (Join-Path $PSScriptRoot 'uninstall-core.ps1') -ConfigDir $ConfigDir
