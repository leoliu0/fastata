* test_strnum.do -- fastata's destring and tostring (slice D) against the originals: fx_both runs
* every spec with fastata off and on and demands the same data (types, formats, labels, notes,
* characteristics, values bitwise, variable order, sort marker), output, return code and r(),
* and checks which path ran. The grid covers str#, strL, numeric-looking strings with junk,
* missing codes, every target type, generate/replace/force/float/ignore()/percent/dpcomma, the
* messages per variable, and the inputs that must fall back.
* Run from tests/stata after scripts/build_plugin.sh:  stata-mp -b do test_strnum.do
version 16
clear all
set more off
fx_setup
quietly fastata on

fx_testdata
quietly {
	* destring inputs
	gen str12 sa = string(xi)
	replace sa = "" in 1/50
	gen str20 sb = " " + string(x2, "%9.3f") + "  "
	replace sb = "." in 100/120
	gen strL sl2 = sb
	gen str12 sc = "$" + string(abs(xi) * 37.5, "%12.2fc")
	replace sc = "NA" in 7
	replace sc = string(abs(xi)) + "%" in 200/400
	gen str12 sd = string(x2, "%9.2f")
	replace sd = subinstr(sd, ".", ",", 1)
	replace sd = "1.234,5" in 3
	gen str4 se = cond(mod(_n, 5) == 0, ".a", cond(mod(_n, 7) == 0, ".z", cond(mod(_n, 11) == 0, ".", string(mod(_n, 90) - 40))))
	replace se = " .b " in 1
	gen str14 sx = string(zi * 1000 + 7, "%14.0f")
	gen str11 sxl = cond(mod(_n, 2), "2147483620", "-2147483647")
	gen str11 sxd = cond(mod(_n, 2), "2147483621", "5")
	gen str6 sy = cond(mod(_n, 3) == 0, "-0", string(mod(_n, 200) - 100))
	gen str10 sf = string(xf)
	replace sf = "1e-5" in 9
	gen str8 sp = string(mod(_n, 13) * 2.5) + cond(mod(_n, 4), "%", "")
	gen str10 s0 = cond(mod(_n, 3) == 0, "0007", cond(mod(_n, 3) == 1, "000", "00.25"))
	gen str12 sm = word("1e3 1d3 +5 5. .5 -.5e-2 inf nan 1,000 1E-2 0.1 -12", mod(_n, 12) + 1)
	replace sm = " " + sm + char(9) in 1/100
	gen str8 sz = ""
	gen str8 sw = char(9) + string(mod(_n, 50)) + char(10)
	gen str8 si = string(mod(_n, 30000))
	replace si = "1 000" in 5
	gen str8 sh = string(_n)
	replace sh = "1.0x+1" in 400
	gen str8 su = string(_n)
	replace su = "1" + uchar(233) in 401
	gen str10 so = string(_n * 3)
	replace so = "1e308" in 402
	gen str6 sk = cond(mod(_n, 9) == 0, "x" + string(_n), string(_n))
	* random numeric-looking strings with junk (no hexadecimal forms)
	set seed 12345
	gen str30 sr = string(round(rnormal() * 10^runiformint(-3, 9), 10^runiformint(-4, 0)), "%20.6g")
	replace sr = sr + "e" + string(runiformint(-20, 20)) if runiform() < .1
	replace sr = word("NA - . .c n/a 1/2 ? x", runiformint(1, 8)) if runiform() < .05
	replace sr = "  " + sr if runiform() < .05
	replace sr = "00" + sr if runiform() < .05
	gen strL slr = sr
	gen strL slong = cond(mod(_n, 2), 300 * "word ", string(_n))
	gen strL slnum = cond(_n == 3, 70 * "1", string(_n))
	label variable sa "a label on sa"
	label variable sb "sb: numbers with spaces"
	note sb: a note on sb
	note sb: a second note
	char sb[foo] bar
	char sa[destring] "left over"
	char sa[destring_cmd] "destring sa, replace"

	* tostring inputs
	gen double xd = round(x1)
	gen double xbig = 123456789012 + _n
	gen double xz = cond(mod(_n, 2), -0, _n)
	gen float xfi = round(xf)
	note xi: a note on xi
	char xl[who] me
	label define ylab 1 "one"
	label values xl ylab
}
frame copy default base
frame copy default bsort
frame bsort: sort sa
frame create small
frame small {
	set obs 2
	gen str4 a = "5"
	replace a = ".b" in 2
	gen double b = 3
}
frame create tiny
frame tiny {
	set obs 1
	gen str4 a = "7"
	gen int b = -3
}
frame create empty
frame empty: gen str4 a = ""

capture program drop ts
program ts
	args cmd kind ecmd frame
	if "`frame'" == "" local frame base
	* destring and tostring are not rclass: their r() leftovers are not part of the contract
	fx_both `"`cmd'"', base(`frame') expect(`ecmd' `kind')
	global TS_N = $TS_N + 1
end
global TS_N 0

* ---------------------------------------------------------------- destring, fast path
ts "destring sn, replace" fast destring
ts "destring sn, replace force" fast destring
ts "destring sn, gen(snn) force" fast destring
ts "destring sn, gen(snn) force float" fast destring
ts "destring sa, replace" fast destring
ts "destring sa, gen(na)" fast destring
ts "destring sa sb sl2, replace" fast destring
ts "destring sa sb sl2, gen(n1 n2 n3)" fast destring
ts "destring sa sb id, gen(n1 n2 n3)" fast destring
ts "destring sb sl2, replace float" fast destring
ts "destring sc, replace" fast destring
ts "destring sc, replace force" fast destring
ts `"destring sc, replace ignore("$,")"' fast destring
ts `"destring sc, gen(nc) ignore("$,%")"' fast destring
ts `"destring sc, gen(nc) ignore("$,") percent force"' fast destring
ts `"destring sc, gen(nc) ignore("$ ,")"' fast destring
ts `"destring sc, gen(nc) ignore("$,", aschars)"' fast destring
ts `"destring sc, gen(nc) ignore("$,", asbytes)"' fast destring
ts `"destring sc sn, gen(nc nn) ignore("$,NA-") force"' fast destring
ts "destring sp, replace percent" fast destring
ts "destring sp, gen(np) percent float" fast destring
ts "destring sp, replace" fast destring
ts "destring sp, replace ignore(%)" fast destring
ts "destring sd, replace dpcomma" fast destring
ts "destring sd, gen(nd) dpcomma force" fast destring
ts "destring sd, gen(nd) force" fast destring
ts "destring se, replace" fast destring
ts "destring se, gen(ne) float" fast destring
ts "destring se, gen(ne) percent ignore(%)" fast destring
ts "destring sx, replace" fast destring
ts "destring sx, replace float" fast destring
ts "destring sxl sxd, replace" fast destring
ts "destring sy, replace" fast destring
ts "destring sy, gen(ny) float" fast destring
ts "destring sf, replace" fast destring
ts "destring sf, replace float" fast destring
ts "destring s0, replace" fast destring
ts "destring sm, replace" fast destring
ts "destring sm, gen(nm) force" fast destring
ts "destring sz, replace" fast destring
ts "destring sz, gen(nz) float" fast destring
ts "destring sw, replace" fast destring
ts "destring si, replace" fast destring
ts "destring si, replace force" fast destring
ts `"destring si, replace ignore(" ")"' fast destring
ts "destring sk, replace force" fast destring
ts "destring slong, replace force" fast destring
ts "destring slong, gen(nl)" fast destring
ts `"destring sc, gen(nc) ignore("$$,,")"' fast destring
ts `"destring sn, gen(nn) ignore("-") force"' fast destring
ts `"destring sn, gen(nn) ignore("A{N}") force"' fast destring
ts "destring sx*, replace" fast destring
ts "destring sa sb sc, gen(n1-n3) force" fast destring
ts "destring sk, replace" fast destring
ts "destring sr, gen(nr) force" fast destring
ts "destring sr slr, gen(nr nlr) force float" fast destring
ts "destring sr, replace" fast destring
ts "destring s sl, replace" fast destring
ts "destring s, replace force" fast destring
ts "destring, replace" fast destring tiny
ts "destring, gen(c d)" fast destring tiny
ts "destring id x1, replace" fast destring
ts "destring sa, replace" fast destring bsort
ts "destring sb, replace" fast destring bsort
ts "destring  sa ,  gen( na )" fast destring
ts "version 15: destring sa sb, replace" fast destring
ts "destring a, replace" fast destring small
ts "destring a, gen(z) float" fast destring small
ts "destring a b, replace" fast destring tiny

* ---------------------------------------------------------------- destring, fallbacks
ts "destring sh, replace" fallback destring
ts "destring su, replace force" fallback destring
ts "destring so, replace" fallback destring
ts "destring slnum, replace" fallback destring
ts "version 13: destring sa, replace" fallback destring
ts "destring sa" fallback destring
ts "destring sa, gen(x) replace" fallback destring
ts "destring sa, gen(id)" fallback destring
ts "destring sa sb, gen(x)" fallback destring
ts "destring sa sa, replace" fallback destring
ts "destring sa sb, gen(x x)" fallback destring
ts "destring nosuch, replace" fallback destring
ts "destring sa in 1/5, replace" fallback destring
ts "destring sc, replace ignore($,)" fallback destring
ts `"destring sc, replace ignore("$", illegal)"' fallback destring
ts `"destring sc, replace ignore("$", asbytes aschars)"' fallback destring
ts `"destring sc, replace ignore("é")"' fallback destring
ts "destring a, replace" fallback destring empty
* every variable: sh, su and so need the original
ts "destring, replace force" fallback destring

* ---------------------------------------------------------------- tostring, fast path
ts "tostring id, replace" fast tostring
ts "tostring id, gen(ids)" fast tostring
ts "tostring xb xi xl, replace" fast tostring
ts "tostring xb xi xl, gen(b2 i2 l2)" fast tostring
ts "tostring xl, replace force" fast tostring
ts "tostring xl, replace" fast tostring
ts "tostring g, replace" fast tostring
ts "tostring g, replace force" fast tostring
ts "tostring g, gen(gs)" fast tostring
ts "tostring zi, replace" fast tostring
ts "tostring zi, replace format(%20.0f)" fast tostring
ts "tostring xd, replace" fast tostring
ts "tostring xd, gen(xds) force format(%5.0f)" fast tostring
ts "tostring xl, gen(zs) format(%3.0f)" fast tostring
ts "tostring xi, gen(zs) format(%1.0f)" fast tostring
ts "tostring zi, replace format(%13.0g)" fast tostring
ts "tostring xz, replace" fast tostring
ts "tostring xfi, replace format(%24.0g)" fast tostring
ts "tostring xbig, replace format(%20.0g)" fast tostring
ts "tostring sa xi, replace" fast tostring
ts "tostring sa xi s, gen(a2 i2 s2)" fast tostring
ts "tostring sa, replace" fast tostring
ts "tostring id, replace" fast tostring bsort
ts "version 8: tostring xb, replace" fast tostring
ts "tostring b, replace" fast tostring small
ts "tostring b, gen(z)" fast tostring tiny

* ---------------------------------------------------------------- tostring, fallbacks
ts "tostring x1, replace" fallback tostring
ts "tostring xbig, gen(xbs) format(%1.0f)" fallback tostring
ts "tostring zi, gen(zs) format(%3.0f)" fallback tostring
ts "tostring zi, replace format(%9.0g)" fallback tostring
ts "tostring x1, replace force" fallback tostring
ts "tostring xf, gen(xs) force" fallback tostring
ts "tostring xbig, replace" fallback tostring
ts "tostring xbig, replace format(%3.0g)" fallback tostring
ts "tostring xb, replace format(%25.0g)" fallback tostring
ts "tostring xb, replace format(%9.2f)" fallback tostring
ts "tostring xb, replace format(%12.0gc)" fallback tostring
ts "tostring xb, replace format(%9s)" fallback tostring
ts "tostring xb, replace format(junk)" fallback tostring
ts "tostring xb, replace usedisplayformat" fallback tostring
ts "tostring xb" fallback tostring
ts "tostring xb, gen(a) replace" fallback tostring
ts "tostring xb, gen(id)" fallback tostring
ts "tostring xb xi, gen(a)" fallback tostring
ts "tostring xb xb, replace" fallback tostring
ts "tostring nosuch, replace" fallback tostring
ts "tostring a, replace" fallback tostring empty

di as result "TEST_STRNUM passed $TS_N specs"
