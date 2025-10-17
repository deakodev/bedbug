@echo off
setlocal enableDelayedExpansion

set "BUILD_TYPE=debug"
set "BUILD_FLAGS=-debug"

:: Build type
if /I "%1"=="debug" (
    set "BUILD_TYPE=debug"
    set "BUILD_FLAGS=-debug"
)
if /I "%1"=="release" (
    set "BUILD_TYPE=release"
    set "BUILD_FLAGS=-o:speed"
)

:: Compile
set "COLLECTIONS=bedbug=."
set "BUILD_DIR=build\win32\%BUILD_TYPE%"
if not exist %BUILD_DIR% mkdir %BUILD_DIR%
set "OUT=%BUILD_DIR%\layers.exe"

odin build core/meta -define:PACKAGE_DIR="modules/game" %BUILD_FLAGS% -collection:%COLLECTIONS% -build-mode:exe -out:%OUT%

endlocal
exit /b %ERRORLEVEL%