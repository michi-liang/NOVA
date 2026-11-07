@echo off
setlocal
set "NOVA_WORK=%~dp0..\work"
if "%~1"=="" (
    echo Drag a PNG or JPG onto this file to make a textured GLB.
    echo The GLB will be saved in this folder.
    pause
    exit /b 0
)
set "HF_HUB_OFFLINE=1"
set "HF_HOME=%NOVA_WORK%\hf-cache"
"%NOVA_WORK%\env\Scripts\python.exe" "%NOVA_WORK%\TripoSR\nova.py" "%~f1" "%~dp0%~n1.glb" %2
set "NOVA_RESULT=%ERRORLEVEL%"
if not "%NOVA_RESULT%"=="0" echo Generation failed. See the message above.
if /I not "%~3"=="--no-pause" pause
exit /b %NOVA_RESULT%
