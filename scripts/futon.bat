@echo off

set EXE=futon.exe
set EXE_RUNNING=false

set BUILD=%CD%\\scripts\\build.bat
set BUILD_DIR=%CD%\\build\\win32\\debug

set SHADER_DIR=%CD%\\modules\\renderer
set SHADER_BUILD_DIR=%CD%\\modules\\renderer

for /F %%x in ('tasklist /NH /FI "IMAGENAME eq %EXE%"') do if %%x == %EXE% set EXE_RUNNING=true

if %EXE_RUNNING% == false (
    del /q /s %BUILD_DIR% >nul 2>nul
)

echo [Compiling shaders...]
if not exist %SHADER_BUILD_DIR% mkdir %SHADER_BUILD_DIR%
for %%f in (%SHADER_DIR%\*.vert) do (
    glslc "%%f" -o "%SHADER_BUILD_DIR%\%%~nf.vert.spv"
)
for %%f in (%SHADER_DIR%\*.frag) do (
    glslc "%%f" -o "%SHADER_BUILD_DIR%\%%~nf.frag.spv"
)
for %%f in (%SHADER_DIR%\*.comp) do (
    glslc "%%f" -o "%SHADER_BUILD_DIR%\%%~nf.comp.spv"
)

echo [Building debug game.dll...]
call %BUILD% debug game.dll
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to build debug game.dll
    exit /b %ERRORLEVEL%
)

if %EXE_RUNNING% == true (
    echo [Hot reloading debug game.dll...]
    exit /b 0
)

echo [Building debug futon.dll...]
call %BUILD% debug futon.dll
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to build debug futon.dll
    exit /b %ERRORLEVEL%
)

echo [Building debug futon.exe...]
call %BUILD% debug futon.exe
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to build futon.exe
    exit /b %ERRORLEVEL%
)

echo [Running debug futon.exe...]
start cmd /c "%BUILD_DIR%\\%EXE% & echo. & echo [Press any key to close...] & pause > nul"

exit /b %ERRORLEVEL%