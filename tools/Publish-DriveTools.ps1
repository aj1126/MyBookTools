#Requires -Version 5.1
<#
.SYNOPSIS
    Publishes the DriveTools module to PowerShell Gallery.
.PARAMETER ApiKey
    The NuGet API key for publishing.
.PARAMETER DryRun
    Runs validation checks and tests without publishing.
.EXAMPLE
    .\Publish-DriveTools.ps1 -ApiKey "your-api-key"
    .\Publish-DriveTools.ps1 -DryRun
#>
param(
    [string]$ApiKey,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$ManifestPath = Join-Path $PSScriptRoot '../src/DriveTools.psd1'
$TestsPath = Join-Path $PSScriptRoot '../tests/DriveTools.Tests.ps1'

# 1. Validate manifest file
Write-Host "Validating module manifest..." -ForegroundColor Cyan
try {
    $manifest = Test-ModuleManifest -Path $ManifestPath
    Write-Host "Manifest valid. Version: $($manifest.Version)" -ForegroundColor Green
} catch {
    throw "Module manifest validation failed: $_"
}

# 2. Run Pester tests
Write-Host "Running Pester tests before publishing..." -ForegroundColor Cyan
if (Get-Module -ListAvailable -Name Pester) {
    try {
        $pester3 = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -eq 3 } | Select-Object -First 1
        if ($pester3) {
            Import-Module Pester -RequiredVersion $pester3.Version -Force -ErrorAction SilentlyContinue
        } else {
            Import-Module Pester -Force -ErrorAction SilentlyContinue
        }
        $testResult = Invoke-Pester -Path $TestsPath -PassThru
        if ($testResult.FailedCount -gt 0) {
            throw "$($testResult.FailedCount) test(s) failed. Aborting publish."
        }
        Write-Host "All tests passed successfully." -ForegroundColor Green
    } catch {
        throw "Pester test execution failed: $_"
    }
} else {
    Write-Warning "Pester is not available. Skipping pre-publish tests."
}

# 3. Publish
if ($DryRun) {
    Write-Host "[DryRun] Validation complete. Ready to publish to PowerShell Gallery." -ForegroundColor Yellow
} else {
    if (-not $ApiKey) {
        throw "API key is required to publish. Specify -ApiKey."
    }
    Write-Host "Publishing to PowerShell Gallery..." -ForegroundColor Cyan
    Publish-Module -Path (Split-Path $ManifestPath -Parent) -NuGetApiKey $ApiKey
    Write-Host "Module published successfully!" -ForegroundColor Green
}
