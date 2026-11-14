@echo off
rem Build gravix-flutter: engine bundle first, then the Flutter targets.
rem
rem   build.bat [target ...] [options]
rem
rem Targets (default: all)
rem   web        build\web                          (static site)
rem   windows    build\windows\x64\runner\<Mode>    (needs Developer Mode)
rem   apk        build\app\outputs\flutter-apk      (Android)
rem   all        web + apk, plus windows when Developer Mode is on
rem   bundle     only the engine bundle (assets\www\gravix_worlds.js)
rem   clean      remove every build output, then stop
rem
rem Options
rem   --debug            debug instead of release builds
rem   --skip-checks      skip typecheck, flutter analyze and flutter test
rem   --base-href PATH   web base href, e.g. /gravix-flutter/ for GitHub Pages
rem   -h, --help         this text
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
set "ROOT=%CD%"

set "MODE=release"
set "CHECKS=1"
set "BASE_HREF="
set "TARGETS="

:parse
if "%~1"=="" goto parsed
if /i "%~1"=="web"      (set "TARGETS=!TARGETS! web"     & shift & goto parse)
if /i "%~1"=="windows"  (set "TARGETS=!TARGETS! windows" & shift & goto parse)
if /i "%~1"=="apk"      (set "TARGETS=!TARGETS! apk"     & shift & goto parse)
if /i "%~1"=="all"      (set "TARGETS=!TARGETS! all"     & shift & goto parse)
if /i "%~1"=="bundle"   (set "TARGETS=!TARGETS! bundle"  & shift & goto parse)
if /i "%~1"=="clean"    (set "TARGETS=!TARGETS! clean"   & shift & goto parse)
if /i "%~1"=="--debug"       (set "MODE=debug" & shift & goto parse)
if /i "%~1"=="--skip-checks" (set "CHECKS=0"   & shift & goto parse)
if /i "%~1"=="--base-href" (
  if "%~2"=="" (set "FAIL=--base-href needs a value, e.g. /gravix-flutter/" & goto fail)
  set "BASE_HREF=%~2"
  shift & shift & goto parse
)
if /i "%~1"=="-h"     goto usage
if /i "%~1"=="--help" goto usage
echo error: unknown argument: %~1
goto usage_fail

:parsed
if "%TARGETS%"=="" set "TARGETS= all"

rem Windows needs Developer Mode for Flutter's plugin symlinks.
set "DEVMODE=0"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense 2>nul | find "0x1" >nul && set "DEVMODE=1"

rem Expand "all" into concrete targets.
set "EXPANDED="
for %%T in (%TARGETS%) do (
  if /i "%%T"=="all" (
    set "EXPANDED=!EXPANDED! web apk"
    if "!DEVMODE!"=="1" (
      set "EXPANDED=!EXPANDED! windows"
    ) else (
      echo note: skipping windows in 'all': Developer Mode is off ^(Settings ^> System ^> For developers^)
    )
  ) else (
    set "EXPANDED=!EXPANDED! %%T"
  )
)
set "TARGETS=%EXPANDED%"

rem ---- clean -------------------------------------------------------------------
echo %TARGETS% | find /i "clean" >nul && (
  echo.
  echo ==^> Cleaning build outputs
  where flutter >nul 2>nul && call flutter clean
  if exist "assets\www\gravix_worlds.js" del /q "assets\www\gravix_worlds.js"
  if exist "assets\www\gravix_worlds.js.map" del /q "assets\www\gravix_worlds.js.map"
  if exist "android\.gradle" rmdir /s /q "android\.gradle"
  echo Clean. ^(web_src\node_modules is kept; delete it to force a fresh npm install.^)
  exit /b 0
)

rem ---- tools -------------------------------------------------------------------
echo.
echo ==^> Checking tools
where node >nul 2>nul || (set "FAIL=Node.js not found (need 22 or newer): https://nodejs.org/" & goto fail)
where npm  >nul 2>nul || (set "FAIL=npm not found (it ships with Node.js)" & goto fail)
for /f %%V in ('node -p "process.versions.node.split('.')[0]"') do set "NODE_MAJOR=%%V"
if %NODE_MAJOR% LSS 22 (set "FAIL=Node.js %NODE_MAJOR% found, need 22 or newer" & goto fail)

set "NEEDS_FLUTTER=0"
for %%T in (%TARGETS%) do if /i not "%%T"=="bundle" set "NEEDS_FLUTTER=1"
if "%NEEDS_FLUTTER%"=="1" (
  where flutter >nul 2>nul || (set "FAIL=flutter not found on PATH: https://docs.flutter.dev/get-started/install" & goto fail)
)
for %%T in (%TARGETS%) do (
  if /i "%%T"=="windows" if not "!DEVMODE!"=="1" (
    set "FAIL=Windows Developer Mode is off; Flutter needs it for plugin symlinks (Settings > System > For developers)"
    goto fail
  )
)
for /f "delims=" %%V in ('node --version') do set "NODE_VERSION=%%V"
echo node %NODE_VERSION%

rem ---- engine bundle -------------------------------------------------------------
echo.
echo ==^> Engine bundle (web_src)
pushd web_src
rem npm ci installs exactly what package-lock.json pins.
call npm ci --no-audit --no-fund || (popd & set "FAIL=npm ci failed" & goto fail)
if "%CHECKS%"=="1" (
  call npm run typecheck || (popd & set "FAIL=typecheck failed" & goto fail)
)
call npm run build || (popd & set "FAIL=bundle build failed" & goto fail)
popd
if not exist "assets\www\gravix_worlds.js" (set "FAIL=bundle was not written to assets\www\gravix_worlds.js" & goto fail)

rem ---- flutter -------------------------------------------------------------------
if "%NEEDS_FLUTTER%"=="1" (
  echo.
  echo ==^> flutter pub get
  call flutter pub get || (set "FAIL=flutter pub get failed" & goto fail)
  if "%CHECKS%"=="1" (
    echo.
    echo ==^> flutter analyze
    call flutter analyze || (set "FAIL=flutter analyze failed" & goto fail)
    echo.
    echo ==^> flutter test
    call flutter test || (set "FAIL=flutter test failed" & goto fail)
  )
)

set "OUTPUTS="
for %%T in (%TARGETS%) do (
  if /i "%%T"=="web" (
    echo.
    echo ==^> Building web ^(%MODE%^)
    if defined BASE_HREF (
      call flutter build web --%MODE% --base-href "!BASE_HREF!" || (set "FAIL=web build failed" & goto fail)
    ) else (
      call flutter build web --%MODE% || (set "FAIL=web build failed" & goto fail)
    )
    set "OUTPUTS=!OUTPUTS!;web      build\web\"
  )
  if /i "%%T"=="windows" (
    echo.
    echo ==^> Building windows ^(%MODE%^)
    call flutter build windows --%MODE% || (set "FAIL=windows build failed" & goto fail)
    if /i "%MODE%"=="debug" (set "WINDIR_OUT=Debug") else (set "WINDIR_OUT=Release")
    set "OUTPUTS=!OUTPUTS!;windows  build\windows\x64\runner\!WINDIR_OUT!\gravix_flutter.exe"
  )
  if /i "%%T"=="apk" (
    echo.
    echo ==^> Building Android APK ^(%MODE%^)
    rem A space in the user profile path can break the JDK's Unix-domain-socket
    rem temp dir ("Unable to establish loopback connection"). Use a short
    rem folder inside build\ unless the JDK is already configured.
    if not defined JAVA_TOOL_OPTIONS (
      if not exist "build\.jdk-sockets" mkdir "build\.jdk-sockets"
      set "JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=%ROOT:\=/%/build/.jdk-sockets"
    )
    call flutter build apk --%MODE% || (set "FAIL=apk build failed" & goto fail)
    set "OUTPUTS=!OUTPUTS!;apk      build\app\outputs\flutter-apk\app-%MODE%.apk"
  )
)

echo.
echo ==^> Done
echo   bundle   assets\www\gravix_worlds.js
for %%O in ("%OUTPUTS:;=" "%") do if not "%%~O"=="" echo   %%~O
exit /b 0

rem Every failure lands here. `exit /b 1` from inside a parenthesized block
rem (an if, or a for over targets) right after CALLing another batch file,
rem such as flutter.bat, can return 0 to whoever ran this script; a goto to a
rem top-level label does not. !FAIL! (delayed expansion) prints messages
rem containing > or ( literally.
:fail
echo.
echo error: !FAIL!
exit /b 1

:usage
rem Print the comment block at the top of this file. A flag, not a goto out of
rem the loop: jumping out of a for loop inside a CALL loses the exit code.
set "INHEAD=1"
for /f "usebackq tokens=* delims=" %%L in ("%~f0") do (
  set "LINE=%%L"
  if "!LINE:~0,3!"=="rem" (
    if "!INHEAD!"=="1" echo(!LINE:~4!
  ) else if not "!LINE:~0,5!"=="@echo" (
    set "INHEAD=0"
  )
)
exit /b 0

:usage_fail
call :usage
exit /b 1
