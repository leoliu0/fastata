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

* _fx mode overrides the env var for the session (the small-data cutoff, which clear all turned
* on again, would run the original on these 74 observations)
_fx mode auto
_fx small off
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

* fast paths broken on purpose: copies of _fx_xtile (bitwise comparison) and _fx_egen (mean() by
* unsorted groups, whose result r is in the accumulation class) that run global TV_PLANT after storing
* r. Each plant changes a single value: of another variable (a number, one byte of a str# or a
* strL, a NaN payload, the sign of a zero: compared bitwise even when r has a tolerance) or of r
* itself. Verify reports it in that variable and keeps the original's data
_fx mode verify
sysuse auto, clear
quietly {
	gen strL ml = make
	gen double zn = 1
	gen double nz = 0
}
mata: _tv_b = bufio(); bufbyteorder(_tv_b, 1)
mata: _tv_nan1 = bufget(_tv_b, char((255, 254, 83, 248, 0, 0, 0, 0)), 0, "%8z", 1)
mata: _tv_nan2 = bufget(_tv_b, char((255, 254, 83, 248, 0, 0, 0, 1)), 0, "%8z", 1)
mata: st_store(7, "zn", _tv_nan1)
frame copy default tvbase
local plants `""quietly replace headroom = headroom + 1 in 7""'
local plants `"`plants' `"mata: st_sstore(9, "make", "Z" + substr(st_sdata(9, "make"), 2, .))"'"'
local plants `"`plants' `"mata: st_sstore(9, "ml", "Z" + substr(st_sdata(9, "ml"), 2, .))"'"'
local plants `"`plants' `"mata: st_store(7, "zn", _tv_nan2)"'"'
local plants `"`plants' `"mata: st_store(3, "nz", -(1e-300*1e-300))"'"'
local plants `"`plants' "quietly replace r = r + 1 in 7""'
capture program drop Fast Parse6 Mark6 Gen6
foreach f in xtile egen {
	tempfile b`f'
	local at = cond("`f'" == "xtile", "label var " + char(96) + "p_var'", "_fx store " + char(96) + "fx_token' " + char(96) + "otype' " + char(96) + "name'")
	mata: l = cat(findfile("_fx_`f'.ado")); i = selectindex(strpos(l, st_local("at")) :> 0); assert(rows(i) == 1)
	* (the inserted line, a tab and the global's name, is built with char() so that this do-file
	* does not expand the global)
	if "`f'" == "xtile" mata: l = l[1..i-1] \ (char(9) + char(36) + "TV_PLANT") \ l[i..rows(l)]
	else mata: l = l[1..i] \ (char(9) + char(36) + "TV_PLANT") \ l[i+1..rows(l)]
	mata: fh = fopen(st_local("b`f'"), "w"); for (j = 1; j <= rows(l); j++) fput(fh, l[j]); fclose(fh)
	capture program drop _fx_`f'
	run `"`b`f''"'
	foreach p of local plants {
		capture frame drop work
		frame copy tvbase work
		frame work {
			global TV_PLANT `"`p'"'
			if "`f'" == "xtile" xtile r = price, nq(4)
			else egen double r = mean(price), by(rep78)
			* the original's data: headroom, make, ml, zn's NaN and nz's +0 as before
			assert headroom == _frval(tvbase, headroom, _n) & make == _frval(tvbase, make, _n)
			assert ml == _frval(tvbase, ml, _n)
			mata: _tv_x = " " * 8; bufput(_tv_b, _tv_x, 0, "%8z", st_data(7, "zn")); assert(ascii(_tv_x)[8] == 0 & st_data(7, "zn") != st_data(7, "zn"))
			mata: bufput(_tv_b, _tv_x, 0, "%8z", st_data(3, "nz")); assert(ascii(_tv_x)[1] == 0)
		}
	}
	global TV_PLANT
	program drop _fx_`f' Fast
	capture program drop Parse6 Mark6 Gen6
}
frame drop work tvbase

di "VERIFY_CHILD passed"
