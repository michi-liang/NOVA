@echo off
setlocal
set "NOVA_PYTHON=%~dp0.runtime\env\Scripts\python.exe"
if not exist "%NOVA_PYTHON%" (
    echo Run setup.ps1 first. See README.md.
    pause
    exit /b 1
)
if "%~1"=="" (
    echo Drag a PNG or JPG onto this file. The GLB will be saved in generated.
    pause
    exit /b 0
)
"%NOVA_PYTHON%" "%~dp0nova.py" "%~f1" "%~dp0generated\%~n1.glb"
set "NOVA_RESULT=%ERRORLEVEL%"
pause
exit /b %NOVA_RESULT%
