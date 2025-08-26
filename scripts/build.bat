@echo off
setlocal enableDelayedExpansion

:: Default values
set "BUILD_TYPE=debug"
set "WITH_EDITOR=false"
set "PROJECT=game"

:: Parse args
for %%A in (%*) do (
    if /I "%%A"=="debug" set "BUILD_TYPE=debug"
    if /I "%%A"=="release" set "BUILD_TYPE=release"
    if /I "%%A"=="game" set "PROJECT=game"
    if /I "%%A"=="viewer" set "PROJECT=viewer"
    if /I "%%A"=="editor" set "WITH_EDITOR=true"
)

:: Config values
set "EXE=%PROJECT%.exe"
set "EXE_RUNNING=false"
set "MODE_FLAGS=-debug"
if /I "%BUILD_TYPE%"=="release" set "MODE_FLAGS=-o:speed"

set "BUILD_DIR=%CD%\build\win32\%BUILD_TYPE%"
set "OUT_EXE=%BUILD_DIR%\%EXE%"

:: Check if EXE is running
for /F %%x in ('tasklist /NH /FI "IMAGENAME eq %EXE%"') do if %%x == %EXE% set EXE_RUNNING=true

:: Clean if not running
if !EXE_RUNNING! == false (
    del /q /s %BUILD_DIR% >nul 2>nul
)

:: Shader step
echo [Compiling shaders...]
call scripts\slangc.bat

:: Project DLL
echo.
echo [Building %BUILD_TYPE% %PROJECT%.dll...]
call scripts\build_target.bat %BUILD_TYPE% %PROJECT%.dll
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%

:: Editor DLL
if /I "%WITH_EDITOR%"=="true" (
    echo.
    echo [Building %BUILD_TYPE% editor.dll...]
    call scripts\build_target.bat %BUILD_TYPE% editor.dll
    if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
)

:: Main EXE
echo.
echo [Building %BUILD_TYPE% %EXE%...]
call scripts\build_target.bat %BUILD_TYPE% %EXE%
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%

echo.
endlocal
exit /b %ERRORLEVEL%
