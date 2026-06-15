# =============================================================================
#  MyBookTools — PowerShell Profile Snippet
#  Add this block to your $PROFILE (run `notepad $PROFILE` to open it).
# =============================================================================

# ── Auto-import ───────────────────────────────────────────────────────────────
if (Get-Module -ListAvailable -Name MyBookTools) {
    Import-Module MyBookTools -ErrorAction SilentlyContinue
} else {
    Write-Warning "MyBookTools not found. Install it to $env:USERPROFILE\Documents\WindowsPowerShell\Modules\MyBookTools\2.0\"
}

# ── Convenience aliases ───────────────────────────────────────────────────────
Set-Alias mba   Invoke-MyBookAuditFast          # mba              → fast audit
Set-Alias mbcat Invoke-MyBookCategorize          # mbcat -DryRun    → preview categorization
Set-Alias mbdup Resolve-MyBookDuplicates         # mbdup -DryRun    → preview dedup
Set-Alias mbfix Invoke-MyBookCleanup             # mbfix -RemoveEmptyDirectories
Set-Alias mbmap Show-MyBookVisualMap             # mbmap -MaxDepth 4
Set-Alias mbst  Get-MyBookStatus                 # mbst             → current operation

# ── Helper: open today's log in Notepad ───────────────────────────────────────
function Open-MyBookLog {
    $log = Join-Path "$env:USERPROFILE\Documents\MyBookLogs" ("MyBook_{0:yyyy-MM-dd}.log" -f (Get-Date))
    if (Test-Path $log) { notepad $log } else { Write-Host "No log file for today yet." }
}

# ── Helper: quick drive health check ─────────────────────────────────────────
function Invoke-MyBookHealthCheck {
    <#
    .SYNOPSIS
        Prints a one-line drive summary (free space, file count, last audit date).
    #>
    param([string]$Drive = 'M:')

    $disk = Get-PSDrive -Name ($Drive.TrimEnd(':\')) -ErrorAction SilentlyContinue
    if (-not $disk) { Write-Warning "Drive $Drive not found."; return }

    $freeGB  = [math]::Round($disk.Free  / 1GB, 2)
    $usedGB  = [math]::Round($disk.Used  / 1GB, 2)
    $totalGB = $freeGB + $usedGB

    $logDir  = "$env:USERPROFILE\Documents\MyBookLogs"
    $lastLog = Get-ChildItem -Path $logDir -Filter 'MyBook_*.log' -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1

    Write-Host ""
    Write-Host "  MyBook Health Check — $Drive" -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────"
    Write-Host ("  Total : {0,8} GB" -f $totalGB)
    Write-Host ("  Used  : {0,8} GB" -f $usedGB)  -ForegroundColor Yellow
    Write-Host ("  Free  : {0,8} GB" -f $freeGB)  -ForegroundColor Green
    if ($lastLog) {
        Write-Host ("  Last audit log : {0}" -f $lastLog.Name) -ForegroundColor DarkGray
    } else {
        Write-Host "  Last audit log : none found" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# ── Prompt badge: show active MyBook operation (optional) ─────────────────────
# Uncomment to append the active operation name to your prompt.
#
# $OriginalPrompt = (Get-Command prompt -ErrorAction SilentlyContinue)?.ScriptBlock
# function prompt {
#     $status = Get-MyBookStatus
#     $badge  = if ($status.Operation) { " [MyBook:$($status.Operation)]" } else { '' }
#     "PS $($executionContext.SessionState.Path.CurrentLocation)$badge> "
# }

# =============================================================================
