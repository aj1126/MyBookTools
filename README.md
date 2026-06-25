# 🚀 Unified PowerShell Profile Framework

A high-performance, metadata-driven, and context-aware PowerShell profile deployment framework designed to unify shell configurations across Windows PowerShell (5.1) and PowerShell Core (7+). This framework transitions your shell startup from simple alphabetical execution into a robust, dependency-sorted, parallel-loading ecosystem.

---

## ✨ Features

* 
**Metadata-Driven Topological Sorting:** Scripts parse explicit header comments (such as `#requires -Module`, `#depends:`, and `#group:`) to dynamically compute a dependency tree and sort execution, entirely eliminating initialization order issues and broken reference errors.


* 
**Context-Aware Profile Modes:** The loader samples your active execution context to dynamically scale loaded configuration groups, ensuring startup remains tight, lightweight, and secure:


* 
`minimal` (Remote SSH/Sessions): Loads exclusively the core group, omitting all aesthetic or optional components.


* 
`safe` (Elevated Local Admin): Omits developmental and external tools to enforce restrictive, risk-free loading boundaries.


* 
`dev` (Integrated VS Code Terminal): Prioritizes testing environments, debugging utilities, and localized logging pipelines.


* 
`full` (Standard/Windows Terminal): Aggregates the complete environment suite (core, dev, ui, tools, and admin configurations).




* 
**Hybrid Parallel Loading (PowerShell 7+):** On modern runtimes, independent and decoupled configuration blocks execute asynchronously using `ForEach-Object -Parallel`, compressing shell bootstrap latency to hardware limits while dependent modules are staged sequentially.


* 
**Resilient Try/Catch Architecture & Diagnostic Logging:** Every module interaction is wrapped in localized error containment blocks. Any script exceptions are caught safely and directed to `profile_loader.log` with target line parameters and failure vectors, letting the rest of your shell initialize unhindered.


* 
**Interactive Runtime Toolkit:** Injects full diagnostic capabilities directly into your live terminal session to inspect, hot-reload, and benchmark your environment.



---

## 🗂️ Repository Structure

```text
Documents/
├── PowerShell/                               # Main PowerShell (Core) workspace (Git repo)
│   ├── Microsoft.PowerShell_profile.ps1      # Entry profile script (Core)
│   ├── powershell.config.json                # Global engine behaviors & engine adjustments
│   ├── profile_loader.log                    # Diagnostic append-log mapping framework metrics
│   ├── profile.d/                            # Unified configuration modules
│   │   ├── 00-Environment.ps1                # Global variable constants & system paths
│   │   ├── 00-F7History.ps1                  # Command pop-up legacy menu engine provider
│   │   ├── 00-Loader.ps1                     # Version dispatcher / entry bootstrap stage
│   │   ├── 00-uvx.ps1                        # uv automated Python package manager integration
│   │   ├── 01-PredictiveText.ps1             # PSReadLine history & inline grey-text engine tuning
│   │   ├── 05-powertoys.ps1                  # PowerToys cross-utility shell hooks
│   │   ├── 10-Functions.ps1                  # Production custom utilities
│   │   ├── 20-Aliases.ps1                    # Accelerated prompt commands
│   │   ├── 90-local.ps1                      # Machine-specific non-tracked configurations
│   │   ├── loader-pwsh.ps1                   # PS7+ multi-threaded topological loading engine
│   │   ├── loader-windowsps.ps1              # PS5.1 backward-compatible topological stage
│   │   └── profile-runtime.ps1               # Shared diagnostic tools & interactive TUI engine
│   ├── Scripts/                              # Automated infrastructure and maintenance
│   │   ├── helpers/                          # Framework correction utilities (fix-loader, test-profiles)
│   │   └── Installers/                       # Package verification and installation assets
│   ├── Modules/                              # Cross-shell mirrored repository module pathing
│   └── Backups/                              # Automated archival snapshots of active states
└── WindowsPowerShell/                        # Windows PowerShell workspace
    └── Microsoft.PowerShell_profile.ps1      # Identical mirrored router entry script (v5.1)

```

---

## 🛠️ Interactive Runtime Toolkit (`profile-runtime.ps1`)

The framework exposes a specialized suite of utility commands to monitor and maintain your environment's performance straight from the prompt:

* 
`Show-ProfileStartupSummary`: Displays a formatted table of all loaded profile elements, sorted from slowest to fastest, to pinpoint bottleneck scripts instantly.


* 
`Reload-ProfileModule -Name <string>`: Hot-reloads an active script module directly into your live session without needing to open a new terminal window.


* 
`Measure-ProfileModule -Name <string> -Iterations <int>`: Isolates a target configuration script and benchmarks its loading speed across multiple execution passes to trace its performance impact.


* 
`Build-ProfileModuleCache` / `Invoke-CachedProfileModule`: Compiles runtime configuration scripts down into high-speed ScriptBlocks stored in memory, bypassing slow disk I/O file lookups entirely.


* 
`Export-VSCodeDependencyGraphFiles`: Generates structured `.json` and Graphviz `.dot` files to let you easily model and visualize your profile configuration dependencies.


* 
`Show-ProfileManager`: Launches a terminal-based interactive Text User Interface (TUI) to inspect, measure, cache, and hot-reload configurations on the fly.



---

## 🛡️ Maintenance & Backups

A quick-access fallback alias `rh` (`Run-Helper`) is available to handle routine framework maintenance tasks automatically under the hood. Before applying any potentially destructive or structural modifications to your live environment, helper utilities capture state backups securely under `Backups/` (or adjacent file markers) to prevent configuration loss.
