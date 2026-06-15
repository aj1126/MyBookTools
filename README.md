<p align="center">
  <img src="https://img.shields.io/github/v/release/AJ1126/MyBookTools?style=for-the-badge" />
  <img src="https://img.shields.io/github/actions/workflow/status/AJ1126/MyBookTools/ci.yml?style=for-the-badge" />
  <img src="https://img.shields.io/powershellgallery/v/MyBookTools?style=for-the-badge" />
  <img src="https://img.shields.io/powershellgallery/dt/MyBookTools?style=for-the-badge" />
  <img src="https://img.shields.io/github/license/AJ1126/MyBookTools?style=for-the-badge" />
</p>


# 📦 MyBookTools

> A PowerShell module for auditing, organizing, deduplicating, and maintaining large external drives (3 TB+).

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)](https://github.com/PowerShell/PowerShell)
[![Pester](https://img.shields.io/badge/Tested%20with-Pester%205-green)](https://pester.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## ✨ Features

| Feature | Description |
|---|---|
| **Fast Audit** | Recursively scans a drive and exports file metadata to CSV |
| **Hash Caching** | Stores SHA256 hashes in a JSON cache; only rehashes files that have changed |
| **Auto-Categorization** | Moves files into `Projects / Media / Archives / Uploads / System` folders based on extension and keyword patterns |
| **Duplicate Resolution** | Detects exact duplicates via hash; keeps the newest copy and removes the rest |
| **Cleanup** | Removes empty directories, reports duplicate groups, compresses the Archives folder |
| **Visual Tree Map** | Generates a Unicode tree of the drive saved to a `.txt` file |
| **Real-Time Status** | `Get-MyBookStatus` returns the currently running operation, start time, and details |
| **Scheduled Maintenance** | Registers a Windows Scheduled Task to run audits automatically (Daily or Hourly) |
| **WPF GUI** | Optional graphical launcher for all operations — no command line required |

---

## 🗂️ Repository Layout

```
MyBookTools/
├── 2.0/
│   ├── MyBookTools.psm1        # Module implementation
│   ├── MyBookTools.psd1        # Module manifest
├── tests/
│   └── MyBookTools.Tests.ps1   # Pester test suite
├── tools/
│   ├── MyBookTools.GUI.ps1     # WPF graphical launcher
│   └── Invoke-MyBookBenchmark.ps1  # Performance benchmark script
├── profile-snippet.ps1         # PowerShell profile snippet
└── README.md
```

---

## ⚡ Installation

### Option A — Manual (recommended for personal use)

```powershell
$dest = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\MyBookTools\2.0"
New-Item -Path $dest -ItemType Directory -Force
Copy-Item MyBookTools.psm1, MyBookTools.psd1 -Destination $dest
```

### Option B — Clone and install

```powershell
git clone https://github.com/you/MyBookTools.git
Set-Location MyBookTools
.\Install.ps1   # copies module to the user module path
```

### Verify installation

```powershell
Import-Module MyBookTools
Get-Module MyBookTools | Select-Object Name, Version, ExportedFunctions
```

---

## 🚀 Quick Start

```powershell
Import-Module MyBookTools

# 1. Audit the drive
$csv = Invoke-MyBookAuditFast -RootPath M:\ -IncludeHashes
Write-Host "Report saved to $csv"

# 2. Preview categorization without moving anything
Invoke-MyBookCategorize -DryRun

# 3. Apply categorization
Invoke-MyBookCategorize

# 4. Find and remove duplicates (dry-run first!)
Resolve-MyBookDuplicates -DryRun
Resolve-MyBookDuplicates

# 5. Clean up empty folders
Invoke-MyBookCleanup -RemoveEmptyDirectories -ReportDuplicates

# 6. View a tree map of the drive
Show-MyBookVisualMap -MaxDepth 3

# 7. Schedule nightly maintenance
Register-MyBookMaintenanceTask -Schedule Daily

# 8. Monitor long-running operations
Get-MyBookStatus
```

---

## 📋 Command Reference

### `Invoke-MyBookAuditFast`

Scans a drive and exports a CSV with file metadata.

```
-RootPath        <string>   Drive or folder to scan          (default: M:\)
-OutputCsvPath   <string>   Destination CSV path
-IncludeHashes   <switch>   Compute SHA256 for every file
```

### `Update-MyBookHashCache`

Builds or refreshes a JSON hash cache; unchanged files reuse their stored hash.

```
-RootPath   <string>   Drive root
-CachePath  <string>   Path to HashCache.json
```

### `Invoke-MyBookCategorize`

Moves files into category folders based on extension and keyword matching.

```
-RootPath                  <string>    Drive root
-CategoryMap               <hashtable> Custom map (category → pattern list)
-DisableDefaultCategoryMap <switch>    Skip the built-in category map
-DryRun                    <switch>    Log actions without moving files
```

**Default CategoryMap:**

| Category | Triggers |
|---|---|
| Projects | `Unity`, `Project`, `Source`, `.sln`, `.csproj`, `Perseus` |
| Media | `.wav`, `.mp3`, `.flac`, `.mp4`, `.mov`, `.mkv`, `.jpg`, `.png`, `.psd`, `.ai` … |
| Archives | `backup`, `export`, `.zip`, `.rar`, `.7z`, `.bak` … |
| Uploads | `UPLOADS`, `upload`, `.torrent`, `.nfo` |
| System | `installer`, `setup`, `.msi`, `.exe`, `.dll`, `.log` |

### `Resolve-MyBookDuplicates`

Hashes all files, groups identical hashes, keeps the newest copy.

```
-RootPath  <string>  Drive root
-DryRun    <switch>  Log what would be deleted without deleting
```

### `Invoke-MyBookCleanup`

Composite cleanup: empty directories, duplicate reports, archive compression.

```
-RemoveEmptyDirectories  <switch>  Delete zero-item folders
-ReportDuplicates        <switch>  Log duplicate groups to the log file
-CompressArchives        <switch>  Zip the Archives\ subfolder
```

### `Show-MyBookVisualMap`

Renders a Unicode tree of the directory structure.

```
-RootPath    <string>  Root to map
-MaxDepth    <int>     Recursion limit (default: 3)
-OutputPath  <string>  Where to save the .txt file
```

### `Register-MyBookMaintenanceTask`

Registers a Windows Scheduled Task that calls `Invoke-MyBookAuditFast` automatically.

```
-TaskName  <string>  Task name (default: MyBookMaintenance)
-Schedule  <string>  Daily | Hourly
```

### `Get-MyBookStatus`

Returns the currently active operation, start time, and last-update timestamp.

---

## 📁 Log Files

All operations write to daily log files:

```
%USERPROFILE%\Documents\MyBookLogs\MyBook_YYYY-MM-DD.log
```

Hash cache is stored at:

```
%USERPROFILE%\Documents\MyBookLogs\MyBook_HashCache.json
```

---

## 🧪 Running Tests

Requires [Pester 5](https://pester.dev/docs/introduction/installation).

```powershell
Install-Module Pester -Force -SkipPublisherCheck
Invoke-Pester .\tests\MyBookTools.Tests.ps1 -Output Detailed
```

---

## 🖥️ WPF GUI

Launch the graphical interface with:

```powershell
.\tools\MyBookTools.GUI.ps1
```

The GUI provides one-click access to all operations, a live status display, and a log viewer.

---

## ⚙️ Configuration

You can override the default drive root and log path in your profile or before importing the module by editing the module variables after import:

```powershell
Import-Module MyBookTools
# Point to a different drive
(Get-Module MyBookTools).Invoke({ $Script:MyBook_DefaultRoot = 'E:\' })
```

Or supply `-RootPath` on every call.

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Add Pester tests for any new functions
4. Open a pull request

---

## 📄 License

MIT — see [LICENSE](LICENSE).
