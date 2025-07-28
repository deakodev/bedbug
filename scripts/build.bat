@echo off

for %%A in (%*) do (

    if /I "%%A"=="debug" (
        set "BUILD_TYPE=debug"
        set "BUILD_FLAGS=-debug"
    )

    if /I "%%A"=="release" (
        set "BUILD_TYPE=release"
        set "BUILD_FLAGS=-o:speed"
    )
  
    if /I "%%A"=="game.dll" (
        set "BUILD_SOURCE=game"
        set "BUILD_TARGET=game"
        set "BUILD_MODE=dll"
        set "BUILD_DEFINES="
    )

    if /I "%%A"=="editor.dll" (
        set "BUILD_SOURCE=editor"
        set "BUILD_TARGET=editor"
        set "BUILD_MODE=dll"
        set "BUILD_DEFINES="
    )

    if /I "%%A"=="futon.exe" (
        set "BUILD_SOURCE=entry\futon"
        set "BUILD_TARGET=futon"
        set "BUILD_MODE=exe"
        set "BUILD_DEFINES="
    )
)

set "BUILD_COLLECTIONS=-collection:bedbug=."

set "BUILD_DIR=build\win32\%BUILD_TYPE%"
if not exist %BUILD_DIR% mkdir %BUILD_DIR%

set "BUILD_OUT=%BUILD_DIR%\%BUILD_TARGET%.%BUILD_MODE%"

echo "odin build %BUILD_SOURCE% %BUILD_FLAGS% %BUILD_DEFINES% %BUILD_COLLECTIONS% -build-mode:%BUILD_MODE% -out:%BUILD_OUT%"
odin build %BUILD_SOURCE% %BUILD_FLAGS% %BUILD_DEFINES% %BUILD_COLLECTIONS% -build-mode:%BUILD_MODE% -out:%BUILD_OUT%

exit /b %ERRORLEVEL%