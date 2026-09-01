#!/bin/bash
# Compila y ejecuta la prueba de humo del nucleo (solo toca directorios temporales).
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH="$(uname -m)"
TARGET="$ARCH-apple-macos13.0"
mkdir -p build

swiftc -target "$TARGET" Sources/Core/*.swift Tests/smoke.swift -o build/smoke
./build/smoke
