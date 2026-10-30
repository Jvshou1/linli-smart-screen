@echo off
setlocal
set "SIXBANK_TD_EXE=C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe"
if not exist "%SIXBANK_TD_EXE%" (
    echo TD executable not found: %SIXBANK_TD_EXE%
    exit /b 1
)
pushd "%~dp0"
set "SIXBANK_SCRIPT=%~dp0src\td_project\build_sixbank_seed2.tcl"
set "SIXBANK_SCRIPT=%SIXBANK_SCRIPT:\=/%"
"%SIXBANK_TD_EXE%" "%SIXBANK_SCRIPT%"
set "SIXBANK_BUILD_RESULT=%ERRORLEVEL%"
popd
if not "%SIXBANK_BUILD_RESULT%"=="0" echo Build failed. Check the TD output for RUN_DIRECTORY and the corresponding run log.
if /i not "%~1"=="--no-pause" pause
exit /b %SIXBANK_BUILD_RESULT%
