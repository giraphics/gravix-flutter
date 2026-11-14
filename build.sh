#!/usr/bin/env bash
# Build gravix-flutter: engine bundle first, then the Flutter targets.
#
#   ./build.sh [target ...] [options]
#
# Targets (default: all)
#   web        build/web                         (static site)
#   windows    build/windows/x64/runner/<Mode>   (Windows host only)
#   apk        build/app/outputs/flutter-apk     (Android)
#   all        web + apk, plus windows when run on Windows
#   bundle     only the engine bundle (assets/www/gravix_worlds.js)
#   clean      remove every build output, then stop
#
# Options
#   --debug            debug instead of release builds
#   --skip-checks      skip typecheck, flutter analyze and flutter test
#   --base-href PATH   web base href, e.g. /gravix-flutter/ for GitHub Pages
#   -h, --help         this text
#
# Works in Git Bash on Windows as well as on macOS and Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

MODE=release
CHECKS=1
BASE_HREF=""
TARGETS=()

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }
step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nerror: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    web|windows|apk|all|bundle|clean) TARGETS+=("$1") ;;
    --debug) MODE=debug ;;
    --skip-checks) CHECKS=0 ;;
    --base-href)
      [ $# -ge 2 ] || fail "--base-href needs a value, e.g. /gravix-flutter/"
      BASE_HREF="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fail "unknown argument: $1" ;;
  esac
  shift
done
[ ${#TARGETS[@]} -gt 0 ] || TARGETS=(all)

on_windows() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; *) return 1 ;; esac; }

# Windows needs Developer Mode for Flutter's plugin symlinks. Checked up front
# so the failure names the setting instead of a symlink error mid-build.
windows_dev_mode() {
  reg.exe query 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' \
    //v AllowDevelopmentWithoutDevLicense 2>/dev/null | grep -q '0x1'
}

# Expand "all" into concrete targets.
EXPANDED=()
for t in "${TARGETS[@]}"; do
  if [ "$t" = all ]; then
    EXPANDED+=(web apk)
    if on_windows; then
      if windows_dev_mode; then
        EXPANDED+=(windows)
      else
        echo "note: skipping windows in 'all': Developer Mode is off (Settings > System > For developers)"
      fi
    fi
  else
    EXPANDED+=("$t")
  fi
done
TARGETS=("${EXPANDED[@]}")

# ---- clean -----------------------------------------------------------------
if [[ " ${TARGETS[*]} " == *" clean "* ]]; then
  step "Cleaning build outputs"
  command -v flutter >/dev/null && flutter clean
  rm -f assets/www/gravix_worlds.js assets/www/gravix_worlds.js.map
  rm -rf android/.gradle
  echo "Clean. (web_src/node_modules is kept; delete it to force a fresh npm install.)"
  exit 0
fi

# ---- tools -----------------------------------------------------------------
step "Checking tools"
command -v node >/dev/null || fail "Node.js not found (need 22 or newer): https://nodejs.org/"
command -v npm >/dev/null || fail "npm not found (it ships with Node.js)"
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 22 ] || fail "Node.js $NODE_MAJOR found, need 22 or newer"
NEEDS_FLUTTER=0
for t in "${TARGETS[@]}"; do [ "$t" = bundle ] || NEEDS_FLUTTER=1; done
if [ "$NEEDS_FLUTTER" = 1 ]; then
  command -v flutter >/dev/null || fail "flutter not found on PATH: https://docs.flutter.dev/get-started/install"
fi
echo "node $(node --version), npm $(npm --version)$([ "$NEEDS_FLUTTER" = 1 ] && printf ', %s' "$(flutter --version 2>/dev/null | head -1)")"

for t in "${TARGETS[@]}"; do
  if [ "$t" = windows ]; then
    on_windows || fail "the windows target needs a Windows host"
    windows_dev_mode || fail "Windows Developer Mode is off; Flutter needs it for plugin symlinks (Settings > System > For developers)"
  fi
done

# ---- engine bundle ---------------------------------------------------------
step "Engine bundle (web_src)"
# npm ci installs exactly what package-lock.json pins.
(cd web_src && npm ci --no-audit --no-fund)
if [ "$CHECKS" = 1 ]; then
  (cd web_src && npm run typecheck)
fi
(cd web_src && npm run build)
[ -s assets/www/gravix_worlds.js ] || fail "bundle was not written to assets/www/gravix_worlds.js"

# ---- flutter ---------------------------------------------------------------
if [ "$NEEDS_FLUTTER" = 1 ]; then
  step "flutter pub get"
  flutter pub get
  if [ "$CHECKS" = 1 ]; then
    step "flutter analyze"
    flutter analyze
    step "flutter test"
    flutter test
  fi
fi

OUTPUTS=()
for t in "${TARGETS[@]}"; do
  case "$t" in
    bundle) ;;
    web)
      step "Building web ($MODE)"
      args=(build web "--$MODE")
      [ -n "$BASE_HREF" ] && args+=(--base-href "$BASE_HREF")
      # Git Bash rewrites arguments that look like Unix paths before handing
      # them to Windows programs: /gravix-flutter/ would reach Flutter as
      # C:/Program Files/Git/gravix-flutter/. Harmless elsewhere.
      MSYS_NO_PATHCONV=1 flutter "${args[@]}"
      OUTPUTS+=("web      build/web/") ;;
    windows)
      step "Building windows ($MODE)"
      flutter build windows "--$MODE"
      dir=Release; [ "$MODE" = debug ] && dir=Debug
      OUTPUTS+=("windows  build/windows/x64/runner/$dir/gravix_flutter.exe") ;;
    apk)
      step "Building Android APK ($MODE)"
      # Some Windows setups (a space in the user profile path) break the JDK's
      # Unix-domain-socket temp dir, and Gradle fails with "Unable to
      # establish loopback connection". Point it at a short folder inside
      # build/ unless the caller already configured the JDK.
      if on_windows && [ -z "${JAVA_TOOL_OPTIONS:-}" ]; then
        mkdir -p build/.jdk-sockets
        export JAVA_TOOL_OPTIONS="-Djdk.net.unixdomain.tmpdir=$(cygpath -m "$ROOT/build/.jdk-sockets")"
      fi
      flutter build apk "--$MODE"
      OUTPUTS+=("apk      build/app/outputs/flutter-apk/app-$MODE.apk") ;;
  esac
done

step "Done"
printf '  %s\n' "bundle   assets/www/gravix_worlds.js" "${OUTPUTS[@]}"
