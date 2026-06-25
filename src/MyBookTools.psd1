#
# MyBookTools.psd1 — Module Manifest
# Generated for MyBookTools v2.0
#

@{

# ── Identity ──────────────────────────────────────────────────────────────────
ModuleVersion = '5.0.0'
GUID              = 'a3f7c2d1-84b6-4e9a-bc13-f0d25e671048'   # regenerate with [guid]::NewGuid() if forking
RootModule        = 'MyBookTools.psm1'

# ── Metadata ──────────────────────────────────────────────────────────────────
Author            = 'Albert'
CompanyName       = ''
Copyright         = '(c) 2025 Albert. MIT License.'
Description       = 'Drive auditing, categorization, deduplication, cleanup, and scheduled maintenance for large external drives (1–3 TB+). Targets a WD MyBook or any external volume.'
Tags              = @('Drive','Audit','Deduplicate','Categorize','Maintenance','MyBook','External','Storage','Cleanup')
ProjectUri        = 'https://github.com/you/MyBookTools'
LicenseUri        = 'https://github.com/you/MyBookTools/blob/main/LICENSE'
ReleaseNotes      = @'
v2.0.0 (2025)
  - Rewritten with full SupportsShouldProcess / -DryRun support
  - Hash caching via JSON (incremental, avoids rehashing unchanged files)
  - Auto-loaded default CategoryMap (Projects / Media / Archives / Uploads / System)
  - Scheduled maintenance task registration (Daily / Hourly)
  - Real-time status object (Get-MyBookStatus)
  - Unicode visual tree map saved to Desktop
  - WPF GUI launcher (tools\MyBookTools.GUI.ps1)
  - Pester 5 test suite (tests\MyBookTools.Tests.ps1)
'@

# ── Requirements ──────────────────────────────────────────────────────────────
PowerShellVersion = '5.1'
# CompatiblePSEditions = @('Desktop', 'Core')   # uncomment when Core compatibility is verified

# ── Exported surface ──────────────────────────────────────────────────────────
FunctionsToExport = @(
    'Invoke-MyBookAuditFast'
    'Update-MyBookHashCache'
    'Invoke-MyBookCategorize'
    'Resolve-MyBookDuplicates'
    'Invoke-MyBookCleanup'
    'Show-MyBookVisualMap'
    'Register-MyBookMaintenanceTask'
    'Write-MyBookLog'
    'Get-MyBookStatus'
    'Set-MyBookStatus'
    'Clear-MyBookStatus'
)

# Nothing else is part of the public API
CmdletsToExport   = @()
VariablesToExport = @()
AliasesToExport   = @()

# ── Private data ──────────────────────────────────────────────────────────────
PrivateData = @{
    PSData = @{
        Tags         = @('Drive','Audit','Deduplicate','Categorize','Maintenance','MyBook','ExternalDrive','Storage','Cleanup','WPF')
        ProjectUri   = 'https://github.com/you/MyBookTools'
        LicenseUri   = 'https://github.com/you/MyBookTools/blob/main/LICENSE'
        Prerelease   = ''
    }
}

}



