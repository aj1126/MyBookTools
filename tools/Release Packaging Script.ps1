$version = (Import-PowerShellDataFile ./src/MyBookTools.psd1).ModuleVersion
$packageRoot = "./release/MyBookTools_$version"

Remove-Item -Recurse -Force $packageRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $packageRoot | Out-Null

Copy-Item ./src/* $packageRoot -Recurse
Copy-Item ./README.md $packageRoot
Copy-Item ./LICENSE $packageRoot

Compress-Archive -Path $packageRoot/* -DestinationPath "./release/MyBookTools_$version.zip" -Force

Write-Host "Release package created: MyBookTools_$version.zip"
