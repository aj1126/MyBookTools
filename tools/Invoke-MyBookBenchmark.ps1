#Requires -Version 5.1
#Requires -Modules MyBookTools
<#
.SYNOPSIS
    MyBookTools Performance Benchmark

.DESCRIPTION
    Measures wall-clock time and memory delta for each major MyBookTools
    operation against a synthetic test tree.  Results are printed to the
    console and exported to a CSV on the Desktop.

.PARAMETER TestRoot
    Temporary directory used as the synthetic "drive".
    Defaults to a folder in $env:TEMP — cleaned up automatically.

.PARAMETER FilesPerCategory
    Number of dummy files to create per category.
    Increase for more realistic large-drive simulations.

.EXAMPLE
    .\Invoke-MyBookBenchmark.ps1
    .\Invoke-MyBookBenchmark.ps1 -FilesPerCategory 500
#>
param(
    [string]$TestRoot          = (Join-Path $env:TEMP "MyBookBenchmark_$(Get-Random)"),
    [int]   $FilesPerCategory  = 50,
    [string]$ResultCsvPath     = "$env:USERPROFILE\Desktop\MyBookBenchmark_$(Get-Date -f yyyyMMdd_HHmmss).csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module MyBookTools -Force

# ── Helpers ───────────────────────────────────────────────────────────────────
function New-BenchmarkTree {
    param([string]$Root, [int]$Count)

    $extensions = @('.wav','.mp3','.mp4','.jpg','.png','.psd','.zip',
                    '.exe','.log','.csproj','.dll','.txt','.bak','.rar')
    $words      = @('Unity','Project','backup','UPLOADS','installer','export','media','source','asset')

    $dirs = @(
        (Join-Path $Root 'Projects\Perseus\Assets'),
        (Join-Path $Root 'Media\Photos'),
        (Join-Path $Root 'Media\Videos'),
        (Join-Path $Root 'Archives\export'),
        (Join-Path $Root 'Uploads'),
        (Join-Path $Root 'System\installer'),
        (Join-Path $Root 'Misc')
    )

    foreach ($d in $dirs) {
        New-Item -Path $d -ItemType Directory -Force | Out-Null
    }

    for ($i = 1; $i -le $Count; $i++) {
        $dir  = $dirs | Get-Random
        $ext  = $extensions | Get-Random
        $word = $words | Get-Random
        $name = "{0}_{1:D4}{2}" -f $word, $i, $ext
        $path = Join-Path $dir $name
        # Write random bytes (0–4 KB) to simulate real files
        $bytes = New-Object byte[] (Get-Random -Minimum 0 -Maximum 4096)
        (New-Object System.Random).NextBytes($bytes)
        [System.IO.File]::WriteAllBytes($path, $bytes)
    }

    # Seed a few intentional duplicates
    $dup = Join-Path $dirs[0] 'duplicate_original.wav'
    [System.IO.File]::WriteAllBytes($dup, [byte[]](1..512))
    Copy-Item $dup (Join-Path $dirs[1] 'duplicate_copy1.wav')
    Copy-Item $dup (Join-Path $dirs[2] 'duplicate_copy2.wav')

    # Seed an empty directory
    New-Item -Path (Join-Path $Root 'EmptyFolder') -ItemType Directory -Force | Out-Null
}

function Measure-Operation {
    param([string]$Name, [scriptblock]$Action)

    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    $memBefore = [System.GC]::GetTotalMemory($false)

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $result = & $Action
        $status = 'OK'
    } catch {
        $result = $null
        $status = "ERROR: $_"
    }
    $sw.Stop()

    [System.GC]::Collect()
    $memAfter = [System.GC]::GetTotalMemory($false)

    [PSCustomObject]@{
        Operation    = $Name
        ElapsedMs    = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        ElapsedSec   = [math]::Round($sw.Elapsed.TotalSeconds, 3)
        MemDeltaKB   = [math]::Round(($memAfter - $memBefore) / 1KB, 1)
        Status       = $status
        ResultPreview= ($result | Out-String).Trim() | ForEach-Object {
                           if ($_.Length -gt 120) { $_.Substring(0,120) + '…' } else { $_ }
                       }
    }
}

# ── Setup ─────────────────────────────────────────────────────────────────────
Write-Host "`n  MyBookTools Performance Benchmark" -ForegroundColor Cyan
Write-Host "  ══════════════════════════════════" -ForegroundColor DarkGray
Write-Host "  Test root       : $TestRoot"
Write-Host "  Files / category: $FilesPerCategory"
Write-Host ""

Write-Host "  [setup] Building synthetic drive tree…" -ForegroundColor Yellow
New-BenchmarkTree -Root $TestRoot -Count $FilesPerCategory
$fileCount = (Get-ChildItem $TestRoot -Recurse -File).Count
Write-Host "  [setup] $fileCount files created.`n" -ForegroundColor Green

$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$cachePath = Join-Path $TestRoot 'BenchHashCache.json'

# ── Benchmark operations ──────────────────────────────────────────────────────

$results.Add((Measure-Operation "Invoke-MyBookAuditFast (no hashes)" {
    Invoke-MyBookAuditFast -RootPath $TestRoot `
        -OutputCsvPath (Join-Path $TestRoot 'AuditFast_noHash.csv')
}))

$results.Add((Measure-Operation "Invoke-MyBookAuditFast (with hashes)" {
    Invoke-MyBookAuditFast -RootPath $TestRoot -IncludeHashes `
        -OutputCsvPath (Join-Path $TestRoot 'AuditFast_withHash.csv')
}))

$results.Add((Measure-Operation "Update-MyBookHashCache (cold — no cache)" {
    Remove-Item $cachePath -ErrorAction SilentlyContinue
    Update-MyBookHashCache -RootPath $TestRoot -CachePath $cachePath
}))

$results.Add((Measure-Operation "Update-MyBookHashCache (warm — cache exists)" {
    Update-MyBookHashCache -RootPath $TestRoot -CachePath $cachePath
}))

$results.Add((Measure-Operation "Show-MyBookVisualMap (depth 5)" {
    Show-MyBookVisualMap -RootPath $TestRoot -MaxDepth 5 `
        -OutputPath (Join-Path $TestRoot 'VisualMap.txt')
}))

$results.Add((Measure-Operation "Invoke-MyBookCategorize (DryRun)" {
    Invoke-MyBookCategorize -RootPath $TestRoot -DryRun
}))

$results.Add((Measure-Operation "Resolve-MyBookDuplicates (DryRun)" {
    Resolve-MyBookDuplicates -RootPath $TestRoot -DryRun
}))

$results.Add((Measure-Operation "Invoke-MyBookCleanup -RemoveEmptyDirectories" {
    Invoke-MyBookCleanup -RootPath $TestRoot -RemoveEmptyDirectories -WhatIf
}))

$results.Add((Measure-Operation "Invoke-MyBookCleanup -ReportDuplicates" {
    Invoke-MyBookCleanup -RootPath $TestRoot -ReportDuplicates -WhatIf
}))

$results.Add((Measure-Operation "Get-MyBookStatus (status poll × 1000)" {
    1..1000 | ForEach-Object { Get-MyBookStatus } | Out-Null
}))

# ── Print results ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  Results ($fileCount files in tree)" -ForegroundColor Cyan
Write-Host ("  {0,-50} {1,10} {2,12} {3,10}" -f 'Operation','ms','sec','ΔMem KB') -ForegroundColor DarkGray
Write-Host ("  {0}" -f ('─' * 88)) -ForegroundColor DarkGray

foreach ($r in $results) {
    $color = if ($r.Status -eq 'OK') { 'White' } else { 'Red' }
    Write-Host ("  {0,-50} {1,10:N1} {2,12:N3} {3,10:N1}  {4}" -f `
        $r.Operation, $r.ElapsedMs, $r.ElapsedSec, $r.MemDeltaKB,
        $(if ($r.Status -ne 'OK') { "⚠  $($r.Status)" })) -ForegroundColor $color
}

# ── Export CSV ────────────────────────────────────────────────────────────────
$results | Export-Csv -Path $ResultCsvPath -NoTypeInformation -Encoding UTF8
Write-Host "`n  CSV saved to: $ResultCsvPath" -ForegroundColor Green

# ── Teardown ──────────────────────────────────────────────────────────────────
Remove-Item $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  Test tree cleaned up.`n" -ForegroundColor DarkGray
