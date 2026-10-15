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

* c(type) double: pctile's default type follows it
set type double
fq "pctile p = x1, nq(6)" pctile fast
set type float

di as result "TEST_QUANT passed $FQ_N specs"
