#Requires -Version 5.1
<#
.SYNOPSIS
    DriveTools WPF GUI — graphical launcher for all DriveTools operations.
.DESCRIPTION
    A self-contained WPF window. Run this script from a PowerShell session
    that already has DriveTools imported, or let the script import it automatically.
.NOTES
    Requires Windows PowerShell 5.1 (Desktop edition).
#>

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Copy PSScriptRoot to local variable to adhere to automatic variables constraint
$ScriptDir = $PSScriptRoot

# Resolve the target module execution file path cleanly to feed background worker runspaces
$ModulePathToLoad = Join-Path $ScriptDir "DriveTools.psm1"

# ── Import module if not already loaded ──────────────────────────────────────
if (-not (Get-Module DriveTools)) {
    $modPath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\DriveTools\2.0\DriveTools.psm1"
    if (Test-Path $ModulePathToLoad) {
        Import-Module $ModulePathToLoad -Force
    } elseif (Test-Path $modPath) {
        $ModulePathToLoad = $modPath
        Import-Module $modPath -Force
    } else {
        [System.Windows.MessageBox]::Show(
            "DriveTools module not found.`nExpected local path:`n$ModulePathToLoad",
            "DriveTools GUI", "OK", "Error") | Out-Null
        exit 1
    }
} else {
    $ModulePathToLoad = (Get-Module DriveTools).Path
}

# Thread-Safe Shared Context State Capsule to bridge UI and Task threads
$Script:GuiContext = [hashtable]::Synchronized(@{
    ActivePowerShell = $null
    OutputCollection = $null
    CustomStartTime  = $null
    CustomStatusText = ""
})

# ── XAML layout ──────────────────────────────────────────────────────────────
[xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="DriveTools v2.0" Height="680" Width="780"
    ResizeMode="CanResize" WindowStartupLocation="CenterScreen"
    Background="#1E1E2E">

    <Window.Resources>
        <Style TargetType="Button" x:Key="ActionBtn">
            <Setter Property="Background"    Value="#313244"/>
            <Setter Property="Foreground"    Value="#CDD6F4"/>
            <Setter Property="BorderBrush"   Value="#45475A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontFamily"    Value="Cascadia Code, Consolas, Monospace"/>
            <Setter Property="FontSize"      Value="13"/>
            <Setter Property="Height"        Value="38"/>
            <Setter Property="Margin"        Value="4"/>
            <Setter Property="Cursor"        Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#45475A"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Background" Value="#1A1A26"/>
                                <Setter Property="Foreground" Value="#585B70"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#585B70"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="CheckBox">
            <Setter Property="Foreground"  Value="#A6ADC8"/>
            <Setter Property="FontFamily"  Value="Cascadia Code, Consolas, Monospace"/>
            <Setter Property="FontSize"    Value="12"/>
            <Setter Property="Margin"      Value="4,2"/>
        </Style>

        <Style TargetType="Label">
            <Setter Property="Foreground"  Value="#89B4FA"/>
            <Setter Property="FontFamily"  Value="Cascadia Code, Consolas, Monospace"/>
            <Setter Property="FontSize"    Value="11"/>
        </Style>

        <Style TargetType="TextBox">
            <Setter Property="Background"  Value="#313244"/>
            <Setter Property="Foreground"  Value="#CDD6F4"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="FontFamily"  Value="Cascadia Code, Consolas, Monospace"/>
            <Setter Property="FontSize"    Value="12"/>
            <Setter Property="Padding"     Value="4,2"/>
        </Style>

        <Style TargetType="ComboBox">
            <Setter Property="Background"  Value="#313244"/>
            <Setter Property="Foreground"  Value="#313244"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="FontFamily"  Value="Cascadia Code, Consolas, Monospace"/>
            <Setter Property="FontSize"    Value="12"/>
        </Style>
    </Window.Resources>

    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>   <RowDefinition Height="Auto"/>   <RowDefinition Height="Auto"/>   <RowDefinition Height="Auto"/>   <RowDefinition Height="Auto"/>   <RowDefinition Height="*"/>      </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
            <TextBlock Text="⚙️ " FontSize="26"/>
            <TextBlock Text="DriveTools" FontSize="22" FontWeight="Bold"
                        Foreground="#89B4FA"
                        FontFamily="Cascadia Code, Consolas, Monospace"
                        VerticalAlignment="Center"/>
            <TextBlock Text=" v2.0" FontSize="14" Foreground="#585B70"
                        FontFamily="Cascadia Code, Consolas, Monospace"
                        VerticalAlignment="Bottom" Margin="4,0,0,2"/>
        </StackPanel>

        <Grid Grid.Row="1" Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="80"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="180"/>
                <ColumnDefinition Width="90"/>
            </Grid.ColumnDefinitions>
            <Label Grid.Column="0" Content="Root Path" VerticalAlignment="Center"/>
            <TextBox Grid.Column="1" x:Name="TxtRoot" Text="C:\" VerticalAlignment="Center"/>
            <ComboBox Grid.Column="2" x:Name="ComboDrives" Margin="6,0,0,0" VerticalAlignment="Center" Height="26"/>
            <Button Grid.Column="3" Content="Browse…" Style="{StaticResource ActionBtn}"
                    x:Name="BtnBrowse" Margin="6,0,0,0"/>
        </Grid>

        <WrapPanel Grid.Row="2" Margin="0,0,0,10">
            <CheckBox x:Name="ChkHashes"           Content="Include Hashes"/>
            <CheckBox x:Name="ChkDryRun"           Content="Dry Run"  IsChecked="True"/>
            <CheckBox x:Name="ChkEmptyDirs"        Content="Remove Empty Dirs"/>
            <CheckBox x:Name="ChkCompress"         Content="Compress Archives"/>
            <CheckBox x:Name="ChkDupeRpt"          Content="Report Duplicates"/>
            <CheckBox x:Name="ChkShowDetails"      Content="Show Details" IsChecked="False"/>
            <CheckBox x:Name="ChkAdvancedDetails"  Content="Advanced Details" IsChecked="False"/>
            <CheckBox x:Name="ChkOutputToLog"      Content="Output to Log" IsChecked="False"/>
        </WrapPanel>

        <UniformGrid Grid.Row="3" Columns="3" Margin="0,0,0,8">
            <Button x:Name="BtnAudit"    Content="🔍 Audit"        Style="{StaticResource ActionBtn}"/>
            <Button x:Name="BtnHashCache" Content="💾 Hash Cache"  Style="{StaticResource ActionBtn}"/>
            <Button x:Name="BtnCategorize" Content="📂 Categorize" Style="{StaticResource ActionBtn}"/>
            <Button x:Name="BtnDupes"    Content="♻️ Dedup"        Style="{StaticResource ActionBtn}"/>
            <Button x:Name="BtnCleanup"  Content="🧹 Cleanup"      Style="{StaticResource ActionBtn}"/>
            <Button x:Name="BtnMap"      Content="🌳 Visual Map"   Style="{StaticResource ActionBtn}"/>
            <Button x:Name="BtnPredict"  Content="🔮 Predict"      Style="{StaticResource ActionBtn}"/>
            <Button x:Name="BtnSchedule" Content="⏰ Schedule"     Style="{StaticResource ActionBtn}"/>
            <Button x:Name="BtnClearLog" Content="🗑️ Clear Log"    Style="{StaticResource ActionBtn}"/>
        </UniformGrid>

        <Border Grid.Row="4" Background="#313244" CornerRadius="4"
                Margin="0,0,0,8" Padding="8,4">
            <Grid>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" VerticalAlignment="Center">
                    <TextBlock Text="Status: " Foreground="#585B70"
                               FontFamily="Cascadia Code, Consolas, Monospace" FontSize="12"/>
                    <TextBlock x:Name="TxtStatus" Text="Idle"
                               Foreground="#A6E3A1"
                               FontFamily="Cascadia Code, Consolas, Monospace" FontSize="12"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <ProgressBar x:Name="UiProgressBar" Width="160" Height="14" Minimum="0" Maximum="100" Visibility="Collapsed" Margin="0,0,8,0"/>
                    <Button x:Name="BtnCancel" Content="🛑 Cancel" Width="75" Height="22" FontSize="11" Background="#F38BA8" Foreground="#11111B" FontWeight="Bold" Visibility="Collapsed" Cursor="Hand">
                        <Button.Template>
                            <ControlTemplate TargetType="Button">
                                <Border Background="{TemplateBinding Background}" CornerRadius="4">
                                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                </Border>
                            </ControlTemplate>
                        </Button.Template>
                    </Button>
                </StackPanel>
            </Grid>
        </Border>

        <Border Grid.Row="5" Background="#181825" BorderBrush="#313244"
                BorderThickness="1" CornerRadius="6">
            <ScrollViewer x:Name="LogScroller" VerticalScrollBarVisibility="Auto">
                <TextBox x:Name="TxtLog"
                          IsReadOnly="True" TextWrapping="Wrap"
                          Background="Transparent" BorderThickness="0"
                          Foreground="#CDD6F4"
                          FontFamily="Cascadia Code, Consolas, Monospace"
                          FontSize="12" Padding="8"
                          VerticalAlignment="Top"
                          AcceptsReturn="True"/>
            </ScrollViewer>
        </Border>
    </Grid>
</Window>
'@

# ── Build the window ──────────────────────────────────────────────────────────
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Named element references
$txtRoot        = $window.FindName('TxtRoot')
$txtStatus      = $window.FindName('TxtStatus')
$txtLog         = $window.FindName('TxtLog')
$logScroller    = $window.FindName('LogScroller')
$chkHashes      = $window.FindName('ChkHashes')
$chkDryRun      = $window.FindName('ChkDryRun')
$chkEmptyDirs   = $window.FindName('ChkEmptyDirs')
$chkCompress    = $window.FindName('ChkCompress')
$chkDupeRpt     = $window.FindName('ChkDupeRpt')
$chkShowDetails = $window.FindName('ChkShowDetails')
$chkAdvancedDetails = $window.FindName('ChkAdvancedDetails')
$comboDrives    = $window.FindName('ComboDrives')
$progressBar    = $window.FindName('UiProgressBar')
$btnCancel      = $window.FindName('BtnCancel')

# ── Populate drives list ──────────────────────────────────────────────────────
$drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
foreach ($d in $drives) {
    $freeGB = [math]::Round($d.AvailableFreeSpace / 1GB, 1)
    $totalGB = [math]::Round($d.TotalSize / 1GB, 1)
    $label = "{0} ({1} GB free / {2} GB)" -f $d.Name, $freeGB, $totalGB
    $comboDrives.Items.Add($label) | Out-Null
}

if ($comboDrives.Items.Count -gt 0) {
    $comboDrives.SelectedIndex = 0
    $txtRoot.Text = $drives[0].Name
}

$comboDrives.Add_SelectionChanged({
    $idx = $comboDrives.SelectedIndex
    if ($idx -ge 0 -and $idx -lt $drives.Count) {
        $txtRoot.Text = $drives[$idx].Name
    }
})

# ── Helper functions ──────────────────────────────────────────────────────────
function Append-Log {
    param([string]$Text)
    $ts = Get-Date -Format 'HH:mm:ss'
    $window.Dispatcher.Invoke({
        $txtLog.AppendText("[$ts] $Text`n")
        $logScroller.ScrollToEnd()
    })

    # Thread-Safe File Logging Pipeline Interceptor
    $opts = $window.FindName('ChkShowDetails') # Borrow thread context check
    if ($window.FindName('ChkDupeRpt').Parent.Children | Where-Object { $_.Name -eq 'ChkCompress' }) {
        # Check if output to log checkbox state is true (handled programmatically via dynamic variables)
        $outputCheckbox = $window.FindName('ChkOutputToLog')
        if ($outputCheckbox -and $outputCheckbox.IsChecked) {
            try {
                $fileDate = Get-Date -Format 'yyyy-MM-dd'
                $uiSessionLog = Join-Path $env:USERPROFILE "Documents\DriveToolsLogs\DriveTools_GuiSession_$fileDate.log"
                Add-Content -Path $uiSessionLog -Value "[$ts] $Text" -ErrorAction SilentlyContinue
            } catch {}
        }
    }
}

function Set-Status {
    param([string]$Text, [string]$Color = '#A6E3A1')
    $window.Dispatcher.Invoke({
        $txtStatus.Text            = $Text
        $txtStatus.Foreground      = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
    })
}

# Enforce button state throttling to prevent parallel process overlapping
function Set-UiButtonsState {
    param([bool]$Enabled)
    $window.Dispatcher.Invoke({
        $actionButtons = @('BtnAudit', 'BtnHashCache', 'BtnCategorize', 'BtnDupes', 'BtnCleanup', 'BtnMap', 'BtnPredict', 'BtnSchedule')
        foreach ($btnName in $actionButtons) {
            $btn = $window.FindName($btnName)
            if ($btn) { $btn.IsEnabled = $Enabled }
        }
    })
}

# Native Thread-Safe Async Pipeline Handler with Complete Mutual Exclusion Toggles
function Invoke-AsyncGuiTask {
    param(
        [ScriptBlock]$Script,
        [object[]]$ArgumentList,
        [string]$RunningStatus
    )
    
    if ($null -ne $Script:GuiContext.ActivePowerShell) {
        Append-Log "Operation Aborted: A background pipeline task is already processing entries. Please wait or cancel."
        return
    }

    $window.Dispatcher.Invoke({ 
        if ($progressBar) {
            $progressBar.Visibility = 'Visible'
            $progressBar.IsIndeterminate = $true
        }
        if ($btnCancel) { $btnCancel.Visibility = 'Visible' }
    })
    
    Set-UiButtonsState -Enabled $false
    
    $Script:GuiContext.CustomStartTime = Get-Date
    $Script:GuiContext.CustomStatusText = $RunningStatus
    
    if ($RunningStatus) { Set-Status $RunningStatus '#F9E2AF' }
    
    $PowerShellInstance = [System.Management.Automation.PowerShell]::Create()
    [void]$PowerShellInstance.AddCommand("Invoke-Command").AddParameter("ScriptBlock", $Script).AddParameter("ArgumentList", $ArgumentList)
    
    $outputCollection = New-Object System.Management.Automation.PSDataCollection[PSObject]
    $outputCollection.Add_DataAdding({
        param($sender, $eventArgs)
        if ($null -ne $eventArgs.ItemValue) {
            Append-Log $eventArgs.ItemValue.ToString()
        }
    })

    $Script:GuiContext.ActivePowerShell = $PowerShellInstance
    $Script:GuiContext.OutputCollection = $outputCollection
    
    try {
        [void]$PowerShellInstance.BeginInvoke($outputCollection)
    }
    catch {
        Append-Log "Failed to initialize async runspace pipeline: $($_.Exception.Message)"
        $Script:GuiContext.ActivePowerShell = $null
        $Script:GuiContext.OutputCollection = $null
        $Script:GuiContext.CustomStartTime = $null
        Set-UiButtonsState -Enabled $true
        $window.Dispatcher.Invoke({
            if ($progressBar) { $progressBar.Visibility = 'Collapsed' }
            if ($btnCancel) { $btnCancel.Visibility = 'Collapsed' }
        })
        Set-Status "Idle" '#A6E3A1'
    }
}

# ── Cancel Button Click Logic ─────────────────────────────────────────────────
if ($btnCancel) {
    $btnCancel.Add_Click({
        $runningEngine = $Script:GuiContext.ActivePowerShell
        if ($null -ne $runningEngine) {
            Append-Log "Cancellation command issued. Stopping background processing workloads..."
            try {
                $runningEngine.Stop()
            } catch {
                Append-Log "Error sending execution stop signal: $($_.Exception.Message)"
            }
        }
    })
}

# ── Browse button ─────────────────────────────────────────────────────────────
$window.FindName('BtnBrowse').Add_Click({
    $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
    Add-Type -AssemblyName System.Windows.Forms
    $dlg.SelectedPath = $txtRoot.Text
    if ($dlg.ShowDialog() -eq 'OK') { $txtRoot.Text = $dlg.SelectedPath }
})

# ── Audit ─────────────────────────────────────────────────────────────────────
$window.FindName('BtnAudit').Add_Click({
    $root       = $txtRoot.Text
    $withHashes = $chkHashes.IsChecked
    Invoke-AsyncGuiTask -Script {
        param($r, $h, $modulePath)
        Import-Module $modulePath -Force
        $csv = Invoke-DriveAuditFast -RootPath $r -IncludeHashes:$h -Asynchronous:$h
        return "CSV saved to: $csv"
    } -ArgumentList @($root, $withHashes, $ModulePathToLoad) -RunningStatus "Auditing Drive Tree"
})

# ── Hash Cache ────────────────────────────────────────────────────────────────
$window.FindName('BtnHashCache').Add_Click({
    $root = $txtRoot.Text
    Invoke-AsyncGuiTask -Script {
        param($r, $modulePath)
        Import-Module $modulePath -Force
        $db = Update-DriveHashCache -RootPath $r -Asynchronous
        return "Hash cache update complete: $db"
    } -ArgumentList @($root, $ModulePathToLoad) -RunningStatus "Updating Hash Index Cache"
})

# ── Categorize ────────────────────────────────────────────────────────────────
$window.FindName('BtnCategorize').Add_Click({
    $root    = $txtRoot.Text
    $dryRun  = $chkDryRun.IsChecked
    $mode    = if ($dryRun) { 'DryRun' } else { 'LIVE' }
    Invoke-AsyncGuiTask -Script {
        param($r, $d, $modulePath)
        Import-Module $modulePath -Force
        Invoke-DriveCategorize -RootPath $r -DryRun:$d
        return "Categorization complete."
    } -ArgumentList @($root, $dryRun, $ModulePathToLoad) -RunningStatus "Categorizing Formats ($mode)"
})

# ── Dedup ─────────────────────────────────────────────────────────────────────
$window.FindName('BtnDupes').Add_Click({
    $root   = $txtRoot.Text
    $dryRun = $chkDryRun.IsChecked
    if (-not $dryRun) {
        $confirm = [System.Windows.MessageBox]::Show(
            "DryRun is OFF. This will permanently delete duplicate files. Continue?",
            "Confirm Dedup", "YesNo", "Warning")
        if ($confirm -ne 'Yes') { Append-Log "Dedup cancelled."; return }
    }
    Invoke-AsyncGuiTask -Script {
        param($r, $d, $modulePath)
        Import-Module $modulePath -Force
        Resolve-DriveDuplicates -RootPath $r -DryRun:$d
        return "Dedup complete."
    } -ArgumentList @($root, $dryRun, $ModulePathToLoad) -RunningStatus "Resolving Redundant Duplicates"
})

# ── Cleanup ───────────────────────────────────────────────────────────────────
$window.FindName('BtnCleanup').Add_Click({
    $root      = $txtRoot.Text
    $emptyDirs = $chkEmptyDirs.IsChecked
    $compress  = $chkCompress.IsChecked
    $dupeRpt   = $chkDupeRpt.IsChecked
    Invoke-AsyncGuiTask -Script {
        param($r, $e, $c, $d, $modulePath)
        Import-Module $modulePath -Force
        Invoke-DriveCleanup -RootPath $r -RemoveEmptyDirectories:$e -CompressArchives:$c -ReportDuplicates:$d
        return "Cleanup complete."
    } -ArgumentList @($root, $emptyDirs, $compress, $dupeRpt, $ModulePathToLoad) -RunningStatus "Running Storage Cleanups"
})

# ── Visual Map ────────────────────────────────────────────────────────────────
$window.FindName('BtnMap').Add_Click({
    $root = $txtRoot.Text
    Invoke-AsyncGuiTask -Script {
        param($r, $modulePath)
        Import-Module $modulePath -Force
        $out = Show-DriveVisualMap -RootPath $r -MaxDepth 4
        return "Map saved — $($out.Count) lines"
    } -ArgumentList @($root, $ModulePathToLoad) -RunningStatus "Generating Tree Layout Map"
})

# ── Schedule ──────────────────────────────────────────────────────────────────
$window.FindName('BtnSchedule').Add_Click({
    Append-Log "Registering daily maintenance task…"
    Register-DriveMaintenanceTask -Schedule Daily
    Append-Log "Task registered: DriveMaintenance (Daily @ 03:00)"
    Set-Status "Idle"
    Clear-DriveToolsStatus
})

# ── Predict ───────────────────────────────────────────────────────────────────
$window.FindName('BtnPredict').Add_Click({
    $root       = $txtRoot.Text
    $withHashes = $chkHashes.IsChecked
    Invoke-AsyncGuiTask -Script {
        param($r, $h, $modulePath)
        Import-Module $modulePath -Force
        
        if (-not (Test-Path $r)) { return "Error: Target path '$r' does not exist." }
        
        $fileCount = 0
        $totalBytes = 0
        
        try {
            $files = [System.IO.Directory]::EnumerateFiles($r, "*", [System.IO.SearchOption]::AllDirectories)
            foreach ($file in $files) {
                $fileCount++
                try { $totalBytes += [System.IO.FileInfo]::new($file).Length } catch {}
                if ($fileCount % 4000 -eq 0) {
                    Write-Output "Analyzed $fileCount directory entry endpoints..."
                }
            }
        } catch {
            return "Forecasting block aborted: $($_.Exception.Message)"
        }
        
        $totalGB = [math]::Round($totalBytes / 1GB, 2)
        $driveRoot = [System.IO.Path]::GetPathRoot($r)
        
        $isHdd = $true
        try {
            if ([System.Management.Automation.PSTypeName]'DriveTools.Core.StorageProfiler') {
                $isHdd = [DriveTools.Core.StorageProfiler]::DetectSeekPenalty($driveRoot)
            }
        } catch {}
        
        $speedMBps = if ($isHdd) { 35 } else { 120 }
        if (-not $h) {
            $estimatedSeconds = $fileCount / 5000
        } else {
            $estimatedSeconds = ($totalBytes / 1MB) / $speedMBps
        }
        
        $ts = [TimeSpan]::FromSeconds($estimatedSeconds)
        $formattedTime = "{0:hh\:mm\:ss}" -f $ts
        if ($ts.TotalMinutes -lt 1) { $formattedTime = "$([math]::Round($ts.TotalSeconds, 1)) seconds" }
        
        return @"

======================================================================
 DRIVE INGESTION FORECAST & CAPACITY REPORT
======================================================================
 Workspace Target   : $r
 Detected Storage Type : $(if ($isHdd) { "Mechanical HDD (Seek Latency active)" } else { "Solid State Drive (SSD/NVMe optimized)" })
 Total File Inventory  : $fileCount items
 Total Data Capacity   : $totalGB GB
 Planned Audit Method  : $(if ($h) { "Cryptographic Hashing SHA256 (Multi-Threaded)" } else { "Fast File Metadata Logging Only" })
 Base Hashing Speed    : $speedMBps MB/s
 Projected Performance Duration Estimate: $formattedTime
======================================================================
"@
    } -ArgumentList @($root, $withHashes, $ModulePathToLoad) -RunningStatus "Predicting Scan Duration"
})

# ── Clear log ─────────────────────────────────────────────────────────────────
$window.FindName('BtnClearLog').Add_Click({
    $txtLog.Clear()
})

# ── Status polling timer & Lifecycle Observer loop ───────────────────────────
$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
    # Calculate live timeline tracking indices
    $elapsedSuffix = ""
    if ($null -ne $Script:GuiContext.CustomStartTime) {
        $span = (Get-Date) - $Script:GuiContext.CustomStartTime
        $elapsedSuffix = " [{0:hh\:mm\:ss}]" -f $span
    }

    # Extract dynamic advanced telemetry memory profiles
    $advancedDetailsCheckbox = $window.FindName('ChkAdvancedDetails')
    $telemetryString = ""
    if ($advancedDetailsCheckbox -and $advancedDetailsCheckbox.IsChecked) {
        $wsMemory = [System.Diagnostics.Process]::GetCurrentProcess().WorkingSet64 / 1MB
        $gcHeapMemory = [System.GC]::GetTotalMemory($false) / 1MB
        $telemetryString = " — RAM: [WS: $([math]::Round($wsMemory,1))MB | Heap: $([math]::Round($gcHeapMemory,1))MB]"
    }

    # 1. Update status text box from engine module if it registers an operation
    $s = Get-DriveToolsStatus
    if ($s.Operation) {
        if ($chkShowDetails.IsChecked) {
            Set-Status "$($s.Operation) — $($s.Details)${telemetryString}${elapsedSuffix}" '#F9E2AF'
        } else {
            Set-Status "$($s.Operation)...${telemetryString}${elapsedSuffix}" '#F9E2AF'
        }
    } else {
        if ($null -eq $Script:GuiContext.ActivePowerShell) {
            if ($txtStatus.Text -notmatch "Idle") {
                Set-Status "Idle" '#A6E3A1'
            }
        } else {
            if ($Script:GuiContext.CustomStatusText) {
                if ($chkShowDetails.IsChecked) {
                    Set-Status "$($Script:GuiContext.CustomStatusText) — Traversing subdirectories${telemetryString}${elapsedSuffix}" '#F9E2AF'
                } else {
                    Set-Status "$($Script:GuiContext.CustomStatusText)...${telemetryString}${elapsedSuffix}" '#F9E2AF'
                }
            }
        }
    }

    # 2. Lifecycle monitor handles clearing UI elements upon backend script completion
    $runningEngine = $Script:GuiContext.ActivePowerShell
    if ($null -ne $runningEngine) {
        $state = $runningEngine.InvocationStateInfo.State
        if ($state -eq 'Completed' -or $state -eq 'Stopped' -or $state -eq 'Failed') {
            
            if ($runningEngine.Streams.Error.Count -gt 0) {
                foreach ($err in $runningEngine.Streams.Error) { Append-Log "Pipeline Exception: $err" }
            }
            if ($state -eq 'Stopped') {
                Append-Log "Current scanning task forcefully aborted by user."
            }

            try { $runningEngine.Dispose() } catch {}
            if ($Script:GuiContext.OutputCollection) {
                try { $Script:GuiContext.OutputCollection.Dispose() } catch {}
            }
            
            $Script:GuiContext.ActivePowerShell = $null
            $Script:GuiContext.OutputCollection = $null
            $Script:GuiContext.CustomStartTime = $null
            $Script:GuiContext.CustomStatusText = ""
            
            Set-UiButtonsState -Enabled $true
            
            $window.Dispatcher.Invoke({ 
                if ($progressBar) {
                    $progressBar.Visibility = 'Collapsed'
                    $progressBar.IsIndeterminate = $false
                }
                if ($btnCancel) { $btnCancel.Visibility = 'Collapsed' }
            })
            Set-Status "Idle" '#A6E3A1'
        }
    }
})
$timer.Start()

# ── Show window ───────────────────────────────────────────────────────────────
Append-Log "DriveTools Core UI Layer initialized dynamically. Target: '$($txtRoot.Text)'"
[void]$window.ShowDialog()
$timer.Stop()