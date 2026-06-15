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
            'Register-MyBookMaintenanceTask'
        )
        foreach ($fn in $expected) {
            Get-Command $fn -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Audit Functions" {
    It "runs fast audit without hashes" {
        $path = Invoke-MyBookAuditFast
        Test-Path $path | Should -BeTrue
    }

    It "runs fast audit with hashes" {
        $path = Invoke-MyBookAuditFast -IncludeHashes
        Test-Path $path | Should -BeTrue
    }
}

Describe "Categorization" {
    It "supports DryRun" {
        { Invoke-MyBookCategorize -DryRun } | Should -Not -Throw
    }
}

Describe "Duplicates" {
    It "supports DryRun duplicate resolution" {
        { Resolve-MyBookDuplicates -DryRun } | Should -Not -Throw
    }
}

Describe "Cleanup" {
    It "runs cleanup safely" {
        { Invoke-MyBookCleanup -RemoveEmptyDirectories } | Should -Not -Throw
    }
}

Describe "Maintenance Task" {
    It "can register maintenance task (no throw)" {
        { Register-MyBookMaintenanceTask -TaskName 'MyBookTools_TestTask' -Schedule Daily } | Should -Not -Throw
    }
}
