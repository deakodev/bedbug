@echo off

odin build plugins -debug -out:plugins.exe -collection:bedbug=.
IF %ERRORLEVEL% NEQ 0 exit /b 1

call plugins.exe

odin build tests -out:sandbox.exe -collection:bedbug=. -debug 
IF %ERRORLEVEL% NEQ 0 exit /b 1