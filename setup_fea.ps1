$ErrorActionPreference = 'Stop'

$python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (!$python) { throw 'Install Python 3.11 or newer and make python available on PATH, then set up the FEA engine again.' }

$environment = Join-Path $PSScriptRoot '.fea-runtime'
if (!(Test-Path -LiteralPath (Join-Path $environment 'Scripts/python.exe') -PathType Leaf)) {
    & $python.Source -m venv $environment
    if ($LASTEXITCODE -ne 0) { throw 'Python could not create the FEA environment.' }
}
$environmentPython = Join-Path $environment 'Scripts/python.exe'
& $environmentPython -m pip install --disable-pip-version-check -e $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw 'FEA dependency installation failed.' }
& $environmentPython -m vase_stress.cli --help | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'The FEA package did not initialize correctly.' }
Write-Output 'FEA engine ready.'
