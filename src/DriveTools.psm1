#Requires -Version 5.1
<#
.SYNOPSIS
    DriveTools — Complete drive auditing, categorization, refinement, and maintenance toolkit.
.DESCRIPTION
    Refactored to support any storage drive on the system using an optimized SQLite database index,
    memory-safe queue directory traversal, ultra-high-speed WizTree MFT ingestion, and comprehensive
    high-performance progress telemetry visualization.
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
        
        $menuArgs = @($i, $d.Name, $d.VolumeLabel, $freeGB, $totalGB)
        Write-Host ("[{0}] {1} ({2}) - {3} GB free of {4} GB" -f $menuArgs)
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
    $logArgs = @(Get-Date)
    $logFile = Join-Path $Script:DriveTools_DefaultLogRoot ("DriveTools_{0:yyyy-MM-dd}.log" -f $logArgs)
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
        # PSAvoidEmptyCatchBlock explanation: Ignore serialization lock constraints to keep tasks uninterrupted
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
        # PSAvoidEmptyCatchBlock explanation: Safe fallback bypass for concurrent handle access
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
            # PSAvoidEmptyCatchBlock explanation: Fallback to active heap snapshot reference safely
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
    [CmdletBinding()]
    param(
        [string]$RootPath,
        [string]$CachePath,
        [switch]$UseMock,
        [switch]$UseWizTree,
        [string]$WizTreePath = 'C:\Program Files\WizTree\WizTree64.exe'
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

    $connectionString = "Data Source=$CachePath;Version=3;Pooling=False;"
    $conn = New-Object System.Data.SQLite.SQLiteConnection($connectionString)
    
    $transaction = $null
    $initCmd     = $null
    $checkCmd    = $null
    $insertCmd   = $null

    try {
        $conn.Open()

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
        $initCmd.Dispose()
        $initCmd = $null

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

        $totalProcessed = 0

        if ($UseWizTree) {
            if (-not (Test-Path $WizTreePath)) {
                throw "WizTree executable mapping target reference not found at: $WizTreePath"
            }
            $TempCsv = [System.IO.Path]::GetTempFileName()
            $procArgs = @(
                "`"$resolvedPath`"",
                "/export=`"$TempCsv`"",
                "/exportfolders=0",
                "/admin=1",
                "/exportdrivecapacity=0"
            )
            
            Write-Verbose "[WizTree] Launching direct MFT binary database export to temporary mirror file..."
            $WizProcess = Start-Process -FilePath $WizTreePath -ArgumentList $procArgs -Wait -NoNewWindow -PassThru
            if ($WizProcess.ExitCode -ne 0) {
                Write-DriveToolsLog -Message "WizTree exited with warning anomalies. Confirm shell elevation constraints." -Level "Warning"
            }

            Write-Verbose "[WizTree] MFT Dump complete. Parsing raw CSV node stream tokens..."
            Add-Type -AssemblyName "Microsoft.VisualBasic"
            $parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($TempCsv)
            $parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
            $parser.SetDelimiters(",")
            $parser.HasFieldsEnclosedInQuotes = $true

            $headerFound = $false
            while (-not $parser.EndOfData -and -not $headerFound) {
                $fields = $parser.ReadFields()
                if ($fields -and $fields[0] -eq "File Name") { $headerFound = $true }
            }

            while (-not $parser.EndOfData) {
                $fields = $parser.ReadFields()
                if (-not $fields -or $fields.Count -lt 5) { continue }

                $filePath = $fields[0]
                $length = [int64]0
                if (-not [int64]::TryParse($fields[2], [ref]$length)) { continue }

                $dateStr = $fields[4]
                $lastWrite = $dateStr
                $parsedDate = [DateTime]::MinValue
                if ([DateTime]::TryParse($dateStr, [ref]$parsedDate)) {
                    $lastWrite = $parsedDate.ToString('o')
                }

                $totalProcessed++
                if ($totalProcessed % 5000 -eq 0) {
                    $progressArgs = @('Update-DriveHashCache (WizTree Engine)', "Processed nodes count: $totalProcessed", $totalProcessed)
                    Write-Progress -Activity $progressArgs[0] -Status $progressArgs[1] -Id 1
                    Write-Verbose ("{0} nodes processed into transactional database cache..." -f $totalProcessed)
                }

                $hash = $null
                $pCheckName.Value = $filePath
                
                $reader = $checkCmd.ExecuteReader()
                $cacheHit = $false
                try {
                    if ($reader.Read()) {
                        $cachedLen  = $reader.GetInt64(0)
                        $cachedTime = $reader.GetString(1)
                        if ($cachedLen -eq $length -and $cachedTime -eq $lastWrite) {
                            $hash = $reader.GetString(2)
                            $cacheHit = $true
                        }
                    }
                } finally {
                    $reader.Close()
                    $reader.Dispose()
                }

                if (-not $cacheHit) {
                    try {
                        # Active I/O Telemetry Intercept for Heavy Asset Nodes
                        if ($length -gt 52428800) {
                            $mbSize = [math]::Round($length / 1MB, 2)
                            Write-Verbose ("  [Heavy I/O Checksum] Hashing large asset node ({0} MB): {1}" -f $mbSize, $filePath)
                        }
                        $hash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                    } catch {
                        # PSAvoidEmptyCatchBlock explanation: Suppress read locked operational nodes safely
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
            }
            $parser.Close()
            $parser.Dispose()
            if (Test-Path $TempCsv) { Remove-Item $TempCsv -Force }

        } else {
            $dirQueue = [System.Collections.Generic.Queue[string]]::new()
            $dirQueue.Enqueue($resolvedPath)

            while ($dirQueue.Count -gt 0) {
                $currentDir = $dirQueue.Dequeue()
                $filePaths = $null
                $subDirs = $null

                try {
                    $filePaths = [System.IO.Directory]::GetFiles($currentDir)
                    $subDirs = [System.IO.Directory]::GetDirectories($currentDir)
                } catch [System.UnauthorizedAccessException] {
                    continue
                } catch [System.IO.IOException] {
                    continue
                }

                foreach ($subDir in $subDirs) { $dirQueue.Enqueue($subDir) }

                foreach ($filePath in $filePaths) {
                    try {
                        $fileInfo = New-Object System.IO.FileInfo($filePath)
                        $length   = $fileInfo.Length
                        $lastWrite = $fileInfo.LastWriteTime.ToString('o')
                        $hash     = $null

                        $totalProcessed++
                        if ($totalProcessed % 5000 -eq 0) {
                            $progressArgs = @('Update-DriveHashCache (Queue Engine)', "Traversing directory trees: $totalProcessed items evaluated", $totalProcessed)
                            Write-Progress -Activity $progressArgs[0] -Status $progressArgs[1] -Id 1
                            Write-Verbose ("{0} sequential nodes traversed and cached..." -f $totalProcessed)
                        }

                        $pCheckName.Value = $filePath
                        
                        $reader = $checkCmd.ExecuteReader()
                        $cacheHit = $false
                        try {
                            if ($reader.Read()) {
                                $cachedLen  = $reader.GetInt64(0)
                                $cachedTime = $reader.GetString(1)
                                if ($cachedLen -eq $length -and $cachedTime -eq $lastWrite) {
                                    $hash = $reader.GetString(2)
                                    $cacheHit = $true
                                }
                            }
                        } finally {
                            $reader.Close()
                            $reader.Dispose()
                        }

                        if (-not $cacheHit) {
                            try {
                                if ($length -gt 52428800) {
                                    $mbSize = [math]::Round($length / 1MB, 2)
                                    Write-Verbose ("  [Heavy I/O Checksum] Hashing large asset node ({0} MB): {1}" -f $mbSize, $filePath)
                                }
                                $hash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                            } catch {
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
                        # PSAvoidEmptyCatchBlock explanation: Keep traversal operations continuous on isolated file skips
                    }
                }
            }
        }
        $transaction.Commit()
    } catch {
        if ($null -ne $transaction) {
            try { $transaction.Rollback() } catch { 
                # Safe fallback bypass
            }
        }
        throw $_
    } finally {
        if ($null -ne $checkCmd) { $checkCmd.Dispose() }
        if ($null -ne $insertCmd) { $insertCmd.Dispose() }
        if ($null -ne $initCmd) { $initCmd.Dispose() }
        if ($null -ne $transaction) { $transaction.Dispose() }
        $conn.Close()
        $conn.Dispose()
        
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        
        Write-Progress -Activity 'Update-DriveHashCache' -Completed -Id 1
        Clear-DriveToolsStatus
    }

    return $CachePath
}

function Invoke-DriveAuditFast {
    [CmdletBinding()]
    param(
        [string]$RootPath,
        [string]$OutputCsvPath,
        [switch]$IncludeHashes,
        [switch]$UseMock,
        [switch]$UseWizTree,
        [string]$WizTreePath = 'C:\Program Files\WizTree\WizTree64.exe'
    )
    $resolvedPath = Get-DriveToolsRootPath -Path $RootPath
    if (-not $OutputCsvPath) {
        $dateArgs = @(Get-Date)
        $OutputCsvPath = Join-Path $env:USERPROFILE ("Desktop\DriveTools_AuditFast_{0:yyyyMMdd_HHmmss}.csv" -f $dateArgs)
    }

    if ($UseMock) {
        "FullName,Length,Extension,LastWriteTime,Hash" | Set-Content -Path $OutputCsvPath -Encoding UTF8
        return $OutputCsvPath
    }

    Set-DriveToolsStatus -Operation "Audit" -Details "Fast audit (IncludeHashes=$IncludeHashes, UseWizTree=$UseWizTree)"
    '"FullName","Length","Extension","LastWriteTime","Hash"' | Set-Content -Path $OutputCsvPath -Encoding UTF8

    $writer = $null
    $totalProcessed = 0
    try {
        $writer = [System.IO.StreamWriter]::new($OutputCsvPath, $true, [System.Text.Encoding]::UTF8)

        if ($UseWizTree) {
            if (-not (Test-Path $WizTreePath)) {
                throw "WizTree executable mapping target reference not found at: $WizTreePath"
            }
            $TempCsv = [System.IO.Path]::GetTempFileName()
            $procArgs = @(
                "`"$resolvedPath`"",
                "/export=`"$TempCsv`"",
                "/exportfolders=0",
                "/admin=1",
                "/exportdrivecapacity=0"
            )
            
            Write-Verbose "[WizTree] Launching direct MFT dump stream parsing..."
            [void](Start-Process -FilePath $WizTreePath -ArgumentList $procArgs -Wait -NoNewWindow)

            Add-Type -AssemblyName "Microsoft.VisualBasic"
            $parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($TempCsv)
            $parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
            $parser.SetDelimiters(",")
            $parser.HasFieldsEnclosedInQuotes = $true

            $headerFound = $false
            while (-not $parser.EndOfData -and -not $headerFound) {
                $fields = $parser.ReadFields()
                if ($fields -and $fields[0] -eq "File Name") { $headerFound = $true }
            }

            while (-not $parser.EndOfData) {
                $fields = $parser.ReadFields()
                if (-not $fields -or $fields.Count -lt 5) { continue }

                $filePath = $fields[0]
                $len = [int64]0
                [void][int64]::TryParse($fields[2], [ref]$len)
                $ext = [System.IO.Path]::GetExtension($filePath)

                $dateStr = $fields[4]
                $time = $dateStr
                if ([DateTime]::TryParse($dateStr, [ref]$parsedDate)) {
                    $time = $parsedDate.ToString('o')
                }

                $totalProcessed++
                if ($totalProcessed % 5000 -eq 0) {
                    $progressArgs = @('Invoke-DriveAuditFast (WizTree Engine)', "Audited records count: $totalProcessed", $totalProcessed)
                    Write-Progress -Activity $progressArgs[0] -Status $progressArgs[1] -Id 2
                    Write-Verbose ("{0} file records written to CSV archive target..." -f $totalProcessed)
                }

                $hash = $null
                if ($IncludeHashes) {
                    try {
                        if ($len -gt 52428800) {
                            $mbSize = [math]::Round($len / 1MB, 2)
                            Write-Verbose ("  [Heavy I/O Checksum] Hashing large asset node ({0} MB): {1}" -f $mbSize, $filePath)
                        }
                        $hash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                    } catch {
                        # PSAvoidEmptyCatchBlock explanation: Skip logging transient file reads cleanly
                    }
                }

                $escapedPath = $filePath -replace '"', '""'
                $fmtArgs = @($escapedPath, $len, $ext, $time, $hash)
                $line = '"{0}",{1},"{2}","{3}","{4}"' -f $fmtArgs
                $writer.WriteLine($line)
            }
            $parser.Close()
            $parser.Dispose()
            if (Test-Path $TempCsv) { Remove-Item $TempCsv -Force }

        } else {
            $dirQueue = [System.Collections.Generic.Queue[string]]::new()
            $dirQueue.Enqueue($resolvedPath)

            while ($dirQueue.Count -gt 0) {
                $currentDir = $dirQueue.Dequeue()
                $filePaths = $null
                $subDirs = $null

                try {
                    $filePaths = [System.IO.Directory]::GetFiles($currentDir)
                    $subDirs = [System.IO.Directory]::GetDirectories($currentDir)
                } catch [System.UnauthorizedAccessException] {
                    continue
                } catch [System.IO.IOException] {
                    continue
                }

                foreach ($subDir in $subDirs) { $dirQueue.Enqueue($subDir) }

                foreach ($filePath in $filePaths) {
                    try {
                        $fileInfo = New-Object System.IO.FileInfo($filePath)
                        $len = $fileInfo.Length
                        $hash = $null
                        if ($IncludeHashes) {
                            try { 
                                if ($len -gt 52428800) {
                                    $mbSize = [math]::Round($len / 1MB, 2)
                                    Write-Verbose ("  [Heavy I/O Checksum] Hashing large asset node ({0} MB): {1}" -f $mbSize, $filePath)
                                }
                                $hash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash 
                            } catch { 
                                # PSAvoidEmptyCatchBlock explanation: Skip access flags
                            }
                        }
                        
                        $totalProcessed++
                        if ($totalProcessed % 5000 -eq 0) {
                            $progressArgs = @('Invoke-DriveAuditFast (Queue Engine)', "Audited rows count: $totalProcessed", $totalProcessed)
                            Write-Progress -Activity $progressArgs[0] -Status $progressArgs[1] -Id 2
                            Write-Verbose ("{0} active nodes written to flat audit index table..." -f $totalProcessed)
                        }

                        $escapedPath = $filePath -replace '"', '""'
                        $ext = $fileInfo.Extension
                        $time = $fileInfo.LastWriteTime.ToString('o')

                        $fmtArgs = @($escapedPath, $len, $ext, $time, $hash)
                        $line = '"{0}",{1},"{2}","{3}","{4}"' -f $fmtArgs
                        $writer.WriteLine($line)
                    } catch {
                        # PSAvoidEmptyCatchBlock explanation: Suppress isolated path reading errors
                    }
                }
            }
        }
    } finally {
        if ($null -ne $writer) { $writer.Close(); $writer.Dispose() }
        Write-Progress -Activity 'Invoke-DriveAuditFast' -Completed -Id 2
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
        $dirQueue = [System.Collections.Generic.Queue[string]]::new()
        $dirQueue.Enqueue($resolvedPath)

        while ($dirQueue.Count -gt 0) {
            $currentDir = $dirQueue.Dequeue()
            $filePaths = $null
            $subDirs = $null

            try {
                $filePaths = [System.IO.Directory]::GetFiles($currentDir)
                $subDirs = [System.IO.Directory]::GetDirectories($currentDir)
            } catch [System.UnauthorizedAccessException] {
                continue
            } catch [System.IO.IOException] {
                continue
            }

            foreach ($subDir in $subDirs) { $dirQueue.Enqueue($subDir) }

            foreach ($filePath in $filePaths) {
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
        Write-DriveToolsLog -Message "Cache index database missing. Generate cache items utilizing Update-DriveHashCache first." -Level "Warning"
        return
    }

    Set-DriveToolsStatus -Operation "Duplicates" -Details "DryRun=$DryRun executing index analytics matching"
    Import-SQLiteDependency

    $connectionString = "Data Source=$CachePath;Version=3;Pooling=False;"
    $conn = New-Object System.Data.SQLite.SQLiteConnection($connectionString)
    $queryCmd = $null
    $delCmd = $null
    $reader = $null

    try {
        $conn.Open()
        $queryCmd = $conn.CreateCommand()
        $queryCmd.CommandText = @'
            SELECT FullName, Hash FROM FileInventory 
            WHERE Hash IN (SELECT Hash FROM FileInventory GROUP BY Hash HAVING COUNT(*) > 1)
            ORDER BY Hash, LastWriteTime DESC
'@

        $reader = $queryCmd.ExecuteReader()
        $currentHash = $null

        while ($reader.Read()) {
            $filePath = $reader.GetString(0)
            $fileHash = $reader.GetString(1)

            if ($fileHash -ne $currentHash) {
                $currentHash = $fileHash
                Write-DriveToolsLog -Message "Keeping master node reference: $filePath"
                continue
            }

            if ($DryRun) {
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
                        $delCmd.Dispose()
                        $delCmd = $null

                        Write-DriveToolsLog -Message "Deleted entry reference: $filePath"
                    } catch {
                        Write-DriveToolsLog -Message "Unable to physically touch target node path: $filePath" -Level "Warning"
                    }
                }
            }
        }
    } finally {
        if ($null -ne $reader) { $reader.Close(); $reader.Dispose() }
        if ($null -ne $queryCmd) { $queryCmd.Dispose() }
        if ($null -ne $delCmd) { $delCmd.Dispose() }
        $conn.Close()
        $conn.Dispose()
        
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        
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
        $discoveredDirs = New-Object System.Collections.Generic.List[string]
        $dirQueue = [System.Collections.Generic.Queue[string]]::new()
        $dirQueue.Enqueue($resolvedPath)

        while ($dirQueue.Count -gt 0) {
            $currentDir = $dirQueue.Dequeue()
            try {
                $subDirs = [System.IO.Directory]::GetDirectories($currentDir)
                foreach ($subDir in $subDirs) {
                    $discoveredDirs.Add($subDir)
                    $dirQueue.Enqueue($subDir)
                }
            } catch [System.UnauthorizedAccessException] {
                # PSAvoidEmptyCatchBlock explanation: Skip restricted locations during system clearance loops
            } catch [System.IO.IOException] {
                # PSAvoidEmptyCatchBlock explanation: Skip transient IO lock visibility boundary shifts
            }
        }

        $sortedDirs = $discoveredDirs | Sort-Object Length -Descending
        
        foreach ($dir in $sortedDirs) {
            try {
                if (([System.IO.Directory]::GetFileSystemEntries($dir)).Count -eq 0) {
                    if ($PSCmdlet.ShouldProcess($dir, "Remove empty directory")) {
                        [System.IO.Directory]::Delete($dir)
                        Write-DriveToolsLog -Message "Removed empty directory: $dir"
                    }
                }
            } catch {
                Write-DriveToolsLog -Message "Failed to remove empty directory tree node: $dir" -Level "Warning"
            }
        }
    }

    if ($ReportDuplicates) {
        $CachePath = Join-Path $Script:DriveTools_DefaultLogRoot 'DriveTools_HashCache.db'
        if (Test-Path $CachePath) {
            Import-SQLiteDependency
            $connectionString = "Data Source=$CachePath;Version=3;Pooling=False;"
            $conn = New-Object System.Data.SQLite.SQLiteConnection($connectionString)
            $queryCmd = $null
            $reader = $null
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
            } catch {
                Write-DriveToolsLog -Message "Error generating duplicate report index sets from database." -Level "Warning"
            } finally {
                if ($null -ne $reader) { $reader.Close(); $reader.Dispose() }
                if ($null -ne $queryCmd) { $queryCmd.Dispose() }
                if ($null -ne $conn) { $conn.Close(); $conn.Dispose() }
                
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
            }
        } else {
            Write-DriveToolsLog -Message "Database cache missing; cannot generate accurate duplication summaries." -Level "Warning"
        }
    }

    if ($CompressArchives) {
        $archiveRoot = Join-Path $resolvedPath 'Archives'
        if (Test-Path $archiveRoot) {
            $zipArgs = @(Get-Date)
            $zipPath = Join-Path $resolvedPath ("Archives_{0:yyyyMMdd_HHmmss}.zip" -f $zipArgs)
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
