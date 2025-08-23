@echo off
setLocal enableDelayedExpansion

:: check if slangc is already in PATH
where slangc.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set "COMPILER=slangc.exe"
    goto :continue
)

:: if not in PATH, check VULKAN_SDK 
if "%VULKAN_SDK%" == "" (
    echo slangc.exe not found in PATH and VULKAN_SDK environment variable is not set
    exit /b 1
)

set "COMPILER=%VULKAN_SDK%\Bin\slangc.exe"

:: check if slangc exists in Vulkan SDK
if not exist "%COMPILER%" (
    echo slangc.exe not found in PATH or in %VULKAN_SDK%\Bin
    exit /b 1
)

:continue

:: check for watch argument
set "watch_mode=false"
if "%1"=="watch" set "watch_mode=true"

:: compilation of all files
set "count=0"
set "errors=0"

set "SRC_DIR=modules\renderer\shaders"
set "OUT_DIR=modules\renderer\shaders\bin"
set "COMMON_ARGS=-entry main -profile glsl_450 -target spirv -capability spvSparseResidency"

for /r %SRC_DIR% %%i in (*.slang) do (
    :: extract filename without path for easier pattern matching
    set "filename=%%~ni"

    :: skip files that end with inc_
    echo !filename! | findstr /i "_inc" > nul
    if !errorlevel! neq 0 (
        echo    %%~nxi
        call %COMPILER% "%%i" %COMMON_ARGS% -o "%OUT_DIR%\%%~ni.spv"
        if !errorlevel! neq 0 (
            echo    Failed to compile %%~nxi
            set /a "errors+=1"
        ) else (
            set /a "count+=1"
        )
    )
)

echo    Successfully compiled: !count! shaders
if !errors! gtr 0 (
    echo    Failed to compile: !errors! shaders
    exit /b 1
)

exit /b 0
endLocal
