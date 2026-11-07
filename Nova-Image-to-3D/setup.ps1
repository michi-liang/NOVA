$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$runtime = Join-Path $PSScriptRoot '.runtime'
$weights = Join-Path $runtime 'weights'
$temp = Join-Path $runtime 'temp'
New-Item -ItemType Directory -Force $weights, $temp | Out-Null
$env:TEMP = $temp
$env:TMP = $temp
if (!$env:UV_CACHE_DIR) { $env:UV_CACHE_DIR = Join-Path $runtime 'uv-cache' }
$env:UV_PYTHON_INSTALL_DIR = Join-Path $runtime 'python'

$uv = Join-Path $runtime 'uv/bin/uv.exe'
if (!(Test-Path -LiteralPath $uv)) {
    if (!(Get-Command python -ErrorAction SilentlyContinue)) {
        throw 'Install Python for Windows from python.org and enable Add Python to PATH, then rerun setup.'
    }
    & python -m pip --disable-pip-version-check install --no-cache-dir --target (Join-Path $runtime 'uv') 'uv==0.13.7'
    if ($LASTEXITCODE) { throw 'Could not install uv.' }
}

$venv = Join-Path $runtime 'env'
$python = Join-Path $venv 'Scripts/python.exe'
if (!(Test-Path -LiteralPath $python)) {
    $managedPython = Join-Path $env:UV_PYTHON_INSTALL_DIR 'cpython-3.11.18-windows-x86_64-none/python.exe'
    & $uv venv --python 3.11.18 $venv
    if ($LASTEXITCODE) {
        if (!(Test-Path -LiteralPath $managedPython)) { throw 'Could not download Python 3.11.' }
        & $uv venv --python $managedPython $venv
        if ($LASTEXITCODE) { throw 'Could not create the local Python environment.' }
    }
}
& $uv pip install --python $python -r requirements.txt
if ($LASTEXITCODE) { throw 'Could not install the Python dependencies.' }
& $uv pip install --python $python --index-url https://download.pytorch.org/whl/cu118 'torch==2.7.1+cu118'
if ($LASTEXITCODE) { throw 'Could not install PyTorch.' }

function Get-ModelFile($Name, $Url, $Sha256) {
    $target = Join-Path $weights $Name
    if ((Test-Path -LiteralPath $target) -and (Get-FileHash -LiteralPath $target).Hash -eq $Sha256) {
        return
    }
    $partial = "$target.download"
    Write-Host "Downloading $Name"
    & curl.exe --fail --location --retry 2 --output $partial $Url
    if ($LASTEXITCODE) { throw "Download failed for $Name. Rerun setup to retry." }
    if ((Get-FileHash -LiteralPath $partial).Hash -ne $Sha256) {
        throw "Checksum mismatch for $Name."
    }
    Move-Item -LiteralPath $partial -Destination $target -Force
}

Get-ModelFile 'model.ckpt' 'https://huggingface.co/stabilityai/TripoSR/resolve/main/model.ckpt' '429E2C6B22A0923967459DE24D67F05962B235F79CDE6B032AA7ED2FFCD970EE'
Get-ModelFile 'dino.json' 'https://huggingface.co/facebook/dino-vitb16/resolve/main/config.json' 'B87C0270B97DB085FD82CF114A761FD0F62AE7914FBD407C752A2260646B689C'
Get-ModelFile 'u2netp.onnx' 'https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2netp.onnx' '309C8469258DDA742793DCE0EBEA8E6DD393174F89934733ECC8B14C76F4DDD8'
Copy-Item -LiteralPath 'model-config.yaml' -Destination (Join-Path $weights 'config.yaml') -Force
Write-Host 'Setup complete. Drag an image onto Generate Nova 3D.cmd.'

