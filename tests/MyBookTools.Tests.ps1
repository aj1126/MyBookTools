# MyBookTools.Tests.ps1
Import-Module "$PSScriptRoot/../src/MyBookTools.psm1" -Force

Describe "MyBookTools Module" {
    It "loads without error" {
        (Get-Module MyBookTools) | Should -Not -BeNullOrEmpty
    }

    It "exports expected functions" {
        $expected = @(
            'Write-MyBookLog','Set-MyBookStatus','Clear-MyBookStatus','Get-MyBookStatus',
            'Show-MyBookVisualMap','Update-MyBookHashCache','Invoke-MyBookAuditFast',
            'Invoke-MyBookCategorize','Resolve-MyBookDuplicates','Invoke-MyBookCleanup',
            'Register-MyBookMaintenanceTask', 'Get-MyBookScanPrediction'
        )
        foreach ($fn in $expected) {
            Get-Command $fn -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Audit Functions" {
    It "runs fast audit without hashes" {
        $tempFolder = Join-Path $env:TEMP "MyBookAuditTest_$(Get-Random)"
        $null = New-Item -Path $tempFolder -ItemType Directory -Force
        $null = New-Item -Path (Join-Path $tempFolder "file.txt") -ItemType File -Value "test"
        try {
            $path = Invoke-MyBookAuditFast -RootPath $tempFolder
            Test-Path $path | Should -Be $true
        } finally {
            Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "runs fast audit with hashes" {
        $tempFolder = Join-Path $env:TEMP "MyBookAuditTest_$(Get-Random)"
        $null = New-Item -Path $tempFolder -ItemType Directory -Force
        $null = New-Item -Path (Join-Path $tempFolder "file.txt") -ItemType File -Value "test"
        try {
            $path = Invoke-MyBookAuditFast -RootPath $tempFolder -IncludeHashes
            Test-Path $path | Should -Be $true
        } finally {
            Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Categorization" {
    It "supports DryRun" {
        $tempFolder = Join-Path $env:TEMP "MyBookCategorizeTest_$(Get-Random)"
        $null = New-Item -Path $tempFolder -ItemType Directory -Force
        try {
            { Invoke-MyBookCategorize -RootPath $tempFolder -DryRun } | Should -Not -Throw
        } finally {
            Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Duplicates" {
    It "supports DryRun duplicate resolution" {
        $tempFolder = Join-Path $env:TEMP "MyBookDupesTest_$(Get-Random)"
        $null = New-Item -Path $tempFolder -ItemType Directory -Force
        try {
            { Resolve-MyBookDuplicates -RootPath $tempFolder -DryRun } | Should -Not -Throw
        } finally {
            Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Cleanup" {
    It "runs cleanup safely" {
        $tempFolder = Join-Path $env:TEMP "MyBookCleanupTest_$(Get-Random)"
        $null = New-Item -Path $tempFolder -ItemType Directory -Force
        try {
            { Invoke-MyBookCleanup -RootPath $tempFolder -RemoveEmptyDirectories } | Should -Not -Throw
        } finally {
            Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Maintenance Task" {
    It "can register maintenance task (no throw)" {
        { Register-MyBookMaintenanceTask -TaskName 'MyBookTools_TestTask' -Schedule Daily } | Should -Not -Throw
    }
}

Describe "Scan Duration Prediction" {
    It "correctly estimates duration for a path" {
        $tempFolder = Join-Path $env:TEMP "MyBookToolsTest_$(Get-Random)"
        $null = New-Item -Path $tempFolder -ItemType Directory -Force
        $null = New-Item -Path (Join-Path $tempFolder "file1.txt") -ItemType File -Value "Hello World"
        $null = New-Item -Path (Join-Path $tempFolder "file2.txt") -ItemType File -Value "PowerShell test file"

        try {
            $prediction = Get-MyBookScanPrediction -RootPath $tempFolder
            $prediction.EstimatedFileCount | Should -Be 2
            $prediction.IncludeHashes | Should -Be $false
            $prediction.TotalEstimatedDuration.TotalSeconds | Should -BeGreaterThan 0
        } finally {
            Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "correctly estimates duration with IncludeHashes" {
        $tempFolder = Join-Path $env:TEMP "MyBookToolsTest_$(Get-Random)"
        $null = New-Item -Path $tempFolder -ItemType Directory -Force
        $null = New-Item -Path (Join-Path $tempFolder "file1.txt") -ItemType File -Value "Hello Hashing World"

        try {
            $prediction = Get-MyBookScanPrediction -RootPath $tempFolder -IncludeHashes
            $prediction.EstimatedFileCount | Should -Be 1
            $prediction.IncludeHashes | Should -Be $true
            $prediction.TotalEstimatedDuration.TotalSeconds | Should -BeGreaterThan 0
        } finally {
            Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "throws error on invalid path" {
        { Get-MyBookScanPrediction -RootPath "C:\NonExistentFolder_$(Get-Random)" } | Should -Throw
    }
}

