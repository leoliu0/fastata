#!/usr/bin/env bash
# startup_test.sh -- end to end on a fresh HOME: net install fastata from the repository's stata/
# (it lands in that HOME's PLUS), fastata enable (it writes that HOME's PERSONAL profile.do), then
# a new Stata session must load fastata at startup: which egen prints the shim in the runtime
# directory. Then, in sessions started in that HOME: fastata disable also removes the lines the
# enable note suggests for the current directory's profile.do, and a later start leaves fastata
# off even when a profile.do still runs fastata_init; fastata enable turns it on again.
# Run from anywhere after scripts/build_plugin.sh; STATA=<binary> overrides stata-mp.
# No real profile.do is ever edited: PATH holds only an empty scratch folder, and install.do stops
# before fastata enable when the profile.do search would find a file outside the scratch HOME (a
# profile.do in the Stata directory, or in BASE or SITE).
# Prints STARTUP_OK on success.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
stata="$(command -v "${STATA:-stata-mp}")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
mkdir bin
run() {  # run <name>: Stata on <name>.do in the scratch HOME with the scratch PATH
  HOME="$tmp" PATH="$tmp/bin" "$stata" -b do "$1.do"
}
fail() {  # fail <message> <log>
  echo "startup_test: $1" >&2
  cat "$2"
  exit 1
}
base="$(printf 'quietly findfile egen.ado, path(BASE)\ndi "BASE_EGEN " r(fn)\n' > base.do && run base && sed -n 's/^BASE_EGEN //p' base.log)"
[ -n "$base" ] || fail "could not locate BASE's egen.ado" base.log
want="$tmp/ado/plus/fastata/egen.ado"
check() {  # check <expected egen.ado> <what>: a new session started in the scratch HOME
  printf 'which egen\n' > check.do
  run check
  grep -qxF "$1" check.log || fail "$2: which egen did not print $1" check.log
}

cat > install.do <<EOF
net install fastata, from("$repo/stata")
_fx profile_first \`"\`: env PATH'"' "" ""
if \`"\`fx_profile'"' != "" & strpos(\`"\`fx_profile'"', "$tmp/") != 1 {
	di as err \`"startup_test: the search finds \`fx_profile'; not editing it"'
	exit 9
}
fastata enable
EOF
run install
grep -q '^fastata: enabled; Stata loads it at startup through' install.log || fail "fastata enable failed" install.log
check "$want" "after enable"

# the current directory's profile.do (here: the scratch HOME, where Stata starts) with the block
# the enable note offers; disable removes it there too, and leaves the user's line
printf '* mine\n* >>> fastata (added by fastata enable; remove with fastata disable)\ncapture fastata_init\n* <<< fastata\n' > profile.do
check "$want" "cwd profile.do with the block"
printf 'fastata disable\n' > disable.do
run disable
grep -q '^fastata: disabled; removed the startup lines from' disable.log || fail "fastata disable failed" disable.log
[ "$(cat profile.do)" = "* mine" ] || fail "disable left profile.do as: $(cat profile.do)" disable.log
check "$base" "after disable"
# a profile.do that still runs fastata_init does not turn fastata on again
printf 'capture fastata_init\n' >> profile.do
check "$base" "after disable, with fastata_init in profile.do"
printf 'fastata enable\n' > enable2.do
run enable2
check "$want" "after enable again"
echo STARTUP_OK
