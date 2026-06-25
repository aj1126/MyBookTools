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

# ── Import module if not already loaded ──────────────────────────────────────
if (-not (Get-Module DriveTools)) {
    $localPath = Join-Path $ScriptDir "DriveTools.psm1"
    $modPath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\DriveTools\2.0\DriveTools.psm1"
    if (Test-Path $localPath) {
        Import-Module $localPath -Force
    } elseif (Test-Path $modPath) {
        Import-Module $modPath -Force
    } else {
        [System.Windows.MessageBox]::Show(
            "DriveTools module not found.`nExpected local path:`n$localPath",
            "DriveTools GUI", "OK", "Error") | Out-Null
        exit 1
    }
}

# ── XAML layout ──────────────────────────────────────────────────────────────
[xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="DriveTools v2.0" Height="680" Width="780"
    ResizeMode="CanResize" WindowStartupLocation="CenterScreen"
    Background="#1E1E2E">

    <Window.Resources>
        <!-- Base button style -->
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
            <RowDefinition Height="Auto"/>   <!-- header -->
            <RowDefinition Height="Auto"/>   <!-- root path row -->
            <RowDefinition Height="Auto"/>   <!-- options row -->
            <RowDefinition Height="Auto"/>   <!-- buttons row -->
            <RowDefinition Height="Auto"/>   <!-- status bar -->
            <RowDefinition Height="*"/>      <!-- log output -->
        </Grid.RowDefinitions>

        <!-- Header -->
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

        <!-- Root path & Drive dropdown -->
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

        <!-- Options -->
        <WrapPanel Grid.Row="2" Margin="0,0,0,10">
            <CheckBox x:Name="ChkHashes"    Content="Include Hashes"/>
            <CheckBox x:Name="ChkDryRun"    Content="Dry Run"  IsChecked="True"/>
            <CheckBox x:Name="ChkEmptyDirs" Content="Remove Empty Dirs"/>
            <CheckBox x:Name="ChkCompress"  Content="Compress Archives"/>
            <CheckBox x:Name="ChkDupeRpt"   Content="Report Duplicates"/>
        </WrapPanel>

        <!-- Action buttons -->
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

        <!-- Status bar -->
        <Border Grid.Row="4" Background="#313244" CornerRadius="4"
                Margin="0,0,0,8" Padding="8,4">
            <StackPanel Orientation="Horizontal">
                <TextBlock Text="Status: " Foreground="#585B70"
                           FontFamily="Cascadia Code, Consolas, Monospace" FontSize="12"/>
                <TextBlock x:Name="TxtStatus" Text="Idle"
                           Foreground="#A6E3A1"
                           FontFamily="Cascadia Code, Consolas, Monospace" FontSize="12"/>
            </StackPanel>
        </Border>

        <!-- Log output -->
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
$txtRoot      = $window.FindName('TxtRoot')
$txtStatus    = $window.FindName('TxtStatus')
$txtLog       = $window.FindName('TxtLog')
$logScroller  = $window.FindName('LogScroller')
$chkHashes    = $window.FindName('ChkHashes')
$chkDryRun    = $window.FindName('ChkDryRun')
$chkEmptyDirs = $window.FindName('ChkEmptyDirs')
$chkCompress  = $window.FindName('ChkCompress')
$chkDupeRpt   = $window.FindName('ChkDupeRpt')
$comboDrives  = $window.FindName('ComboDrives')

# ── Populate drives list ──────────────────────────────────────────────────────
$drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -in 'Fixed','Removable' }
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
}

function Set-Status {
    param([string]$Text, [string]$Color = '#A6E3A1')
    $window.Dispatcher.Invoke({
        $txtStatus.Text            = $Text
        $txtStatus.Foreground      = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
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
    Set-Status "Running audit…" '#F9E2AF'
    Append-Log "Starting audit of '$root' (Hashes=$withHashes)"
    $job = Start-Job -ScriptBlock {
        param($r,$h)
        Import-Module DriveTools -Force
        $csv = Invoke-DriveAuditFast -RootPath $r -IncludeHashes:$h
        "CSV saved to: $csv"
    } -ArgumentList $root,$withHashes
    Register-ObjectEvent $job -EventName StateChanged -Action {
        $result = $job | Receive-Job -ErrorAction SilentlyContinue
        Append-Log ($result -join "`n")
        Set-Status "Idle"
        $job | Remove-Job -Force
    } | Out-Null
})

# ── Hash Cache ────────────────────────────────────────────────────────────────
$window.FindName('BtnHashCache').Add_Click({
    $root = $txtRoot.Text
    Set-Status "Updating hash cache…" '#F9E2AF'
    Append-Log "Updating hash cache for '$root'"
    $job = Start-Job -ScriptBlock {
        param($r)
        Import-Module DriveTools -Force
        Update-DriveHashCache -RootPath $r
    } -ArgumentList $root
    Register-ObjectEvent $job -EventName StateChanged -Action {
        Receive-Job $job -ErrorAction SilentlyContinue | ForEach-Object { Append-Log $_ }
        Set-Status "Idle"
        $job | Remove-Job -Force
    } | Out-Null
})

# ── Categorize ────────────────────────────────────────────────────────────────
$window.FindName('BtnCategorize').Add_Click({
    $root    = $txtRoot.Text
    $dryRun  = $chkDryRun.IsChecked
    $mode    = if ($dryRun) { 'DryRun' } else { 'LIVE' }
    Set-Status "Categorizing… ($mode)" '#F9E2AF'
    Append-Log "Categorize: root='$root' DryRun=$dryRun"
    $job = Start-Job -ScriptBlock {
        param($r,$d)
        Import-Module DriveTools -Force
        Invoke-DriveCategorize -RootPath $r -DryRun:$d
        "Categorization complete."
    } -ArgumentList $root,$dryRun
    Register-ObjectEvent $job -EventName StateChanged -Action {
        Receive-Job $job -ErrorAction SilentlyContinue | ForEach-Object { Append-Log $_ }
        Set-Status "Idle"
        $job | Remove-Job -Force
    } | Out-Null
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
    Set-Status "Resolving duplicates…" '#F9E2AF'
    Append-Log "Dedup: root='$root' DryRun=$dryRun"
    $job = Start-Job -ScriptBlock {
        param($r,$d)
        Import-Module DriveTools -Force
        Resolve-DriveDuplicates -RootPath $r -DryRun:$d
        "Dedup complete."
    } -ArgumentList $root,$dryRun
    Register-ObjectEvent $job -EventName StateChanged -Action {
        Receive-Job $job -ErrorAction SilentlyContinue | ForEach-Object { Append-Log $_ }
        Set-Status "Idle"
        $job | Remove-Job -Force
    } | Out-Null
})

# ── Cleanup ───────────────────────────────────────────────────────────────────
$window.FindName('BtnCleanup').Add_Click({
    $root      = $txtRoot.Text
    $emptyDirs = $chkEmptyDirs.IsChecked
    $compress  = $chkCompress.IsChecked
    $dupeRpt   = $chkDupeRpt.IsChecked
    Set-Status "Running cleanup…" '#F9E2AF'
    Append-Log "Cleanup: EmptyDirs=$emptyDirs Compress=$compress DupeReport=$dupeRpt"
    $job = Start-Job -ScriptBlock {
        param($r,$e,$c,$d)
        Import-Module DriveTools -Force
        Invoke-DriveCleanup -RootPath $r `
            -RemoveEmptyDirectories:$e `
            -CompressArchives:$c `
            -ReportDuplicates:$d
        "Cleanup complete."
    } -ArgumentList $root,$emptyDirs,$compress,$dupeRpt
    Register-ObjectEvent $job -EventName StateChanged -Action {
        Receive-Job $job -ErrorAction SilentlyContinue | ForEach-Object { Append-Log $_ }
        Set-Status "Idle"
        $job | Remove-Job -Force
    } | Out-Null
})

# ── Visual Map ────────────────────────────────────────────────────────────────
$window.FindName('BtnMap').Add_Click({
    $root = $txtRoot.Text
    Set-Status "Generating tree map…" '#F9E2AF'
    Append-Log "Building visual map for '$root'"
    $job = Start-Job -ScriptBlock {
        param($r)
        Import-Module DriveTools -Force
        $out = Show-DriveVisualMap -RootPath $r -MaxDepth 4
        "Map saved — $($out.Count) lines"
    } -ArgumentList $root
    Register-ObjectEvent $job -EventName StateChanged -Action {
        Receive-Job $job -ErrorAction SilentlyContinue | ForEach-Object { Append-Log $_ }
        Set-Status "Idle"
        $job | Remove-Job -Force
    } | Out-Null
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
    Set-Status "Predicting scan duration…" '#F9E2AF'
    Append-Log "Starting scan duration prediction for '$root' (Hashes=$withHashes)"
    $job = Start-Job -ScriptBlock {
        param($r,$h)
        Import-Module MyBookTools
        Get-MyBookScanPrediction -RootPath $r -IncludeHashes:$h
    } -ArgumentList $root,$withHashes
    Register-ObjectEvent $job -EventName StateChanged -Action {
        $prediction = $job | Receive-Job -ErrorAction SilentlyContinue
        if ($prediction) {
            Append-Log "--------------------------------------------"
            Append-Log "Scan Duration Prediction Results:"
            Append-Log "  Root Path: $($prediction.RootPath)"
            Append-Log "  Estimated Files: {0:N0}" -f $prediction.EstimatedFileCount
            Append-Log "  Estimated Size: {0:N2} GB" -f ($prediction.EstimatedTotalSizeBytes / 1GB)
            Append-Log "  Traversal Speed: {0:N0} files/sec" -f $prediction.TraversalSpeedFilesPerSec
            Append-Log "  Estimated Traversal: $($prediction.EstimatedTraversalDuration)"
            if ($prediction.IncludeHashes) {
                Append-Log "  Hashing Speed: {0:N2} MB/sec" -f ($prediction.HashingSpeedBytesPerSec / 1MB)
                Append-Log "  Estimated Hashing: $($prediction.EstimatedHashingDuration)"
            }
            Append-Log "  Total Estimated Duration: $($prediction.TotalEstimatedDuration)"
            Append-Log "--------------------------------------------"
        } else {
            Append-Log "Failed to retrieve prediction."
        }
        Set-Status "Idle"
        $job | Remove-Job -Force
    } | Out-Null
})

# ── Clear log ─────────────────────────────────────────────────────────────────
$window.FindName('BtnClearLog').Add_Click({
    $txtLog.Clear()
})

# ── Status polling timer (updates status bar from module) ─────────────────────
$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({
    $s = Get-DriveToolsStatus
    if ($s.Operation) {
        Set-Status "$($s.Operation) — $($s.Details)" '#F9E2AF'
    } else {
        Set-Status "Idle" '#A6E3A1'
    }
})
$timer.Start()

# ── Show window ───────────────────────────────────────────────────────────────
Append-Log "DriveTools GUI ready. Root='$($txtRoot.Text)'"
[void]$window.ShowDialog()
$timer.Stop()

