$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Security

$window = [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'studio.xaml')))
$ui = @{}
foreach ($name in @(
    'Model', 'ModelFile', 'ImportModel', 'SetupPhotoGenerator',
    'Celadon', 'Cobalt', 'Oatmeal', 'CustomGlaze', 'CustomSwatch', 'CustomColorPanel', 'CustomColorWheel',
    'CustomOpacity', 'CustomOpacityLabel', 'CustomColorHex', 'CustomColorPreview',
    'Thickness', 'Temperature', 'OptionsTabs', 'AdditionalTabs', 'Atmosphere', 'AtmosphereNotes',
    'Cone', 'Ramp', 'Soak', 'Schedule', 'CoolingRate', 'CoolingProfile', 'Clay',
    'ClayColor', 'ThicknessMap', 'Geometry', 'LocateBlender', 'BlenderPath',
    'Render', 'ExportSetup', 'Preview', 'EmptyPreview', 'PreviewLabel', 'Status', 'SavePreview',
    'Orient', 'OrientationEditor', 'OrientationModel', 'RotateSurface', 'Turn', 'Tilt', 'Roll',
    'ResetOrientation', 'BakePhotoTexture', 'DraftPhotoMesh', 'ChatKeyToggle', 'ChatKeyPanel',
    'ChatApiKey', 'ChatSaveKey', 'ChatScroll', 'ChatMessages', 'ChatThinking', 'ChatInput', 'ChatSend',
    'FeaModelPath', 'FeaBrowseModel', 'FeaUseCurrentModel', 'FeaOutput', 'FeaSetup', 'FeaRun',
    'FeaOpenOutput', 'FeaOpenStress', 'FeaResult', 'FeaGeometryMode', 'FeaModelScale', 'FeaUpAxis',
    'FeaWallThickness', 'FeaVoxelSize', 'FeaPreparedVoxelSize', 'FeaMaxVoxels',
    'FeaYoungModulus', 'FeaPoissonRatio', 'FeaDensity', 'FeaGravity', 'FeaFixedDepth',
    'FeaTopDepth', 'FeaForceX', 'FeaForceY', 'FeaForceZ', 'FeaLogRange',
    'CombinedTop', 'CombinedBase', 'CombinedCone', 'CombinedRun', 'CombinedLoad', 'CombinedSetup',
    'CombinedSample', 'CombinedStatus', 'CombinedResult', 'CombinedSwatch', 'CombinedColor', 'CombinedMatch', 'CombinedApply',
    'CombinedApiAccess', 'CombinedApiToken'
)) {
    $ui[$name] = $window.FindName($name)
}

$script:customColor = '#C84B32'
$script:customPreviewPending = $false
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
    $ui.CustomColorHex.Text = $script:customColor
    $color = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($script:customColor)
    $ui.CustomSwatch.Fill = [Windows.Media.SolidColorBrush]::new($color)
    $ui.CustomColorPreview.Background = $ui.CustomSwatch.Fill
    $ui.CustomColorPreview.Opacity = $ui.CustomOpacity.Value
    $ui.CustomOpacityLabel.Text = ('{0:P0} opacity' -f $ui.CustomOpacity.Value)
    Request-CustomPreview
}
function Set-CustomColorFromHex([string]$hex) {
    $script:customColor = $hex.ToUpperInvariant()
    if ($ui.CustomGlaze.IsChecked) { Update-CustomColor }
    else { $ui.CustomGlaze.IsChecked = $true }
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
            else {
                double offset = 1.0 - chroma;
                pixels[i] = (byte)Math.Round((b + offset) * 255);
                pixels[i + 1] = (byte)Math.Round((g + offset) * 255);
                pixels[i + 2] = (byte)Math.Round((r + offset) * 255);
            }
            pixels[i + 3] = 255;
        }
        var bitmap = new WriteableBitmap(size, size, 96, 96, PixelFormats.Bgra32, null);
        bitmap.WritePixels(new Int32Rect(0, 0, size, size), pixels, size * 4, 0);
        return bitmap;
    }
}
'@
}
$ui.CustomColorWheel.Source = [NovaColorWheel]::Create(174)
$pickWheelColor = {
    param($sender, $eventArgs)
    if ($eventArgs.LeftButton -ne 'Pressed') { return }
    $point = $eventArgs.GetPosition($sender)
    $dx = $point.X - $sender.ActualWidth / 2
    $dy = $sender.ActualHeight / 2 - $point.Y
    $radius = [math]::Sqrt($dx*$dx + $dy*$dy)
    if ($radius -le $sender.ActualWidth / 2) {
        $hue = ([math]::Atan2($dy, $dx) * 180 / [math]::PI + 360) % 360
        $saturation = [math]::Min(1, $radius / ($sender.ActualWidth / 2))
        $hex = Get-HsvRgb $hue $saturation 1
        if ($hex -ne $script:customColor) { Set-CustomColorFromHex $hex }
    }
}
$ui.CustomColorWheel.Add_MouseLeftButtonDown($pickWheelColor)
$ui.CustomColorWheel.Add_MouseMove($pickWheelColor)
$ui.CustomOpacity.Add_ValueChanged({ Update-CustomColor })
foreach ($presetName in @('Celadon', 'Cobalt', 'Oatmeal')) {
    $ui[$presetName].Add_Checked({
        $ui.CustomColorPanel.Visibility = [Windows.Visibility]::Collapsed
        $script:customPreviewPending = $false
        Update-LiveGlaze
    })
}
$ui.CustomGlaze.Add_Checked({
    $ui.CustomColorPanel.Visibility = [Windows.Visibility]::Visible
    Update-CustomColor
})

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
            $ui.OptionsTabs.SelectedIndex = 2
            $ui.AdditionalTabs.SelectedIndex = 0
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
        $ui.OptionsTabs.SelectedIndex = 2
        $ui.AdditionalTabs.SelectedIndex = 0
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
        custom_glaze_opacity = if ($glaze.Tag -eq 'CUSTOM') { $ui.CustomOpacity.Value } else { $null }
        appearance_source = $appearanceSource
        inputs = [ordered]@{
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

function Add-ChatMessage([string]$message, [bool]$fromUser = $false) {
    if (!$message.Trim()) { return }
    $text = [Windows.Controls.TextBlock]::new()
    $text.Text = $message
    $text.TextWrapping = [Windows.TextWrapping]::Wrap
    $text.FontSize = 12
    $bubble = [Windows.Controls.Border]::new()
    $bubble.CornerRadius = [Windows.CornerRadius]::new(8)
    $bubble.Padding = [Windows.Thickness]::new(9)
    $bubble.Margin = [Windows.Thickness]::new(0, 0, 0, 7)
    $bubble.HorizontalAlignment = if ($fromUser) { [Windows.HorizontalAlignment]::Right } else { [Windows.HorizontalAlignment]::Left }
    $bubble.Background = if ($fromUser) { [Windows.Media.SolidColorBrush]::new([Windows.Media.Color]::FromRgb(225, 233, 225)) } else { [Windows.Media.Brushes]::White }
    $bubble.Child = $text
    [void]$ui.ChatMessages.Children.Add($bubble)
    $ui.ChatScroll.ScrollToEnd()
}

function Get-ChatApiKey {
    if ($env:NOVA_OPENROUTER_API_KEY) { return $env:NOVA_OPENROUTER_API_KEY }
    if (!(Test-Path -LiteralPath $script:chatKeyPath -PathType Leaf)) { return $null }
    try {
        $encrypted = [Convert]::FromBase64String([IO.File]::ReadAllText($script:chatKeyPath))
        $plain = [Security.Cryptography.ProtectedData]::Unprotect(
            $encrypted, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [Text.Encoding]::UTF8.GetString($plain)
    } catch {
        throw 'NOVA could not unlock its saved API key for this Windows account. Enter and save the key again.'
    }
}

function Save-ChatApiKey {
    $apiKey = $ui.ChatApiKey.Password.Trim()
    if (!$apiKey) { throw 'Paste your OpenRouter API key first.' }
    $protected = [Security.Cryptography.ProtectedData]::Protect(
        [Text.Encoding]::UTF8.GetBytes($apiKey), $null, [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $script:chatKeyPath))
    [IO.File]::WriteAllText($script:chatKeyPath, [Convert]::ToBase64String($protected))
    $ui.ChatApiKey.Clear()
    $ui.ChatKeyPanel.Visibility = [Windows.Visibility]::Collapsed
    Add-ChatMessage 'API key saved encrypted for this Windows account. You can ask me to change a glaze, model, or firing field, or ask a pottery question.'
}

function Apply-AssistantChanges($changes) {
    $changed = [Collections.Generic.List[string]]::new()
    if ($changes.model_id -and $changes.model_id -in @('BOWL', 'VASE', 'CUP')) {
        $index = @{ BOWL = 0; VASE = 1; CUP = 2 }[[string]$changes.model_id]
        if ($ui.Model.SelectedIndex -ne $index) { $ui.Model.SelectedIndex = $index; $changed.Add('model') }
    }
    if ($changes.glaze_id -and $changes.glaze_id -in @('CELADON', 'COBALT', 'OATMEAL', 'CUSTOM')) {
        $radio = @{ CELADON = $ui.Celadon; COBALT = $ui.Cobalt; OATMEAL = $ui.Oatmeal; CUSTOM = $ui.CustomGlaze }[[string]$changes.glaze_id]
        if (!$radio.IsChecked) { $radio.IsChecked = $true; $changed.Add('glaze') }
    }
    if ($changes.custom_color_srgb -and $changes.custom_color_srgb -match '^#[0-9a-fA-F]{6}$') {
        $before = $ui.CustomColorHex.Text
        Set-CustomColorFromHex $changes.custom_color_srgb
        if ($before -ne $ui.CustomColorHex.Text) { $changed.Add('custom color') }
    }

    $textFields = @{
        atmosphere_notes = $ui.AtmosphereNotes
        cone = $ui.Cone
        firing_schedule = $ui.Schedule
        cooling_profile = $ui.CoolingProfile
        clay_body = $ui.Clay
        fired_clay_color_srgb = $ui.ClayColor
        thickness_map_path = $ui.ThicknessMap
        firing_geometry_notes = $ui.Geometry
    }
    foreach ($field in $textFields.Keys) {
        $value = $changes.$field
        if ($null -ne $value -and $textFields[$field].Text -ne [string]$value) {
            $textFields[$field].Text = [string]$value
            $changed.Add($field.Replace('_', ' '))
        }
    }
    $numberFields = @{
        nominal_thickness_mm = @{ Control = $ui.Thickness; Max = 100; AllowZero = $false }
        peak_temperature_C = @{ Control = $ui.Temperature; Max = 2500; AllowZero = $false }
        heat_up_rate_C_per_hour = @{ Control = $ui.Ramp; Max = 5000; AllowZero = $false }
        peak_soak_minutes = @{ Control = $ui.Soak; Max = 100000; AllowZero = $true }
        cooling_rate_C_per_hour = @{ Control = $ui.CoolingRate; Max = 5000; AllowZero = $false }
    }
    foreach ($field in $numberFields.Keys) {
        $value = $changes.$field
        if ($null -eq $value) { continue }
        $rule = $numberFields[$field]
        $number = [double]$value
        if ([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt 0 -or $number -gt $rule.Max -or (!$rule.AllowZero -and $number -eq 0)) { continue }
        $formatted = $number.ToString([Globalization.CultureInfo]::InvariantCulture)
        if ($rule.Control.Text -ne $formatted) { $rule.Control.Text = $formatted; $changed.Add($field.Replace('_', ' ')) }
    }
    if ($changes.atmosphere -eq 'unspecified') {
        if ($ui.Atmosphere.SelectedIndex -ne 0) { $ui.Atmosphere.SelectedIndex = 0; $changed.Add('kiln atmosphere') }
    } elseif ($changes.atmosphere -and $changes.atmosphere -in @('oxidation', 'neutral', 'reduction')) {
        for ($i = 1; $i -lt $ui.Atmosphere.Items.Count; $i++) {
            if ($ui.Atmosphere.Items[$i].Tag -eq $changes.atmosphere -and $ui.Atmosphere.SelectedIndex -ne $i) {
                $ui.Atmosphere.SelectedIndex = $i; $changed.Add('kiln atmosphere'); break
            }
        }
    }
    foreach ($field in $changes.clear_fields) {
        if ($textFields.ContainsKey([string]$field) -and $textFields[[string]$field].Text) {
            $textFields[[string]$field].Clear(); $changed.Add(([string]$field).Replace('_', ' '))
        } elseif ($numberFields.ContainsKey([string]$field) -and $numberFields[[string]$field].Control.Text) {
            $numberFields[[string]$field].Control.Clear(); $changed.Add(([string]$field).Replace('_', ' '))
        }
    }
    if ($changed.Count) {
        Set-Status ("Assistant changed: " + (($changed | Select-Object -Unique) -join ', ') + '. Click Render Preview to see the update.')
    }
    return ,@($changed | Select-Object -Unique)
}

function Start-ChatRequest([string]$prompt) {
    if ($script:job) { return }
    $apiKey = Get-ChatApiKey
    if (!$apiKey) {
        $ui.ChatKeyPanel.Visibility = [Windows.Visibility]::Visible
        Add-ChatMessage 'Add your OpenRouter API key with the API key button, then send your message again.'
        return
    }
    $current = [ordered]@{
        model = if ($script:glbPath) { 'Imported GLB' } else { [string]$ui.Model.SelectedItem.Tag }
        glaze = if ($ui.CustomGlaze.IsChecked) { "CUSTOM $($ui.CustomColorHex.Text)" } elseif ($ui.Cobalt.IsChecked) { 'COBALT' } elseif ($ui.Oatmeal.IsChecked) { 'OATMEAL' } else { 'CELADON' }
        custom_glaze_opacity = if ($ui.CustomGlaze.IsChecked) { $ui.CustomOpacity.Value } else { $null }
        thickness_mm = $ui.Thickness.Text
        peak_temperature_C = $ui.Temperature.Text
        atmosphere = $ui.Atmosphere.SelectedItem.Content
        atmosphere_notes = $ui.AtmosphereNotes.Text
        cone = $ui.Cone.Text
        heat_up_rate_C_per_hour = $ui.Ramp.Text
        peak_soak_minutes = $ui.Soak.Text
        firing_schedule = $ui.Schedule.Text
        cooling_rate_C_per_hour = $ui.CoolingRate.Text
        cooling_profile = $ui.CoolingProfile.Text
        clay_body = $ui.Clay.Text
        fired_clay_color_srgb = $ui.ClayColor.Text
        firing_geometry_notes = $ui.Geometry.Text
    } | ConvertTo-Json -Compress -Depth 5
    $system = @'
You are NOVA's pottery studio assistant. Answer questions about using NOVA, pottery glaze appearance, and firing setup. You may suggest settings, but do not claim a firing schedule is universally safe or guaranteed; encourage test tiles and a kiln manufacturer's instructions when appropriate. Only populate changes when the user asks to change a setting or clearly requests a design that implies a change. Never change settings for a general question. Leave every unchanged field null. Use clear_fields only when the user asks to clear a field. Keep replies concise, explain what changed, and mention that Render Preview is needed to view the new glaze or model.
Supported models: BOWL, VASE, CUP. Supported glaze choices: CELADON, COBALT, OATMEAL, CUSTOM. Custom color uses #RRGGBB. Atmospheres are oxidation, neutral, or reduction. Numeric values must be plausible; thickness is millimeters, temperatures Celsius, heating and cooling rates Celsius per hour, and soak is minutes. Do not invent a model name or a glaze preset. Respond to the latest user message with current settings for context.
'@
    $history = @($script:chatHistory | Select-Object -Last 10)
    $messages = @(@{ role = 'system'; content = $system }) + $history + @(@{ role = 'user'; content = "Current NOVA settings: $current`n`nUser: $prompt" })
    $requestPath = Join-Path $scratch ([guid]::NewGuid().ToString('N') + '-chat-request.json')
    $outputPath = Join-Path $scratch ([guid]::NewGuid().ToString('N') + '-chat-response.json')
    [IO.File]::WriteAllText($requestPath, (@{ messages = $messages } | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))

    $helper = Join-Path $PSScriptRoot 'chat_assistant.ps1'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" "{1}" "{2}"' -f $helper, $requestPath, $outputPath
    $launch = New-Object Diagnostics.ProcessStartInfo -Property @{
        FileName = Join-Path $PSHOME 'powershell.exe'
        Arguments = $arguments
        UseShellExecute = $false
        CreateNoWindow = $true
        RedirectStandardOutput = $true
        RedirectStandardError = $true
    }
    $launch.EnvironmentVariables['NOVA_OPENROUTER_API_KEY'] = $apiKey
    $apiKey = $null
    $process = [Diagnostics.Process]::Start($launch)
    $script:job = @{
        Kind = 'Chat'; Tool = 'NOVA assistant'; Output = $outputPath; Request = $requestPath
        Prompt = $prompt; Process = $process; Stdout = $process.StandardOutput.ReadToEndAsync(); Stderr = $process.StandardError.ReadToEndAsync()
    }
    $ui.ChatSend.IsEnabled = $false
    $ui.ChatInput.IsEnabled = $false
    $ui.ImportModel.IsEnabled = $false
    $ui.FeaRun.IsEnabled = $false
    $ui.FeaSetup.IsEnabled = $false
    Set-CombinedActionsEnabled $false
    $ui.ChatThinking.Visibility = 'Visible'
    $ui.ChatScroll.ScrollToEnd()
    $timer.Start()
}

function Set-FeaModel([string]$path) {
    if (!(Test-Path -LiteralPath $path -PathType Leaf) -or [IO.Path]::GetExtension($path) -ne '.glb') {
        throw 'Select an existing GLB file for finite element analysis.'
    }
    $script:feaModelPath = [IO.Path]::GetFullPath($path)
    $ui.FeaModelPath.Text = $script:feaModelPath
}

function Write-FeaSettings([string]$path) {
    $values = [ordered]@{
        geometry_mode = [string]$ui.FeaGeometryMode.SelectedItem.Tag
        model_scale = $ui.FeaModelScale.Text.Trim()
        up_axis = [string]$ui.FeaUpAxis.SelectedItem.Tag
        wall_thickness_m = $ui.FeaWallThickness.Text.Trim()
        voxel_size_m = $ui.FeaVoxelSize.Text.Trim()
        prepared_voxel_size_m = $ui.FeaPreparedVoxelSize.Text.Trim()
        max_voxels = $ui.FeaMaxVoxels.Text.Trim()
        young_modulus_pa = $ui.FeaYoungModulus.Text.Trim()
        poisson_ratio = $ui.FeaPoissonRatio.Text.Trim()
        density_kg_m3 = $ui.FeaDensity.Text.Trim()
        gravity_m_s2 = $ui.FeaGravity.Text.Trim()
        fixed_base_depth_m = $ui.FeaFixedDepth.Text.Trim()
        top_load_depth_m = $ui.FeaTopDepth.Text.Trim()
        force_x_n = $ui.FeaForceX.Text.Trim()
        force_y_n = $ui.FeaForceY.Text.Trim()
        force_z_n = $ui.FeaForceZ.Text.Trim()
        log_range_decades = $ui.FeaLogRange.Text.Trim()
    }
    $lines = foreach ($key in $values.Keys) { "$key = $($values[$key])" }
    [IO.File]::WriteAllLines($path, [string[]]$lines, [Text.UTF8Encoding]::new($false))
}

function Test-FeaRuntime {
    $script:feaPython = Join-Path $PSScriptRoot '.fea-runtime/Scripts/python.exe'
    return (Test-Path -LiteralPath $script:feaPython -PathType Leaf)
}

function Start-FeaSetup {
    if ($script:job) { return }
    try {
        $setupScript = Join-Path $PSScriptRoot 'setup_fea.ps1'
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $setupScript
        Start-StudioJob (Join-Path $PSHOME 'powershell.exe') $arguments @{
            Kind = 'FEASetup'; Tool = 'FEA setup'
        } 'Setting up the local FEA engine. This downloads its Python dependencies once...'
    } catch {
        Set-Status $_.Exception.Message
        $ui.FeaResult.Text = $_.Exception.Message
    }
}

function Start-FeaAnalysis {
    if ($script:job) { return }
    try {
        if (!(Test-FeaRuntime)) {
            $ui.FeaResult.Text = 'Set up the FEA engine before running an analysis.'
            throw 'Click Set Up FEA Engine on the FEA tab first.'
        }
        if (!$script:feaModelPath -or !(Test-Path -LiteralPath $script:feaModelPath -PathType Leaf)) {
            throw 'Choose a vase GLB, or click Use imported Studio GLB on the FEA tab.'
        }
        $output = $ui.FeaOutput.Text.Trim()
        if (!$output) { $output = Join-Path $PSScriptRoot ('outputs/fea-run-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
        if (![IO.Path]::IsPathRooted($output)) { $output = Join-Path $PSScriptRoot $output }
        $output = [IO.Path]::GetFullPath($output)
        $ui.FeaOutput.Text = $output

        $settingsPath = Join-Path $scratch ([guid]::NewGuid().ToString('N') + '-fea-settings.txt')
        Write-FeaSettings $settingsPath
        $arguments = '-m vase_stress.cli run --model "{0}" --settings "{1}" --output "{2}"' -f $script:feaModelPath, $settingsPath, $output
        $ui.FeaOpenOutput.IsEnabled = $false
        $ui.FeaOpenStress.IsEnabled = $false
        $ui.FeaResult.Text = 'Analysis running. Large or fine meshes can take several minutes.'
        Start-StudioJob $script:feaPython $arguments @{
            Kind = 'FEA'; Tool = 'FEA engine'; Output = Join-Path $output 'summary.json'; OutputFolder = $output
        } 'Running finite element analysis. This may take several minutes...'
    } catch {
        Set-Status $_.Exception.Message
        $ui.FeaResult.Text = $_.Exception.Message
    }
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

function Update-LiveGlaze {
    $model = $ui.OrientationModel.Content
    if (!$model) { return }
    $hex = if ($ui.CustomGlaze.IsChecked) { $script:customColor }
        elseif ($ui.Cobalt.IsChecked) { '#365A88' }
        elseif ($ui.Oatmeal.IsChecked) { '#C6A67C' }
        else { '#729882' }
    $color = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($hex)
    if ($ui.CustomGlaze.IsChecked) {
        $clay = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString('#C6A58A')
        $opacity = $ui.CustomOpacity.Value
        if ($opacity -eq 0) { $color = $clay }
        elseif ($opacity -lt 1) {
            $color = [Windows.Media.Color]::FromScRgb(1,
                ($clay.ScR + ($color.ScR - $clay.ScR) * $opacity),
                ($clay.ScG + ($color.ScG - $clay.ScG) * $opacity),
                ($clay.ScB + ($color.ScB - $clay.ScB) * $opacity))
        }
    }
    $model.Material.Brush = [Windows.Media.SolidColorBrush]::new($color)
}

function Request-CustomPreview {
    Update-LiveGlaze
    if (!$ui.CustomGlaze.IsChecked) { return }
    if ($script:job) {
        if ($script:job.Kind -ne 'Orientation') { $script:customPreviewPending = $true }
        return
    }
    Start-OrientationEditor -KeepOpen
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
    Update-LiveGlaze
    Show-OrientationEditor $true
}

function Get-BlenderArguments([string]$request, [string]$output) {
    return '--background --factory-startup --disable-autoexec --python-exit-code 1 --python "{0}" -- "{1}" "{2}"' -f $worker, $request, $output
}

function Start-OrientationEditor([switch]$KeepOpen) {
    if ($script:job) { return }
    if ($ui.OrientationEditor.Visibility -eq 'Visible') {
        if (!$KeepOpen) { Show-OrientationEditor $false }
        return
    }
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

function Start-StudioJob([string]$program, [string]$arguments, [hashtable]$job, [string]$message, [hashtable]$environment = @{}) {
    $launch = New-Object Diagnostics.ProcessStartInfo -Property @{
        FileName = $program
        Arguments = $arguments
        UseShellExecute = $false
        CreateNoWindow = $true
        RedirectStandardOutput = $true
        RedirectStandardError = $true
    }
    foreach ($name in $environment.Keys) { $launch.EnvironmentVariables[$name] = $environment[$name] }
    $job.Process = [Diagnostics.Process]::Start($launch)
    $job.Stdout = $job.Process.StandardOutput.ReadToEndAsync()
    $job.Stderr = $job.Process.StandardError.ReadToEndAsync()
    $script:job = $job
    $ui.Render.IsEnabled = $false
    $ui.ImportModel.IsEnabled = $false
    $ui.SetupPhotoGenerator.IsEnabled = $false
    $ui.Orient.IsEnabled = $false
    $ui.ChatSend.IsEnabled = $false
    $ui.ChatInput.IsEnabled = $false
    $ui.FeaRun.IsEnabled = $false
    $ui.FeaSetup.IsEnabled = $false
    Set-CombinedActionsEnabled $false
    if ($job.Kind -in @('Photo', 'Orientation')) {
        $ui.Model.IsEnabled = $false
    }
    Set-Status $message
    $timer.Start()
}

function Start-Preview {
    if ($script:job) { return }
    try {
        if (!$script:blender -or !(Test-Path -LiteralPath $script:blender -PathType Leaf)) {
            $ui.OptionsTabs.SelectedIndex = 2
            $ui.AdditionalTabs.SelectedIndex = 0
            $ui.LocateBlender.BringIntoView()
            throw 'Install Blender 5.2 or newer, then use Locate Blender under the Additional Options tab.'
        }

        $setup = Get-Setup
        $modelName = if ($script:glbPath) { [IO.Path]::GetFileNameWithoutExtension($script:glbPath) } else { $ui.Model.SelectedItem.Content }
        $glazeName = switch ($setup.glaze_id) {
            'CELADON' { 'Jade Celadon' }
            'COBALT' { 'Cobalt Blue' }
            'OATMEAL' { 'Speckled Oatmeal' }
            'CUSTOM' { "Custom $($setup.custom_color_srgb) / $($setup.custom_glaze_opacity.ToString('P0')) opacity" }
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

function Start-PhotoGeneration([string]$photoPath) {
    if ($script:job) { return }
    try {
        if (!(Test-PhotoGenerator)) {
            $ui.OptionsTabs.SelectedIndex = 2
            $ui.AdditionalTabs.SelectedIndex = 0
            $ui.SetupPhotoGenerator.BringIntoView()
            throw 'Open the Additional Options tab and click Set Up Photo Generator first.'
        }

        $output = New-Object Microsoft.Win32.SaveFileDialog -Property @{
            Filter = 'glTF binary (*.glb)|*.glb'; DefaultExt = '.glb'
            FileName = [IO.Path]::GetFileNameWithoutExtension($photoPath) + '.glb'
        }
        if (!$output.ShowDialog($window)) { return }
        if ([IO.Path]::GetExtension($output.FileName) -ne '.glb') { throw 'Choose a .glb output filename.' }

        $staged = Join-Path $scratch ([guid]::NewGuid().ToString('N') + '.glb')
        $arguments = '-B "{0}" "{1}" "{2}"' -f $generatorScript, $photoPath, $staged
        if (!$ui.BakePhotoTexture.IsChecked) { $arguments += ' --geometry-only' }
        if ($ui.DraftPhotoMesh.IsChecked) { $arguments += ' --mesh-resolution 96' }
        Start-StudioJob $generatorPython $arguments @{
            Kind = 'Photo'; Tool = 'Photo generator'; Output = $staged; Destination = $output.FileName
        } 'Generating a GLB from the photo. This can take several minutes...'
    } catch {
        Set-Status $_.Exception.Message
    }
}

function Import-ModelFile([string]$path) {
    switch ([IO.Path]::GetExtension($path)) {
        '.glb' { Set-GlbModel $path }
        { $_ -in @('.png', '.jpg', '.jpeg') } { Start-PhotoGeneration $path }
        default { Set-Status 'Choose a GLB, PNG, or JPEG file.' }
    }
}

$script:blender = Find-Blender
$script:glbPath = $null
$script:feaModelPath = $null
$ui.FeaModelPath.Text = 'No FEA model selected'
$ui.FeaOutput.Text = ''
$script:job = $null
$script:lastImage = $null
$script:chatHistory = @()
$script:chatKeyPath = Join-Path $env:LOCALAPPDATA 'NOVA/openrouter-key.dpapi'
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
    if (!$job -or !$job.Process.HasExited) { return }
    $timer.Stop()
    try {
        if ($job.Kind -eq 'Chat') {
            if ($job.Process.ExitCode -ne 0 -or !(Test-Path -LiteralPath $job.Output -PathType Leaf)) {
                $detail = ($job.Stderr.Result -split '\r?\n') | Where-Object { $_.Trim() } | Select-Object -Last 1
                if (!$detail) { $detail = 'The OpenRouter request did not complete.' }
                throw $detail
            }
            $reply = Get-Content -LiteralPath $job.Output -Raw -Encoding UTF8 | ConvertFrom-Json
            $ui.ChatThinking.Visibility = 'Collapsed'
            $changed = Apply-AssistantChanges $reply.changes
            $script:chatHistory += @(
                @{ role = 'user'; content = $job.Prompt },
                @{ role = 'assistant'; content = [string]$reply.reply }
            )
            if ($script:chatHistory.Count -gt 16) { $script:chatHistory = @($script:chatHistory | Select-Object -Last 16) }
            Add-ChatMessage ([string]$reply.reply)
            if ($changed.Count) { Set-Status 'Assistant settings applied. Click Render Preview to see them.' }
            return
        }
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
            Set-Status 'Photo generator ready. Use the import icon to choose a photo.'
            return
        }
        if ($job.Kind -eq 'FEASetup') {
            if (!(Test-FeaRuntime)) { throw 'The FEA setup did not create its Python environment.' }
            $ui.FeaResult.Text = 'FEA engine ready. Choose a GLB and review the FEA settings before running.'
            Set-Status 'FEA engine ready'
            return
        }
        if ($job.Kind -eq 'CombinedSetup') {
            Update-CombinedCatalog
            $ui.CombinedStatus.Text = 'Combined predictor ready. Choose glazes or run the bundled sample.'
            Set-Status 'Combined predictor ready'
            return
        }
        if ($job.Kind -eq 'CombinedPrediction') {
            Complete-CombinedPrediction $job.Output
            Set-Status 'Combined glaze prediction ready'
            return
        }
        if ($job.Kind -eq 'FEA') {
            $summary = Get-Content -LiteralPath $job.Output -Raw -Encoding UTF8 | ConvertFrom-Json
            $stress = ([double]$summary.max_von_mises_pa).ToString('0.###E+0', [Globalization.CultureInfo]::InvariantCulture)
            $displacement = ([double]$summary.max_displacement_m).ToString('0.###E+0', [Globalization.CultureInfo]::InvariantCulture)
            $ui.FeaResult.Text = "Complete. Max von Mises stress: $stress Pa. Max displacement: $displacement m. Results: $($job.OutputFolder)"
            $ui.FeaOpenOutput.IsEnabled = $true
            $ui.FeaOpenStress.IsEnabled = $true
            Set-Status 'FEA analysis complete'
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
        if ($job.Kind -eq 'Chat') {
            Add-ChatMessage "I couldn't get a reply. Check your API key and connection, then try again."
        } else {
            Set-Status $_.Exception.Message
            if ($job.Kind -in @('FEA', 'FEASetup')) { $ui.FeaResult.Text = $_.Exception.Message }
            if ($job.Kind -in @('CombinedPrediction', 'CombinedSetup')) { $ui.CombinedStatus.Text = $_.Exception.Message }
            if ($job.Kind -eq 'CombinedPrediction' -and $_.Exception.Message -like '*API denied access*') {
                $ui.CombinedApiAccess.IsExpanded = $true
            }
        }
    } finally {
        $job.Process.Dispose()
        $script:job = $null
        $ui.Render.IsEnabled = $true
        $ui.ImportModel.IsEnabled = $true
        $ui.SetupPhotoGenerator.IsEnabled = $true
        $ui.Orient.IsEnabled = $true
        $ui.Model.IsEnabled = $true
        $ui.ChatSend.IsEnabled = $true
        $ui.ChatInput.IsEnabled = $true
        $ui.FeaRun.IsEnabled = $true
        $ui.FeaSetup.IsEnabled = $true
        Set-CombinedActionsEnabled $true
        $ui.ChatThinking.Visibility = 'Collapsed'
        if ($script:customPreviewPending) {
            $script:customPreviewPending = $false
            Request-CustomPreview
        }
    }
})

$ui.ChatKeyToggle.Add_Click({
    $ui.ChatKeyPanel.Visibility = if ($ui.ChatKeyPanel.Visibility -eq [Windows.Visibility]::Visible) {
        [Windows.Visibility]::Collapsed
    } else { [Windows.Visibility]::Visible }
})
$ui.ChatSaveKey.Add_Click({
    try { Save-ChatApiKey; Set-Status 'OpenRouter key saved securely for this Windows account.' }
    catch { Add-ChatMessage "I couldn't save your API key. Enter it again and retry." }
})
$ui.ChatSend.Add_Click({
    if ($script:job) { return }
    $prompt = $ui.ChatInput.Text.Trim()
    if (!$prompt) { return }
    $ui.ChatInput.Clear()
    Add-ChatMessage $prompt $true
    try { Start-ChatRequest $prompt }
    catch { Add-ChatMessage "I couldn't start the chat. Check your API key and try again." }
})
$ui.ChatInput.Add_PreviewKeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.Key -eq [Windows.Input.Key]::Enter -and [Windows.Input.Keyboard]::Modifiers.HasFlag([Windows.Input.ModifierKeys]::Control)) {
        $eventArgs.Handled = $true
        $ui.ChatSend.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    }
})
$ui.FeaBrowseModel.Add_Click({
    $dialog = New-Object Microsoft.Win32.OpenFileDialog -Property @{ Filter = 'glTF binary (*.glb)|*.glb' }
    if ($dialog.ShowDialog($window)) {
        try { Set-FeaModel $dialog.FileName; $ui.FeaResult.Text = 'GLB selected. Review FEA settings, then run the analysis.' }
        catch { Set-Status $_.Exception.Message; $ui.FeaResult.Text = $_.Exception.Message }
    }
})
$ui.FeaUseCurrentModel.Add_Click({
    if ($script:glbPath) {
        try { Set-FeaModel $script:glbPath; $ui.FeaResult.Text = 'Using the imported Studio GLB for analysis.' }
        catch { Set-Status $_.Exception.Message; $ui.FeaResult.Text = $_.Exception.Message }
    } else {
        Set-Status 'Import a GLB in Studio first, or browse for an FEA GLB.'
        $ui.FeaResult.Text = 'No imported Studio GLB is selected.'
    }
})
$ui.FeaSetup.Add_Click({ Start-FeaSetup })
$ui.FeaRun.Add_Click({ Start-FeaAnalysis })
$ui.FeaOpenOutput.Add_Click({
    $output = $ui.FeaOutput.Text.Trim()
    if ($output -and (Test-Path -LiteralPath $output -PathType Container)) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$output`""
    } else {
        Set-Status 'The FEA results folder no longer exists.'
    }
})
$ui.FeaOpenStress.Add_Click({
    $stressGlb = Join-Path $ui.FeaOutput.Text 'stress.glb'
    if (Test-Path -LiteralPath $stressGlb -PathType Leaf) {
        Start-Process -FilePath $stressGlb
    } else {
        Set-Status 'The stress GLB is not available in the selected results folder.'
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
$ui.ImportModel.Add_Click({
    if ($script:job) { return }
    $dialog = New-Object Microsoft.Win32.OpenFileDialog -Property @{
        Title = 'Import a GLB or a photo'
        Filter = 'GLB and photos (*.glb;*.png;*.jpg;*.jpeg)|*.glb;*.png;*.jpg;*.jpeg|GLB (*.glb)|*.glb|Photos (*.png;*.jpg;*.jpeg)|*.png;*.jpg;*.jpeg'
    }
    if ($dialog.ShowDialog($window)) { Import-ModelFile $dialog.FileName }
})
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

. (Join-Path $PSScriptRoot 'combined_glaze/studio.ps1')
Update-CombinedCatalog
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
