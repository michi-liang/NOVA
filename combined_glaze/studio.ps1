$combinedRuntime = Join-Path (Split-Path -Parent $PSScriptRoot) '.combined-glaze'
$combinedPython = Join-Path $combinedRuntime 'env/Scripts/python.exe'
$combinedWorker = Join-Path $PSScriptRoot 'predict.py'
$combinedSetup = Join-Path (Split-Path -Parent $PSScriptRoot) 'setup_combined_glaze.ps1'
$script:combinedColor = $null

function Set-CombinedActionsEnabled([bool]$enabled) {
    foreach ($name in @('CombinedRun', 'CombinedLoad', 'CombinedSetup', 'CombinedSample', 'CombinedApply')) {
        $ui[$name].IsEnabled = $enabled
    }
}

function Update-CombinedCatalog {
    $modelPath = Join-Path $combinedRuntime 'model.json'
    if (!(Test-Path -LiteralPath $modelPath -PathType Leaf)) { return }
    try {
        $model = Get-Content -LiteralPath $modelPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $ids = @(foreach ($record in $model.records) {
            foreach ($match in [regex]::Matches([string]$record.pair_label, '\b[A-Z]{1,5}-\d{2,4}\b')) { $match.Value }
        }) | Sort-Object -Unique
        foreach ($box in @($ui.CombinedTop, $ui.CombinedBase)) {
            $selected = $box.Text
            $box.ItemsSource = @($ids)
            $box.Text = $selected
        }
    } catch { $ui.CombinedStatus.Text = 'Could not read the glaze catalog. Run setup again.' }
}

function Start-CombinedPrediction($request) {
    if ($script:job) { return }
    try {
        if (!(Test-Path -LiteralPath $combinedPython -PathType Leaf) -or
            !(Test-Path -LiteralPath (Join-Path $combinedRuntime 'model.json') -PathType Leaf)) {
            throw 'Click Set Up Combined Predictor and select the supplied predictor folder first.'
        }
        $prefix = Join-Path $scratch ([guid]::NewGuid().ToString('N') + '-combined')
        Write-Setup $request "$prefix-request.json"
        $report = "$prefix.json"
        $arguments = '-B "{0}" "{1}" "{2}" "{3}"' -f $combinedWorker, $combinedRuntime, "$prefix-request.json", $report
        Start-StudioJob $combinedPython $arguments @{
            Kind = 'CombinedPrediction'; Tool = 'Combined predictor'; Output = $report
        } 'Generating a glaze color and retrieved swatch...'
        $ui.CombinedStatus.Text = 'Working on the prediction...'
    } catch { $ui.CombinedStatus.Text = $_.Exception.Message }
}

function Complete-CombinedPrediction([string]$reportPath) {
    $result = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $bitmap = [Windows.Media.Imaging.BitmapImage]::new()
    $bitmap.BeginInit()
    $bitmap.CacheOption = 'OnLoad'
    $bitmap.UriSource = [uri][IO.Path]::ChangeExtension($reportPath, '.png')
    $bitmap.EndInit()
    $ui.CombinedSwatch.Source = $bitmap
    $script:combinedColor = $result.base_color_srgb
    $ui.CombinedColor.Text = "Predicted base color $script:combinedColor"
    $ui.CombinedMatch.Text = "Closest of $($result.candidate_samples) photos: $($result.closest_sample)"
    $pair = $result.input_glazes
    $source = if ($result.source -eq 'api') { 'Live prediction' } else { 'Saved prediction' }
    $ui.CombinedStatus.Text = if ($pair.top -and $pair.base) {
        "$source / $($pair.top) over $($pair.base) / $($pair.cone)"
    } else { $source }
    $ui.CombinedResult.Visibility = 'Visible'
}

$ui.CombinedSetup.Add_Click({
    if ($script:job) { return }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = [Windows.Forms.FolderBrowserDialog]::new()
        try {
            $dialog.Description = 'Select the Combined_Glaze_Predictor folder containing model.json and textures.'
            $dialog.ShowNewFolderButton = $false
            if ($dialog.ShowDialog() -ne 'OK') { return }
            $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -BundlePath "{1}"' -f $combinedSetup, $dialog.SelectedPath.TrimEnd('\')
        } finally { $dialog.Dispose() }
        Start-StudioJob (Join-Path $PSHOME 'powershell.exe') $arguments @{
            Kind = 'CombinedSetup'; Tool = 'Combined predictor setup'
        } 'Installing the combined predictor...'
        $ui.CombinedStatus.Text = 'Installing local dependencies and importing the texture library...'
    } catch { $ui.CombinedStatus.Text = $_.Exception.Message }
})

$ui.CombinedRun.Add_Click({
    Start-CombinedPrediction @{
        top = $ui.CombinedTop.Text; base = $ui.CombinedBase.Text; cone = $ui.CombinedCone.Text
    }
})
$ui.CombinedSample.Add_Click({
    $path = Join-Path $combinedRuntime 'sample_prediction.json'
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
        $ui.CombinedStatus.Text = 'Install the bundle containing examples/sample_prediction.json first.'
        return
    }
    Start-CombinedPrediction @{ prediction_json = $path }
})
$ui.CombinedLoad.Add_Click({
    if ($script:job) { return }
    $dialog = New-Object Microsoft.Win32.OpenFileDialog -Property @{ Filter = 'Prediction JSON (*.json)|*.json' }
    if ($dialog.ShowDialog($window)) { Start-CombinedPrediction @{ prediction_json = $dialog.FileName } }
})
$ui.CombinedApply.Add_Click({
    if ($script:job -or !$script:combinedColor) { return }
    $ui.OptionsTabs.SelectedIndex = 0
    $ui.CustomOpacity.Value = 1
    Set-CustomColorFromHex $script:combinedColor
})
