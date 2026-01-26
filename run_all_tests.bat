@echo off
REM Run all tests from all extensions

setlocal

set "SCRIPT_DIR=%~dp0"

echo =========================================
echo Running CPLUS+_Ex Extension Tests
echo =========================================
cd /d "%SCRIPT_DIR%RedactedRiceExts\exts\CPLUS+_Ex"
call busted
if %errorlevel% neq 0 (
    echo CPLUS+_Ex tests failed!
    exit /b 1
)

echo.
echo =========================================
echo Running memhack Extension Tests
echo =========================================
cd /d "%SCRIPT_DIR%RedactedRiceExts\exts\memhack"
call busted
if %errorlevel% neq 0 (
    echo memhack tests failed!
    exit /b 1
)

echo.
echo =========================================
echo All tests completed successfully!
echo =========================================
