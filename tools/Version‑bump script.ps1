param(
    [Parameter(Mandatory)][string]$NewVersion
)

$manifest = Join-Path $PSScriptRoot '../src/MyBookTools.psd1'
$psd1 = Get-Content $manifest -Raw

$psd1 = $psd1 -replace "ModuleVersion\s*=\s*'[^']+'", "ModuleVersion = '$NewVersion'"

Set-Content -Path $manifest -Value $psd1 -Encoding UTF8

Write-Host "Version updated to $NewVersion"
