$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework

$window = [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'studio.xaml')))
$ui = @{}
foreach ($name in @(
    'Model', 'ModelFile', 'ImportGlb', 'GenerateFromPhoto', 'SetupPhotoGenerator',
    'Celadon', 'Cobalt', 'Oatmeal', 'CustomGlaze', 'CustomSwatch', 'CustomColorWheel',
    'CustomBrightness', 'CustomColorHex', 'Recipe',
    'Thickness', 'Temperature', 'OptionsTabs', 'Atmosphere', 'AtmosphereNotes',
    'Cone', 'Ramp', 'Soak', 'Schedule', 'CoolingRate', 'CoolingProfile', 'Clay',
    'ClayColor', 'ThicknessMap', 'Geometry', 'LocateBlender', 'BlenderPath',
    'Render', 'ExportSetup', 'Preview', 'EmptyPreview', 'PreviewLabel', 'Status', 'SavePreview',
    'Orient', 'OrientationEditor', 'OrientationModel', 'RotateSurface', 'Turn', 'Tilt', 'Roll',
    'ResetOrientation', 'BakePhotoTexture', 'DraftPhotoMesh'
)) {
    $ui[$name] = $window.FindName($name)
}

$script:customHue = 10.0
$script:customSaturation = 0.75
$script:customColor = '#C84B32'
function Get-HsvRgb([double]$hue, [double]$saturation, [double]$value) {
    $chroma = $value * $saturation
    $h = (($hue % 360) + 360) % 360 / 60
    $x = $chroma * (1 - [math]::Abs(($h % 2) - 1))
    if ($h -lt 1) { $r=$chroma; $g=$x; $b=0 }
    elseif ($h -lt 2) { $r=$x; $g=$chroma; $b=0 }
    elseif ($h -lt 3) { $r=0; $g=$chroma; $b=$x }
    elseif ($h -lt 4) { $r=0; $g=$x; $b=$chroma }
    elseif ($h -lt 5) { $r=$x; $g=0; $b=$chroma }
    else { $r=$chroma; $g=0; $b=$x }
    $m = $value - $chroma
    return ('#{0:X2}{1:X2}{2:X2}' -f [int][math]::Round(($r+$m)*255), [int][math]::Round(($g+$m)*255), [int][math]::Round(($b+$m)*255))
}
function Update-CustomColor {
    $script:customColor = Get-HsvRgb $script:customHue $script:customSaturation $ui.CustomBrightness.Value
    $ui.CustomColorHex.Text = $script:customColor
    $color = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($script:customColor)
    $ui.CustomSwatch.Fill = [Windows.Media.SolidColorBrush]::new($color)
}

# The wheel maps angle to hue and distance from its center to saturation.
if (-not ('NovaColorWheel' -as [type])) {
    Add-Type -ReferencedAssemblies PresentationCore, WindowsBase -TypeDefinition @'
using System;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
public static class NovaColorWheel {
    public static WriteableBitmap Create(int size) {
        byte[] pixels = new byte[size * size * 4];
        double center = (size - 1) / 2.0;
        for (int y = 0; y < size; y++) for (int x = 0; x < size; x++) {
            double dx = x - center, dy = center - y;
            double saturation = Math.Min(1.0, Math.Sqrt(dx * dx + dy * dy) / center);
            double hue = (Math.Atan2(dy, dx) * 180.0 / Math.PI + 360.0) % 360.0;
            double chroma = saturation, h = hue / 60.0;
            double part = chroma * (1.0 - Math.Abs(h % 2.0 - 1.0));
            double r = 0, g = 0, b = 0;
            if (h < 1) { r = chroma; g = part; }
            else if (h < 2) { r = part; g = chroma; }
            else if (h < 3) { g = chroma; b = part; }
            else if (h < 4) { g = part; b = chroma; }
            else if (h < 5) { r = part; b = chroma; }
            else { r = chroma; b = part; }
            int i = (y * size + x) * 4;
            if (dx * dx + dy * dy > center * center) { pixels[i] = 235; pixels[i + 1] = 242; pixels[i + 2] = 245; }
            else { pixels[i] = (byte)Math.Round(b * 255); pixels[i + 1] = (byte)Math.Round(g * 255); pixels[i + 2] = (byte)Math.Round(r * 255); }
            pixels[i + 3] = 255;
        }
        var bitmap = new WriteableBitmap(size, size, 96, 96, PixelFormats.Bgra32, null);
        bitmap.WritePixels(new Int32Rect(0, 0, size, size), pixels, size * 4, 0);
        return bitmap;
    }
}
'@
}
$ui.CustomColorWheel.Source = [NovaColorWheel]::Create(190)
$ui.CustomColorWheel.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    $point = $eventArgs.GetPosition($sender)
    $dx = $point.X - $sender.ActualWidth / 2
    $dy = $sender.ActualHeight / 2 - $point.Y
    $radius = [math]::Sqrt($dx*$dx + $dy*$dy)
    if ($radius -le $sender.ActualWidth / 2) {
        $script:customHue = ([math]::Atan2($dy, $dx) * 180 / [math]::PI + 360) % 360
        $script:customSaturation = [math]::Min(1, $radius / ($sender.ActualWidth / 2))
        $ui.CustomGlaze.IsChecked = $true
        Update-CustomColor
    }
})
$ui.CustomBrightness.Add_ValueChanged({ $ui.CustomGlaze.IsChecked = $true; Update-CustomColor })

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
            $ui.OptionsTabs.SelectedIndex = 1
        }
        $control.BringIntoView()
        [void]$control.Focus()
        $range = if ($AllowZero) { 'zero or greater' } else { 'greater than zero' }
        throw "$label must be a number $range."
    }
    return $number
}

function Get-ModelSelection {
    if ($script:glbPath) { return [ordered]@{ kind = 'glb'; path = $script:glbPath } }
    return [ordered]@{ kind = 'preset'; id = [string]$ui.Model.SelectedItem.Tag }
}

function Get-Setup {
    $glaze = @($ui.Celadon, $ui.Cobalt, $ui.Oatmeal, $ui.CustomGlaze) | Where-Object { $_.IsChecked } | Select-Object -First 1
    $model = Get-ModelSelection
    $model.rotation_xyz_degrees = @($ui.Tilt.Value, $ui.Roll.Value, $ui.Turn.Value)
    $clayColor = Get-OptionalText $ui.ClayColor
    if ($clayColor -and $clayColor -notmatch '^#[0-9a-fA-F]{6}$') {
        $ui.OptionsTabs.SelectedIndex = 1
        [void]$ui.ClayColor.Focus()
        throw 'Fired clay color must use the #RRGGBB format.'
    }

    $customGlazeColor = $null
    $appearanceSource = 'blender_preset'
    $layer = [ordered]@{ glaze_id = [string]$glaze.Tag; order = 1 }
    if ($glaze.Tag -eq 'CUSTOM') {
        $customGlazeColor = $ui.CustomColorHex.Text
        $appearanceSource = 'blender_custom'
        $layer.color_srgb = $customGlazeColor
    }

    [ordered]@{
        schema_version = 1
        model = $model
        glaze_id = [string]$glaze.Tag
        custom_color_srgb = $customGlazeColor
        appearance_source = $appearanceSource
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
            layers = @($layer)
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

function Set-GlbModel([string]$path) {
    $ui.Model.SelectedIndex = -1
    $script:glbPath = $path
    $ui.ModelFile.Text = [IO.Path]::GetFileName($path)
    $ui.ModelFile.ToolTip = $path
    $ui.ModelFile.Visibility = 'Visible'
    Clear-OrientationMesh
}

function Show-OrientationEditor([bool]$visible) {
    $ui.OrientationEditor.Visibility = if ($visible) { 'Visible' } else { 'Collapsed' }
    $ui.Orient.Content = if ($visible) { 'Back to Render' } else { 'Orient Model' }
}

function Reset-ModelOrientation {
    $ui.Turn.Value = $ui.Tilt.Value = $ui.Roll.Value = 0
}

function Clear-OrientationMesh {
    Show-OrientationEditor $false
    $ui.OrientationModel.Content = $null
    Reset-ModelOrientation
}

function Open-OrientationMesh([string]$path) {
    $reader = [IO.BinaryReader]::new([IO.File]::OpenRead($path))
    try {
        $pointCount = $reader.ReadInt32()
        $indexCount = $reader.ReadInt32()
        if ($pointCount -le 0 -or $indexCount -le 0 -or $reader.BaseStream.Length -ne (8L + 12L * $pointCount + 4L * $indexCount)) {
            throw 'Blender returned an invalid orientation mesh.'
        }
        $positions = [Windows.Media.Media3D.Point3DCollection]::new($pointCount)
        for ($i = 0; $i -lt $pointCount; $i++) {
            $positions.Add([Windows.Media.Media3D.Point3D]::new($reader.ReadSingle(), $reader.ReadSingle(), $reader.ReadSingle()))
        }
        $indices = [Windows.Media.Int32Collection]::new($indexCount)
        for ($i = 0; $i -lt $indexCount; $i++) { $indices.Add($reader.ReadInt32()) }
    } finally {
        $reader.Dispose()
    }
    $mesh = [Windows.Media.Media3D.MeshGeometry3D]::new()
    $mesh.Positions = $positions
    $mesh.TriangleIndices = $indices
    $mesh.Freeze()
    $material = [Windows.Media.Media3D.DiffuseMaterial]::new([Windows.Media.Brushes]::SlateGray)
    $model = [Windows.Media.Media3D.GeometryModel3D]::new($mesh, $material)
    $model.BackMaterial = $material
    $model.Transform = $orientationTransform
    $ui.OrientationModel.Content = $model
    Show-OrientationEditor $true
}

function Get-BlenderArguments([string]$request, [string]$output) {
    return '--background --factory-startup --disable-autoexec --python-exit-code 1 --python "{0}" -- "{1}" "{2}"' -f $worker, $request, $output
}

function Start-OrientationEditor {
    if ($script:job) { return }
    if ($ui.OrientationEditor.Visibility -eq 'Visible') { Show-OrientationEditor $false; return }
    if ($ui.OrientationModel.Content) { Show-OrientationEditor $true; return }
    try {
        if (!$script:blender) { throw 'Select Blender under the Additional Options tab before orienting a model.' }
        $prefix = Join-Path $scratch ([guid]::NewGuid().ToString('N'))
        $request = "$prefix.json"
        $mesh = "$prefix.mesh"
        Write-Setup @{
            model = Get-ModelSelection
            glaze_id = 'CELADON'
            inputs = @{ layers = @(@{ glaze_id = 'CELADON'; order = 1 }) }
        } $request
        Start-StudioJob $script:blender ((Get-BlenderArguments $request $mesh) + ' mesh') @{
            Kind = 'Orientation'; Tool = 'Blender'; Output = $mesh
        } 'Loading model for orientation...'
    } catch {
        Set-Status $_.Exception.Message
    }
}

function Start-StudioJob([string]$program, [string]$arguments, [hashtable]$job, [string]$message) {
    $launch = New-Object Diagnostics.ProcessStartInfo -Property @{
        FileName = $program
        Arguments = $arguments
        UseShellExecute = $false
        CreateNoWindow = $true
        RedirectStandardOutput = $true
        RedirectStandardError = $true
    }
    $job.Process = [Diagnostics.Process]::Start($launch)
    $job.Stdout = $job.Process.StandardOutput.ReadToEndAsync()
    $job.Stderr = $job.Process.StandardError.ReadToEndAsync()
    $script:job = $job
    $ui.Render.IsEnabled = $false
    $ui.GenerateFromPhoto.IsEnabled = $false
    $ui.SetupPhotoGenerator.IsEnabled = $false
    $ui.Orient.IsEnabled = $false
    if ($job.Kind -in @('Photo', 'Orientation')) {
        $ui.Model.IsEnabled = $false
        $ui.ImportGlb.IsEnabled = $false
    }
    Set-Status $message
    $timer.Start()
}

function Start-Preview {
    if ($script:job) { return }
    try {
        if (!$script:blender -or !(Test-Path -LiteralPath $script:blender -PathType Leaf)) {
            $ui.OptionsTabs.SelectedIndex = 1
            $ui.LocateBlender.BringIntoView()
            throw 'Install Blender 5.2 or newer, then use Locate Blender under the Additional Options tab.'
        }

        $setup = Get-Setup
        $modelName = if ($script:glbPath) { [IO.Path]::GetFileNameWithoutExtension($script:glbPath) } else { $ui.Model.SelectedItem.Content }
        $glazeName = switch ($setup.glaze_id) {
            'CELADON' { 'Jade Celadon' }
            'COBALT' { 'Cobalt Blue' }
            'OATMEAL' { 'Speckled Oatmeal' }
            'CUSTOM' { "Custom $($setup.custom_color_srgb)" }
        }
        $prefix = Join-Path $scratch ([guid]::NewGuid().ToString('N'))
        $request = "$prefix.json"
        $image = "$prefix.png"
        Write-Setup $setup $request

        $arguments = Get-BlenderArguments $request $image
        $label = "$modelName / $glazeName"
        Start-StudioJob $script:blender $arguments @{
            Kind = 'Preview'; Tool = 'Blender'; Output = $image; Label = $label
        } "Rendering $label in Blender..."
    } catch {
        Set-Status $_.Exception.Message
    }
}

function Test-PhotoGenerator {
    if (!(Test-Path -LiteralPath $generatorPython -PathType Leaf)) { return $false }
    foreach ($name in @('model.ckpt', 'config.yaml', 'dino.json', 'u2netp.onnx')) {
        if (!(Test-Path -LiteralPath (Join-Path $generatorRoot ".runtime/weights/$name") -PathType Leaf)) {
            return $false
        }
    }
    return $true
}

function Start-PhotoGeneration {
    if ($script:job) { return }
    try {
        if (!(Test-PhotoGenerator)) {
            $ui.OptionsTabs.SelectedIndex = 1
            $ui.SetupPhotoGenerator.BringIntoView()
            throw 'Open the Additional Options tab and click Set Up Photo Generator first.'
        }

        $photo = New-Object Microsoft.Win32.OpenFileDialog -Property @{
            Filter = 'Photos (*.png;*.jpg;*.jpeg)|*.png;*.jpg;*.jpeg'
        }
        if (!$photo.ShowDialog($window)) { return }

        $output = New-Object Microsoft.Win32.SaveFileDialog -Property @{
            Filter = 'glTF binary (*.glb)|*.glb'; DefaultExt = '.glb'
            FileName = [IO.Path]::GetFileNameWithoutExtension($photo.FileName) + '.glb'
        }
        if (!$output.ShowDialog($window)) { return }
        if ([IO.Path]::GetExtension($output.FileName) -ne '.glb') { throw 'Choose a .glb output filename.' }

        $staged = Join-Path $scratch ([guid]::NewGuid().ToString('N') + '.glb')
        $arguments = '-B "{0}" "{1}" "{2}"' -f $generatorScript, $photo.FileName, $staged
        if (!$ui.BakePhotoTexture.IsChecked) { $arguments += ' --geometry-only' }
        if ($ui.DraftPhotoMesh.IsChecked) { $arguments += ' --mesh-resolution 96' }
        Start-StudioJob $generatorPython $arguments @{
            Kind = 'Photo'; Tool = 'Photo generator'; Output = $staged; Destination = $output.FileName
        } 'Generating a GLB from the photo. This can take several minutes...'
    } catch {
        Set-Status $_.Exception.Message
    }
}

$script:blender = Find-Blender
$script:glbPath = $null
$script:job = $null
$script:lastImage = $null
$worker = Join-Path $PSScriptRoot 'render_preview.py'
$generatorRoot = Join-Path $PSScriptRoot 'Nova-Image-to-3D'
$generatorScript = Join-Path $generatorRoot 'nova.py'
$generatorPython = Join-Path $generatorRoot '.runtime/env/Scripts/python.exe'
$orientationTransform = [Windows.Media.Media3D.Transform3DGroup]::new()
$rotation = @{}
# Blender uses XYZ rotation in order. In the viewport, Blender Y maps to -Z and Z maps to Y.
foreach ($axis in @('Tilt', 'Roll', 'Turn')) {
    $vector = switch ($axis) {
        'Tilt' { [Windows.Media.Media3D.Vector3D]::new(1, 0, 0) }
        'Roll' { [Windows.Media.Media3D.Vector3D]::new(0, 0, -1) }
        'Turn' { [Windows.Media.Media3D.Vector3D]::new(0, 1, 0) }
    }
    $rotation[$axis] = [Windows.Media.Media3D.AxisAngleRotation3D]::new($vector, 0)
    $orientationTransform.Children.Add([Windows.Media.Media3D.RotateTransform3D]::new($rotation[$axis]))
    $ui[$axis].Add_ValueChanged({ param($sender, $eventArgs) $rotation[$sender.Name].Angle = $eventArgs.NewValue })
}
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('nova-pottery-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(200)

$timer.Add_Tick({
    $job = $script:job
    if (!$job.Process.HasExited) { return }
    $timer.Stop()
    try {
        if ($job.Process.ExitCode -ne 0 -or ($job.Output -and !(Test-Path -LiteralPath $job.Output -PathType Leaf))) {
            $lines = ($job.Stdout.Result + "`n" + $job.Stderr.Result) -split '\r?\n'
            $detail = $lines | Where-Object { $_ -match '(?i)error: |exception: ' -and $_ -notlike 'Error: script failed*' } | Select-Object -Last 1
            if (!$detail) {
                $detail = ($job.Stderr.Result -split '\r?\n') | Where-Object { $_.Trim() } | Select-Object -First 1
            }
            if ($detail) { throw $detail }
            throw "$($job.Tool) did not finish successfully (exit code $($job.Process.ExitCode))."
        }

        if ($job.Kind -eq 'Photo') {
            [IO.File]::Copy($job.Output, $job.Destination, $true)
            Set-GlbModel $job.Destination
            Set-Status 'GLB generated and selected. Click Render Preview to apply the glaze.'
            return
        }
        if ($job.Kind -eq 'Setup') {
            if (!(Test-PhotoGenerator)) { throw 'Setup did not produce all required photo generator files.' }
            Set-Status 'Photo generator ready. Click Generate GLB from Photo to begin.'
            return
        }
        if ($job.Kind -eq 'Orientation') {
            Open-OrientationMesh $job.Output
            Set-Status 'Drag to turn and tilt, or use the sliders. Render Preview applies the orientation.'
            return
        }

        $bitmap = New-Object Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.CacheOption = 'OnLoad'
        $bitmap.UriSource = [uri]$job.Output
        $bitmap.EndInit()
        $ui.Preview.Source = $bitmap
        $ui.EmptyPreview.Visibility = 'Collapsed'
        $ui.PreviewLabel.Text = "Last render / $($job.Label)"
        $script:lastImage = $job.Output
        $ui.SavePreview.IsEnabled = $true
        Show-OrientationEditor $false
        Set-Status 'Preview ready'
    } catch {
        Set-Status $_.Exception.Message
    } finally {
        $job.Process.Dispose()
        $script:job = $null
        $ui.Render.IsEnabled = $true
        $ui.GenerateFromPhoto.IsEnabled = $true
        $ui.SetupPhotoGenerator.IsEnabled = $true
        $ui.Orient.IsEnabled = $true
        $ui.Model.IsEnabled = $true
        $ui.ImportGlb.IsEnabled = $true
    }
})

$ui.Model.Add_SelectionChanged({
    $script:glbPath = $null
    $ui.ModelFile.Visibility = 'Collapsed'
    Clear-OrientationMesh
})
$ui.Orient.Add_Click({ Start-OrientationEditor })
$ui.ResetOrientation.Add_Click({ Reset-ModelOrientation })
$ui.RotateSurface.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    $script:dragStart = $eventArgs.GetPosition($sender)
    $script:dragTurn = $ui.Turn.Value
    $script:dragTilt = $ui.Tilt.Value
    [void]$sender.CaptureMouse()
})
$ui.RotateSurface.Add_MouseMove({
    param($sender, $eventArgs)
    if (!$sender.IsMouseCaptured -or $eventArgs.LeftButton -ne 'Pressed') { return }
    $point = $eventArgs.GetPosition($sender)
    $turn = [math]::Round($script:dragTurn + ($point.X - $script:dragStart.X) * .6)
    $tilt = [math]::Round($script:dragTilt + ($point.Y - $script:dragStart.Y) * .6)
    $ui.Turn.Value = ((($turn + 180) % 360 + 360) % 360) - 180
    $ui.Tilt.Value = ((($tilt + 180) % 360 + 360) % 360) - 180
})
$ui.RotateSurface.Add_MouseLeftButtonUp({ param($sender, $eventArgs) $sender.ReleaseMouseCapture() })
$ui.ImportGlb.Add_Click({
    $dialog = New-Object Microsoft.Win32.OpenFileDialog -Property @{ Filter = 'glTF binary (*.glb)|*.glb' }
    if ($dialog.ShowDialog($window)) {
        Set-GlbModel $dialog.FileName
    }
})
$ui.GenerateFromPhoto.Add_Click({ Start-PhotoGeneration })
$ui.SetupPhotoGenerator.Add_Click({
    if ($script:job) { return }
    try {
        $setupScript = Join-Path $generatorRoot 'setup.ps1'
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $setupScript
        Start-StudioJob (Join-Path $PSHOME 'powershell.exe') $arguments @{
            Kind = 'Setup'; Tool = 'Photo generator setup'
        } 'Installing photo generator dependencies and model weights. This can take several minutes...'
    } catch {
        Set-Status $_.Exception.Message
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
