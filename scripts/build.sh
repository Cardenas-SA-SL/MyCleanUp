#!/bin/bash
# Compila MyCleanUp.app con swiftc (Command Line Tools, sin Xcode ni SPM).
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH="$(uname -m)"
TARGET="$ARCH-apple-macos13.0"
BUILD=build
APP="$BUILD/MyCleanUp.app"

mkdir -p "$BUILD"

echo "==> Compilando MyCleanUp ($TARGET)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -target "$TARGET" \
  Sources/Core/*.swift Sources/App/*.swift \
  -o "$APP/Contents/MacOS/MyCleanUp"

if [ ! -f Resources/AppIcon.icns ]; then
  echo "==> Generando icono"
  swiftc -O -target "$TARGET" scripts/make_icon.swift -o "$BUILD/make_icon"
  rm -rf "$BUILD/AppIcon.iconset"
  "$BUILD/make_icon" "$BUILD/AppIcon.iconset"
  iconutil -c icns "$BUILD/AppIcon.iconset" -o Resources/AppIcon.icns
fi

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "==> Listo: $APP"
