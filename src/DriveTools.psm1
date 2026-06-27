#Requires -Version 5.1
<#
.SYNOPSIS
    DriveTools — Complete drive auditing, categorization, refinement, and maintenance toolkit.
.DESCRIPTION
    Refactored to support any storage drive on the system.
#>

# =====================================================================
#  MODULE INITIALIZATION
# =====================================================================

$Script:DriveTools_DefaultLogRoot = Join-Path $env:USERPROFILE 'Documents\DriveToolsLogs'

if (-not (Test-Path $Script:DriveTools_DefaultLogRoot)) {
    New-Item -Path $Script:DriveTools_DefaultLogRoot -ItemType Directory -Force | Out-Null
}

$Script:DriveTools_Status = [PSCustomObject]@{
    Operation  = $null
    StartedAt  = $null
    LastUpdate = $null
    Details    = $null
}

$Script:DriveTools_DefaultCategoryMap = @{
    Projects = @('Unity','Project','Source','.sln','.csproj','Perseus')
    Media    = @('.wav','.mp3','.flac','.aiff','.mp4','.mov','.mkv','.avi','.jpg','.png','.psd','.ai','.prproj','.aep')
    Archives = @('backup','export','Dec_17_2023','March-2025','.zip','.rar','.7z','.bak')
    Uploads  = @('UPLOADS','upload','.torrent','.nfo')
    System   = @('installer','setup','.msi','.exe','.dll','logs','.log')
}

# =====================================================================
#  DRIVE SELECTION LOGIC
# =====================================================================

function Get-DriveToolsRootPath {
    param(
        [string]$Path
    )
    if ($Path -and (Test-Path $Path)) {
        return $Path
    }

    $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
    if ($drives.Count -eq 0) {
        throw "No ready drives found."
    }

    # If non-interactive or running in automated tests
    if (-not [Environment]::UserInteractive) {
        return $drives[0].Name
    }

    Write-Host "--- Drive Selection Menu ---"
    for ($i = 0; $i -lt $drives.Count; $i++) {
        $d = $drives[$i]
        $freeGB = [math]::Round($d.AvailableFreeSpace / 1GB, 2)
        $totalGB = [math]::Round($d.TotalSize / 1GB, 2)
        Write-Host ("[{0}] {1} ({2}) - {3} GB free of {4} GB" -f $i, $d.Name, $d.VolumeLabel, $freeGB, $totalGB)
    }

    $selection = -1
    while ($selection -lt 0 -or $selection -ge $drives.Count) {
        $userInput = Read-Host "Select a drive (0-$($drives.Count - 1))"
        if ([int]::TryParse($userInput, [ref]$selection)) {
            if ($selection -ge 0 -and $selection -lt $drives.Count) {
                break
            }
        }
        Write-Host "Invalid selection. Please try again." -ForegroundColor Red
    }
    return $drives[$selection].Name
}

# =====================================================================
#  LOGGING + STATUS HELPERS
# =====================================================================

function Write-DriveToolsLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info','Warning','Error')][string]$Level = 'Info'
    )
    $logFile = Join-Path $Script:DriveTools_DefaultLogRoot ("DriveTools_{0:yyyy-MM-dd}.log" -f (Get-Date))
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logFile -Value "[${timestamp}] [$Level] $Message"
}

function Set-DriveToolsStatus {
    param(
        [string]$Operation,
        [string]$Details
    )
    if (-not $Script:DriveTools_Status.StartedAt) {
        $Script:DriveTools_Status.StartedAt = Get-Date
    }
    $Script:DriveTools_Status.Operation  = $Operation
    $Script:DriveTools_Status.Details    = $Details
    $Script:DriveTools_Status.LastUpdate = Get-Date

    try {
        $statusFile = Join-Path $Script:DriveTools_DefaultLogRoot 'DriveTools_Status.json'
        $Script:DriveTools_Status | ConvertTo-Json | Set-Content -Path $statusFile -Encoding UTF8
    } catch {
        # Ignore write/serialization errors to prevent interrupting core drive tasks if the disk/folder is temporarily locked.
    }
}

function Clear-DriveToolsStatus {
    $Script:DriveTools_Status.Operation  = $null
    $Script:DriveTools_Status.Details    = $null
    $Script:DriveTools_Status.StartedAt  = $null
    $Script:DriveTools_Status.LastUpdate = $null

    try {
        $statusFile = Join-Path $Script:DriveTools_DefaultLogRoot 'DriveTools_Status.json'
        if (Test-Path $statusFile) {
            Remove-Item -Path $statusFile -Force -ErrorAction SilentlyContinue
        }
    } catch {
        # Ignore removal errors if status file is already deleted or locked by another process.
    }
}

function Get-DriveToolsStatus {
    $statusFile = Join-Path $Script:DriveTools_DefaultLogRoot 'DriveTools_Status.json'
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
        } catch {
            # Ignore read/deserialization errors; fall back to in-memory status object.
        }
    }
    $Script:DriveTools_Status
}

# =====================================================================
#  CORE FUNCTIONS
# =====================================================================

function Show-DriveVisualMap {
    param(
        [string]$RootPath,
        [int]$MaxDepth = 3,
        [string]$OutputPath,
        [switch]$UseMock
    )
    $resolvedPath = Get-DriveToolsRootPath -Path $RootPath
    if (-not $OutputPath) {
        $OutputPath = Join-Path $env:USERPROFILE ("Desktop\DriveTools_VisualMap.txt")
    }

    if ($UseMock) {
        $charCorner = [char]0x2514
        $charLine = [char]0x2500
        $mockLines = @(
            "$charCorner$charLine$charLine MockDrive",
            "    $charCorner$charLine$charLine FolderA",
            "    $charCorner$charLine$charLine FolderB"
        )
        $mockLines | Set-Content -Path $OutputPath -Encoding UTF8
        return $mockLines
    }

    $lines = New-Object System.Collections.Generic.List[string]

    function Add-Tree {
        param([string]$Path, [int]$Depth)

        if ($Depth -gt $MaxDepth) { return }

        $charLine = [char]0x2502 # │
        $charCorner = [char]0x2514 # └
        $charDash = [char]0x2500 # ─

        $indent = ("$charLine   " * $Depth)
        $name = Split-Path $Path -Leaf
        if (-not $name) { $name = $Path.TrimEnd('\') }
        $fmtArgs = @($indent, [string]$charCorner, [string]$charDash, $name)
        $lines.Add('{0}{1}{2}{2} {3}' -f $fmtArgs)

        Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name |
            ForEach-Object { Add-Tree -Path $_.FullName -Depth ($Depth + 1) }
    }

    Add-Tree -Path $resolvedPath -Depth 0
    $lines | Set-Content -Path $OutputPath -Encoding UTF8
    $lines
}

function Update-DriveHashCache {
    param(
        [string]$RootPath,
        [string]$CachePath,
        [switch]$UseMock
    )
    $resolvedPath = Get-DriveToolsRootPath -Path $RootPath
    if (-not $CachePath) {
        $CachePath = Join-Path $Script:DriveTools_DefaultLogRoot 'DriveTools_HashCache.json'
    }

    if ($UseMock) {
        $mockCache = @{ "MockFile.txt" = @{ Length = 100; LastWriteTime = (Get-Date).ToString('o'); Hash = "MOCKHASH" } }
        $mockCache | ConvertTo-Json | Set-Content -Path $CachePath -Encoding UTF8
        return $CachePath
    }

    Set-DriveToolsStatus -Operation "HashCache" -Details "Updating hash cache"

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

    Get-ChildItem -Path $resolvedPath -Recurse -File -ErrorAction SilentlyContinue |
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

    Clear-DriveToolsStatus
    $CachePath
}

function Invoke-DriveAuditFast {
    param(
        [string]$RootPath,
        [string]$OutputCsvPath,
        [switch]$IncludeHashes,
        [switch]$UseMock
    )
    $resolvedPath = Get-DriveToolsRootPath -Path $RootPath
    if (-not $OutputCsvPath) {
        $OutputCsvPath = Join-Path $env:USERPROFILE ("Desktop\DriveTools_AuditFast_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date))
    }

    if ($UseMock) {
        "FullName,Length,Extension,LastWriteTime,Hash" | Set-Content -Path $OutputCsvPath -Encoding UTF8
        return $OutputCsvPath
    }

    Set-DriveToolsStatus -Operation "Audit" -Details "Fast audit (IncludeHashes=$IncludeHashes)"

    $stream = New-Object System.Collections.Generic.List[object]

    Get-ChildItem -Path $resolvedPath -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $hash = $null
            if ($IncludeHashes) {
                try { $hash = (Get-FileHash -LiteralPath $_.FullName).Hash } catch {
                    # Ignore hashing errors for locked or unreadable files so the audit can proceed.
                }
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

    Clear-DriveToolsStatus
    $OutputCsvPath
}

function Invoke-DriveCategorize {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RootPath,
        [hashtable]$CategoryMap,
        [switch]$DisableDefaultCategoryMap,
        [switch]$DryRun,
        [switch]$UseMock
    )
    if ($UseMock) {
        Write-DriveToolsLog -Message "[Mock] Categorization complete"
        return
    }

    $resolvedPath = Get-DriveToolsRootPath -Path $RootPath
    Set-DriveToolsStatus -Operation "Categorize" -Details "DryRun=$DryRun"

    if (-not $DisableDefaultCategoryMap -and -not $CategoryMap) {
        $CategoryMap = $Script:DriveTools_DefaultCategoryMap
    }

    if (-not $CategoryMap) {
        Write-DriveToolsLog -Message "No CategoryMap provided; skipping categorization."
        Clear-DriveToolsStatus
        return
    }

    $destinations = @{}
    foreach ($cat in $CategoryMap.Keys) {
        $dest = Join-Path $resolvedPath $cat
        if (-not (Test-Path $dest)) {
            New-Item -Path $dest -ItemType Directory -Force | Out-Null
        }
        $destinations[$cat] = $dest
    }

    $files = Get-ChildItem -Path $resolvedPath -Recurse -File -ErrorAction SilentlyContinue

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
        $relative = $file.FullName.Substring($resolvedPath.Length).TrimStart('\')
        $destPath = Join-Path $destRoot $relative
        $destDir  = Split-Path $destPath -Parent

        if (-not (Test-Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }

        if ($DryRun) {
            Write-DriveToolsLog -Message "[DryRun] Would move: $($file.FullName) -> $destPath"
        } else {
            if ($PSCmdlet.ShouldProcess($file.FullName, "Move to $destPath")) {
                Move-Item -Path $file.FullName -Destination $destPath -Force
                Write-DriveToolsLog -Message "Moved: $($file.FullName) -> $destPath"
            }
        }
    }

    Clear-DriveToolsStatus
}

function Resolve-DriveDuplicates {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RootPath,
        [switch]$DryRun,
        [switch]$UseMock
    )
    if ($UseMock) {
        Write-DriveToolsLog -Message "[Mock] Duplicate resolution complete"
        return
    }

    $resolvedPath = Get-DriveToolsRootPath -Path $RootPath
    Set-DriveToolsStatus -Operation "Duplicates" -Details "DryRun=$DryRun"

    $files = Get-ChildItem -Path $resolvedPath -Recurse -File -ErrorAction SilentlyContinue
    $hashGroups = $files | Get-FileHash | Group-Object Hash | Where-Object Count -gt 1

    foreach ($group in $hashGroups) {
        # Map back to FileInfo objects to retrieve LastWriteTime
        $duplicateFiles = $group.Group | ForEach-Object { Get-Item -LiteralPath $_.Path }
        $sorted = $duplicateFiles | Sort-Object LastWriteTime -Descending
        $keep   = $sorted[0]
        $remove = $sorted[1..($sorted.Count - 1)]

        Write-DriveToolsLog -Message "Keeping newest duplicate: $($keep.FullName)"

        foreach ($f in $remove) {
            if ($DryRun) {
                Write-DriveToolsLog -Message "[DryRun] Would delete: $($f.FullName)"
            } else {
                if ($PSCmdlet.ShouldProcess($f.FullName, "Delete duplicate")) {
                    Remove-Item -LiteralPath $f.FullName -Force
                    Write-DriveToolsLog -Message "Deleted duplicate: $($f.FullName)"
                }
            }
        }
    }

    Clear-DriveToolsStatus
}

function Invoke-DriveCleanup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RootPath,
        [switch]$RemoveEmptyDirectories,
        [switch]$ReportDuplicates,
        [switch]$CompressArchives,
        [switch]$UseMock
    )
    if ($UseMock) {
        Write-DriveToolsLog -Message "[Mock] Cleanup complete"
        return
    }

    $resolvedPath = Get-DriveToolsRootPath -Path $RootPath
    Set-DriveToolsStatus -Operation "Cleanup" -Details "Running cleanup tasks"

    if ($RemoveEmptyDirectories) {
        Get-ChildItem -Path $resolvedPath -Recurse -Directory |
            Where-Object { ($_.GetFileSystemInfos()).Count -eq 0 } |
            ForEach-Object {
                if ($PSCmdlet.ShouldProcess($_.FullName, "Remove empty directory")) {
                    Remove-Item -Path $_.FullName -Force
                    Write-DriveToolsLog -Message "Removed empty directory: $($_.FullName)"
                }
            }
    }

    if ($ReportDuplicates) {
        $files = Get-ChildItem -Path $resolvedPath -Recurse -File
        $hashGroups = $files | Get-FileHash | Group-Object Hash | Where-Object Count -gt 1

        foreach ($group in $hashGroups) {
            Write-DriveToolsLog -Message "Duplicate group (Hash=$($group.Name)):"
            $group.Group | ForEach-Object {
                Write-DriveToolsLog -Message "  $_.Path"
            }
        }
    }

    if ($CompressArchives) {
        $archiveRoot = Join-Path $resolvedPath 'Archives'
        if (Test-Path $archiveRoot) {
            $zipPath = Join-Path $resolvedPath ("Archives_{0:yyyyMMdd_HHmmss}.zip" -f (Get-Date))
            Compress-Archive -Path (Join-Path $archiveRoot '*') -DestinationPath $zipPath -Force
            Write-DriveToolsLog -Message "Compressed archives -> $zipPath"
        }
    }

    Clear-DriveToolsStatus
}

function Register-DriveMaintenanceTask {
    param(
        [string]$TaskName = 'DriveMaintenance',
        [string]$Schedule = 'Daily',
        [switch]$UseMock
    )
    if ($UseMock) {
        Write-DriveToolsLog -Message "[Mock] Registered scheduled task '$TaskName'"
        return
    }

    $ScriptDir = $PSScriptRoot
    $ModulePsm1 = Join-Path $ScriptDir 'DriveTools.psm1'

    $scriptBlock = @"
Import-Module `"$ModulePsm1`"
Invoke-DriveAuditFast | Out-Null
"@

    $tempScript = Join-Path $Script:DriveTools_DefaultLogRoot 'DriveTools_MaintenanceTask.ps1'
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
        -Description 'DriveTools maintenance logging' `
        -User $env:USERNAME `
        -RunLevel Highest `
        -Force

    Write-DriveToolsLog -Message "Registered scheduled task '$TaskName' (Schedule=$Schedule, Script=$tempScript)"

    Clear-DriveToolsStatus
}

# =====================================================================
#  EXPORT MODULE MEMBERS
# =====================================================================

Export-ModuleMember -Function *-Drive*, Get-DriveToolsStatus, Set-DriveToolsStatus, Clear-DriveToolsStatus, Write-DriveToolsLog, Get-DriveToolsRootPath
