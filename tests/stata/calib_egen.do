* calib_egen.do -- calibrations of egen's fast path (plan: C1 by-group part, C2).
*   C1 (by groups): egen pctile(p), median and iqr with by() for every group size 1..500, with
*      and without ties, over the plan's percentile list: the _gpctile/_gmedian/_giqr formulas.
*   C2 (no by): egen total, mean, sd and std without by() (summarize's arithmetic: r(sum),
*      r(mean), r(sd)) on adversarial data: magnitudes 1e-8..1e8, cancellation, constants,
*      large offsets, float values, n = 1..1e6, with and without if.
* Each case runs the original (fastata off) and the fast path (fastata on) into two double
* variables and counts observations whose values differ bitwise (missing codes included).
* Prints TEST_CALIB egen mismatches=<n> (and per-part lines); exits 9 unless n = 0.
version 16
clear all
set more off
fx_setup
quietly fastata on
_fx mode auto

mata:
real scalar _ce_nfast()
{
	pointer() scalar p
	if ((p = findexternal("_fx_cnt")) == NULL) return(0)
	if (!asarray_contains(*p, "egen")) return(0)
	return(asarray(*p, "egen")[1])
}
// Observations where a and b differ (missing codes compared as values).
real scalar _ce_diff(string scalar a, string scalar b)
{
	return(sum(st_data(., a) :!= st_data(., b)))
}
end

global CE_MIS 0
global CE_CASES 0
capture program drop ce
* ce "<egen arguments after the new variable name>": runs egen double cea = ... with fastata
* off and egen double ceb = ... with it on, counts differences
program ce
	args rhs
	capture drop cea ceb
	quietly fastata off
	quietly egen double cea = `rhs'
	quietly fastata on
	mata: st_local("n0", strofreal(_ce_nfast()))
	quietly egen double ceb = `rhs'
	mata: st_local("n1", strofreal(_ce_nfast()))
	if `n1' != `n0' + 1 {
		di as err "calib_egen: `rhs' did not run the fast path"
		exit 9
	}
	mata: st_local("d", strofreal(_ce_diff("cea", "ceb")))
	if `d' {
		di as err "calib_egen: `rhs': `d' mismatches"
		list cea ceb if cea != ceb in 1/`=min(_N, 50000)', noobs
	}
	global CE_MIS = $CE_MIS + `d'
	global CE_CASES = $CE_CASES + 1
	drop cea ceb
end

* ---- C1: by-group quantiles, group sizes 1..500
set seed 20261015
quietly {
	set obs 125250
	gen long g = .
	gen long k = _n
	* group of size s holds observations s(s-1)/2+1 .. s(s+1)/2
	replace g = ceil((sqrt(8*k + 1) - 1)/2)
	gen double xc = rnormal()*100
	gen double xt = round(rnormal()*3, .5)
	replace xt = . if runiform() < .05
	replace xt = .a if runiform() < .02
	gen float xf = runiform()
	sort g k
}
global CE_MIS0 $CE_MIS
foreach x in xc xt xf {
	foreach p in 0.5 1 2 2.5 5 10 12.5 20 25 30 33.333 33.3333 40 50 60 66.6667 70 75 80 87.5 90 95 97.5 99 99.5 {
		ce "pctile(`x'), by(g) p(`p')"
	}
	ce "median(`x'), by(g)"
	ce "iqr(`x'), by(g)"
}
local c1 = $CE_MIS - $CE_MIS0
di as txt "TEST_CALIB egen C1 by-group quantiles: cases=$CE_CASES mismatches=`c1'"

* ---- C2: summarize arithmetic (no by)
global CE_MIS0 $CE_MIS
global CE_CASES0 $CE_CASES
foreach n in 1 2 3 7 100 1000 10000 100000 1000000 {
	foreach kind in mixed cancel const offset float {
		clear
		quietly {
			set obs `n'
			if "`kind'" == "mixed" gen double x = (2*(runiform() < .5) - 1) * 10^(-8 + 16*runiform()) * (1 + runiform())
			if "`kind'" == "cancel" {
				gen double x = 10^(8*runiform()) * (1 + runiform())
				replace x = -x[_n-1]*(1 + 1e-12*runiform()) if mod(_n, 2) == 0
			}
			if "`kind'" == "const" gen double x = 0.1
			if "`kind'" == "offset" gen double x = 1e8 + runiform()*1e-3
			if "`kind'" == "float" gen float x = rnormal()*1e4
			replace x = . if runiform() < .01
			gen double u = runiform()
		}
		foreach f in total mean sd std {
			ce "`f'(x)"
			ce "`f'(x) if u < .7"
		}
	}
}
local c2 = $CE_MIS - $CE_MIS0
di as txt "TEST_CALIB egen C2 summarize arithmetic: cases=`=$CE_CASES - $CE_CASES0' mismatches=`c2'"

di as result "TEST_CALIB egen mismatches=$CE_MIS"
if $CE_MIS exit 9
