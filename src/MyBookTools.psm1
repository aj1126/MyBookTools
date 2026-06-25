<#
.SYNOPSIS
    MyBookTools v2 — Complete drive auditing, categorization, refinement, and maintenance toolkit.

.DESCRIPTION
    This module provides a full workflow for analyzing, organizing, refining, and maintaining
    large external drives (default M:\). It includes:
      - Fast audits
      - Hash caching
      - Categorization with auto-loaded CategoryMap
      - Duplicate detection and resolution
      - Cleanup operations
      - Visual tree maps
      - Real-time status reporting
      - Scheduled maintenance automation

    Designed for large drives (1–3 TB+) and long-running background tasks.

.NOTES
    Author: Copilot (for Albert)
    Version: 2.0
#>

# =====================================================================
#  MODULE INITIALIZATION
# =====================================================================

# Default paths
$Script:MyBook_DefaultRoot = 'M:\'
$Script:MyBook_DefaultLogRoot = Join-Path $env:USERPROFILE 'Documents\MyBookLogs'

# Ensure log directory exists on module import
if (-not (Test-Path $Script:MyBook_DefaultLogRoot)) {
    New-Item -Path $Script:MyBook_DefaultLogRoot -ItemType Directory -Force | Out-Null
}

# Status object
$Script:MyBook_Status = [PSCustomObject]@{
    Operation  = $null
    StartedAt  = $null
    LastUpdate = $null
    Details    = $null
}

# Default CategoryMap (auto-loaded unless disabled)
$Script:MyBook_DefaultCategoryMap = @{
    Projects = @('Unity','Project','Source','.sln','.csproj','Perseus')
    Media    = @('.wav','.mp3','.flac','.aiff','.mp4','.mov','.mkv','.avi','.jpg','.png','.psd','.ai','.prproj','.aep')
    Archives = @('backup','export','Dec_17_2023','March-2025','.zip','.rar','.7z','.bak')
    Uploads  = @('UPLOADS','upload','.torrent','.nfo')
    System   = @('installer','setup','.msi','.exe','.dll','logs','.log')
}

# =====================================================================
#  LOGGING + STATUS HELPERS
# =====================================================================

function Write-MyBookLog {
<#
.SYNOPSIS
    Writes a timestamped entry to the MyBook log.

.PARAMETER Message
    The message to log.

.PARAMETER Level
    Log level: Info, Warning, Error.

.EXAMPLE
    Write-MyBookLog -Message "Scan started"
#>
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info','Warning','Error')][string]$Level = 'Info'
    )

    $logFile = Join-Path $Script:MyBook_DefaultLogRoot ("MyBook_{0:yyyy-MM-dd}.log" -f (Get-Date))
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logFile -Value "[${timestamp}] [$Level] $Message"
}

function Set-MyBookStatus {
<#
.SYNOPSIS
    Updates the module's real-time status.

.PARAMETER Operation
    Name of the current operation.

.PARAMETER Details
    Additional details about the operation.

.EXAMPLE
    Set-MyBookStatus -Operation "Audit" -Details "Scanning with hashes"
#>
    param(
        [string]$Operation,
        [string]$Details
    )

    if (-not $Script:MyBook_Status.StartedAt) {
        $Script:MyBook_Status.StartedAt = Get-Date
    }

    $Script:MyBook_Status.Operation  = $Operation
    $Script:MyBook_Status.Details    = $Details
    $Script:MyBook_Status.LastUpdate = Get-Date

    # Dump status to a JSON file for cross-process communication
    try {
        $statusFile = Join-Path $Script:MyBook_DefaultLogRoot 'MyBook_Status.json'
        $Script:MyBook_Status | ConvertTo-Json | Set-Content -Path $statusFile -Encoding UTF8
    } catch {}
}

function Clear-MyBookStatus {
<#
.SYNOPSIS
    Clears the current status.
#>
    $Script:MyBook_Status.Operation  = $null
    $Script:MyBook_Status.Details    = $null
    $Script:MyBook_Status.StartedAt  = $null
    $Script:MyBook_Status.LastUpdate = $null

    # Clear status in the JSON file
    try {
        $statusFile = Join-Path $Script:MyBook_DefaultLogRoot 'MyBook_Status.json'
        if (Test-Path $statusFile) {
            Remove-Item -Path $statusFile -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

function Get-MyBookStatus {
<#
.SYNOPSIS
    Returns the current module status.

.EXAMPLE
    Get-MyBookStatus
#>
    $statusFile = Join-Path $Script:MyBook_DefaultLogRoot 'MyBook_Status.json'
    if (Test-Path $statusFile) {
        try {
            $json = Get-Content -Path $statusFile -Raw | ConvertFrom-Json
            if ($json -and $json.Operation) {
                return [PSCustomObject]@{
                    Operation  = $json.Operation
                    StartedAt  = $json.StartedAt
                    LastUpdate = $json.LastUpdate
                    Details    = $json.Details
                }
            }
        } catch {}
    }
    $Script:MyBook_Status
}

# =====================================================================
#  VISUAL MAP
# =====================================================================

function Show-MyBookVisualMap {
<#
.SYNOPSIS
    Displays a visual tree map of the drive.

.PARAMETER RootPath
    Root directory to map.

.PARAMETER MaxDepth
    Maximum depth of recursion.

.PARAMETER OutputPath
    Optional file to save the map.

.EXAMPLE
    Show-MyBookVisualMap -MaxDepth 3
#>
    param(
        [string]$RootPath = $Script:MyBook_DefaultRoot,
        [int]$MaxDepth = 3,
        [string]$OutputPath = "$env:USERPROFILE\Desktop\MyBook_VisualMap.txt"
    )

    $lines = New-Object System.Collections.Generic.List[string]

    function Add-Tree {
        param([string]$Path, [int]$Depth)

        if ($Depth -gt $MaxDepth) { return }

        $indent = ('│   ' * $Depth)
        $name = Split-Path $Path -Leaf
        if (-not $name) { $name = $Path.TrimEnd('\') }

        $lines.Add("{0}└── {1}" -f $indent, $name)

        Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name |
            ForEach-Object { Add-Tree -Path $_.FullName -Depth ($Depth + 1) }
    }

    Add-Tree -Path $RootPath -Depth 0
    $lines | Set-Content -Path $OutputPath -Encoding UTF8
    $lines
}

# =====================================================================
#  AUDIT + HASH CACHE
# =====================================================================

function Update-MyBookHashCache {
<#
.SYNOPSIS
    Updates or creates the hash cache for fast duplicate detection.

.PARAMETER RootPath
    Directory to scan.

.PARAMETER CachePath
    Path to the JSON cache file.

.EXAMPLE
    Update-MyBookHashCache -RootPath M:\ -CachePath "$env:USERPROFILE\Documents\MyBookLogs\HashCache.json"
#>
    param(
        [string]$RootPath = $Script:MyBook_DefaultRoot,
        [string]$CachePath = (Join-Path $Script:MyBook_DefaultLogRoot 'MyBook_HashCache.json')
    )

    Set-MyBookStatus -Operation "HashCache" -Details "Updating hash cache"

    $cache = @{}
    if (Test-Path $CachePath) {
        $jsonObj = Get-Content -Path $CachePath -Raw | ConvertFrom-Json
        if ($jsonObj) {
            foreach ($prop in $jsonObj.psobject.properties) {
                $cache[$prop.Name] = $prop.Value
            }
        }
    }

    $result = @{}

    Get-ChildItem -Path $RootPath -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $key = $_.FullName
            $meta = @{
                Length        = $_.Length
                LastWriteTime = $_.LastWriteTime.ToString('o')
            }

            if ($null -ne $cache[$key] -and
                $cache[$key].Length -eq $meta.Length -and
                $cache[$key].LastWriteTime -eq $meta.LastWriteTime) {

                $hash = $cache[$key].Hash
            } else {
                try { $hash = (Get-FileHash -LiteralPath $_.FullName).Hash } catch { $hash = $null }
            }

            $result[$key] = @{
                Length        = $meta.Length
                LastWriteTime = $meta.LastWriteTime
                Hash          = $hash
            }
        }

    ($result | ConvertTo-Json -Depth 5) | Set-Content -Path $CachePath -Encoding UTF8

    Clear-MyBookStatus
    $CachePath
}

function Invoke-MyBookAuditFast {
<#
.SYNOPSIS
    Performs a fast audit of the drive with optional hashing.

.PARAMETER RootPath
    Directory to scan.

.PARAMETER OutputCsvPath
    Path to save the CSV.

.PARAMETER IncludeHashes
    Compute hashes for each file.

.EXAMPLE
    Invoke-MyBookAuditFast -IncludeHashes
#>
    param(
        [string]$RootPath = $Script:MyBook_DefaultRoot,
        [string]$OutputCsvPath = "$env:USERPROFILE\Desktop\MyBook_AuditFast_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date),
        [switch]$IncludeHashes
    )

    Set-MyBookStatus -Operation "Audit" -Details "Fast audit (IncludeHashes=$IncludeHashes)"

    $stream = New-Object System.Collections.Generic.List[object]

    Get-ChildItem -Path $RootPath -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $hash = $null
            if ($IncludeHashes) {
                try { $hash = (Get-FileHash -LiteralPath $_.FullName).Hash } catch {}
            }

            $stream.Add([PSCustomObject]@{
                FullName      = $_.FullName
                Length        = $_.Length
                Extension     = $_.Extension
                LastWriteTime = $_.LastWriteTime
                Hash          = $hash
            })
        }

    $stream | Export-Csv -Path $OutputCsvPath -NoTypeInformation -Encoding UTF8

    Clear-MyBookStatus
    $OutputCsvPath
}

# =====================================================================
#  CATEGORIZATION
# =====================================================================

function Invoke-MyBookCategorize {
<#
.SYNOPSIS
    Categorizes files based on extension and keyword patterns.

.PARAMETER RootPath
    Root directory to categorize.

.PARAMETER CategoryMap
    Custom category map.

.PARAMETER DisableDefaultCategoryMap
    Disables the built-in CategoryMap.

.PARAMETER DryRun
    Shows what would be moved without making changes.

.EXAMPLE
    Invoke-MyBookCategorize -DryRun

.EXAMPLE
    Invoke-MyBookCategorize -DisableDefaultCategoryMap -CategoryMap $CustomMap
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RootPath = $Script:MyBook_DefaultRoot,
        [hashtable]$CategoryMap,
        [switch]$DisableDefaultCategoryMap,
        [switch]$DryRun
    )

    Set-MyBookStatus -Operation "Categorize" -Details "DryRun=$DryRun"

    if (-not $DisableDefaultCategoryMap -and -not $CategoryMap) {
        $CategoryMap = $Script:MyBook_DefaultCategoryMap
    }

    if (-not $CategoryMap) {
        Write-MyBookLog -Message "No CategoryMap provided; skipping categorization."
        Clear-MyBookStatus
        return
    }

    $destinations = @{}
    foreach ($cat in $CategoryMap.Keys) {
        $dest = Join-Path $RootPath $cat
        if (-not (Test-Path $dest)) {
            New-Item -Path $dest -ItemType Directory -Force | Out-Null
        }
        $destinations[$cat] = $dest
    }

    $files = Get-ChildItem -Path $RootPath -Recurse -File -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        # Skip if file is already inside one of the target category destination folders
        $alreadyCategorized = $false
        foreach ($dest in $destinations.Values) {
            if ($file.FullName.StartsWith($dest, [System.StringComparison]::InvariantCultureIgnoreCase)) {
                $alreadyCategorized = $true
                break
            }
        }
        if ($alreadyCategorized) { continue }

        $targetCategory = $null

        foreach ($cat in $CategoryMap.Keys) {
            foreach ($pattern in $CategoryMap[$cat]) {
                if ($pattern.StartsWith('.')) {
                    if ($file.Extension -eq $pattern) { $targetCategory = $cat; break }
                } else {
                    if ($file.FullName -like "*$pattern*") { $targetCategory = $cat; break }
                }
            }
            if ($targetCategory) { break }
        }

        if (-not $targetCategory) { continue }

        $destRoot = $destinations[$targetCategory]
        $relative = $file.FullName.Substring($RootPath.Length).TrimStart('\')
        $destPath = Join-Path $destRoot $relative
        $destDir  = Split-Path $destPath -Parent

        if (-not (Test-Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }

        if ($DryRun) {
            Write-MyBookLog -Message "[DryRun] Would move: $($file.FullName) → $destPath"
        } else {
            if ($PSCmdlet.ShouldProcess($file.FullName, "Move to $destPath")) {
                Move-Item -Path $file.FullName -Destination $destPath -Force
                Write-MyBookLog -Message "Moved: $($file.FullName) → $destPath"
            }
        }
    }

    Clear-MyBookStatus
}

# =====================================================================
#  DUPLICATE RESOLUTION
# =====================================================================

function Resolve-MyBookDuplicates {
<#
.SYNOPSIS
    Resolves duplicate files by keeping the newest and deleting older copies.

.PARAMETER RootPath
    Directory to scan.

.PARAMETER DryRun
    Shows what would be deleted without making changes.

.EXAMPLE
    Resolve-MyBookDuplicates -DryRun

.EXAMPLE
    Resolve-MyBookDuplicates
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RootPath = $Script:MyBook_DefaultRoot,
        [switch]$DryRun
    )

    Set-MyBookStatus -Operation "Duplicates" -Details "DryRun=$DryRun"

    $files = Get-ChildItem -Path $RootPath -Recurse -File -ErrorAction SilentlyContinue
    $hashGroups = $files | Get-FileHash | Group-Object Hash | Where-Object Count -gt 1

    foreach ($group in $hashGroups) {
        # Map back to FileInfo objects to retrieve LastWriteTime
        $duplicateFiles = $group.Group | ForEach-Object { Get-Item -LiteralPath $_.Path }
        $sorted = $duplicateFiles | Sort-Object LastWriteTime -Descending
        $keep   = $sorted[0]
        $remove = $sorted[1..($sorted.Count - 1)]

        Write-MyBookLog -Message "Keeping newest duplicate: $($keep.FullName)"

        foreach ($f in $remove) {
            if ($DryRun) {
                Write-MyBookLog -Message "[DryRun] Would delete: $($f.FullName)"
            } else {
                if ($PSCmdlet.ShouldProcess($f.FullName, "Delete duplicate")) {
                    Remove-Item -LiteralPath $f.FullName -Force
                    Write-MyBookLog -Message "Deleted duplicate: $($f.FullName)"
                }
            }
        }
    }

    Clear-MyBookStatus
}

# =====================================================================
#  CLEANUP
# =====================================================================

function Invoke-MyBookCleanup {
<#
.SYNOPSIS
    Performs cleanup operations: empty directories, duplicates, compression.

.PARAMETER RemoveEmptyDirectories
    Removes empty folders.

.PARAMETER ReportDuplicates
    Logs duplicate groups.

.PARAMETER CompressArchives
    Compresses the Archives folder.

.EXAMPLE
    Invoke-MyBookCleanup -RemoveEmptyDirectories -ReportDuplicates
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RootPath = $Script:MyBook_DefaultRoot,
        [switch]$RemoveEmptyDirectories,
        [switch]$ReportDuplicates,
        [switch]$CompressArchives
    )

    Set-MyBookStatus -Operation "Cleanup" -Details "Running cleanup tasks"

    if ($RemoveEmptyDirectories) {
        Get-ChildItem -Path $RootPath -Recurse -Directory |
            Where-Object { ($_.GetFileSystemInfos()).Count -eq 0 } |
            ForEach-Object {
                if ($PSCmdlet.ShouldProcess($_.FullName, "Remove empty directory")) {
                    Remove-Item -Path $_.FullName -Force
                    Write-MyBookLog -Message "Removed empty directory: $($_.FullName)"
                }
            }
    }

    if ($ReportDuplicates) {
        $files = Get-ChildItem -Path $RootPath -Recurse -File
        $hashGroups = $files | Get-FileHash | Group-Object Hash | Where-Object Count -gt 1

        foreach ($group in $hashGroups) {
            Write-MyBookLog -Message "Duplicate group (Hash=$($group.Name)):"
            $group.Group | ForEach-Object {
                Write-MyBookLog -Message "  $_.Path"
            }
        }
    }

    if ($CompressArchives) {
        $archiveRoot = Join-Path $RootPath 'Archives'
        if (Test-Path $archiveRoot) {
            # Compress files inside Archives to a zip at RootPath, avoiding zipping the zip itself recursively
            $zipPath = Join-Path $RootPath ("Archives_{0:yyyyMMdd_HHmmss}.zip" -f (Get-Date))
            Compress-Archive -Path (Join-Path $archiveRoot '*') -DestinationPath $zipPath -Force
            Write-MyBookLog -Message "Compressed archives → $zipPath"
        }
    }

    Clear-MyBookStatus
}

# =====================================================================
#  MAINTENANCE TASK
# =====================================================================

function Register-MyBookMaintenanceTask {
<#
.SYNOPSIS
    Registers a scheduled task for daily maintenance logging.

.PARAMETER TaskName
    Name of the scheduled task.

.PARAMETER Schedule
    Daily or Hourly.

.EXAMPLE
    Register-MyBookMaintenanceTask -Schedule Daily
#>
    param(
        [string]$TaskName = 'MyBookMaintenance',
        [string]$Schedule = 'Daily'
    )

    $scriptBlock = @"
Import-Module `"$PSScriptRoot\MyBookTools.psm1`"
Invoke-MyBookAuditFast | Out-Null
"@

    $tempScript = Join-Path $Script:MyBook_DefaultLogRoot 'MyBook_MaintenanceTask.ps1'
    Set-Content -Path $tempScript -Value $scriptBlock -Encoding UTF8

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$tempScript`""


    switch ($Schedule) {
        'Daily' {
            $trigger = New-ScheduledTaskTrigger -Daily -At "3:00 AM"
        }
        'Hourly' {
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5)
            $trigger.RepetitionInterval = 'PT1H'
            $trigger.RepetitionDuration = 'P1D'
        }
        default {
            $trigger = New-ScheduledTaskTrigger -Daily -At "3:00 AM"
        }
    }

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Description 'MyBook drive maintenance logging' `
        -User $env:USERNAME `
        -RunLevel Highest `
        -Force

    Write-MyBookLog -Message "Registered scheduled task '$TaskName' (Schedule=$Schedule, Script=$tempScript)"

    Clear-MyBookStatus
}

# =====================================================================
#  SCAN PREDICTION
# =====================================================================

function Get-MyBookScanPrediction {
<#
.SYNOPSIS
    Predicts the duration of a scan on a given path.

.PARAMETER RootPath
    The directory to analyze.

.PARAMETER IncludeHashes
    Whether the scan will compute hashes.

.PARAMETER UseCache
    Whether the scan will utilize the hash cache.

.EXAMPLE
    Get-MyBookScanPrediction -RootPath M:\ -IncludeHashes
#>
    param(
        [string]$RootPath = $Script:MyBook_DefaultRoot,
        [switch]$IncludeHashes,
        [switch]$UseCache = $true
    )

    if (-not (Test-Path $RootPath)) {
        throw "Path '$RootPath' does not exist."
    }

    Set-MyBookStatus -Operation "Predict" -Details "Predicting scan duration for $RootPath"

    # 1. Timed traversal (up to 1.5 seconds)
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $filesCount = 0
    $totalSize = 0
    
    # Use .NET Directory EnumerateFiles to perform fast, interruptible traversal
    $enumerator = [System.IO.Directory]::EnumerateFiles($RootPath, "*", [System.IO.SearchOption]::AllDirectories).GetEnumerator()
    $completedTraversal = $true

    while ($true) {
        if ($stopwatch.ElapsedMilliseconds -ge 1500) {
            $completedTraversal = $false
            break
        }
        try {
            if (-not $enumerator.MoveNext()) {
                break
            }
            $filesCount++
            $file = [System.IO.FileInfo]::new($enumerator.Current)
            $totalSize += $file.Length
        } catch {
            # Skip errors (access denied etc.)
        }
    }
    $stopwatch.Stop()
    $traversalTimeSec = $stopwatch.Elapsed.TotalSeconds

    # 2. Extrapolate total files/size using drive metadata if traversal did not complete
    $estFileCount = $filesCount
    $estTotalSize = $totalSize

    if (-not $completedTraversal -and $filesCount -gt 0) {
        try {
            # Try to get volume used bytes
            $driveQualifier = Split-Path $RootPath -Qualifier
            if ($driveQualifier) {
                $drive = [System.IO.DriveInfo]::new($driveQualifier)
                $usedBytes = $drive.TotalSize - $drive.TotalFreeSpace
                if ($usedBytes -gt $totalSize) {
                    $ratio = $usedBytes / $totalSize
                    $estFileCount = [math]::Round($filesCount * $ratio)
                    $estTotalSize = $usedBytes
                }
            } else {
                # Fallback scaling
                $estFileCount = $filesCount * 5
                $estTotalSize = $totalSize * 5
            }
        } catch {
            # Fallback scaling
            $estFileCount = $filesCount * 5
            $estTotalSize = $totalSize * 5
        }
    }

    # 3. Calculate traversal speed (files/sec)
    $traversalSpeed = 2000 # default fallback
    if ($traversalTimeSec -gt 0 -and $filesCount -gt 0) {
        $traversalSpeed = $filesCount / $traversalTimeSec
    }
    
    # Estimated traversal time
    $estTraversalDurationSec = 0
    if ($traversalSpeed -gt 0) {
        $estTraversalDurationSec = $estFileCount / $traversalSpeed
    }

    # 4. Measure Hashing Speed (Benchmark)
    $hashingSpeed = 50MB # Default 50MB/sec fallback
    $estHashingDurationSec = 0

    if ($IncludeHashes) {
        # Timed hashing benchmark (hash files we already enumerated up to 10MB or 0.5 seconds)
        $hashStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $bytesHashed = 0
        $benchmarkFiles = @()
        
        # Collect some small files that actually exist and we can read
        $sampleCount = 0
        try {
            $enumerator2 = [System.IO.Directory]::EnumerateFiles($RootPath, "*", [System.IO.SearchOption]::AllDirectories).GetEnumerator()
            while ($enumerator2.MoveNext() -and $sampleCount -lt 10) {
                $fPath = $enumerator2.Current
                if (Test-Path $fPath) {
                    $fInfo = [System.IO.FileInfo]::new($fPath)
                    if ($fInfo.Length -gt 0 -and $fInfo.Length -lt 10MB) {
                        $benchmarkFiles += $fPath
                        $sampleCount++
                    }
                }
            }
        } catch {}
        
        foreach ($f in $benchmarkFiles) {
            if ($hashStopwatch.ElapsedMilliseconds -ge 500 -or $bytesHashed -ge 10MB) {
                break
            }
            try {
                $len = (Get-Item -LiteralPath $f).Length
                $null = Get-FileHash -LiteralPath $f
                $bytesHashed += $len
            } catch {}
        }
        $hashStopwatch.Stop()
        $hashTimeSec = $hashStopwatch.Elapsed.TotalSeconds

        if ($hashTimeSec -gt 0 -and $bytesHashed -gt 0) {
            $hashingSpeed = $bytesHashed / $hashTimeSec
        }

        # 5. Account for Hash Cache if UseCache is true
        $sizeToHash = $estTotalSize
        if ($UseCache) {
            $cachePath = Join-Path $Script:MyBook_DefaultLogRoot 'MyBook_HashCache.json'
            if (Test-Path $cachePath) {
                # Assume 90% of files are cached (cache hit), so we only hash 10%
                $sizeToHash = $estTotalSize * 0.10
            }
        }
        
        if ($hashingSpeed -gt 0) {
            $estHashingDurationSec = $sizeToHash / $hashingSpeed
        }
    }

    $totalEstDurationSec = $estTraversalDurationSec + $estHashingDurationSec

    Clear-MyBookStatus

    return [PSCustomObject]@{
        RootPath                   = $RootPath
        IncludeHashes              = $IncludeHashes
        UseCache                   = $UseCache
        EstimatedFileCount         = [int]$estFileCount
        EstimatedTotalSizeBytes    = [long]$estTotalSize
        TraversalSpeedFilesPerSec  = [double][math]::Round($traversalSpeed, 2)
        HashingSpeedBytesPerSec    = [double][math]::Round($hashingSpeed, 2)
        EstimatedTraversalDuration = [TimeSpan]::FromSeconds($estTraversalDurationSec)
        EstimatedHashingDuration   = [TimeSpan]::FromSeconds($estHashingDurationSec)
        TotalEstimatedDuration     = [TimeSpan]::FromSeconds($totalEstDurationSec)
    }
}

# =====================================================================
#  EXPORT MODULE MEMBERS
# =====================================================================

Export-ModuleMember -Function *-MyBook*, Show-MyBookVisualMap

