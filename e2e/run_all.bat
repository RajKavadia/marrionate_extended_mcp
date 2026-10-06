@echo off
REM Replays every JSON scenario against a running app.
REM
REM The app must already be running with a reachable VM service or CDP bridge:
REM   flutter run -d windows      (native, marionette + flutter-skill)
REM   flutter run -d chrome       (web, flutter-skill JS bridge only)
REM
REM On native, marionette tools are available; on web they are refused with an
REM explanatory error rather than hanging, because no VM service exists there.

setlocal

set "SCENARIOS=%~dp0scenarios"
set "FORMAT=%~1"
if "%FORMAT%"=="" set "FORMAT=text"

echo Validating scenarios...
dart run "%~dp0..\tool\validate_scenarios.dart" "%SCENARIOS%" || exit /b 1

echo.
echo Replaying scenarios (format: %FORMAT%)...
dart run "%~dp0..\packages\flutter-e2e-mcp\bin\replay.dart" ^
  --scenarios "%SCENARIOS%" ^
  --format "%FORMAT%"

exit /b %ERRORLEVEL%
