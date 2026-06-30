#Requires -Version 5.1
<#
.SYNOPSIS
    Automated Pester testing suite for the DriveTools module framework.
.DESCRIPTION
    Executes structural unit tests, type validation checks, mock safety verification,
    and state serialization path analysis in an isolated ephemeral sandbox environment.
.NOTES
    Optimized for Pester v5+ and Windows PowerShell 5.1 runtime parameters.
#>

$ModuleRoot = Join-Path $PSScriptRoot "..\src\DriveTools.psm1"

Describe "DriveTools Core Architecture Test Suite" {
    
    BeforeAll {
        Write-Host "[Test Setup] Initializing virtual sandbox environment..." -ForegroundColor Cyan
        
        # Force import of the verified module framework
        if (Test-Path $ModuleRoot) {
            Import-Module $ModuleRoot -Force
        } else {
            throw "Critical Setup Fault: Module root script file could not be resolved at target destination: $ModuleRoot"
        }

        # Parenthesize static method call to resolve the PowerShell 5.1 parameter parsing constraint
        $TemporaryTempPath = [System.IO.Path]::GetTempPath()
        $Script:TestLogDir = Join-Path $TemporaryTempPath "DriveTools_TestSandbox_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -Path $Script:TestLogDir -ItemType Directory -Force | Out-Null

        # Backup original module tracking root and overwrite with sandbox anchor
        $Script:OrigLogRoot = $Script:DriveTools_DefaultLogRoot
        $Script:DriveTools_DefaultLogRoot = $Script:TestLogDir
    }

    AfterAll {
        Write-Host "[Test Teardown] Tearing down virtual sandbox environment..." -ForegroundColor Cyan
        
        # Restore module tracking roots
        $Script:DriveTools_DefaultLogRoot = $Script:OrigLogRoot

        # Safely remove testing directory assets
        if (Test-Path $Script:TestLogDir) {
            Remove-Item -Path $Script:TestLogDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Force garbage collection recycling to release open database file handles
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }

    # ── SECTION 1: C# APPDOMAIN TYPE INTEGRITY ───────────────────────────────
    Context ".NET Process AppDomain Precompiled Assembly Verification" {
        
        It "Should have compiled and registered the DriveTools.Core.AuditEngine type" {
            $Type = [System.Management.Automation.PSTypeName]'DriveTools.Core.AuditEngine'
            $Type.Type | Should -Not -BeNullOrEmpty
        }

        It "Should have compiled and registered the DriveTools.Core.StorageProfiler type" {
            $Type = [System.Management.Automation.PSTypeName]'DriveTools.Core.StorageProfiler'
            $Type.Type | Should -Not -BeNullOrEmpty
        }

        It "Should successfully instantiate the AuditEngine class with safe bounded structures" {
            $MockLog = Join-Path $Script:TestLogDir "engine_init_test.csv"
            $Engine = [DriveTools.Core.AuditEngine]::new(5000, $MockLog)
            
            $Engine | Should -Not -BeNullOrEmpty
            $Engine.ProcessedCount | Should -Be 0
            $Engine.ErrorCount | Should -Be 0
            $Engine.FileQueue | Should -Not -BeNullOrEmpty
        }
    }

    # ── SECTION 2: LOGGING & SERIALIZATION STATE ────────────────────────────
    Context "Telemetry Logging and Status Serialization Subsystems" {
        
        It "Should generate a valid log file entry with clean timestamps" {
            $TestMessage = "Automated testing transaction token trace entry."
            Write-DriveToolsLog -Message $TestMessage -Level "Info"
            
            $FileDate = Get-Date -Format 'yyyy-MM-dd'
            $ExpectedLogFile = Join-Path $Script:TestLogDir "DriveTools_${FileDate}.log"
            
            Test-Path $ExpectedLogFile | Should -Be $true
            $Content = Get-Content -Path $ExpectedLogFile -Raw
            $Content | Should -Match "\[Info\] $TestMessage"
        }

        It "Should atomically serialize process task profiles to disk as a JSON string" {
            Clear-DriveToolsStatus
            Set-DriveToolsStatus -Operation "UnitTesting" -Details "Verifying serialization parameters"
            
            $ExpectedStatusFile = Join-Path $Script:TestLogDir "DriveTools_Status.json"
            Test-Path $ExpectedStatusFile | Should -Be $true
            
            $StatusObject = Get-DriveToolsStatus
            $StatusObject.Operation | Should -Be "UnitTesting"
            $StatusObject.Details | Should -Be "Verifying serialization parameters"
        }

        It "Should completely erase the status json configuration node upon clear invocation" {
            Set-DriveToolsStatus -Operation "PurgeTest" -Details "Pending erasure"
            Clear-DriveToolsStatus
            
            $ExpectedStatusFile = Join-Path $Script:TestLogDir "DriveTools_Status.json"
            Test-Path $ExpectedStatusFile | Should -Be $false
            
            $StatusObject = Get-DriveToolsStatus
            $StatusObject.Operation | Should -BeNullOrEmpty
        }
    }

    # ── SECTION 3: MOCK PROTECTION PATH VERIFICATION ────────────────────────
    Context "Non-Destructive Mock Safety Path Verification" {
        
        It "Should execute the fast audit engine mock tracking path and emit a valid string payload" {
            $MockOutputCsv = Join-Path $Script:TestLogDir "mock_audit_out.csv"
            $Result = Invoke-DriveAuditFast -RootPath "C:\" -OutputCsvPath $MockOutputCsv -UseMock
            
            $Result | Should -Be $MockOutputCsv
            Test-Path $MockOutputCsv | Should -Be $true
            $Header = Get-Content -Path $MockOutputCsv -First 1
            $Header | Should -Be "FullName,Length,Extension,LastWriteTime,Hash"
        }

        It "Should route Update-DriveHashCache safely under mock conditions" {
            $MockDb = Join-Path $Script:TestLogDir "mock_cache.db"
            $Result = Update-DriveHashCache -RootPath "C:\" -CachePath $MockDb -UseMock
            
            $Result | Should -Be $MockDb
            Test-Path $MockDb | Should -Be $true
            $JsonContent = Get-Content -Path $MockDb -Raw | ConvertFrom-Json
            $JsonContent."MockFile.txt".Hash | Should -Be "MOCKHASH"
        }

        It "Should preserve drive topology blocks intact when running Categorize in DryRun mode" {
            $TestSandboxFolder = Join-Path $Script:TestLogDir "categorize_sandbox"
            New-Item -Path $TestSandboxFolder -ItemType Directory -Force | Out-Null
            
            $TargetFile = Join-Path $TestSandboxFolder "test_unity_asset.unity"
            Set-Content -Path $TargetFile -Value "Fake binary assets signature data payload block."
            
            # Executing live categorized DryRun should never move files or allocate physical subfolders
            Invoke-DriveCategorize -RootPath $TestSandboxFolder -DryRun
            
            Test-Path $TargetFile | Should -Be $true
            Test-Path (Join-Path $TestSandboxFolder "Projects") | Should -Be $false
        }
    }

    # ── SECTION 4: ROBUST BOUNDARY EXCEPTION HANDLING ───────────────────────
    Context "Robust Defensive Exception Boundary Handling" {
        
        It "Should gracefully handle UnauthorizedAccessException or deep folder access errors" {
            # Standardized Poster v5 block check verification ensures pipeline errors don't collapse tests
            { Show-DriveVisualMap -RootPath "C:\" -MaxDepth 1 -OutputPath (Join-Path $Script:TestLogDir "vmap.txt") } | Should -Not -Throw
        }

        It "Should break cleanly with a descriptive log entry if an un-hydrated cache database is queried for dedup" {
            $EmptySandbox = Join-Path $Script:TestLogDir "empty_sandbox"
            New-Item -Path $EmptySandbox -ItemType Directory -Force | Out-Null
            
            $MissingCacheDb = Join-Path $Script:TestLogDir "non_existent_cache_index.db"
            
            # Temporarily point log directory to a custom subfolder path context
            $Script:DriveTools_DefaultLogRoot = Join-Path $Script:TestLogDir "broken_scope_path"
            
            $LogFileDate = Get-Date -Format 'yyyy-MM-dd'
            $CurrentLogFile = Join-Path $Script:OrigLogRoot "DriveTools_${LogFileDate}.log"
            $InitialLineCount = if (Test-Path $CurrentLogFile) { (Get-Content $CurrentLogFile).Count } else { 0 }
            
            Resolve-DriveDuplicates -RootPath $EmptySandbox -DryRun
            
            $FinalLineCount = if (Test-Path $CurrentLogFile) { (Get-Content $CurrentLogFile).Count } else { 0 }
            $NewLines = if ($FinalLineCount -gt $InitialLineCount) { Get-Content $CurrentLogFile | Select-Object -Last ($FinalLineCount - $InitialLineCount) } else { @() }
            
            $NewLines -join " " | Should -Match "Cache index database missing"
        }
    }
}