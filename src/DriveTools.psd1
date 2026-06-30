#
# DriveTools.psd1 — Module Manifest
# Generated for DriveTools v2.0
#

@{

# ── Identity ──────────────────────────────────────────────────────────────────
ModuleVersion = '3.0.0'
GUID              = 'e8c4592a-fa6c-486a-8d1b-7484df7c8651'
RootModule        = 'DriveTools.psm1'

# ── Metadata ──────────────────────────────────────────────────────────────────
Author            = 'Albert'
CompanyName       = ''
Copyright         = '(c) 2025 Albert. MIT License.'
Description       = 'Drive auditing, categorization, deduplication, cleanup, and scheduled maintenance for local, external, or other system storage drives.'

# ── Requirements ──────────────────────────────────────────────────────────────
PowerShellVersion = '5.1'

# ── Exported surface ──────────────────────────────────────────────────────────
FunctionsToExport = @(
    'Invoke-DriveAuditFast'
    'Update-DriveHashCache'
    'Invoke-DriveCategorize'
    'Resolve-DriveDuplicates'
    'Invoke-DriveCleanup'
    'Show-DriveVisualMap'
    'Register-DriveMaintenanceTask'
    'Write-DriveToolsLog'
    'Get-DriveToolsStatus'
    'Set-DriveToolsStatus'
    'Clear-DriveToolsStatus'
    'Get-DriveToolsRootPath'
)

CmdletsToExport   = @()
VariablesToExport = @()
AliasesToExport   = @()

# ── Private data ──────────────────────────────────────────────────────────────
PrivateData = @{
    PSData = @{
        Tags         = @('Drive','Audit','Deduplicate','Categorize','Maintenance','Storage','Cleanup','WPF')
        Prerelease   = ''
    }
}

}