* verify_child.do -- run by test_verify.do in a separate Stata process with env FASTATA_MODE=verify
* and FASTATA_COUNTS set (Stata cannot set environment variables). Uses the runtime directory
* that test_verify.do built (tests/stata/_plus/fastata/) without rebuilding it. Prints
* VERIFY_CHILD passed; test_verify.do checks the FASTATA_COUNTS lines.
version 16
clear all
set more off
local here `"`c(pwd)'"'
quietly cd "../../stata"
quietly adopath ++ `"`c(pwd)'/"'
quietly cd `"`here'"'
sysdir set PLUS `"`here'/_plus/"'
quietly fastata on

* the mode comes from FASTATA_MODE
_fx status
assert "`fx_mode'" == "verify"
sysuse auto, clear
egen double m = mean(price), by(foreign)

* clear all drops Mata externals; the mode still comes from FASTATA_MODE
clear all
_fx status
assert "`fx_mode'" == "verify"
assert `fx_nfast_egen' == 0
sysuse auto, clear
xtile q = price, nq(4)

* _fx mode overrides the env var for the session
_fx mode auto
_fx status
assert "`fx_mode'" == "auto"
xtile q2 = price, nq(4)
assert q2 == q

* a fast path broken on purpose: a copy of _fx_xtile that adds 1 to the first value it stores;
* verify reports it and keeps the original's value
_fx mode verify
tempfile broken
mata: l = cat(findfile("_fx_xtile.ado")); i = selectindex(strpos(l, "label var " + char(96) + "p_var'") :> 0); assert(rows(i) == 1); l = l[1..i-1] \ ("	quietly replace " + char(96) + "p_var' = " + char(96) + "p_var' + 1 in 1") \ l[i..rows(l)]; fh = fopen(st_local("broken"), "w"); for (j = 1; j <= rows(l); j++) fput(fh, l[j]); fclose(fh)
program drop _fx_xtile
run `"`broken'"'
xtile q3 = price, nq(4)
assert q3 == q
_fx status
assert `fx_vok_xtile' == 1 & `fx_vmis_xtile' == 1 & `fx_vskip_xtile' == 0
fastata status
program drop _fx_xtile

* no snapshot (here: no frame left; Stata allows 100): verify_skipped, and the fast path's result
local k 0
local rc 0
while !`rc' {
	local ++k
	capture frame create __tvf`k'
	local rc = _rc
}
xtile q5 = price, nq(4)
assert q5 == q
forvalues j = 1/`=`k' - 1' {
	frame drop __tvf`j'
}
_fx status
assert `fx_vskip_xtile' == 1

* mode original, set by _fx mode, wins over the env var too
_fx mode original
isid make

di "VERIFY_CHILD passed"
