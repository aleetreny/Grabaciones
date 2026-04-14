param(
    [Parameter(Mandatory = $true)]
    [string]$SessionId,
    [Parameter(Mandatory = $true)]
    [string]$StatusFile,
    [Parameter(Mandatory = $true)]
    [string]$LogFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Procesar llamadas"
        Width="620"
        Height="360"
        MinWidth="560"
        MinHeight="320"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanMinimize"
        Background="#FFF7F8FA">
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Margin="0,0,0,10">
            <TextBlock Text="Procesar llamadas"
                       FontSize="24"
                       FontWeight="Bold"
                       Foreground="#111827" />
            <TextBlock Text="La ventana puede quedarse minimizada mientras el proceso sigue en segundo plano."
                       Margin="0,8,0,0"
                       FontSize="14"
                       Foreground="#374151"
                       TextWrapping="Wrap" />
        </StackPanel>

        <StackPanel Grid.Row="1" Margin="0,0,0,12">
            <TextBlock x:Name="StatusText"
                       Text="Preparando proceso..."
                       FontSize="18"
                       FontWeight="SemiBold"
                       Foreground="#111827"
                       TextWrapping="Wrap" />
            <TextBlock x:Name="DetailText"
                       Margin="0,6,0,0"
                       Text="Abriendo la preparacion de Windows."
                       FontSize="14"
                       Foreground="#4B5563"
                       TextWrapping="Wrap" />
        </StackPanel>

        <ProgressBar x:Name="MainProgress"
                     Grid.Row="2"
                     Height="18"
                     IsIndeterminate="True"
                     Minimum="0"
                     Maximum="100"
                     Value="0"
                     Margin="0,0,0,12" />

        <TextBox x:Name="LogBox"
                 Grid.Row="3"
                 IsReadOnly="True"
                 TextWrapping="Wrap"
                 VerticalScrollBarVisibility="Auto"
                 HorizontalScrollBarVisibility="Disabled"
                 FontFamily="Consolas"
                 FontSize="12"
                 Background="White"
                 Foreground="#111827"
                 BorderBrush="#D1D5DB" />

        <Grid Grid.Row="4" Margin="0,14,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="*" />
            </Grid.ColumnDefinitions>

            <Button x:Name="MinimizeButton"
                    Grid.Column="0"
                    Content="Dejar en segundo plano"
                    Margin="0,0,8,0"
                    Padding="10,7" />
            <Button x:Name="CloseButton"
                    Grid.Column="1"
                    Content="Cerrar ventana"
                    Margin="8,0,0,0"
                    Padding="10,7" />
        </Grid>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$statusText = $window.FindName("StatusText")
$detailText = $window.FindName("DetailText")
$progressBar = $window.FindName("MainProgress")
$logBox = $window.FindName("LogBox")
$minimizeButton = $window.FindName("MinimizeButton")
$closeButton = $window.FindName("CloseButton")

$minimizeButton.Add_Click({
    $window.WindowState = [System.Windows.WindowState]::Minimized
})

$closeButton.Add_Click({
    $window.Close()
})

$window.Add_SourceInitialized({
    $window.Activate()
    $window.Topmost = $true
})

$topmostTimer = New-Object System.Windows.Threading.DispatcherTimer
$topmostTimer.Interval = [TimeSpan]::FromSeconds(1.2)
$topmostTimer.Add_Tick({
    $window.Topmost = $false
    $topmostTimer.Stop()
})

$refreshTimer = New-Object System.Windows.Threading.DispatcherTimer
$refreshTimer.Interval = [TimeSpan]::FromMilliseconds(350)
$refreshTimer.Add_Tick({
    try {
        if (Test-Path -LiteralPath $StatusFile) {
            $rawState = Get-Content -LiteralPath $StatusFile -Raw -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($rawState)) {
                $state = $rawState | ConvertFrom-Json

                if ($null -ne $state.session_id -and [string]$state.session_id -ne $SessionId) {
                    $refreshTimer.Stop()
                    $window.Close()
                    return
                }

                if ($null -ne $state.status) {
                    $statusText.Text = [string]$state.status
                }
                if ($null -ne $state.detail) {
                    $detailText.Text = [string]$state.detail
                }

                $isIndeterminate = $true
                if ($null -ne $state.indeterminate) {
                    $isIndeterminate = [bool]$state.indeterminate
                }
                $progressBar.IsIndeterminate = $isIndeterminate

                if (-not $isIndeterminate -and $null -ne $state.percent) {
                    $progressBar.Value = [double]$state.percent
                } elseif ($isIndeterminate) {
                    $progressBar.Value = 0
                }

                if ($state.close -eq $true) {
                    $refreshTimer.Stop()
                    $window.Close()
                    return
                }
            }
        }

        if (Test-Path -LiteralPath $LogFile) {
            $lines = Get-Content -LiteralPath $LogFile -Tail 10 -ErrorAction SilentlyContinue
            if ($null -ne $lines) {
                $text = ($lines -join [Environment]::NewLine).Trim()
                if ($logBox.Text -ne $text) {
                    $logBox.Text = $text
                    $logBox.ScrollToEnd()
                }
            }
        }
    } catch {
    }
})

$window.Add_Closed({
    $refreshTimer.Stop()
    $topmostTimer.Stop()
})

$topmostTimer.Start()
$refreshTimer.Start()
[void]$window.ShowDialog()
