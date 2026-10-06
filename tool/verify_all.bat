@echo off
REM Runs every gate in the repository. Non-zero exit if any gate fails.
REM
REM   1. vendor integrity   - no leftover old names, no unrecorded vendor edits
REM   2. analyzer           - every package clean
REM   3. keys               - every interactive widget has a ValueKey
REM   4. scenarios          - valid against the action vocabulary and KeyRegistry
REM   5. tests              - toolkit and MCP server suites
REM
REM Usage:  tool\verify_all.bat

setlocal enabledelayedexpansion
set "ROOT=%~dp0.."
set "FAILED="

echo ================================================================
echo 1. Vendor integrity
echo ================================================================
call dart run "%ROOT%\tool\rename_package.dart" --verify || set "FAILED=!FAILED! rename"
call dart run "%ROOT%\tool\check_drift.dart" || set "FAILED=!FAILED! drift"

echo.
echo ================================================================
echo 2. Analyzer, per package
echo ================================================================
for %%D in (
  "vendor\flutter_skill"
  "vendor\marionette_flutter"
  "vendor\marionette_mcp"
  "vendor\marionette_logging"
  "vendor\marionette_logger"
  "vendor\marionette_cli"
  "packages\flutter_e2e_toolkit"
  "packages\flutter-e2e-mcp"
  "packages\app"
) do (
  pushd "%ROOT%\%%D"
  findstr /C:"  flutter:" pubspec.yaml >nul && set "ISFLUTTER=1" || set "ISFLUTTER=0"
  if "!ISFLUTTER!"=="1" (
    call flutter analyze
  ) else (
    call dart analyze
  )
  if errorlevel 1 set "FAILED=!FAILED! analyze:%%D"
  popd
)

echo.
echo ================================================================
echo 3. ValueKey coverage
echo ================================================================
call dart run "%ROOT%\tool\check_keys.dart" || set "FAILED=!FAILED! keys"

echo.
echo ================================================================
echo 4. Scenario validation
echo ================================================================
call dart run "%ROOT%\tool\validate_scenarios.dart" || set "FAILED=!FAILED! scenarios"

echo.
echo ================================================================
echo 5. Tests
echo ================================================================
pushd "%ROOT%\packages\flutter_e2e_toolkit"
call flutter test
if errorlevel 1 set "FAILED=!FAILED! toolkit-tests"
popd

pushd "%ROOT%\packages\flutter-e2e-mcp"
call flutter test
if errorlevel 1 set "FAILED=!FAILED! mcp-tests"
popd

pushd "%ROOT%\packages\app"
call flutter test
if errorlevel 1 set "FAILED=!FAILED! app-tests"
popd

echo.
echo ================================================================
if defined FAILED (
  echo RESULT: FAILED -!FAILED!
  exit /b 1
)
echo RESULT: all gates passed.
exit /b 0
