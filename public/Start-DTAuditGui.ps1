function Start-DTAuditGui {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$ScanPath,
        [Parameter(Mandatory = $true)] [string]$CsvLogPath,
        [int]$QueueLimit = 10000
    )

    # 1. Instantiate the WPF window from file
    $XamlPath = Join-Path $PSScriptRoot "..\src\UI\MainWindow.xaml"
    [xml]$XamlContent = Get-Content -Raw -Path $XamlPath
    $Reader = [System.Xml.XmlNodeReader]::new($XamlContent)
    $Window = [System.Windows.Markup.XamlReader]::Load($Reader)

    # 2. Extract UI control references
    $StartButton = $Window.FindName("StartButton")
    $ProgressBar = $Window.FindName("AuditProgressBar")
    $StatusLabel = $Window.FindName("StatusText")
    $PathLabel   = $Window.FindName("PathText")

    $PathLabel.Text = "Target Path: $ScanPath"

    # 3. Handle click event via asynchronous worker threads
    $StartButton.Add_Click({
        $StartButton.IsEnabled = $false
        
        # Instantiate the shared state context using our precompiled C# engine
        $Engine = [DriveTools.Core.AuditEngine]::new($QueueLimit, $CsvLogPath)
        $LogicalCores = [System.Environment]::ProcessorCount

        # Spawn consumer workers to compute hashes in parallel
        [System.Threading.Tasks.Task]::Run({
            $RunspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $LogicalCores + 1)
            $RunspacePool.Open()
            $ActiveTasks = [System.Collections.Generic.List[object]]::new()

            $WorkerBlock = { param([DriveTools.Core.AuditEngine]$EngineInstance) $EngineInstance.StartConsumerWorker() }

            for ($i = 0; $i < $LogicalCores; $i++) {
                $PS = [System.Management.Automation.PowerShell]::Create().AddScript($WorkerBlock).AddArgument($Engine)
                $PS.RunspacePool = $RunspacePool
                $AsyncResult = $PS.BeginInvoke()
                $ActiveTasks.Add([PSCustomObject]@{ Pipeline = $PS; Result = $AsyncResult })
            }

            # File System Traversal (Producer Loop)
            [System.Threading.Tasks.Task]::Run({
                try {
                    $Files = [System.IO.Directory]::EnumerateFiles($ScanPath, "*", [System.IO.SearchOption]::AllDirectories)
                    foreach ($File in $Files) {
                        if ([System.IO.File]::GetAttributes($File).HasFlag([System.IO.FileAttributes]::ReparsePoint)) { continue }
                        $Engine.FileQueue.Add($File)
                    }
                }
                finally { $Engine.FileQueue.CompleteAdding() }
            })

            # 4. Decoupled UI Progress Monitor Loop (Marshals to the UI Thread)
            while (-not $Engine.FileQueue.IsCompleted) {
                [System.Threading.Thread]::Sleep(250) # Throttles context switches to protect CPU frames

                $Processed = $Engine.ProcessedCount
                $CurrentPath = $Engine.ActiveFile
                $DisplayPath = if ($CurrentPath.Length -gt 55) { "..." + $CurrentPath.Substring($CurrentPath.Length - 52) } else { $CurrentPath }

                # Safe cross-thread invocation to avoid Thread Access Exceptions
                [System.Windows.Application]::Current.Dispatcher.Invoke([Action]{
                    $StatusLabel.Text = "Processing Data: $Processed files hashed..."
                    $PathLabel.Text = "Current Node: $DisplayPath"
                })
            }

            # Clean tear-down of pipeline contexts
            foreach ($Task in $ActiveTasks) {
                $null = $Task.Pipeline.EndInvoke($Task.Result)
                $Task.Pipeline.Dispose()
            }
            $RunspacePool.Close(); $RunspacePool.Dispose()

            [System.Windows.Application]::Current.Dispatcher.Invoke([Action]{
                $StatusLabel.Text = "Audit Completed Successfully!"
                $ProgressBar.Value = 100
            })
        })
    })

    # Render window frame model safely
    $null = $Window.ShowDialog()
}