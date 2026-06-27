#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the DriveTools module to the user's PowerShell modules directory.
.PARAMETER AddToProfile
    Appends the DriveTools profile snippet to the active PowerShell profile.
.PARAMETER Force
    Overwrites any existing DriveTools installation.
.EXAMPLE
    .\Install.ps1 -AddToProfile
#>
param(
    [switch]$AddToProfile,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# 1. Verify environment
$destDir = Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Modules\DriveTools\2.0'
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $destDir = Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules\DriveTools\2.0'
}

Write-Host "Installing DriveTools to: $destDir" -ForegroundColor Cyan

# 2. Copy files
if (Test-Path $destDir) {
    if ($Force) {
        Remove-Item -Path $destDir -Recurse -Force
    } else {
        throw "DriveTools is already installed. Use -Force to overwrite."
    }
}

New-Item -Path $destDir -ItemType Directory -Force | Out-Null
Copy-Item -Path "$PSScriptRoot\src\*" -Destination $destDir -Recurse -Force

Write-Host "Files copied successfully." -ForegroundColor Green

# 3. Add to profile if requested
if ($AddToProfile) {
    if (-not $PROFILE) {
        throw "PowerShell profile path is not available."
    }

    $profileDir = Split-Path $PROFILE -Parent
    if (-not (Test-Path $profileDir)) {
        New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path $PROFILE)) {
        New-Item -Path $PROFILE -ItemType File -Force | Out-Null
    }

    $profileContent = Get-Content -Path $PROFILE -Raw -ErrorAction SilentlyContinue
    if ($null -eq $profileContent) { $profileContent = "" }

    if ($profileContent -like "*Import-Module DriveTools*") {
        Write-Host "DriveTools import is already configured in profile." -ForegroundColor Yellow
    } else {
        $snippetPath = Join-Path $PSScriptRoot 'tools\profile-snippet.ps1'
        if (Test-Path $snippetPath) {
            $snippet = Get-Content -Path $snippetPath -Raw
            Add-Content -Path $PROFILE -Value "`n# ── DriveTools Snippet ──`n$snippet" -Encoding UTF8
            Write-Host "Profile snippet successfully added to $PROFILE." -ForegroundColor Green
        } else {
            Write-Warning "Profile snippet file not found at $snippetPath."
        }
    }
}

Write-Host "Installation complete! Load the module using: Import-Module DriveTools" -ForegroundColor Green
