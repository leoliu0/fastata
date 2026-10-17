* test_fallback.do -- fastata's layer is transparent: with _fx mode original, every replaced
* command runs its original through the shim, and fx_both finds the same data, output, return
* code and r() (all of it) as with fastata off, for a grid of specs across the seven commands:
* by forms, if/in, weights, types, missing codes, string and strL keys, and error cases. Then the
* small-data cutoff (on: the original, counted as fallback "small data"; off: the fast path), and
* a store that cannot use the plugin (drops its new variables).
version 16
clear all
set more off
fx_setup
quietly fastata on
_fx mode original

fx_testdata
* a cutpoint variable for xtile: the original loops over every observation of it
gen double cp = -10 + 2.5*_n if _n <= 9
frame copy default base
frame copy default bg
frame bg: sort g id

capture program drop fb
program fb
	args cmd ecmd frame
	if "`frame'" == "" local frame base
	fx_both `"`cmd'"', base(`frame') allr expect(`ecmd' fallback)
	global FB_N = $FB_N + 1
end
global FB_N 0

* egen
fb "egen m = mean(x1)" egen
fb "egen double m = mean(x1), by(g)" egen
fb "bysort g: egen float m = sd(xf)" egen
fb "by g: egen m = total(x2)" egen bg
fb "by g, rc0: egen m = mean(x1)" egen bg
fb "egen t = tag(g s)" egen
fb "egen gg = group(s g), missing" egen
fb "egen gl = group(g), label" egen
fb "egen r = rank(x1), by(g) field" egen
fb "egen md = median(x2) if u < .5, by(gbig)" egen
fb "egen p = pctile(x1) in 100/20000, p(90)" egen
fb "egen c = count(x2), by(s)" egen
fb "egen mx = max(xi), by(g)" egen
fb "egen mn = min(xb) if g > 3" egen
fb "egen tot = total(x1), missing" egen
fb "egen z = iqr(x2), by(sl)" egen
fb "egen rt = rowtotal(x1 x2 xf)" egen
fb "egen rm = rowmean(x1 x2)" egen
fb "egen rmi = rowmiss(x1 x2 xf)" egen
fb "egen rs = rowsd(x1 x2 xf)" egen
fb "egen st = std(x1), by(g)" egen
fb "version 12: egen z = group(g)" egen
fb "egen x1 = mean(x2)" egen
fb "egen z = nosuchfn(x1)" egen
fb "egen z = rank(x1), field track" egen
fb "by g: egen z = mean(x1), by(s)" egen bg

* isid
fb "isid id" isid
fb "isid id2" isid
fb "isid g id" isid
fb "isid x2" isid
fb "isid x2, missok" isid
fb "isid s sl id" isid
fb "isid zi" isid
fb "isid nosuchvar" isid
fb "isid id, sort" isid bg

* duplicates
fb "duplicates report g" duplicates
fb "duplicates report id" duplicates
fb "duplicates report" duplicates
fb "duplicates examples gbig" duplicates
fb "duplicates list gbig s if id < 30" duplicates
fb "duplicates tag g s, gen(dt)" duplicates
fb "duplicates tag id2 if u < .5, gen(dt)" duplicates
fb "duplicates drop g s, force" duplicates
fb "duplicates drop" duplicates
fb "duplicates drop id2, force" duplicates
fb "duplicates drop g" duplicates

* xtile
fb "xtile q = x1, nq(10)" xtile
fb "xtile q = x2 if u < .5, nq(4)" xtile
fb "xtile q = x1 [aw=w], nq(5)" xtile
fb "xtile q = x1 [fw=fw], nq(3)" xtile
fb "xtile q = x1, cutpoints(cp)" xtile
fb "xtile q = xf, nq(5) altdef" xtile
fb "xtile q = x1, nq(1)" xtile

* pctile
fb "pctile p = x1, nq(10)" pctile
fb "pctile p = x1, nq(4) genp(pp)" pctile
fb "pctile p = x2 [aw=w], nq(20)" pctile
fb "pctile p = x1, altdef nq(5)" pctile
fb "pctile p = x1, nq(30002)" pctile

* destring
fb "destring sn, replace" destring
fb "destring sn, replace force" destring
fb "destring sn, gen(snn) force" destring
fb `"destring sn, gen(snn) ignore("NA-")"' destring
fb "destring sn, gen(snn) float force" destring
fb "destring id, replace" destring
fb "destring s, gen(sx)" destring
fb "destring sn s, replace force" destring

* tostring
fb "tostring id, replace" tostring
fb "tostring x1, replace" tostring
fb "tostring x1, replace force" tostring
fb "tostring zi, gen(zs)" tostring
fb "tostring xb xi, gen(b2 i2)" tostring
fb "tostring x1, gen(x1s) format(%9.2f) force" tostring
fb "tostring xf, replace usedisplayformat force" tostring
fb "tostring g, replace" tostring

_fx mode auto

* the small-data cutoff: with it on, a call on few observations runs the original right away
* (counted as fallback "small data") with the same data, output and r(); with it off (as
* fx_setup leaves it), the same call takes the fast path. On data above the call's cutoff the
* fast path runs with the cutoff on too, and xtile, which has no cutoff, always takes it.
frame copy base sm
frame sm: quietly keep in 1/60
frame copy sm smg
frame smg: sort g id
capture program drop fs
program fs
	args cmd ecmd frame opts
	_fx small on
	fx_both `"`cmd'"', base(`frame') allr expect(`ecmd' fallback)
	assert `"`fxb_why'"' == "small data"
	_fx small off
	fx_both `"`cmd'"', base(`frame') expect(`ecmd' fast) `opts'
	global FB_N = $FB_N + 2
end
fs "egen double m = mean(x1), by(g)" egen sm tol(1e-13)
fs "by g: egen double m = mean(x1)" egen smg tol(1e-13)
fs "egen double rt = rowtotal(x1 x2)" egen sm
fs "egen gg = group(s g)" egen sm
fs "isid id" isid sm
fs "duplicates report g" duplicates sm allr
fs "duplicates tag g, gen(dt)" duplicates sm allr
fs "pctile double p = x1, nq(4)" pctile sm
fs "destring sn, replace force" destring sm
fs "tostring zi, gen(zs)" tostring sm
_fx small on
fx_both "egen double m = mean(x1), by(g)", base(base) expect(egen fast) tol(1e-13)
fx_both "xtile q = x1, nq(4)", base(sm) expect(xtile fast)
_fx small off
global FB_N = $FB_N + 2
frame drop sm smg

* _fx store drops the new (nofill) variables and fails when _fx_call cannot use the plugin (a
* copy of _fx_call that expects another plugin version): no unwritten variable is left
frame copy base st
frame st {
	tempfile badcall
	mata: l = cat(findfile("_fx_call.ado")); i = selectindex(strpos(l, "local fx_version ") :> 0); assert(rows(i) == 1); l[i] = char(9) + "local fx_version 9.9.9"; fh = fopen(st_local("badcall"), "w"); for (j = 1; j <= rows(l); j++) fput(fh, l[j]); fclose(fh)
	capture program drop _fx_call
	run `"`badcall'"'
	local k0 = c(k)
	capture _fx store 1 double newv
	assert _rc == 9999
	assert c(k) == `k0'
	capture confirm variable newv
	assert _rc == 111
	program drop _fx_call _fx_plugin
}
frame drop st
global FB_N = $FB_N + 1

* a do-file that resets the ado-path after fastata's programs were loaded leaves the runtime
* directory off the path; _fx_call (here dropped, as if it had never been loaded) can then not
* be found, so a call that would take the fast path runs the original instead (reason
* "runtime directory off the ado-path"), with the original's results
frame copy base ap
frame ap {
	quietly fastata off
	set sortseed 1
	egen double m0 = mean(x1), by(g)
	quietly fastata on
	isid id
	egen double m1 = mean(x1), by(g)
	drop m1
	capture program drop _fx_call
	local ado0 `"$S_ADO"'
	global S_ADO "BASE;SITE;.;PERSONAL;PLUS;OLDPLACE"
	capture noisily isid id2
	local rc1 = _rc
	set sortseed 1
	capture noisily egen double m = mean(x1), by(g)
	local rc2 = _rc
	global S_ADO `"`ado0'"'
	assert `rc1' == 459 & `rc2' == 0
	assert m == m0
	_fx status
	assert `"`fx_last_isid'"' == "runtime directory off the ado-path"
	assert `"`fx_last_egen'"' == "runtime directory off the ado-path"
}
frame drop ap
global FB_N = $FB_N + 1

di as result "TEST_FALLBACK passed $FB_N specs"
