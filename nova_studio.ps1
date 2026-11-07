$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework

$window = [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'studio.xaml')))
$ui = @{}
foreach ($name in @(
    'Model', 'ModelFile', 'ImportGlb', 'Celadon', 'Cobalt', 'Oatmeal', 'Recipe',
    'Thickness', 'Temperature', 'Advanced', 'Atmosphere', 'AtmosphereNotes',
    'Cone', 'Ramp', 'Soak', 'Schedule', 'CoolingRate', 'CoolingProfile', 'Clay',
    'ClayColor', 'ThicknessMap', 'Geometry', 'LocateBlender', 'BlenderPath',
    'Render', 'ExportSetup', 'Preview', 'EmptyPreview', 'PreviewLabel', 'Status', 'SavePreview'
)) {
    $ui[$name] = $window.FindName($name)
}

function Find-Blender {
    if ($env:NOVA_BLENDER -and (Test-Path -LiteralPath $env:NOVA_BLENDER -PathType Leaf)) {
        return $env:NOVA_BLENDER
    }
    $command = Get-Command blender.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }

    $installRoot = Join-Path $env:ProgramFiles 'Blender Foundation'
    if (Test-Path -LiteralPath $installRoot) {
        $install = Get-ChildItem -LiteralPath $installRoot -Directory |
            Where-Object { $_.Name -match '^Blender \d+\.\d+(\.\d+)?$' } |
            Sort-Object { [version]($_.Name -replace '^Blender ', '') } -Descending |
            ForEach-Object { Join-Path $_.FullName 'blender.exe' } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -First 1
        return $install
    }
}

function Get-OptionalText($control) {
    $value = $control.Text.Trim()
    if ($value) { return $value }
    return $null
}

function Get-OptionalNumber($control, [string]$label, [switch]$AllowZero) {
    $value = Get-OptionalText $control
    if (!$value) { return $null }

    $number = 0.0
    $style = [Globalization.NumberStyles]::Float
    $parsed = [double]::TryParse($value, $style, [Globalization.CultureInfo]::CurrentCulture, [ref]$number) -or
        [double]::TryParse($value, $style, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)
    if (!$parsed -or [double]::IsNaN($number) -or [double]::IsInfinity($number) -or
        $number -lt 0 -or (!$AllowZero -and $number -eq 0)) {
        if (!$control.IsVisible -and $control -in @($ui.Ramp, $ui.Soak, $ui.CoolingRate)) {
            $ui.Advanced.IsExpanded = $true
        }
        $control.BringIntoView()
        [void]$control.Focus()
        $range = if ($AllowZero) { 'zero or greater' } else { 'greater than zero' }
        throw "$label must be a number $range."
    }
    return $number
}

function Get-Setup {
    $glaze = @($ui.Celadon, $ui.Cobalt, $ui.Oatmeal) | Where-Object { $_.IsChecked } | Select-Object -First 1
    $model = if ($script:glbPath) {
        [ordered]@{ kind = 'glb'; path = $script:glbPath }
    } else {
        [ordered]@{ kind = 'preset'; id = [string]$ui.Model.SelectedItem.Tag }
    }
    $clayColor = Get-OptionalText $ui.ClayColor
    if ($clayColor -and $clayColor -notmatch '^#[0-9a-fA-F]{6}$') {
        $ui.Advanced.IsExpanded = $true
        [void]$ui.ClayColor.Focus()
        throw 'Fired clay color must use the #RRGGBB format.'
    }

    [ordered]@{
        schema_version = 1
        model = $model
        glaze_id = [string]$glaze.Tag
        appearance_source = 'blender_preset'
        inputs = [ordered]@{
            recipe_id_or_composition = Get-OptionalText $ui.Recipe
            nominal_thickness_mm = Get-OptionalNumber $ui.Thickness 'Glaze thickness'
            peak_temperature_C = Get-OptionalNumber $ui.Temperature 'Peak firing temperature'
            atmosphere = $ui.Atmosphere.SelectedItem.Tag
            atmosphere_notes = Get-OptionalText $ui.AtmosphereNotes
            cone = Get-OptionalText $ui.Cone
            heat_up_rate_C_per_hour = Get-OptionalNumber $ui.Ramp 'Heat-up rate'
            peak_soak_minutes = Get-OptionalNumber $ui.Soak 'Peak hold' -AllowZero
            firing_schedule = Get-OptionalText $ui.Schedule
            cooling_rate_C_per_hour = Get-OptionalNumber $ui.CoolingRate 'Cooling rate'
            cooling_profile = Get-OptionalText $ui.CoolingProfile
            clay_body = Get-OptionalText $ui.Clay
            fired_clay_color_srgb = $clayColor
            thickness_map_path = Get-OptionalText $ui.ThicknessMap
            firing_geometry_notes = Get-OptionalText $ui.Geometry
            layers = @([ordered]@{ glaze_id = [string]$glaze.Tag; order = 1 })
        }
    }
}

function Write-Setup($setup, [string]$path) {
    [IO.File]::WriteAllText($path, ($setup | ConvertTo-Json -Depth 6))
}

function Set-Status([string]$message) {
    $ui.Status.Text = $message
    $ui.Status.ToolTip = $message
}

function Update-BlenderPath {
    $ui.BlenderPath.Text = if ($script:blender) { $script:blender } else { 'Blender 5.2 or newer is required.' }
}

function Start-Preview {
    if ($script:job) { return }
    try {
        if (!$script:blender -or !(Test-Path -LiteralPath $script:blender -PathType Leaf)) {
            $ui.Advanced.IsExpanded = $true
            $ui.LocateBlender.BringIntoView()
            throw 'Install Blender 5.2 or newer, then use Locate Blender under Advanced Options.'
        }

        $setup = Get-Setup
        $modelName = if ($script:glbPath) { [IO.Path]::GetFileNameWithoutExtension($script:glbPath) } else { $ui.Model.SelectedItem.Content }
        $glazeName = switch ($setup.glaze_id) {
            'CELADON' { 'Jade Celadon' }
            'COBALT' { 'Cobalt Blue' }
            'OATMEAL' { 'Speckled Oatmeal' }
        }
        $prefix = Join-Path $scratch ([guid]::NewGuid().ToString('N'))
        $request = "$prefix.json"
        $image = "$prefix.png"
        Write-Setup $setup $request

        $launch = New-Object Diagnostics.ProcessStartInfo -Property @{
            FileName = $script:blender
            Arguments = '--background --factory-startup --disable-autoexec --python-exit-code 1 --python "{0}" -- "{1}" "{2}"' -f $worker, $request, $image
            UseShellExecute = $false
            CreateNoWindow = $true
            RedirectStandardOutput = $true
            RedirectStandardError = $true
        }
        $process = [Diagnostics.Process]::Start($launch)
        $script:job = @{
            Process = $process
            Image = $image
            Stdout = $process.StandardOutput.ReadToEndAsync()
            Stderr = $process.StandardError.ReadToEndAsync()
            Label = "$modelName / $glazeName"
        }
        $ui.Render.IsEnabled = $false
        Set-Status "Rendering $($script:job.Label) in Blender..."
        $timer.Start()
    } catch {
        Set-Status $_.Exception.Message
    }
}

$script:blender = Find-Blender
$script:glbPath = $null
$script:job = $null
$script:lastImage = $null
$worker = Join-Path $PSScriptRoot 'render_preview.py'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('nova-pottery-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(200)

$timer.Add_Tick({
    $job = $script:job
    if (!$job.Process.HasExited) { return }
    $timer.Stop()
    try {
        if ($job.Process.ExitCode -ne 0 -or !(Test-Path -LiteralPath $job.Image -PathType Leaf)) {
            $lines = ($job.Stdout.Result + "`n" + $job.Stderr.Result) -split '\r?\n'
            $detail = $lines | Where-Object { $_ -match 'Error: |Exception: ' -and $_ -notlike 'Error: script failed*' } | Select-Object -Last 1
            if ($detail) { throw $detail }
            throw "Blender exited with code $($job.Process.ExitCode) before saving the preview."
        }

        $bitmap = New-Object Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.CacheOption = 'OnLoad'
        $bitmap.UriSource = [uri]$job.Image
        $bitmap.EndInit()
        $ui.Preview.Source = $bitmap
        $ui.EmptyPreview.Visibility = 'Collapsed'
        $ui.PreviewLabel.Text = "Last render / $($job.Label)"
        $script:lastImage = $job.Image
        $ui.SavePreview.IsEnabled = $true
        Set-Status 'Preview ready'
    } catch {
        Set-Status $_.Exception.Message
    } finally {
        $job.Process.Dispose()
        $script:job = $null
        $ui.Render.IsEnabled = $true
    }
})

$ui.Model.Add_SelectionChanged({
    $script:glbPath = $null
    $ui.ModelFile.Visibility = 'Collapsed'
})
$ui.ImportGlb.Add_Click({
    $dialog = New-Object Microsoft.Win32.OpenFileDialog -Property @{ Filter = 'glTF binary (*.glb)|*.glb' }
    if ($dialog.ShowDialog($window)) {
        $ui.Model.SelectedIndex = -1
        $script:glbPath = $dialog.FileName
        $ui.ModelFile.Text = [IO.Path]::GetFileName($script:glbPath)
        $ui.ModelFile.ToolTip = $script:glbPath
        $ui.ModelFile.Visibility = 'Visible'
    }
})
$ui.LocateBlender.Add_Click({
    $dialog = New-Object Microsoft.Win32.OpenFileDialog -Property @{ Filter = 'Blender (blender.exe)|blender.exe' }
    if ($dialog.ShowDialog($window)) {
        $script:blender = $dialog.FileName
        Update-BlenderPath
        Set-Status 'Blender selected. Click Render Preview to begin.'
    }
})
$ui.Render.Add_Click({ Start-Preview })
$ui.ExportSetup.Add_Click({
    try {
        $setup = Get-Setup
        $dialog = New-Object Microsoft.Win32.SaveFileDialog -Property @{
            Filter = 'NOVA setup (*.json)|*.json'; FileName = 'nova-setup.json'; DefaultExt = '.json'
        }
        if ($dialog.ShowDialog($window)) {
            Write-Setup $setup $dialog.FileName
            Set-Status 'Setup exported'
        }
    } catch {
        Set-Status $_.Exception.Message
    }
})
$ui.SavePreview.Add_Click({
    try {
        $dialog = New-Object Microsoft.Win32.SaveFileDialog -Property @{
            Filter = 'PNG image (*.png)|*.png'; FileName = 'nova-preview.png'; DefaultExt = '.png'
        }
        if ($dialog.ShowDialog($window)) {
            [IO.File]::Copy($script:lastImage, $dialog.FileName, $true)
            Set-Status 'Preview saved'
        }
    } catch {
        Set-Status $_.Exception.Message
    }
})

Update-BlenderPath
$window.Add_ContentRendered({ Start-Preview })
$window.Add_Closed({
    $timer.Stop()
    if ($script:job) {
        $process = $script:job.Process
        if (!$process.HasExited) { $process.Kill() }
        [void]$process.WaitForExit(3000)
        $process.Dispose()
    }
    Get-ChildItem -LiteralPath $scratch -File | Remove-Item -ErrorAction SilentlyContinue
    [IO.Directory]::Delete($scratch)
})
[void]$window.ShowDialog()
