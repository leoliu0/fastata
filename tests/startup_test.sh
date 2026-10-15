#!/usr/bin/env bash
# startup_test.sh -- end to end on a fresh HOME: net install fastata from the repository's stata/
# (it lands in that HOME's PLUS), fastata enable (it writes that HOME's PERSONAL profile.do), then
# a new Stata session must load fastata at startup: which egen prints the shim in the runtime
# directory. Run from anywhere after scripts/build_plugin.sh; STATA=<binary> overrides stata-mp.
# Prints STARTUP_OK on success.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
stata="${STATA:-stata-mp}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

printf 'net install fastata, from("%s/stata")\nfastata enable\n' "$repo" > install.do
HOME="$tmp" "$stata" -b do install.do
if ! grep -q '^fastata: enabled; Stata loads it at startup through' install.log; then
  cat install.log
  exit 1
fi

printf 'which egen\n' > check.do
HOME="$tmp" "$stata" -b do check.do
want="$tmp/ado/plus/fastata/egen.ado"
if ! grep -qxF "$want" check.log; then
  echo "startup_test: which egen did not print $want" >&2
  cat check.log
  exit 1
fi
echo STARTUP_OK
