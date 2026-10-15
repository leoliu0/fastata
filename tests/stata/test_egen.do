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
* te "<command>" fast|fallback [frame] [tol]
program te
	args cmd kind frame tol
	if "`frame'" == "" local frame base
	if "`tol'" == "" local tol 0
	capture noisily fx_both `"`cmd'"', base(`frame') expect(egen `kind') tol(`tol')
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
			* no by
			te "egen `ty' v = `f'(x1) `smp'" fast
			* by prefix on sorted data, numeric and string keys: bitwise
			if !strpos("`smp'", "in ") {
				te "by g: egen `ty' v = `f'(x2) `smp'" fast bg
				te "by s: egen `ty' v = `f'(x1) `smp'" fast bs
				te "by g s: egen `ty' v = `f'(xf) `smp'" fast bgs
				te "by gsz: egen `ty' v = `f'(x1) `smp'" fast bsz
				te "bysort gbig: egen `ty' v = `f'(xz) `smp'" fast
			}
			* by() on unsorted data
			te "egen `ty' v = `f'(x1) `smp', by(g)" fast base `tol'
			te "egen `ty' v = `f'(x2) `smp', by(sl)" fast base `tol'
			te "egen `ty' v = `f'(xz) `smp', by(gm se)" fast base `tol'
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
		if `byp' te "by gsz: egen double v = pctile(xz) `smp', p(`p')" fast bsz
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

if $TE_NFAIL {
	di as err "TEST_EGEN failed: $TE_NFAIL of $TE_N specs (lines TEST_EGEN FAIL above)"
	exit 9
}
di as result "TEST_EGEN passed $TE_N specs"
