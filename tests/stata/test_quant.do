* test_quant.do -- xtile and pctile: fx_both runs every spec with fastata off (the original) and
* on, and requires identical data (bitwise), output and return code, and the expected path (fast or
* fallback); r() is not compared (xtile and pctile are not r-class: their leftovers are a
* documented exception). Covers nquantiles() defaults, if/in, weights (aw/fw/pw), altdef,
* expressions, ties and nonunique percentiles, extended missing codes, result types, sort
* order, a dataset large enough for several plugin chunks, and every fallback class.
version 16
clear all
set more off
fx_setup
quietly fastata on

fx_testdata
gen double cp = -10 + 2.5*_n if _n <= 9
gen double xneg = -abs(x2)
gen double xc = round(x1, 5)
* zz: +0 in odd and -0 in even observations (Stata expressions turn -0 into 0; Mata stores it)
gen double zz = 0
mata: st_store(selectindex(mod(1::st_nobs(), 2) :== 0), "zz", J(floor(st_nobs()/2), 1, -(1e-300*1e-300)))
frame copy default base
frame copy default bg
frame bg: sort g id

* 3 x 70,000 observations: several plugin chunks (65,536 rows each)
frame create big
frame big {
	set seed 271828
	quietly {
		set obs 210000
		gen double x = rnormal()*100
		replace x = .a if runiform() < .01
		replace x = . if runiform() < .02
		gen double xt = round(rnormal()*5)
		gen double w = runiform() + .2
		replace w = . if runiform() < .01
		gen int fw = ceil(runiform()*3)
		gen double u = runiform()
	}
}

capture program drop fq
program fq
	args cmd ecmd kind frame
	if "`frame'" == "" local frame base
	fx_both `"`cmd'"', base(`frame') expect(`ecmd' `kind')
	global FQ_N = $FQ_N + 1
end
global FQ_N 0

* ---------------------------------------------------------------- xtile, fast
fq "xtile q = x1, nq(10)" xtile fast
fq "xtile q = x1" xtile fast
fq "xtile q = x2 if u < .5, nq(4)" xtile fast
fq "xtile q = x1 in 100/20000, nq(7)" xtile fast
fq "xtile q = x1 if g > 10 in 5/25000, nq(3)" xtile fast
fq "xtile q = xf, nq(5) altdef" xtile fast
fq "xtile q = x2 if th < .3, nq(9) altdef" xtile fast
fq "xtile q = xb, nq(10)" xtile fast
fq "xtile q = xb, nq(100)" xtile fast
fq "xtile q = xc, nq(150)" xtile fast
fq "xtile q = xi, nq(200)" xtile fast
fq "xtile q = x1, nq(1000)" xtile fast
fq "xtile q = x1, nq(1001)" xtile fast
fq "xtile q = xl, nq(20)" xtile fast
fq "xtile q = xneg, nq(6)" xtile fast
fq "xtile q = zi, nq(10)" xtile fast
fq "xtile q = x1 [aw=w], nq(5)" xtile fast
fq "xtile q = x1 [aweight=w], nq(4)" xtile fast
fq "xtile q = x1 [fw=fw], nq(3)" xtile fast
fq "xtile q = xb [fw=fw], nq(12)" xtile fast
fq "xtile q = x2 [pw=w] if u < .7, nq(8)" xtile fast
fq "xtile q = x1 [aw=fw] in 1/9000, nq(10)" xtile fast
fq "xtile q = x1*2 + x2, nq(4)" xtile fast
fq "xtile q = log(xf) if xf > 0, nq(6)" xtile fast
fq "xtile double q = x1, nq(4)" xtile fast
fq "xtile q = x1, nquantiles(5)" xtile fast
fq "xtile q=x1,nq(5)" xtile fast
fq "xtile q = x1, nq(4)" xtile fast bg
fq "xtile q = x2 if id < 50, nq(30)" xtile fast
fq "xtile q = x2 if id < 3, nq(3)" xtile fast
fq "xtile q = x, nq(10)" xtile fast big
fq "xtile q = xt, nq(100)" xtile fast big
fq "xtile q = x if u < .6, nq(7) altdef" xtile fast big
fq "xtile q = x [fw=fw], nq(5)" xtile fast big
fq "xtile q = xt [aw=fw] if u > .2, nq(9)" xtile fast big
fq "xtile q = x [aw=w], nq(4)" xtile fast big

* random functions in exp: evaluated under xtile.ado's version 6 for the if/in sample only, so
* the same seed gives the same draws (fx_both does not reset the seed, so compare by hand)
foreach m in off on {
	capture frame drop r_`m'
	frame copy base r_`m'
	quietly fastata `m'
	frame r_`m' {
		set seed 7
		xtile q = x1 + runiform() if u < .5, nq(5)
	}
}
fx_cmpframes r_off r_on, tol(0) what("xtile with runiform()")
frame drop r_off
frame drop r_on
global FQ_N = $FQ_N + 1

mata:
// (fast, fallback) calls of fastata's cmd this session
real rowvector _tq_counts(string scalar cmd)
{
	pointer() scalar p

	if ((p = findexternal("_fx_cnt")) == NULL) return((0, 0))
	if (!asarray_contains(*p, cmd)) return((0, 0))
	return(asarray(*p, cmd))
}
end
* random functions and a fallback after the fast path evaluated exp or if: the original must
* draw the same numbers, and a later draw must match. rq "<cmd>" fast|fallback ["<reason>"]
* runs cmd (under capture) and then gen after = runiform() from seed 7, with fastata off and on
capture program drop rq
program rq
	args cmd kind why
	local c : word 1 of `cmd'
	foreach m in off on {
		capture frame drop r_`m'
		frame copy base r_`m'
		quietly fastata `m'
		if "`m'" == "on" mata: _rq0 = _tq_counts("`c'")
		frame r_`m' {
			set seed 7
			capture noisily `cmd'
			local rc_`m' = _rc
			gen double after = runiform()
		}
	}
	mata: _rq1 = _tq_counts("`c'")
	mata: st_local("nfast", strofreal(_rq1[1] - _rq0[1])); st_local("nfb", strofreal(_rq1[2] - _rq0[2]))
	if "`kind'" == "fast" assert `nfast' == 1 & `nfb' == 0
	else {
		mata: st_local("w", asarray(*findexternal("_fx_why"), "`c'"))
		if `nfb' != 1 | `"`w'"' != `"`why'"' {
			di as err `"`cmd': expected fallback [`why'], got `nfast' fast, `nfb' fallback [`w']"'
			exit 9
		}
	}
	assert `rc_off' == `rc_on'
	fx_cmpframes r_off r_on, tol(0) what(`"`cmd', then runiform()"')
	frame drop r_off
	frame drop r_on
	global FQ_N = $FQ_N + 1
end
rq "pctile double p = zz*(1+0*runiform()), nq(4)" fallback "signed zero"
rq "pctile p = x1*(1+0*runiform()) if u > 2, nq(4)" fallback error
rq "xtile q = .*runiform(), nq(2)" fallback error
rq "xtile q = zz if runiform() < .5, nq(3)" fallback "signed zero"
rq "xtile q = zz [aw=w] if rnormal() > 0, nq(3)" fallback "signed zero"
rq "xtile q = x1 + runiform() if u < .5, nq(5)" fast
rq "pctile p = x1 + rnormal(), nq(7)" fast

* state-dependent functions: r() (xtile.ado replaces it with count's before it evaluates exp
* when nquantiles() is given), s() and regexs()/ustrregexs()
capture program drop qr1
program qr1
	quietly summarize x1
	xtile q = x1 - r(mean), nq(4)
end
capture program drop qr2
program qr2
	quietly summarize x1
	xtile q = x1 if x1 > r(mean), nq(4)
end
capture program drop qr3
program qr3
	quietly summarize x1
	pctile p = x1 - r(mean) if x1 > r(min) + 1, nq(4)
end
capture program drop qr4
program qr4
	quietly summarize x1
	xtile q = x1 - r(mean)
end
fq "qr1" xtile fallback
fq "qr2" xtile fast
fq "qr3" pctile fast
fq "qr4" xtile fast
fq `"xtile q = x1 if regexm(s, "s(1)") & regexs(1) == "1", nq(3)"' xtile fallback
fq `"pctile p = x1 + (ustrregexs(0) == ""), nq(3)"' pctile fallback
fq `"xtile q = x1 + (s(weight) == ""), nq(3)"' xtile fallback

* a variable name followed by if or in is read directly; pctile.ado takes exp as a variable list
* when confirm variable accepts it (x1 x2), else as an expression (x1-x2 is a difference)
fq "pctile p = x1 if u < .5, nq(4)" pctile fast
fq "pctile double p = xf in 10/20000, nq(9)" pctile fast
fq "xtile q = xf  if u < .5 , nq(4)" xtile fast
fq "pctile p = x1 x2, nq(4)" pctile fallback
fq "pctile p = x1-x2, nq(4)" pctile fast
fq "xtile q = x1-x2, nq(4)" xtile fast

* ---------------------------------------------------------------- xtile, fallback
fq "xtile q = x1 if x1 > 1000, nq(4)" xtile fallback
fq "xtile q = x1, nq(1)" xtile fallback
fq "xtile q = x1, nq(0)" xtile fallback
fq "xtile q = x1, nq(04)" xtile fallback
fq "xtile q = x1, nq(2000)" xtile fallback
fq "xtile q = x1, nq(30002)" xtile fallback
fq "xtile q = x2 if id < 3, nq(4)" xtile fallback
fq "xtile q = x1, cutpoints(cp)" xtile fallback
fq "xtile q = x1, nq(4) cutpoints(cp)" xtile fallback
fq "xtile q = x1 [w=w], nq(4)" xtile fallback
fq "xtile q = x1 [weight=w], nq(4)" xtile fallback
fq "xtile q = x1 [aw=w*2], nq(4)" xtile fallback
fq "xtile q = x1 [iw=iw], nq(4)" xtile fallback
fq "xtile q = x1 [aw=w], nq(4) altdef" xtile fallback
fq "xtile q = x1 [fw=w], nq(4)" xtile fallback
fq "xtile q = x1 [aw=iw], nq(4)" xtile fallback
fq "xtile q = x1 [aw=s], nq(4)" xtile fallback
fq "xtile q = s, nq(4)" xtile fallback
fq "xtile q = sl, nq(4)" xtile fallback
fq "xtile x1 = x2, nq(4)" xtile fallback
fq `"xtile q = x1 if s == "s1", nq(4)"' xtile fast
fq `"xtile q = x1 * (s == "s1"), nq(2)"' xtile fallback
fq "xtile q = nosuchvar, nq(4)" xtile fallback
fq "xtile q = x1, nq(4) bogus" xtile fallback
fq "xtile q = x1 if nosuchvar > 1, nq(4)" xtile fallback

* ---------------------------------------------------------------- pctile, fast
fq "pctile p = x1, nq(10)" pctile fast
fq "pctile p = x1" pctile fast
fq "pctile double p = x2 if u < .5, nq(20)" pctile fast
fq "pctile float p = x2 in 10/400, nq(7)" pctile fast
fq "pctile p = x1 [aw=w], nq(5)" pctile fast
fq "pctile p = x1 [fw=fw], nq(8)" pctile fast
fq "pctile p = x1 [pw=w] in 1/5000, nq(4)" pctile fast
fq "pctile p = xf, nq(5) altdef" pctile fast
fq "pctile double p = x2 if th > .2, nq(13) altdef" pctile fast
fq "pctile p = x1*2, nq(100)" pctile fast
fq "pctile double p = x1, nq(1001)" pctile fast
fq "pctile p = xb, nq(50)" pctile fast
fq "pctile p = xb [fw=fw], nq(50)" pctile fast
fq "pctile p = xi if g < 5, nq(3)" pctile fast
fq "pctile p = zi, nq(4)" pctile fast
fq "pctile p = x2 if id < 4, nq(30)" pctile fast
fq "pctile p = x1, nq(4)" pctile fast bg
fq "pctile double p = x, nq(100)" pctile fast big
fq "pctile p = xt [fw=fw] if u < .5, nq(10)" pctile fast big
fq "pctile double p = x [aw=w], nq(3)" pctile fast big

* ---------------------------------------------------------------- pctile, fallback
fq "pctile byte p = x1, nq(4)" pctile fallback
fq "pctile long p = x1, nq(4)" pctile fallback
fq "pctile p = x1, nq(4) genp(pp)" pctile fallback
fq "pctile p = x1, nq(1002)" pctile fallback
fq "pctile p = x1, nq(30002)" pctile fallback
fq "pctile p = x1, nq(1)" pctile fallback
fq "pctile p = s, nq(4)" pctile fallback
fq "pctile p = x1 if x1 > 1e6, nq(4)" pctile fallback
fq "pctile p = x1 [w=w], nq(4)" pctile fallback
fq "pctile p = x1 [aw=w], nq(4) altdef" pctile fallback
fq "pctile p = x1 [fw=w], nq(4)" pctile fallback
fq "pctile p = x1, nq(2.5)" pctile fallback
fq "pctile x2 = x1, nq(4)" pctile fallback
fq "pctile str5 p = x1, nq(4)" pctile fallback
frame copy base bnan
frame bnan {
	* NaN bit patterns (a plugin or Mata's st_store() can leave one in a variable): xn (x1), wn and fwn (weights)
	quietly gen double xn = x1
	quietly gen double wn = u + .2
	quietly gen double fwn = fw
	mata: _tn_b = bufio(); bufbyteorder(_tn_b, 1)
	mata: _tn_nan = bufget(_tn_b, char((255, 254, 83, 248, 0, 0, 0, 0)), 0, "%8z", 1)
	mata: st_store((3 \ 25000), "xn", J(2, 1, _tn_nan)); st_store(17, "wn", _tn_nan); st_store(9000, "fwn", _tn_nan)
}
* ---------------------------------------------------------------- NaN values
* a NaN in x or in the weight runs the original (marksample takes it for missing, the kernels
* for a number); in an expression it becomes . and stays fast; elsewhere it changes nothing
fq "xtile q = xn, nq(4)" xtile fallback bnan
fq "xtile q = x1 [aw=wn], nq(4)" xtile fallback bnan
fq "xtile q = x2 [fw=fwn], nq(3)" xtile fallback bnan
fq "pctile p = xn, nq(5)" pctile fallback bnan
fq "pctile double p = x1 [pw=wn], nq(4)" pctile fallback bnan
fq "xtile q = xn + 0, nq(4)" xtile fast bnan
fq "pctile p = xn * 1, nq(4)" pctile fast bnan
fq "xtile q = x1, nq(10)" xtile fast bnan
fq "pctile p = x2 [aw=u], nq(4)" pctile fast bnan


* ---------------------------------------------------------------- values near the largest double
* the average of two values below -8.988e307 is -inf (_pctile returns .); a total weight times
* nq beyond the largest double
frame create bovf
frame bovf {
	quietly {
		set obs 40
		gen long id = _n
		gen double xp = 8.9e307 - (_n - 1) * 1e305
		gen double xn = -xp
		gen double xr = -8e307 * 2 - _n * 1e304 in 1/20
		replace xr = 8e307 - _n * 1e300 in 21/40
		gen double xr2 = -8e307 * 2 - _n * 1e305
		gen double xm = cond(mod(_n, 2), 8.98e307, -8.98e307)
		gen double xf = 1.7014118e38 + (_n - 20) * 1e31
		gen double xf2 = 3e38 * (_n - 20)
		gen double wbig = 8e307
		gen double wmid = 1e306
		gen double fbig = 4e307
		gen double fmid = 1e306
		gen double one = 1
		gen double xs = _n
	}
}
fq "pctile double p = xp, nq(4)" pctile fast bovf
fq "pctile double p = xn, nq(4)" pctile fast bovf
fq "pctile double p = xm, nq(4)" pctile fast bovf
fq "pctile double p = xm, nq(5) altdef" pctile fast bovf
fq "pctile double p = xr, nq(4)" pctile fallback bovf
fq "pctile double p = xr2, nq(4)" pctile fallback bovf
fq "pctile double p = xr2, nq(3) altdef" pctile fast bovf
fq "pctile double p = xr2, nq(3)" pctile fast bovf
fq "pctile float p = xf, nq(4)" pctile fast bovf
fq "pctile float p = xf2, nq(5) altdef" pctile fast bovf
fq "pctile double p = xs [aw=wbig], nq(4)" pctile fallback bovf
fq "pctile double p = xs [fw=fbig], nq(4)" pctile fallback bovf
fq "pctile double p = xs [aw=wmid], nq(4)" pctile fast bovf
fq "pctile double p = xs [fw=fmid], nq(4)" pctile fast bovf
fq "pctile double p = xr2 [aw=one], nq(4)" pctile fallback bovf
fq "pctile double p = xn*2, nq(4)" pctile any bovf
fq "xtile q = xr2, nq(4)" xtile fallback bovf
fq "xtile q = xr, nq(4)" xtile any bovf
fq "xtile q = xm, nq(4)" xtile fast bovf
fq "xtile q = xr2, nq(3) altdef" xtile fast bovf
fq "xtile q = xs [aw=wbig], nq(4)" xtile fallback bovf
fq "xtile q = xs [aw=wmid], nq(4)" xtile fast bovf
fq "xtile q = xr2 [aw=one], nq(4)" xtile fallback bovf
fq "xtile q = xn*2, nq(4)" xtile any bovf
fq "xtile q = xp*2, nq(4)" xtile fallback bovf

* c(type) double: pctile's default type follows it
set type double
fq "pctile p = x1, nq(6)" pctile fast
set type float

di as result "TEST_QUANT passed $FQ_N specs"
