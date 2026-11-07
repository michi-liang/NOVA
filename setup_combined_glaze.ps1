param(
    [Parameter(Mandatory = $true)][string]$BundlePath,
    [string]$PythonPath
)

$ErrorActionPreference = 'Stop'
$bundle = (Resolve-Path -LiteralPath $BundlePath).Path
$runtime = Join-Path $PSScriptRoot '.combined-glaze'
$modelPath = Join-Path $bundle 'model.json'
if (!(Test-Path -LiteralPath $modelPath -PathType Leaf)) {
    throw 'Select the Combined_Glaze_Predictor folder containing model.json and textures.'
}
$model = Get-Content -LiteralPath $modelPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (!$model.records) { throw 'The selected model.json contains no retrieval samples.' }
$images = foreach ($record in $model.records) {
    if ($record.image -notmatch '^sample_\d+\.jpg$') { throw 'The model references an invalid texture filename.' }
    $path = Join-Path $bundle ('textures/' + $record.image)
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "The bundle is missing $($record.image)." }
    $path
}

$environment = Join-Path $runtime 'env'
$python = Join-Path $environment 'Scripts/python.exe'
if (!(Test-Path -LiteralPath $python -PathType Leaf)) {
    if (!$PythonPath) {
        $command = Get-Command python.exe -All -CommandType Application -ErrorAction SilentlyContinue |
            Where-Object { $_.Source -notlike '*\Microsoft\WindowsApps\*' } | Select-Object -First 1
        $PythonPath = if ($command) { $command.Source } else { 'python.exe' }
    }
    & $PythonPath -m venv --without-pip $environment
    if ($LASTEXITCODE -ne 0) { throw 'Install Python 3.10 or newer on PATH, then retry setup.' }
}
$packages = Join-Path $environment 'Lib/site-packages'
if (!(Test-Path -LiteralPath (Join-Path $packages 'numpy')) -or !(Test-Path -LiteralPath (Join-Path $packages 'PIL'))) {
    if (!(Test-Path -LiteralPath (Join-Path $packages 'pip'))) {
        & $python -m ensurepip --upgrade
        if ($LASTEXITCODE -ne 0) { throw 'Could not install pip in the combined predictor environment.' }
    }
    & $python -m pip install --disable-pip-version-check 'numpy>=1.24,<3' 'Pillow>=10,<13'
    if ($LASTEXITCODE -ne 0) { throw 'Could not install NumPy and Pillow for the combined predictor.' }
}
& $python -c 'import numpy, PIL'
if ($LASTEXITCODE -ne 0) { throw 'The combined predictor could not load NumPy or Pillow.' }

$textures = Join-Path $runtime 'textures'
[void][IO.Directory]::CreateDirectory($textures)
foreach ($path in $images) { Copy-Item -LiteralPath $path -Destination $textures -Force }
$sample = Join-Path $bundle 'examples/sample_prediction.json'
if (Test-Path -LiteralPath $sample -PathType Leaf) {
    Copy-Item -LiteralPath $sample -Destination (Join-Path $runtime 'sample_prediction.json') -Force
}
Copy-Item -LiteralPath $modelPath -Destination (Join-Path $runtime 'model.json') -Force
Write-Output 'Combined predictor installed.'
