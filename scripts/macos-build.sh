#!/bin/bash
# Build KeyMouse (Deskflow fork) on macOS and produce a Deskflow.app bundle.
#
# Usage:   scripts/macos-build.sh [build-dir]
# Output:  <build-dir>/bin/Deskflow.app  (default build-dir: ./build)
#
# Requires Xcode Command Line Tools and Homebrew. Installs cmake, ninja,
# qt, openssl and pkg-config from Homebrew if they are missing.

set -euo pipefail

BUILD_DIR="${1:-build}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$REPO_DIR/$BUILD_DIR.log"

cd "$REPO_DIR"

echo "==> KeyMouse macOS build"
echo "    repo:  $REPO_DIR"
echo "    build: $BUILD_DIR"
echo "    log:   $LOG"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "!!  Xcode Command Line Tools not found. Run: xcode-select --install"
  echo "    then re-run this script."
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "!!  Homebrew not found. Install from https://brew.sh then re-run."
  exit 1
fi

echo "==> Checking Homebrew packages"
for pkg in cmake ninja qt openssl@3 pkg-config; do
  if brew list --versions "$pkg" >/dev/null 2>&1; then
    echo "    ok   $pkg"
  else
    echo "    add  $pkg"
    brew install "$pkg"
  fi
done

QT_PREFIX="$(brew --prefix qt)"
SSL_PREFIX="$(brew --prefix openssl@3)"

echo "==> Configuring (Qt: $QT_PREFIX)"
cmake -S . -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$QT_PREFIX;$SSL_PREFIX" \
  -DOPENSSL_ROOT_DIR="$SSL_PREFIX" \
  -DBUILD_TESTS=OFF \
  -DBUILD_INSTALLER=OFF \
  -DBUILD_OSX_BUNDLE=ON \
  2>&1 | tee "$LOG"

echo "==> Building"
cmake --build "$BUILD_DIR" 2>&1 | tee -a "$LOG"

APP="$BUILD_DIR/bin/Deskflow.app"
if [ -d "$APP" ]; then
  echo "==> Built: $APP"
  echo "    Next: scripts/macos-install.sh"
else
  echo "!!  Build finished but $APP was not found. See $LOG"
  exit 1
fi
