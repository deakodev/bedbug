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

:: Build target
set "TARGET=%2"

if /I "%TARGET%"=="editor.dll" (
    set "SOURCE=modules/editor"
    set "NAME=editor"
    set "MODE=dll"
    set "DEFINES=-extra-linker-flags:"/IGNORE:4075""
)
if /I "%TARGET%"=="game.dll" (
    set "SOURCE=modules/game"
    set "NAME=game"
    set "MODE=dll"
    set "DEFINES="
)
if /I "%TARGET%"=="viewer.dll" (
    set "SOURCE=modules/viewer"
    set "NAME=viewer"
    set "MODE=dll"
    set "DEFINES="
)
if /I "%TARGET%"=="game.exe" (
    set "SOURCE=runtime"
    set "NAME=game"
    set "MODE=exe"
    set "DEFINES=-extra-linker-flags:"/IGNORE:4075""
)
if /I "%TARGET%"=="viewer.exe" (
    set "SOURCE=runtime"
    set "NAME=viewer"
    set "MODE=exe"
    set "DEFINES=-extra-linker-flags:"/IGNORE:4075""
)

:: Compile
set "COLLECTIONS=bedbug=."
set "BUILD_DIR=build\win32\%BUILD_TYPE%"
if not exist %BUILD_DIR% mkdir %BUILD_DIR%
set "OUT=%BUILD_DIR%\%NAME%.%MODE%"

odin build %SOURCE% %BUILD_FLAGS% %DEFINES% -collection:%COLLECTIONS% -build-mode:%MODE% -out:%OUT%

endlocal
exit /b %ERRORLEVEL%
