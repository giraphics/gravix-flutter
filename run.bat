@echo off
rem Run gravix-flutter: engine bundle first, then flutter run.
rem
rem   run.bat [device] [flutter run options]
rem
rem Devices (default: chrome)
rem   chrome     the browser (hot reload for Dart; refresh the tab after web_src changes)
rem   edge       Microsoft Edge
rem   windows    desktop app (needs Developer Mode and Visual Studio C++)
rem   android    the connected phone or running emulator
rem   <id>       any other id from "flutter devices"
rem
rem Examples
rem   run.bat
rem   run.bat windows
rem   run.bat android
rem   run.bat chrome --web-port 5000
rem
rem The Traffic card connects to the simulator when you press Connect.
rem Start it first with ..\gravix-sim-backend\run-sim-server.bat
rem   (Android emulator: ws://10.0.2.2:8081, the default there)
setlocal EnableExtensions
cd /d "%~dp0"
set "ROOT=%CD%"

set "DEVICE=%~1"
if "%DEVICE%"=="" set "DEVICE=chrome"
if /i "%DEVICE%"=="-h" goto usage
if /i "%DEVICE%"=="--help" goto usage

rem Everything after the device name goes to flutter run.
set "EXTRA="
shift
:collect
if "%~1"=="" goto collected
set "EXTRA=%EXTRA% %1"
shift
goto collect
:collected

where node >nul 2>nul
if errorlevel 1 (
  echo [error] Node.js is not installed or not on PATH. Install Node 22 or newer from https://nodejs.org
  goto fail
)
rem Flutter is not always on PATH in a fresh terminal. Try the usual folders.
where flutter >nul 2>nul
if errorlevel 1 if exist "C:\dev\flutter\bin\flutter.bat" set "PATH=%PATH%;C:\dev\flutter\bin"
if errorlevel 1 if exist "%USERPROFILE%\flutter\bin\flutter.bat" set "PATH=%PATH%;%USERPROFILE%\flutter\bin"
where flutter >nul 2>nul
if errorlevel 1 (
  echo [error] Flutter is not installed or not on PATH. See https://docs.flutter.dev/get-started/install
  goto fail
)

echo.
echo ==^> Building the engine bundle ^(web_src^)
pushd web_src
if not exist node_modules (
  call npm ci
  if errorlevel 1 (popd & echo [error] npm ci failed. & goto fail)
)
call npm run build
if errorlevel 1 (popd & echo [error] The bundle build failed. & goto fail)
popd

echo.
echo ==^> flutter pub get
call flutter pub get
if errorlevel 1 (echo [error] flutter pub get failed. & goto fail)

rem A space in the user profile path can break the JDK's Unix-domain-socket
rem handling and Gradle with it. Point it at a folder inside build\ unless the
rem JDK is already configured. Same fix as build.bat.
if /i "%DEVICE%"=="android" if not defined JAVA_TOOL_OPTIONS (
  if not exist "build\.jdk-sockets" mkdir "build\.jdk-sockets"
  set "JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=%ROOT:\=/%/build/.jdk-sockets"
)

echo.
echo ==^> flutter run -d %DEVICE%%EXTRA%
echo     ^(r = hot reload, R = hot restart, q = quit^)
echo.
call flutter run -d %DEVICE%%EXTRA%
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" echo [error] flutter run exited with code %CODE%.
echo.
pause
exit /b %CODE%

:usage
echo Usage: run.bat [chrome^|edge^|windows^|android^|device-id] [flutter run options]
echo Example: run.bat windows
exit /b 0

:fail
echo.
pause
exit /b 1
