# Global Rules

- **Continuous Verification & Bug-Checking**: When you learn a new rule or constraint (e.g., via the `/learn` workflow), you must immediately ask to check/verify the rule against the current project files to scan for and resolve any existing violations.

---

# PowerShell Development Rules

## 1. File Encoding and Compatibility (PowerShell 5.1+)
- **UTF-8 with BOM Requirement**: Any `.ps1` or `.psm1` script containing Unicode characters (e.g., box-drawing characters, arrows, symbols) MUST be saved in **UTF-8 with BOM** (Byte Order Mark) encoding. This ensures that Windows PowerShell 5.1 parses the file correctly instead of defaulting to ANSI and throwing syntax errors, while remaining fully compatible with PowerShell Core (7+).

## 2. Cross-Process State Management in GUI Background Jobs
- **File-Based State Communication**: When running long-running module functions in background threads or processes (e.g., via `Start-Job` in a WPF GUI launcher), do not rely on variable scope sharing for real-time status updates. Instead, have the background worker dump its status payload to a local shared JSON file (e.g., `MyBook_Status.json`), which the main thread polls to update the user interface.

## 3. Pester v3.4.0 Syntax Compatibility
- **Assertion Operators**: Pester v3.4.0 does not support advanced dash-prefixed parameters (e.g., `Should -Not -BeNullOrEmpty` or `Should -Not -Throw`). Always write assertions using the legacy syntax:
  - Negation: use `Should Not BeNullOrEmpty`, `Should Not Throw`, `Should Not Be $null`
  - Boolean: use `Should Be $true` or `Should Be $false`
  - Comparison: use `Should BeGreaterThan 0`

## 4. Re-Saving UTF-8 with BOM Safely
- **Avoiding Encoding Corruption**: When converting/saving a file to UTF-8 with BOM via PowerShell, ensure you read the file using `-Encoding UTF8` before writing it back. Reading it as ANSI will corrupt existing Unicode glyphs:
  ```powershell
  # CORRECT:
  $content = Get-Content -LiteralPath "src\File.psm1" -Encoding UTF8 -Raw
  $content | Set-Content -LiteralPath "src\File.psm1" -Encoding UTF8

  # INCORRECT (converts already-corrupted characters):
  (Get-Content "src\File.psm1" -Raw) | Set-Content "src\File.psm1" -Encoding UTF8
  ```

## 5. Safe String Formatting in Modules
- **Explicit Array Packaging**: When using the string format operator (`-f`) inside module functions, avoid passing comma-separated lists of mixed characters and strings directly. PowerShell can experience parameter unpacking failures. Package formatting arguments explicitly in an array first:
  ```powershell
  $fmtArgs = @($indent, [string]$charCorner, [string]$charDash, $name)
  $lines.Add('{0}{1}{2}{2} {3}' -f $fmtArgs)
  ```

## 6. Non-Interactive Test Runs
- **Always Pass Target Paths**: When testing module functions that contain fallback interactive prompts (e.g., `Read-Host` console selection menus), always pass explicit target parameters (like `-RootPath "C:\"`) inside test blocks to prevent automated/background test suites from hanging on input prompts.

## 7. PSAvoidEmptyCatchBlock Compliance
- **Justify Empty Catch Blocks**: Catch blocks must not be empty. If an error is meant to be ignored silently (e.g. transient file lock or background status serialization), include an explicit comment inside the catch block explaining the rationale:
  ```powershell
  try {
      Remove-Item -Path $statusFile -Force
  } catch {
      # Ignore removal errors if status file is already deleted or locked by another process.
  }
  ```
