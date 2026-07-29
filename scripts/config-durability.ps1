[CmdletBinding()]
param(
    [ValidateSet('Enable','Snapshot','Verify','Restore','Status')]
    [string]$Action = 'Status',
    [string]$ConfigDir,
    [string]$DurabilityRoot,
    [string]$SnapshotId,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$DurabilityVersion = '3.3.1'
$ExcludedTopLevelDirectories = @('backups', '.durability')

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Resolve-AbsolutePath([string]$Path, [string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw "$Name is required." }
    $Expanded = [Environment]::ExpandEnvironmentVariables($Path)
    return [System.IO.Path]::GetFullPath($Expanded).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Resolve-ConfigDirectory([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        $Value = if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $HOME '.config\opencode' }
    }
    return Resolve-AbsolutePath $Value 'ConfigDir'
}

function Resolve-DurabilityDirectory([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        if ($env:LOCALAPPDATA) {
            $Value = Join-Path $env:LOCALAPPDATA 'OpenCodeGovernance\config-durability'
        } else {
            $Value = Join-Path $HOME '.local\share\opencode-governance\config-durability'
        }
    }
    return Resolve-AbsolutePath $Value 'DurabilityRoot'
}

function Test-SameOrChild([string]$Parent, [string]$Candidate) {
    if ($Parent.Equals($Candidate, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    $Prefix = $Parent + [System.IO.Path]::DirectorySeparatorChar
    return $Candidate.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-NonOverlappingRoots([string]$ResolvedConfigDir, [string]$ResolvedDurabilityRoot) {
    if ((Test-SameOrChild $ResolvedConfigDir $ResolvedDurabilityRoot) -or (Test-SameOrChild $ResolvedDurabilityRoot $ResolvedConfigDir)) {
        throw 'ConfigDir and DurabilityRoot must not overlap.'
    }
}

function Get-RelativePath([string]$Root, [string]$FullName) {
    $Prefix = $Root + [System.IO.Path]::DirectorySeparatorChar
    if (-not $FullName.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escaped protected root: $FullName"
    }
    return $FullName.Substring($Prefix.Length).Replace('\', '/')
}

function Assert-SafeRelativePath([string]$RelativePath, [string]$Root, [string]$Context) {
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { throw "$Context is blank." }
    if ([System.IO.Path]::IsPathRooted($RelativePath)) { throw "$Context must be relative: $RelativePath" }

    $Normalized = $RelativePath.Replace('\', '/')
    $Segments = @($Normalized -split '/')
    if ($Segments.Count -eq 0 -or @($Segments | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
        throw "$Context contains an unsafe segment: $RelativePath"
    }

    $Native = $Normalized.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $Candidate = [System.IO.Path]::GetFullPath((Join-Path $Root $Native))
    if (-not (Test-SameOrChild $Root $Candidate) -or $Candidate.Equals($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Context escaped its root: $RelativePath"
    }
    return $Normalized
}

function Test-ReparsePoint([System.IO.FileSystemInfo]$Item) {
    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-ProtectedFiles([string]$ResolvedConfigDir) {
    if (-not (Test-Path -LiteralPath $ResolvedConfigDir -PathType Container)) { return @() }

    $Files = New-Object System.Collections.Generic.List[object]
    $Pending = New-Object System.Collections.Generic.Stack[string]
    $Pending.Push($ResolvedConfigDir)

    while ($Pending.Count -gt 0) {
        $Directory = $Pending.Pop()
        foreach ($Item in @(Get-ChildItem -LiteralPath $Directory -Force -ErrorAction Stop)) {
            if (Test-ReparsePoint $Item) {
                throw "Reparse points are not allowed in protected configuration: $($Item.FullName)"
            }

            $Relative = Get-RelativePath $ResolvedConfigDir $Item.FullName
            $TopLevel = ($Relative -split '/')[0]
            if ($Item.PSIsContainer) {
                if ($Directory -eq $ResolvedConfigDir -and $TopLevel -in $ExcludedTopLevelDirectories) { continue }
                $Pending.Push($Item.FullName)
                continue
            }

            $Files.Add([pscustomobject]@{
                full_name = $Item.FullName
                path = $Relative
                length = [int64]$Item.Length
                sha256 = (Get-FileHash -LiteralPath $Item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            })
        }
    }

    return @($Files | Sort-Object path)
}

function Get-ProtectedDirectories([string]$ResolvedConfigDir) {
    if (-not (Test-Path -LiteralPath $ResolvedConfigDir -PathType Container)) { return @() }

    $Directories = New-Object System.Collections.Generic.List[object]
    $Pending = New-Object System.Collections.Generic.Stack[string]
    $Pending.Push($ResolvedConfigDir)

    while ($Pending.Count -gt 0) {
        $Directory = $Pending.Pop()
        foreach ($Item in @(Get-ChildItem -LiteralPath $Directory -Directory -Force -ErrorAction Stop)) {
            if (Test-ReparsePoint $Item) {
                throw "Reparse points are not allowed in protected configuration: $($Item.FullName)"
            }
            $Relative = Get-RelativePath $ResolvedConfigDir $Item.FullName
            $TopLevel = ($Relative -split '/')[0]
            if ($Directory -eq $ResolvedConfigDir -and $TopLevel -in $ExcludedTopLevelDirectories) { continue }
            $Directories.Add([pscustomobject]@{ full_name = $Item.FullName; path = $Relative })
            $Pending.Push($Item.FullName)
        }
    }

    return @($Directories | Sort-Object { $_.full_name.Length } -Descending)
}

function Get-SnapshotDirectory([string]$ResolvedDurabilityRoot, [string]$Id, [string]$Collection = 'snapshots') {
    if ([string]::IsNullOrWhiteSpace($Id) -or $Id -notmatch '^[A-Za-z0-9._-]+$') { throw 'SnapshotId is invalid.' }
    return Join-Path (Join-Path $ResolvedDurabilityRoot $Collection) $Id
}

function Get-LatestSnapshotId([string]$ResolvedDurabilityRoot) {
    $Snapshots = Join-Path $ResolvedDurabilityRoot 'snapshots'
    if (-not (Test-Path -LiteralPath $Snapshots -PathType Container)) { return $null }
    $Latest = Get-ChildItem -LiteralPath $Snapshots -Directory -Force | Sort-Object Name -Descending | Select-Object -First 1
    if ($Latest) { return $Latest.Name }
    return $null
}

function New-Snapshot(
    [string]$ResolvedConfigDir,
    [string]$ResolvedDurabilityRoot,
    [string]$Collection = 'snapshots'
) {
    Assert-NonOverlappingRoots $ResolvedConfigDir $ResolvedDurabilityRoot
    New-Item -ItemType Directory -Force -Path $ResolvedConfigDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $ResolvedDurabilityRoot $Collection) | Out-Null

    $Id = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'), ([Guid]::NewGuid().ToString('N').Substring(0, 8))
    $SnapshotDirectory = Get-SnapshotDirectory $ResolvedDurabilityRoot $Id $Collection
    $CopyRoot = Join-Path $SnapshotDirectory 'config'
    New-Item -ItemType Directory -Force -Path $CopyRoot | Out-Null

    $Entries = @()
    foreach ($File in @(Get-ProtectedFiles $ResolvedConfigDir)) {
        $Destination = Join-Path $CopyRoot ($File.path.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        $Parent = Split-Path -Parent $Destination
        if ($Parent) { New-Item -ItemType Directory -Force -Path $Parent | Out-Null }
        Copy-Item -LiteralPath $File.full_name -Destination $Destination -Force
        $Entries += [ordered]@{
            path = $File.path
            length = $File.length
            sha256 = $File.sha256
        }
    }

    $Manifest = [ordered]@{
        schema_version = '1.0'
        durability_version = $DurabilityVersion
        snapshot_id = $Id
        collection = $Collection
        created_at = (Get-Date).ToUniversalTime().ToString('o')
        config_dir = $ResolvedConfigDir
        files = $Entries
    }
    Write-Utf8NoBom (Join-Path $SnapshotDirectory 'manifest.json') (($Manifest | ConvertTo-Json -Depth 20) + [Environment]::NewLine)

    return [pscustomobject]@{
        action = 'Snapshot'
        config_dir = $ResolvedConfigDir
        durability_root = $ResolvedDurabilityRoot
        snapshot_id = $Id
        collection = $Collection
        file_count = $Entries.Count
        match = $true
        added = @()
        removed = @()
        changed = @()
    }
}

function Read-SnapshotManifest([string]$ResolvedDurabilityRoot, [string]$Id, [string]$Collection = 'snapshots') {
    $Directory = Get-SnapshotDirectory $ResolvedDurabilityRoot $Id $Collection
    $ManifestPath = Join-Path $Directory 'manifest.json'
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Snapshot manifest not found: $ManifestPath" }
    try { $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json } catch { throw "Snapshot manifest is invalid: $ManifestPath" }
    if ([string]$Manifest.schema_version -ne '1.0') { throw 'Unsupported snapshot schema_version.' }
    if ([string]$Manifest.snapshot_id -ne $Id) { throw 'Snapshot manifest ID mismatch.' }
    if ([string]$Manifest.collection -ne $Collection) { throw 'Snapshot manifest collection mismatch.' }
    return [pscustomobject]@{ directory = $Directory; manifest = $Manifest }
}

function Get-ValidatedManifestEntries([object]$Manifest, [string]$CopyRoot) {
    $Entries = @()
    $Seen = @{}
    foreach ($Entry in @($Manifest.files)) {
        $Path = Assert-SafeRelativePath ([string]$Entry.path) $CopyRoot 'Snapshot manifest path'
        if ($Seen.ContainsKey($Path)) { throw "Snapshot manifest contains a duplicate path: $Path" }
        if ([int64]$Entry.length -lt 0) { throw "Snapshot manifest contains a negative length: $Path" }
        if ([string]$Entry.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw "Snapshot manifest contains an invalid SHA-256: $Path" }
        $Seen[$Path] = $true
        $Entries += [pscustomobject]@{
            path = $Path
            length = [int64]$Entry.length
            sha256 = ([string]$Entry.sha256).ToLowerInvariant()
        }
    }
    return $Entries
}

function Test-Snapshot(
    [string]$ResolvedConfigDir,
    [string]$ResolvedDurabilityRoot,
    [string]$Id,
    [string]$Collection = 'snapshots'
) {
    Assert-NonOverlappingRoots $ResolvedConfigDir $ResolvedDurabilityRoot
    $Snapshot = Read-SnapshotManifest $ResolvedDurabilityRoot $Id $Collection
    $ManifestConfig = Resolve-AbsolutePath ([string]$Snapshot.manifest.config_dir) 'manifest.config_dir'
    if (-not $ManifestConfig.Equals($ResolvedConfigDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Snapshot belongs to a different ConfigDir.'
    }

    $CopyRoot = Join-Path $Snapshot.directory 'config'
    $Expected = @{}
    foreach ($Entry in @(Get-ValidatedManifestEntries $Snapshot.manifest $CopyRoot)) { $Expected[$Entry.path] = $Entry }

    $Current = @{}
    foreach ($Entry in @(Get-ProtectedFiles $ResolvedConfigDir)) { $Current[$Entry.path] = $Entry }

    $Added = @($Current.Keys | Where-Object { -not $Expected.ContainsKey($_) } | Sort-Object)
    $Removed = @($Expected.Keys | Where-Object { -not $Current.ContainsKey($_) } | Sort-Object)
    $Changed = @(
        $Expected.Keys |
            Where-Object {
                $Current.ContainsKey($_) -and (
                    [int64]$Expected[$_].length -ne [int64]$Current[$_].length -or
                    [string]$Expected[$_].sha256 -ne [string]$Current[$_].sha256
                )
            } |
            Sort-Object
    )

    return [pscustomobject]@{
        action = 'Verify'
        config_dir = $ResolvedConfigDir
        durability_root = $ResolvedDurabilityRoot
        snapshot_id = $Id
        collection = $Collection
        match = ($Added.Count -eq 0 -and $Removed.Count -eq 0 -and $Changed.Count -eq 0)
        added = $Added
        removed = $Removed
        changed = $Changed
    }
}

function Assert-SnapshotContent([string]$SnapshotDirectory, [object]$Manifest) {
    $CopyRoot = Join-Path $SnapshotDirectory 'config'
    $Entries = @(Get-ValidatedManifestEntries $Manifest $CopyRoot)
    foreach ($Entry in $Entries) {
        $Source = Join-Path $CopyRoot $Entry.path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Snapshot content missing: $($Entry.path)" }
        $Item = Get-Item -LiteralPath $Source -Force
        if (Test-ReparsePoint $Item) { throw "Snapshot contains a reparse point: $($Entry.path)" }
        $Hash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash.ToLowerInvariant()
        if ([int64]$Item.Length -ne $Entry.length -or $Hash -ne $Entry.sha256) {
            throw "Snapshot content integrity failure: $($Entry.path)"
        }
    }
    return $Entries
}

function Remove-ProtectedState([string]$ResolvedConfigDir) {
    $Files = @(Get-ProtectedFiles $ResolvedConfigDir)
    $Directories = @(Get-ProtectedDirectories $ResolvedConfigDir)

    foreach ($File in $Files) { Remove-Item -LiteralPath $File.full_name -Force }
    foreach ($Directory in $Directories) {
        if (-not (Get-ChildItem -LiteralPath $Directory.full_name -Force | Select-Object -First 1)) {
            Remove-Item -LiteralPath $Directory.full_name -Force
        }
    }
}

function Restore-Snapshot(
    [string]$ResolvedConfigDir,
    [string]$ResolvedDurabilityRoot,
    [string]$Id,
    [string]$Collection = 'snapshots'
) {
    Assert-NonOverlappingRoots $ResolvedConfigDir $ResolvedDurabilityRoot
    $Snapshot = Read-SnapshotManifest $ResolvedDurabilityRoot $Id $Collection
    $ManifestConfig = Resolve-AbsolutePath ([string]$Snapshot.manifest.config_dir) 'manifest.config_dir'
    if (-not $ManifestConfig.Equals($ResolvedConfigDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Snapshot belongs to a different ConfigDir.'
    }
    $Entries = @(Assert-SnapshotContent $Snapshot.directory $Snapshot.manifest)

    New-Item -ItemType Directory -Force -Path $ResolvedConfigDir | Out-Null
    Remove-ProtectedState $ResolvedConfigDir
    $CopyRoot = Join-Path $Snapshot.directory 'config'
    foreach ($Entry in $Entries) {
        $RelativeNative = $Entry.path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $Source = Join-Path $CopyRoot $RelativeNative
        $Destination = Join-Path $ResolvedConfigDir $RelativeNative
        $Parent = Split-Path -Parent $Destination
        if ($Parent) { New-Item -ItemType Directory -Force -Path $Parent | Out-Null }
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }

    $Verification = Test-Snapshot $ResolvedConfigDir $ResolvedDurabilityRoot $Id $Collection
    if (-not $Verification.match) { throw 'Post-restore verification failed.' }
    $Verification.action = 'Restore'
    return $Verification
}

$ResolvedConfigDir = Resolve-ConfigDirectory $ConfigDir
$ResolvedDurabilityRoot = Resolve-DurabilityDirectory $DurabilityRoot
Assert-NonOverlappingRoots $ResolvedConfigDir $ResolvedDurabilityRoot

switch ($Action) {
    'Enable' {
        New-Item -ItemType Directory -Force -Path $ResolvedConfigDir | Out-Null
        [Environment]::SetEnvironmentVariable('OPENCODE_CONFIG_DIR', $ResolvedConfigDir, 'User')
        $env:OPENCODE_CONFIG_DIR = $ResolvedConfigDir
        $Result = New-Snapshot $ResolvedConfigDir $ResolvedDurabilityRoot
        $Result.action = 'Enable'
        $Result | Add-Member -MemberType NoteProperty -Name persisted_config_dir -Value $ResolvedConfigDir -Force
    }
    'Snapshot' {
        $Result = New-Snapshot $ResolvedConfigDir $ResolvedDurabilityRoot
    }
    'Verify' {
        if ([string]::IsNullOrWhiteSpace($SnapshotId)) { $SnapshotId = Get-LatestSnapshotId $ResolvedDurabilityRoot }
        if ([string]::IsNullOrWhiteSpace($SnapshotId)) { throw 'No snapshot is available.' }
        $Result = Test-Snapshot $ResolvedConfigDir $ResolvedDurabilityRoot $SnapshotId
    }
    'Restore' {
        if ([string]::IsNullOrWhiteSpace($SnapshotId)) { $SnapshotId = Get-LatestSnapshotId $ResolvedDurabilityRoot }
        if ([string]::IsNullOrWhiteSpace($SnapshotId)) { throw 'No snapshot is available.' }
        $Result = Restore-Snapshot $ResolvedConfigDir $ResolvedDurabilityRoot $SnapshotId
    }
    'Status' {
        $Latest = Get-LatestSnapshotId $ResolvedDurabilityRoot
        $Result = [pscustomobject]@{
            action = 'Status'
            durability_version = $DurabilityVersion
            config_dir = $ResolvedConfigDir
            durability_root = $ResolvedDurabilityRoot
            persisted_config_dir = [Environment]::GetEnvironmentVariable('OPENCODE_CONFIG_DIR', 'User')
            snapshot_id = $Latest
            match = $null
            added = @()
            removed = @()
            changed = @()
        }
    }
}

if ($PassThru) {
    return $Result
}
$Result | ConvertTo-Json -Depth 20
