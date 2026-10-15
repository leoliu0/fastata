#!/bin/sh
# Checks that every version string of a release agrees: the Cargo package version, fastata in
# Cargo.lock, `*! version` and `local fx_version` in stata/fastata.ado, and the versioned plugin
# file name fastata_<version>.plugin that stata/_fx_call.ado loads.
# Usage: scripts/check-versions.sh [vX.Y.Z]   (with a tag argument it must equal v<version>)
# Prints the version on success; exits 1 on any mismatch.
set -eu
cd "$(dirname "$0")/.."

cargo_version=$(awk '
  /^\[package\]/ { inpkg = 1; next }
  /^\[/ { inpkg = 0 }
  inpkg && /^version *=/ { gsub(/.*= *"|".*/, ""); print; exit }
' Cargo.toml)
if [ -z "$cargo_version" ]; then
  echo "could not read [package] version from Cargo.toml" >&2
  exit 1
fi

status=0
check() { # name value
  if [ "$2" != "$cargo_version" ]; then
    echo "version mismatch: $1 is '$2', Cargo.toml version is '$cargo_version'" >&2
    status=1
  fi
}

check "stata/fastata.ado *! version" "$(sed -n 's/^\*! version \([^ ,]*\).*/\1/p' stata/fastata.ado | head -n 1)"
check "stata/fastata.ado local fx_version" \
  "$(sed -n 's/^[[:space:]]*local fx_version[[:space:]]*\([^[:space:]]*\).*/\1/p' stata/fastata.ado | head -n 1)"
check "stata/_fx_call.ado plugin file name" \
  "$(sed -n 's/.*using("fastata_\([^"]*\)\.plugin").*/\1/p' stata/_fx_call.ado | head -n 1)"
check "Cargo.lock fastata" "$(awk '
  /^\[\[package\]\]/ { name = "" }
  /^name = / { name = $3; gsub(/"/, "", name) }
  /^version = / && name == "fastata" { v = $3; gsub(/"/, "", v); print v; exit }
' Cargo.lock)"
if [ $# -ge 1 ]; then
  check "tag $1 (without the leading v)" "${1#v}"
  case "$1" in v*) ;; *) echo "tag '$1' does not start with v" >&2; status=1 ;; esac
fi

[ $status -eq 0 ] || exit 1
echo "$cargo_version"
