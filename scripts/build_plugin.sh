#!/usr/bin/env bash
# Builds the Stata plugin in release mode and copies it into stata/ as
#   stata/fastata.<linux64|macos-universal|win64>.plugin  (the name used by fastata.pkg)
#   stata/fastata.plugin                                   (the name the runtime copies)
# Usage: scripts/build_plugin.sh [extra cargo args...]
# On macOS both architectures are built and merged with lipo (needs both rustc targets).
set -euo pipefail
cd "$(dirname "$0")/.."

os="$(uname -s)"
case "$os" in
  Linux)
    cargo build --release "$@"
    src="target/release/libfastata.so"
    name="linux64"
    ;;
  Darwin)
    export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
    cargo build --release --target aarch64-apple-darwin "$@"
    MACOSX_DEPLOYMENT_TARGET=10.13 cargo build --release --target x86_64-apple-darwin "$@"
    mkdir -p target/universal
    lipo -create \
      target/aarch64-apple-darwin/release/libfastata.dylib \
      target/x86_64-apple-darwin/release/libfastata.dylib \
      -output target/universal/libfastata.dylib
    codesign --force -s - target/universal/libfastata.dylib
    src="target/universal/libfastata.dylib"
    name="macos-universal"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    cargo build --release --target x86_64-pc-windows-msvc "$@"
    src="target/x86_64-pc-windows-msvc/release/fastata.dll"
    name="win64"
    ;;
  *)
    echo "build_plugin.sh: unsupported OS $os" >&2
    exit 1
    ;;
esac

mkdir -p stata
# Copy then rename, so a Stata session that has the old plugin loaded keeps its own file.
for dst in "stata/fastata.$name.plugin" "stata/fastata.plugin"; do
  cp "$src" "$dst.tmp"
  mv -f "$dst.tmp" "$dst"
done
echo "built stata/fastata.$name.plugin and stata/fastata.plugin"
