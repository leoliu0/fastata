* test_egen.do -- egen's fast path gives what the original egen gives (fx_both: data, types,
* formats, labels, notes, sort marker, missing codes, log text, return code) over a grid of the
* 21 functions x by forms (none, by g:, by s:, bysort, by(), strL and multi-variable keys,
* groups crossing the plugin's 8192-row blocks) x samples (if, in, both) x storage types, plus
* the inputs that must fall back. Bitwise, except the accumulation class (total/sum/mean/sd/std
* with by() on unsorted data: reldif 1e-13 for double results, 2^-23 for float results).
* Prints TEST_EGEN passed <n> specs.
version 16
clear all
set more off
fx_setup
quietly fastata on
_fx mode auto

fx_testdata
quietly {
	* -0 and +0, ties, missing codes in a value; missing codes, -0 and "" in keys
	gen double xz = cond(mod(_n, 3) == 0, -1*0, cond(mod(_n, 3) == 1, 0, round(rnormal()*3)))
	replace xz = .c if mod(_n, 97) == 0
	gen double gm = cond(runiform() < .03, ., cond(runiform() < .03, .a, cond(runiform() < .05, -1*0, floor(runiform()*30))))
	gen str8 se = cond(runiform() < .05, "", "k" + string(floor(runiform()*20)))
	* group sizes 1, 2, 3, 8191, 8192, 8193 and the rest, in data order
	gen long gsz = 1
	replace gsz = 2 if _n > 1
	replace gsz = 3 if _n > 3
	replace gsz = 4 if _n > 6
	replace gsz = 5 if _n > 6 + 8191
	replace gsz = 6 if _n > 6 + 8191 + 8192
	replace gsz = 7 if _n > 6 + 8191 + 8192 + 8193
	* integer values for integer result types
	gen int xs = mod(_n, 50) - 20 if mod(_n, 13)
}
frame copy default base
frame copy default bg
frame bg: sort g id
frame copy default bs
frame bs: sort s id
frame copy default bgs
frame bgs: sort g s
frame copy default bsz
frame bsz: sort gsz

global TE_N 0
global TE_NFAIL 0
capture program drop te
* te "<command>" fast|fallback [frame] [tol] [names: fx_both's zsfree()]
program te
	args cmd kind frame tol zs
	if "`frame'" == "" local frame base
	if "`tol'" == "" local tol 0
	local zsopt
	if "`zs'" != "" local zsopt zsfree(`zs')
	capture noisily fx_both `"`cmd'"', base(`frame') expect(egen `kind') tol(`tol') `zsopt'
	if _rc {
		global TE_NFAIL = $TE_NFAIL + 1
		di as err `"TEST_EGEN FAIL: `cmd' [`frame']"'
	}
	global TE_N = $TE_N + 1
end

* ---- expression functions: by forms x samples x types
local samples `""" "if u < .5" "in 101/25000" "if x2 > -2 in 5000/29000""'
local exprfns total sum mean max min count median iqr sd std rank
foreach f of local exprfns {
	foreach smp of local samples {
		foreach ty in "" double {
			local acc = inlist("`f'", "total", "sum", "mean", "sd", "std")
			local tol = cond(`acc', cond("`ty'" == "double", 1e-13, 1.2e-7), 0)
			* xz holds -0 and +0: the sign of a zero that a by-group function selects follows
			* the random tie order of the original's sort (by the groups and the value for
			* median and iqr; by the groups, which reorders only unsorted data, for max and min)
			local zss = cond(inlist("`f'", "median", "iqr"), "v", "")
			local zsu = cond(inlist("`f'", "median", "iqr", "max", "min"), "v", "")
			* no by
			te "egen `ty' v = `f'(x1) `smp'" fast
			* by prefix on sorted data, numeric and string keys: bitwise
			if !strpos("`smp'", "in ") {
				te "by g: egen `ty' v = `f'(x2) `smp'" fast bg
				te "by s: egen `ty' v = `f'(x1) `smp'" fast bs
				te "by g s: egen `ty' v = `f'(xf) `smp'" fast bgs
				te "by gsz: egen `ty' v = `f'(x1) `smp'" fast bsz
				te "bysort gbig: egen `ty' v = `f'(xz) `smp'" fast base 0 `zss'
			}
			* by() on unsorted data
			te "egen `ty' v = `f'(x1) `smp', by(g)" fast base `tol'
			te "egen `ty' v = `f'(x2) `smp', by(sl)" fast base `tol'
			te "egen `ty' v = `f'(xz) `smp', by(gm se)" fast base `tol' `zsu'
			* by() on data sorted by the keys: bitwise
			te "egen `ty' v = `f'(x1) `smp', by(g)" fast bg
		}
	}
}

* expression forms: expressions, outer parentheses, abbreviations, float and integer variables
foreach f in total mean max min sd std median iqr rank count {
	local acc = inlist("`f'", "total", "mean", "sd", "std")
	local tol = cond(`acc', 1.2e-7, 0)
	te "egen v = `f'(x1*2 + x2)" fast
	te "egen v = `f'(((x1)))" fast
	te "egen v = `f'( xf )" fast
	te "egen v = `f'(xb), by(g)" fast base `tol'
	te "egen v = `f'(xi + xl) if xb > 0, by(gbig)" fast base `tol'
	te "by g: egen double v = `f'(xf / 3)" fast bg
	te "egen v = `f'(x1-x2)" fast
	te "egen v = `f'(x1-x2), by(g)" fast bg
}

* function options (max/min with missing and an if without in fall back: the original then
* makes its sample with gen byte, which truncates and may print a message)
foreach smp in "" "if u < .3" "in 1/12000" "if u < .3 in 1/12000" {
	local mm = cond(strpos("`smp'", "if ") & !strpos("`smp'", "in "), "fallback", "fast")
	local byp = !strpos("`smp'", "in ")
	te "egen v = total(x2) `smp', missing" fast
	te "egen v = total(x2) `smp', by(gm) missing" fast base 1.2e-7
	if `byp' te "by gsz: egen double v = total(x1) `smp', missing" fast bsz
	te "egen v = sum(x1) `smp'" fast
	te "egen v = max(x1) `smp', missing" `mm'
	te "egen v = min(x1) `smp', by(g) missing" `mm'
	if `byp' te "by s: egen float v = max(x1) `smp', missing" `mm' bs
	te "egen v = min(xz) `smp', missing" `mm'
	te "egen v = max(x1) `smp', by(gm) missing" `mm'
	foreach p in 1 10 25 33.3 50 66.6667 90 99.5 {
		te "egen v = pctile(x1) `smp', p(`p')" fast
		te "egen v = pctile(x2) `smp', by(g) p(`p')" fast
		if `byp' te "by gsz: egen double v = pctile(xz) `smp', p(`p')" fast bsz 0 v
	}
	te "egen v = pctile(x1) `smp'" fast
	te "egen v = std(x1) `smp', mean(10) sd(2)" fast
	te "egen v = std(x1) `smp', by(g) mean(-1.5) std(.5)" fast base 1.2e-7
	if `byp' te "by g: egen double v = std(x2) `smp', sd(3)" fast bg
	te "egen v = rank(x1) `smp', field" fast
	te "egen v = rank(xz) `smp', by(g) track" fast
	if `byp' te "by s: egen v = rank(xi) `smp', field" fast bs
	te "egen double v = rank(xs) `smp', by(gsz) track" fast
}

* count of strings and expressions
te "egen v = count(s)" fast
te "egen v = count(se), by(g)" fast
te "egen v = count(sl) if u < .5" fast
te "egen v = count(x1 > 0), by(se)" fast
te "egen v = count(se + s)" fast

* conditions with string literals
te `"egen v = mean(x1) if s == "s1", by(g)"' fast base 1.2e-7
te `"egen v = count(x1) if strpos(s, "1")"' fast
te `"egen v = rank(x1) if s != "s2", by(s)"' fast
te `"egen v = group(s) if s > "s1""' fast
te `"egen v = rowtotal(x1 x2) if se == """' fast
te "egen v = total(x1) if x2, by(g)" fast base 1.2e-7
te "egen v = median(x1) if xz, by(g)" fast
te "egen v = rowmean(x1 x2) if x2" fast
te "egen v = tag(g) if xz" fast

* integer result types: fit or fall back
foreach ty in byte int long {
	te "egen `ty' v = count(x1), by(g)" `=cond("`ty'" == "byte", "fallback", "fast")'
	te "egen `ty' v = count(x1), by(gsz)" `=cond("`ty'" == "byte", "fallback", "fast")'
	te "egen `ty' v = rank(xs), by(g) track" `=cond("`ty'" == "byte", "fallback", "fast")'
	te "egen `ty' v = rank(xs), by(g)" fallback
	te "egen `ty' v = max(xs), by(g)" fast
	te "egen `ty' v = min(xs) if u < .5" fast
	te "egen `ty' v = total(xs), by(gbig)" `=cond("`ty'" == "long", "fast", "fallback")'
	te "egen `ty' v = mean(x1), by(g)" fallback
	te "egen `ty' v = median(x1), by(g)" fallback
	te "version 19: egen `ty' v = group(g)" fast
	te "egen `ty' v = group(g)" fallback
	te "version 19: egen `ty' v = group(gm se), missing" `=cond("`ty'" == "byte", "fallback", "fast")'
	te "egen `ty' v = tag(g)" fast
	te "egen `ty' v = rowmiss(x1 x2 s)" fast
	te "egen `ty' v = rownonmiss(x1 x2 s), strok" fast
	te "egen `ty' v = rowtotal(xb xi)" `=cond("`ty'" == "byte", "fallback", "fast")'
	te "egen `ty' v = rowmax(xb xi xs)" `=cond("`ty'" == "byte", "fallback", "fast")'
	te "egen `ty' v = rowmin(xs xb)" fast
	te "version 16.1: egen `ty' v = group(g)" fallback
	te "version 12: egen `ty' v = group(g)" fallback
}

* ---- group and tag
foreach smp of local samples {
	foreach o in "" ", missing" {
		te "egen v = group(g) `smp' `o'" fast
		te "egen double v = group(gm se) `smp' `o'" fast
		te "egen v = group(s sl) `smp' `o'" fast
		te "egen v = group(xz gm) `smp' `o'" fast
		te "egen v = group(x1) `smp' `o'" fast
		te "egen v = tag(g) `smp' `o'" fast
		te "egen v = tag(gm se) `smp' `o'" fast
		te "egen v = tag(sl xz) `smp' `o'" fast
		te "egen v = tag(id) `smp' `o'" fast
	}
}
te "egen v = group(id zi)" fast
te "version 12: egen v = group(g s)" fast
te "egen v = group(id id2 g gbig s sl zi x1 x2 xf xb xi xl sn w fw iw th u)" fast
te "egen v = tag(id id2 g gbig s sl zi x1 x2 xf xb xi xl sn w fw iw th u)" fast
te "egen v = group(g), label" fallback
te "egen v = group(g), lname(gl)" fallback
te "egen v = group(g), autotype" fallback
te "by g: egen v = group(s)" fallback bg
te "egen v = tag(g), by(s)" fallback
te "egen v = group()" fallback

* ---- row functions
foreach smp of local samples {
	foreach ty in "" double {
		te "egen `ty' v = rowtotal(x1 x2 xf) `smp'" fast
		te "egen `ty' v = rowtotal(x1 x2 xf xz) `smp', missing" fast
		te "egen `ty' v = rowmean(x1 x2 xf) `smp'" fast
		te "egen `ty' v = rowmax(x1 x2) `smp'" fast
		te "egen `ty' v = rowmax(x2 x1 xz) `smp'" fast
		te "egen `ty' v = rowmin(x1 x2 xz) `smp'" fast
		te "egen `ty' v = rowsd(x1 x2 xf) `smp'" fast
		te "egen `ty' v = rowsd(x1 x2) `smp'" fast
		te "egen `ty' v = rowmiss(x1 x2 se sl) `smp'" fast
		te "egen `ty' v = rownonmiss(x1 x2 xz) `smp'" fast
		te "egen `ty' v = rownonmiss(x1 se sl) `smp', strok" fast
		te "egen `ty' v = rowtotal(x1-xl) `smp'" fast
		te "egen `ty' v = rowtotal(x1 x1 x2) `smp'" fast
	}
}
te "egen v = rowtotal(x1 s)" fallback
te "egen v = rowmean(x1 s)" fallback
te "egen v = rownonmiss(x1 s)" fallback
* a string variable before a numeric one (test_random case 344)
te "egen double v = rownonmiss(sl xb xi) in 13052" fallback
te "egen v = rownonmiss(s x1)" fallback
te "egen v = rowtotal(s x1 x2)" fallback
te "egen v = rowsd(x1)" fallback
te "by g: egen v = rowtotal(x1 x2)" fallback bg
te "egen v = rowmax(x1 x2), by(g)" fallback

* ---- labels and messages
te "egen v = rank( x1 )" fast
te "egen v = rank( x1 ) if u < .5" fast
te "egen v = rank((x1)) in 1/9, field" fast
te "by g: egen v = rank(x1), track" fast bg
te "egen v = rank(x1+0) , by( g )" fast
te "egen v = std( (x1) )" fast
te "egen v = std(((x2)))" fast
te "egen v = std(x1 + x2) if u > .5, by(g)" fast base 1.2e-7
te "egen v = median(x1) if x1 > 1e9" fast
te "egen v = iqr(x1) if x2 >= ." fast
te "egen v = pctile(x2) in 1/1, p(20)" fast
te "egen v = median(x1) if x1 > 1e9, by(g)" fast
te "egen v = mean(x1) in 1" fast
te "egen v = sd(x1) in 1/2" fast
te "egen v = count(x1) if 0" fast
te "egen v = tag(g) if 0" fast
te "egen v = group(g) if 0" fast

* ---- names starting with _: exact names of variables (tempvars as ado-files and do-files use
* them, _merge) run the fast path; abbreviations and reserved names fall back
tempvar a c b
frame copy base bt
frame bt {
	quietly gen double `a' = round(x1/3)
	quietly gen int `c' = mod(g, 7) if mod(id, 50)
	quietly gen byte _merge = 1 + mod(id, 3)
}
frame copy bt btg
frame btg: sort g id
te "egen `b' = max(`a'), by(g)" fast bt
te "egen double `b' = min(`a') if `a' > 0, by(`c')" fast bt
te "bysort g: egen double `b' = mean(`a')" fast bt
te "by g: egen `b' = total(`a')" fast btg
te "egen double `b' = total(`a'), by(`c')" fast bt 1e-13
te "egen `b' = rowtotal(`a' x1)" fast bt
te "egen `b' = rowmax(x1 `a' `c')" fast bt
te "egen `b' = group(`a')" fast bt
te "egen `b' = group(`c' s), missing" fast bt
te "egen `b' = tag(`a' g)" fast bt
te "egen `b' = mean(x1) if `a' > 0" fast bt
te "egen `b' = mean(x1) if `a'>0&`c'<3, by(g)" fast bt 1.2e-7
te "egen `b' = rank(`a')" fast bt
te "egen `b' = rank(`a'), by(`c') field" fast bt
te "egen `b' = median(`a' + x2), by(g)" fast bt
te "egen `b' = count(`c')" fast bt
te "egen v = mean(x1), by(_merge)" fast bt 1.2e-7
te "egen v = count(_merge), by(g)" fast bt
te "egen v = total(x1) if _merge == 3" fast bt
te "egen v = tag(_merge g)" fast bt
te "egen v = rowmiss(_merge `a' x1)" fast bt
local abbr = substr("`a'", 1, strlen("`a'") - 1)
te "egen v = mean(`abbr')" fallback bt
te "egen v = max(`abbr'), by(g)" fallback bt
te "egen v = mean(_mer)" fallback bt
te "egen v = mean(_Merge)" fallback bt
te "egen v = mean(x1) if _n > 5" fallback bt
te "egen v = total(_n)" fallback bt
te "egen v = mean(_pi*x1)" fallback bt
te "egen v = mean(_pi * `a')" fallback bt
te "egen v = mean(x1) if _b[x1] > 0" fallback bt
te "egen v = mean(`a') if _N > 5" fallback bt

* ---- NaN bit patterns (a plugin or Mata's st_store() can leave one in a variable; seen in
* dataverse-A9ZFFF, where pdslasso's lassoutils.ado runs egen group() on data holding one). A NaN
* in a variable the call does not read changes nothing: the fast path runs, and verify mode finds
* its result equal to the original's. A NaN in a key or a value runs the original (Stata takes
* it for a missing value). fx_both cannot compare such data (NaN != NaN), so tn compares every
* variable by its bits.
frame copy base bn
frame bn {
	* zn: all 1 but one NaN; zu: x2 with two NaNs
	quietly gen double zn = 1
	quietly gen double zu = x2
	mata: _te_b = bufio(); bufbyteorder(_te_b, 1)
	mata: _te_nan = bufget(_te_b, char((255, 254, 83, 248, 0, 0, 0, 0)), 0, "%8z", 1)
	mata: st_store(7, "zn", _te_nan); st_store((7 \ 20000), "zu", J(2, 1, _te_nan))
}
capture program drop tn
* tn "<command>" fast|fallback: runs the command with fastata off and on, from frame bn
program tn
	args cmd kind
	foreach f in fa fb {
		capture frame drop `f'
		frame copy bn `f'
	}
	quietly fastata off
	set sortseed 20261015
	frame fa: capture noisily `cmd'
	local rca = _rc
	quietly fastata on
	_fx status
	local k0 = cond("`kind'" == "fast", `fx_nfast_egen', `fx_nfb_egen')
	set sortseed 20261015
	frame fb: capture noisily `cmd'
	local rcb = _rc
	_fx status
	local k1 = cond("`kind'" == "fast", `fx_nfast_egen', `fx_nfb_egen')
	mata: st_local("same", strofreal(_te_samebits("fa", "fb")))
	if `rca' != `rcb' | `k1' != `k0' + 1 | !`same' {
		global TE_NFAIL = $TE_NFAIL + 1
		di as err `"TEST_EGEN FAIL: `cmd' [NaN; rc `rca' vs `rcb', path `kind' `=`k1'-`k0'', same bits `same']"'
	}
	global TE_N = $TE_N + 1
end
mata:
// 1 when frames fa and fb have the same variables with bitwise-equal values (NaN included).
real scalar _te_samebits(string scalar fa, string scalar fb)
{
	string scalar cur
	string rowvector va, vb
	string matrix a, b
	real scalar j

	cur = st_framecurrent()
	st_framecurrent(fa)
	va = st_varname(1..st_nvar())
	a = J(st_nobs(), 0, "")
	for (j = 1; j <= st_nvar(); j++) a = a, (st_isstrvar(j) ? st_sdata(., j) : strofreal(st_data(., j), "%21x"))
	st_framecurrent(fb)
	vb = st_varname(1..st_nvar())
	b = J(st_nobs(), 0, "")
	for (j = 1; j <= st_nvar(); j++) b = b, (st_isstrvar(j) ? st_sdata(., j) : strofreal(st_data(., j), "%21x"))
	st_framecurrent(cur)
	return(va == vb & a == b)
}
end
tn "egen v = group(g) if u < .5" fast
tn "egen v = mean(x1), by(g)" fast
tn "egen v = mean(zn)" fallback
tn "egen v = mean(zu), by(g)" fallback
tn "bysort g: egen v = total(zu)" fallback
* (a NaN in a key also falls back, see src/egen/tests.rs; not run here: Stata's own sort never
* returns on a NaN key, with or without fastata)
tn "egen v = rowtotal(x1 zu)" fallback
* an expression turns a NaN into . (as Stata evaluates every expression): fast path
tn "egen v = rank(zu * 2)" fast
* verify mode with a NaN in a variable the call does not read: no mismatch
frame copy bn bv
frame bv {
	_fx status
	local ok0 `fx_vok_egen'
	local bad0 = `fx_vmis_egen' + `fx_vskip_egen'
	_fx mode verify
	egen v1 = group(g) if u < .5
	egen v2 = mean(x1), by(g)
	_fx mode auto
	_fx status
	if `fx_vok_egen' != `ok0' + 2 | `fx_vmis_egen' + `fx_vskip_egen' != `bad0' {
		global TE_NFAIL = $TE_NFAIL + 1
		di as err "TEST_EGEN FAIL: verify mode with a NaN in another variable (ok +`=`fx_vok_egen'-`ok0'', not ok +`=`fx_vmis_egen'+`fx_vskip_egen'-`bad0'')"
	}
	global TE_N = $TE_N + 2
}
frame drop bv
frame drop bn

* ---- inputs that fall back
te "egen x1 = mean(x2)" fallback
te "egen v = mean(s)" fallback
te "egen v = mean(s), by(g)" fallback
te "egen v = rank(x1), unique" fallback
* fallbacks whose original breaks sort ties at random: fastata must not draw from the sort-tie
* random numbers first (test_random cases 346, 1184, 1594)
te "egen double v = rank(xs), unique" fallback
te "egen long v = rank(xs) if u < .7, unique" fallback
te "egen v = min(xs/3) if xs, by(gm se) missing" fallback
te "egen v = rank(x1), field track" fallback
te "egen v = rank(x1), suffix(x)" fallback
te "egen v = pctile(x1), p(100)" fallback
te "egen v = pctile(x1), p(0)" fallback
te "egen v = std(x1), sd(2) std(3)" fallback
te "egen v = median(x1), autotype" fallback
te "egen v = mean(x1[_n-1])" fallback
te "egen v = mean(x1) if _n > 5" fallback
te "egen v = total(_n)" fallback
te "egen v = mean(x1) if runiform() < 2" fallback
te "egen v = mean(x1) if x1 > r(mean)" fallback
te "egen v = mean(sum(x1))" fallback
te "by g: egen v = mean(x1), by(s)" fallback bg
te "by g: egen v = mean(x1) in 1/100" fallback bg
te "egen str5 v = mean(x1)" fallback
te "egen strL v = mean(x1)" fallback
te "egen v = mean(x1 x2)" fallback
te "egen v = mean(x)" fallback
te "egen v = nosuchfn(x1)" fallback
te "egen v = mode(g)" fallback
te "egen v = mean x1" fallback
te "egen v mean(x1)" fallback
te "egen v = mean(x1), nosuchoption" fallback
te "egen v = total(x1), by(nosuchvar)" fallback
te "egen v = mean(x1) if nosuchvar > 0" fallback
te "egen v = max(x1) if u < .5, missing" fallback
te "egen v = rowtotal(_all)" fallback
te "egen v = rowtotal(*)" fallback
te "egen v = rowtotal(x*)" fast
te "egen v = rowtotal(*1)" fallback
te `"egen v = rank(cond(s == "s1", x1, x2))"' fallback

* ---- group() on more than 50,000 observations: _ggroup.ado looks for the groups in a sample of
* the data (a non-quiet mata: line, {res} in an SMCL log) when the sample has an observation,
* the keys are fewer than log2(_N), numeric and integer-valued in the sample, and missing is not
* specified; otherwise it sorts (dataverse-77YTLD: egen firmtime = group(nit date_q))
frame create big
frame big {
	quietly {
		set obs 60000
		gen long nit = 1000 + floor(runiform()*3000)
		gen float date_q = yq(2004, 1) + floor(runiform()*13)
		format date_q %tq
		gen double xd = floor(runiform()*40)
		gen double xn = floor(runiform()*40) + .5
		gen byte odd = mod(_n, 2)
		gen double xh = cond(odd, floor(runiform()*40), floor(runiform()*40) + .5)
		gen double xm = cond(runiform() < .05, ., cond(runiform() < .02, .a, floor(runiform()*9)))
		gen str3 ks = "k" + string(floor(runiform()*30))
		forvalues i = 1/16 {
			gen byte b`i' = runiform() < .5
		}
	}
}
frame copy big big5
frame big5: quietly keep in 1/50000
te "egen v = group(nit date_q)" fast big
te "egen double v = group(date_q nit)" fast big
te "version 18: egen long v = group(nit date_q)" fast big
te "egen v = group(xd)" fast big
te "egen v = group(xn)" fast big
te "egen v = group(xh)" fast big
te "egen v = group(xh) if odd" fast big
te "egen v = group(xh nit) if !odd" fast big
te "egen v = group(xm nit)" fast big
te "egen v = group(xm nit), missing" fast big
te "egen v = group(nit ks)" fast big
te "egen v = group(nit) in 1/40000" fast big
te "egen v = group(nit) if nit < 0" fast big
te "egen v = group(b1-b15)" fast big
te "egen v = group(b1-b16)" fast big
te "egen v = group(nit date_q)" fast big5

* ---- -0 and +0 among the values (xz). _pctile orders them as ties in an order of its own:
* median, pctile and iqr without by-groups fall back. Of equal max or min values, summarize (no
* by-groups, no missing) returns the first, _gmax and _gmin (by-groups, missing) the last; on
* data sorted by the groups that order is the data order
te "egen v = median(xz) if xz == 0" fallback
te "egen v = pctile(xz) in 1/300, p(30)" fallback
te "egen v = iqr(xz)" fallback
te "egen double v = median(xz) if xz != 0" fast
te "egen double v = median(xz) if xz == 0, by(gbig)" fast base 0 v
te "egen v = min(xz) if xz == 0" fast
te "egen v = max(xz) if xz >= 0" fast
te "egen v = max(xz) in 1/20000, missing" fast
te "egen v = min(xz) in 2/30000, missing" fast
te "egen v = max(xz) if xz == 0, by(g)" fast bg
te "egen v = min(xz) if xz <= 0, by(g)" fast bg
te "by g: egen double v = max(xz) if xz == 0" fast bg
te "by g: egen v = min(xz), missing" fast bg
te "egen double v = max(xz*x1), by(g) missing" fast bg
te "egen double v = min(0*x1) if x1 < ., by(g)" fast bg
te "by gsz: egen v = max(xz) if xz == 0" fast bsz
te "egen v = max(xz) if xz == 0, by(g)" fast base 0 v

* ---- intermediate results beyond . (rust_kernels F1): Stata keeps a finite result past . raw
* (positive: a missing value the next operation turns into ., negative: a number), stores
* +-inf as ., and sum() adds a -inf; the fast path falls back [overflow] where its f64
* arithmetic would differ. g=1 (8e307 x2), g=2 (-8e307 x3), g=3 (1e160, -1e160, 0),
* g=4 (+-6e307 x2); w*y is -inf in observation 1, z*y is past . there.
capture program drop tw
* tw "<command>" <frame> <reason>: falls back for <reason>, with the original's result
program tw
	args cmd frame why
	capture noisily fx_both `"`cmd'"', base(`frame') expect(egen fallback)
	if _rc | `"`fxb_why'"' != `"`why'"' {
		global TE_NFAIL = $TE_NFAIL + 1
		di as err `"TEST_EGEN FAIL: `cmd' [`frame'; reason `fxb_why', not `why']"'
	}
	global TE_N = $TE_N + 1
end
frame create bov
frame bov {
	quietly {
		set obs 12
		gen byte g = cond(_n <= 2, 1, cond(_n <= 5, 2, cond(_n <= 8, 3, 4)))
		gen double x = cond(_n <= 2, 8e307, cond(_n <= 5, -8e307, cond(mod(_n, 2), 6e307, -6e307)))
		replace x = 1e160 in 6
		replace x = -1e160 in 7
		replace x = 0 in 8
		gen double y = cond(_n == 1, 8e307, 2)
		gen double w = cond(_n == 1, -8e307, 1)
		gen double z = 1 + mod(_n, 3)
		gen double q = cond(_n <= 4, x, cond(_n <= 6, _n - 4, .))
		sort g
	}
}
foreach f in total sum mean sd std {
	tw "by g: egen double v = `f'(x)" bov overflow
	tw "egen double v = `f'(x), by(g)" bov overflow
	tw "by g: egen v = `f'(x) if g == 1" bov overflow
	tw "egen double v = `f'(w*y) if g == 1, by(g)" bov overflow
	tw "by g: egen double v = `f'(w*y + z)" bov overflow
}
tw "by g: egen double v = total(x) if g == 2" bov overflow
te "by g: egen double v = total(x) if g == 3" fast bov
te "by g: egen double v = mean(x) if g == 4" fast bov
tw "by g: egen double v = sd(x) if g == 3" bov overflow
tw "by g: egen double v = sd(x) if g == 4" bov overflow
tw "by g: egen double v = std(x) if g == 4, mean(1)" bov overflow
tw "by g: egen double v = median(x) if g == 1" bov overflow
tw "egen double v = pctile(x) if g == 1, by(g) p(50)" bov overflow
tw "by g: egen double v = iqr(x) if g == 4" bov overflow
te "by g: egen double v = iqr(x) if g <= 2" fast bov
te "by g: egen double v = median(x) if g == 4" fast bov
te "by g: egen double v = total(z*y)" fast bov
tw "egen double v = rowtotal(x x) if g == 2" bov overflow
tw "egen double v = rowtotal(x x), missing" bov overflow
tw "egen double v = rowmean(x x z) if g == 2" bov overflow
tw "egen double v = rowsd(x x) if g == 2" bov overflow
te "egen double v = rowtotal(x x) if g == 3" fast bov
te "egen double v = rowmean(x z) if g >= 3" fast bov
tw "egen double v = iqr(q)" bov overflow
te "egen double v = iqr(q) in 3/12" fast bov

* ---- state functions (stata_fastpaths F1): regexs() and its kin return the match of the
* latest regexm() call, which the original evaluates together with the if condition
tw `"egen m = max(real(regexs(1))) if regexm(s, "(.+)"), by(g)"' base state
tw `"egen double m = mean(real(ustrregexs(1))) if ustrregexm(s, "(.+)"), by(g)"' base state
tw `"egen m = min(real(regexcapture(1))) if regexmatch(s, "(.+)")"' base state
tw `"by g: egen m = total(real(regexs(1))) if regexm(s, "(.+)")"' bg state

* ---- chained time-series operators (stata_fastpaths F2): the original sorts by the by()
* variables first and then fails (not sorted)
frame create bts
frame bts {
	quietly {
		set obs 400
		gen int pid = ceil(_n/20)
		gen int t = mod(_n - 1, 20)
		gen double x = rnormal()
		gen byte gg = mod(_n, 7)
		tsset pid t
	}
}
foreach op in LD DL L2D D2L LS FD {
	tw "egen double m = mean(`op'.x), by(gg)" bts subscript
	tw "egen double m = total(`op'.x) if x > 0, by(pid)" bts subscript
}

if $TE_NFAIL {
	di as err "TEST_EGEN failed: $TE_NFAIL of $TE_N specs (lines TEST_EGEN FAIL above)"
	exit 9
}
di as result "TEST_EGEN passed $TE_N specs"
