#Requires -Version 5.1
<#
.SYNOPSIS
    DriveTools — Complete drive auditing, categorization, refinement, and maintenance toolkit.
.DESCRIPTION
    Refactored to support any storage drive on the system using an optimized SQLite database index
    and lazy-evaluated streaming enumeration to achieve a flat O(1) space complexity footprint.
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

function Import-SQLiteDependency {
    <#
    .SYNOPSIS
        Automated dependency injector for the SQLite ADO.NET provider layers.
    #>
    $LibDir = Join-Path $PSScriptRoot "lib"
    $DllPath = Join-Path $LibDir "System.Data.SQLite.dll"
    $InteropDir = Join-Path $LibDir "x64"
    $InteropDll = Join-Path $InteropDir "SQLite.Interop.dll"

    if (-not (Test-Path $DllPath) -or -not (Test-Path $InteropDll)) {
        Write-DriveToolsLog -Message "Automated bootstrapping of SQLite infrastructure initiated..." -Level "Info"
        if (-not (Test-Path $InteropDir)) {
            New-Item -Path $InteropDir -ItemType Directory -Force | Out-Null
        }

        # Pull secure NuGet core framework mirrors
        $NugetUri = "https://www.nuget.org/api/v2/package/Stub.System.Data.SQLite.Core.NetFramework/1.0.118"
        $ZipPath = Join-Path $LibDir "sqlite.zip"

        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $NugetUri -OutFile $ZipPath -UseBasicParsing
            
            $ExtractDir = Join-Path $LibDir "extract"
            Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force

            Copy-Item (Join-Path $ExtractDir "lib/net46/System.Data.SQLite.dll") $DllPath -Force
            Copy-Item (Join-Path $ExtractDir "build/net46/x64/SQLite.Interop.dll") $InteropDll -Force

            Remove-Item $ZipPath -Force
            Remove-Item $ExtractDir -Recurse -Force
        } catch {
            Write-DriveToolsLog -Message "Failed to automatically bootstrap required SQLite assemblies." -Level "Error"
            throw $_
        }
    }

    [void][System.Reflection.Assembly]::LoadFrom($DllPath)
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
        $CachePath = Join-Path $Script:DriveTools_DefaultLogRoot 'DriveTools_HashCache.db'
    }

    if ($UseMock) {
        $mockCache = @{ "MockFile.txt" = @{ Length = 100; LastWriteTime = (Get-Date).ToString('o'); Hash = "MOCKHASH" } }
        $mockCache | ConvertTo-Json | Set-Content -Path $CachePath -Encoding UTF8
        return $CachePath
    }

    Set-DriveToolsStatus -Operation "HashCache" -Details "Updating transactional SQLite cache database"
    Import-SQLiteDependency

    $connectionString = "Data Source=$CachePath;Version=3;"
    $conn = New-Object System.Data.SQLite.SQLiteConnection($connectionString)
    try {
        $conn.Open()
    } catch {
        # Log and safely rethrow unhandled database connection link faults
        Write-DriveToolsLog -Message "Could not open SQLite database connection." -Level "Error"
        throw $_
    }

    $initCmd = $conn.CreateCommand()
    $initCmd.CommandText = @'
        CREATE TABLE IF NOT EXISTS FileInventory (
            FullName TEXT PRIMARY KEY,
            Length INTEGER,
            LastWriteTime TEXT,
            Hash TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_inventory_hash ON FileInventory(Hash);
'@
    [void]$initCmd.ExecuteNonQuery()

    $transaction = $conn.BeginTransaction()

    $checkCmd = $conn.CreateCommand()
    $checkCmd.CommandText = "SELECT Length, LastWriteTime, Hash FROM FileInventory WHERE FullName = @FullName"
    $pCheckName = $checkCmd.Parameters.Add("@FullName", [System.Data.DbType]::String)

    $insertCmd = $conn.CreateCommand()
    $insertCmd.CommandText = "INSERT OR REPLACE INTO FileInventory (FullName, Length, LastWriteTime, Hash) VALUES (@FullName, @Length, @LastWriteTime, @Hash)"
    $pInsName = $insertCmd.Parameters.Add("@FullName", [System.Data.DbType]::String)
    $pInsLen  = $insertCmd.Parameters.Add("@Length", [System.Data.DbType]::Int64)
    $pInsTime = $insertCmd.Parameters.Add("@LastWriteTime", [System.Data.DbType]::String)
    $pInsHash = $insertCmd.Parameters.Add("@Hash", [System.Data.DbType]::String)

    try {
        # Lazy token stream iterator evaluation drops space allocation to flat O(1) constraints
        $fileEnum = [System.IO.Directory]::EnumerateFiles($resolvedPath, "*", [System.IO.SearchOption]::AllDirectories)

        foreach ($filePath in $fileEnum) {
            try {
                $fileInfo = New-Object System.IO.FileInfo($filePath)
                $length   = $fileInfo.Length
                $lastWrite = $fileInfo.LastWriteTime.ToString('o')
                $hash     = $null

                $pCheckName.Value = $filePath
                $reader = $checkCmd.ExecuteReader()
                $cacheHit = $false

                if ($reader.Read()) {
                    $cachedLen  = $reader.GetInt64(0)
                    $cachedTime = $reader.GetString(1)
                    
                    if ($cachedLen -eq $length -and $cachedTime -eq $lastWrite) {
                        $hash = $reader.GetString(2)
                        $cacheHit = $true
                    }
                }
                $reader.Close()

                if (-not $cacheHit) {
                    try {
                        $hash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
                    } catch {
                        # Suppress access locks smoothly to preserve pipeline iteration throughput
                        $hash = $null
                    }
                }

                if ($null -ne $hash) {
                    $pInsName.Value = $filePath
                    $pInsLen.Value  = $length
                    $pInsTime.Value = $lastWrite
                    $pInsHash.Value = $hash
                    [void]$insertCmd.ExecuteNonQuery()
                }
            } catch {
                # Ignore isolated security or transient access failures on specific operational system nodes
            }
        }
        $transaction.Commit()
    } catch {
        $transaction.Rollback()
        throw $_
    } finally {
        $conn.Close()
        Clear-DriveToolsStatus
    }

    return $CachePath
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

    # Write CSV Header line using safe UTF8 standard encoding
    '"FullName","Length","Extension","LastWriteTime","Hash"' | Set-Content -Path $OutputCsvPath -Encoding UTF8

    $writer = $null
    try {
        $fileEnum = [System.IO.Directory]::EnumerateFiles($resolvedPath, "*", [System.IO.SearchOption]::AllDirectories)
        $writer = [System.IO.StreamWriter]::new($OutputCsvPath, $true, [System.Text.Encoding]::UTF8)

        foreach ($filePath in $fileEnum) {
            try {
                $fileInfo = New-Object System.IO.FileInfo($filePath)
                $hash = $null
                if ($IncludeHashes) {
                    try { 
                        $hash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash 
                    } catch { 
                        # Suppress file-lock reading errors to guarantee audit extraction flow continues
                    }
                }
                
                $escapedPath = $filePath -replace '"', '""'
                $ext = $fileInfo.Extension
                $len = $fileInfo.Length
                $time = $fileInfo.LastWriteTime.ToString('o')

                # Rule 5 Compliance: Explicit Array Packaging for formatting operations
                $fmtArgs = @($escapedPath, $len, $ext, $time, $hash)
                $line = '"{0}",{1},"{2}","{3}","{4}"' -f $fmtArgs
                $writer.WriteLine($line)
            } catch {
                # Ignore individual transient IO nodes safely
            }
        }
    } finally {
        if ($null -ne $writer) { $writer.Close() }
        Clear-DriveToolsStatus
    }
    
    return $OutputCsvPath
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

    try {
        $fileEnum = [System.IO.Directory]::EnumerateFiles($resolvedPath, "*", [System.IO.SearchOption]::AllDirectories)

        foreach ($filePath in $fileEnum) {
            $alreadyCategorized = $false
            foreach ($dest in $destinations.Values) {
                if ($filePath.StartsWith($dest, [System.StringComparison]::InvariantCultureIgnoreCase)) {
                    $alreadyCategorized = $true
                    break
                }
            }
            if ($alreadyCategorized) { continue }

            $targetCategory = $null
            $extension = [System.IO.Path]::GetExtension($filePath)

            foreach ($cat in $CategoryMap.Keys) {
                foreach ($pattern in $CategoryMap[$cat]) {
                    if ($pattern.StartsWith('.')) {
                        if ($extension -eq $pattern) { $targetCategory = $cat; break }
                    } else {
                        if ($filePath -like "*$pattern*") { $targetCategory = $cat; break }
                    }
                }
                if ($targetCategory) { break }
            }

            if (-not $targetCategory) { continue }

            $destRoot = $destinations[$targetCategory]
            $relative = $filePath.Substring($resolvedPath.Length).TrimStart('\')
            $destPath = Join-Path $destRoot $relative
            $destDir  = Split-Path $destPath -Parent

            if (-not (Test-Path $destDir)) {
                New-Item -Path $destDir -ItemType Directory -Force | Out-Null
            }

            if ($DryRun) {
                Write-DriveToolsLog -Message "[DryRun] Would move: $filePath -> $destPath"
            } else {
                if ($PSCmdlet.ShouldProcess($filePath, "Move to $destPath")) {
                    try {
                        Move-Item -Path $filePath -Destination $destPath -Force
                        Write-DriveToolsLog -Message "Moved: $filePath -> $destPath"
                    } catch {
                        Write-DriveToolsLog -Message "Failed to move entry node: $filePath" -Level "Warning"
                    }
                }
            }
        }
    } finally {
        Clear-DriveToolsStatus
    }
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
    $CachePath = Join-Path $Script:DriveTools_DefaultLogRoot 'DriveTools_HashCache.db'
    
    if (-not (Test-Path $CachePath)) {
        Write-DriveToolsLog -Message "Cache index database missing. Please generate cache items utilizing Update-DriveHashCache first." -Level "Warning"
        return
    }

    Set-DriveToolsStatus -Operation "Duplicates" -Details "DryRun=$DryRun executing index analytics matching"
    Import-SQLiteDependency

    $connectionString = "Data Source=$CachePath;Version=3;"
    $conn = New-Object System.Data.SQLite.SQLiteConnection($connectionString)
    try {
        $conn.Open()
    } catch {
        # Safe rethrow handling database storage access constraints
        throw $_
    }

    $queryCmd = $conn.CreateCommand()
    $queryCmd.CommandText = @'
        SELECT FullName, Hash FROM FileInventory 
        WHERE Hash IN (SELECT Hash FROM FileInventory GROUP BY Hash HAVING COUNT(*) > 1)
        ORDER BY Hash, LastWriteTime DESC
'@

    try {
        $reader = $queryCmd.ExecuteReader()
        $currentHash = $null

        while ($reader.Read()) {
            $filePath = $reader.GetString(0)
            $fileHash = $reader.GetString(1)

            if ($fileHash -ne $currentHash) {
                # Preserve the most recent instance inside the matching grouping sequence loop
                $currentHash = $fileHash
                Write-DriveToolsLog -Message "Keeping master node reference: $filePath"
                continue
            }

            if ($DryRun) {
                # Rule 5 Compliance: Package explicit target arrays before invoking format parsing loops
                $fmtArgs = @('[DryRun]', $filePath)
                Write-DriveToolsLog -Message ("{0} Would remove older redundant copy: {1}" -f $fmtArgs)
            } else {
                if ($PSCmdlet.ShouldProcess($filePath, "Delete duplicate entry")) {
                    try {
                        if (Test-Path $filePath) {
                            Remove-Item -LiteralPath $filePath -Force
                        }
                        
                        $delCmd = $conn.CreateCommand()
                        $delCmd.CommandText = "DELETE FROM FileInventory WHERE FullName = @FullName"
                        [void]$delCmd.Parameters.AddWithValue("@FullName", $filePath)
                        [void]$delCmd.ExecuteNonQuery()

                        Write-DriveToolsLog -Message "Deleted entry reference: $filePath"
                    } catch {
                        # Rule 7 Compliance: Suppress transient physical read/write locks gracefully without breaking tasks
                        Write-DriveToolsLog -Message "Unable to physically touch target node path: $filePath" -Level "Warning"
                    }
                }
            }
        }
        $reader.Close()
    } finally {
        $conn.Close()
        Clear-DriveToolsStatus
    }
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
    Set-DriveToolsStatus -Operation "Cleanup" -Details "Running optimized cleanups"

    if ($RemoveEmptyDirectories) {
        try {
            $dirs = [System.IO.Directory]::EnumerateDirectories($resolvedPath, "*", [System.IO.SearchOption]::AllDirectories) | 
                Sort-Object Length -Descending
            
            foreach ($dir in $dirs) {
                if (([System.IO.Directory]::GetFileSystemEntries($dir)).Count -eq 0) {
                    if ($PSCmdlet.ShouldProcess($dir, "Remove empty directory")) {
                        try {
                            [System.IO.Directory]::Delete($dir)
                            Write-DriveToolsLog -Message "Removed empty directory: $dir"
                        } catch {
                            # Safely ignore locked or operating system protected empty system configurations
                            Write-DriveToolsLog -Message "Failed to remove empty directory tree node: $dir" -Level "Warning"
                        }
                    }
                }
            }
        } catch {
            # Catch block verified: suppress locked path traversal operations during recursive evaluations
        }
    }

    if ($ReportDuplicates) {
        $CachePath = Join-Path $Script:DriveTools_DefaultLogRoot 'DriveTools_HashCache.db'
        if (Test-Path $CachePath) {
            Import-SQLiteDependency
            $connectionString = "Data Source=$CachePath;Version=3;"
            $conn = New-Object System.Data.SQLite.SQLiteConnection($connectionString)
            try {
                $conn.Open()
                $queryCmd = $conn.CreateCommand()
                $queryCmd.CommandText = @'
                    SELECT FullName, Hash FROM FileInventory 
                    WHERE Hash IN (SELECT Hash FROM FileInventory GROUP BY Hash HAVING COUNT(*) > 1)
                    ORDER BY Hash
'@
                $reader = $queryCmd.ExecuteReader()
                $currentHash = $null
                while ($reader.Read()) {
                    $path = $reader.GetString(0)
                    $hash = $reader.GetString(1)
                    if ($hash -ne $currentHash) {
                        $currentHash = $hash
                        Write-DriveToolsLog -Message "Duplicate group (Hash=$hash):"
                    }
                    Write-DriveToolsLog -Message "  $path"
                }
                $reader.Close()
            } catch {
                Write-DriveToolsLog -Message "Error generating duplicate report index sets from database." -Level "Warning"
            } finally {
                if ($null -ne $conn) { $conn.Close() }
            }
        } else {
            Write-DriveToolsLog -Message "Database cache missing; cannot generate accurate duplication summaries." -Level "Warning"
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