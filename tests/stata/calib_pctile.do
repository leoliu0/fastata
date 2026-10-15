* calib_pctile.do -- calibration C1: fastata's percentiles (plugin command quant, the code behind
* the xtile and pctile fast paths) against Stata's _pctile, bitwise, on
*   n = 1..2000 observations (every n up to 400, then every 7th, plus 999 1000 1001 1500 2000),
*     x continuous, integer with many ties, or on a 0.1 grid (ties), by n;
*   p in {0.5 1 2 2.5 5 10 12.5 20 25 30 33.333 33.3333 40 50 60 66.6667 70 75 80 87.5 90 95
*     97.5 99 99.5} (one plist call) and nq in {2..20, 50, 100, 1000} (one call each);
*   the default definition, altdef, and aweight (integer, fractional), fweight and pweight
*     (fractional) weights.
* The plugin falls back where the answer is not determined (weighted percentiles within the band
* of _pctile's tolerance); those cells are counted, not compared: the fast path then runs the
* original. Prints one CALIB line per definition and
*   TEST_CALIB pctile mismatches=<n>
* Run from tests/stata (needs stata/fastata.plugin).
version 16
clear all
set more off
fx_setup
quietly fastata on
quietly _fx threads
global CB_THREADS `fx_threads'

local plist 0.5 1 2 2.5 5 10 12.5 20 25 30 33.333 33.3333 40 50 60 66.6667 70 75 80 87.5 90 95 97.5 99 99.5
global CB_PC : subinstr local plist " " ",", all
global CB_NQ 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 50 100 1000

* One comparison: _pctile and the plugin on x [w] if t, at the plist or at n(nq). def is
* default|altdef|aw|awf|fw|pw. Adds to the CB_* counters of def.
capture program drop cb_one
program cb_one
	args def nq
	local wt
	local wtype none
	local alt
	if "`def'" == "altdef" local alt altdef
	if inlist("`def'", "aw", "awf") {
		local wv = cond("`def'" == "aw", "wi", "wf")
		local wt [aw=`wv']
		local wtype aw
	}
	if "`def'" == "fw" {
		local wt [fw=wi]
		local wtype fw
		local wv wi
	}
	if "`def'" == "pw" {
		local wt [pw=wf]
		local wtype pw
		local wv wf
	}
	if "`nq'" == "" {
		quietly _pctile x `wt' if t, p($CB_PC) `alt'
		local pos `""kind=plist" "p=$CB_PC""'
		local m : word count $CB_PC
	}
	else {
		quietly _pctile x `wt' if t, n(`nq') `alt'
		local pos `""kind=pctile" "nq=`nq'""'
		local m = `nq' - 1
	}
	_fx_call x `wv' t, quant "phase=compute" "threads=$CB_THREADS" `pos' "wtype=`wtype'" "altdef=`=("`alt'" != "")'" "touse=1"
	if `fx_plugrc' {
		di as err `"quant failed: `fx_errmsg'"'
		exit `fx_plugrc'
	}
	if `"`fx_fallback'"' != "" {
		global CB_FB_`def' = ${CB_FB_`def'} + `m'
		exit
	}
	_fx store `fx_token' double cb_q
	mata: cb_compare(`m', "`def'")
	drop cb_q
end

mata:
void cb_compare(real scalar m, string scalar def)
{
	real scalar k, bad, a, b
	real colvector q

	q = st_data((1, m), "cb_q")
	bad = 0
	for (k = 1; k <= m; k++) {
		a = st_numscalar("r(r" + strofreal(k) + ")")
		b = q[k]
		if (a != b | strofreal(a, "%21x") != strofreal(b, "%21x")) {
			bad++
			if (strtoreal(st_global("CB_SHOWN")) < 20) {
				printf("{err}MISMATCH %s n=%g k=%g: _pctile %21x, fastata %21x\n", def, st_numscalar("cb_n"), k, a, b)
				st_global("CB_SHOWN", strofreal(strtoreal(st_global("CB_SHOWN")) + 1))
			}
		}
	}
	st_global("CB_N_" + def, strofreal(strtoreal(st_global("CB_N_" + def)) + m))
	st_global("CB_BAD_" + def, strofreal(strtoreal(st_global("CB_BAD_" + def)) + bad))
}
end

local defs default altdef aw awf fw pw
foreach d of local defs {
	global CB_N_`d' 0
	global CB_BAD_`d' 0
	global CB_FB_`d' 0
}
global CB_SHOWN 0

set seed 20261015
quietly {
	set obs 2000
	gen double x = .
	gen double wi = ceil(runiform()*5)
	gen double wf = runiform() + .05
	gen byte t = 0
}
numlist "1/400 407(7)2000 999 1000 1001 1500 2000"
local ns `r(numlist)'
local ns : list uniq ns
foreach n of local ns {
	scalar cb_n = `n'
	local xk = mod(`n', 3)
	quietly {
		if `xk' == 0 replace x = rnormal()*10
		if `xk' == 1 replace x = round(rnormal()*3)
		if `xk' == 2 replace x = round(rnormal(), .1)
		replace t = _n <= `n'
	}
	foreach d of local defs {
		cb_one `d'
		foreach nq of global CB_NQ {
			cb_one `d' `nq'
		}
	}
}

* Near the switch of _pctile's weighted tolerance: j unit weights then one weight t placed so
* that W(j) - P = s*(1+e)*1e-7*W. Undetermined cells (|e| below about 1e-6) fall back; the
* others must match.
capture program drop cb_tol
program cb_tol
	args p
	quietly _pctile x [aw=wt] if t, p(`p')
	_fx_call x wt t, quant "phase=compute" "threads=$CB_THREADS" "kind=plist" "p=`p'" "wtype=aw" "touse=1"
	if `fx_plugrc' {
		di as err `"quant failed: `fx_errmsg'"'
		exit `fx_plugrc'
	}
	if `"`fx_fallback'"' != "" {
		global CB_FB_awtol = $CB_FB_awtol + 1
		exit
	}
	_fx store `fx_token' double cb_q
	mata: cb_compare(1, "awtol")
	drop cb_q
end
local defs `defs' awtol
global CB_N_awtol 0
global CB_BAD_awtol 0
global CB_FB_awtol 0
quietly replace x = _n
quietly gen double wt = 1
foreach j in 1 2 3 7 {
	scalar cb_n = `j'
	quietly replace t = _n <= `j' + 1
	quietly replace wt = 1
	foreach p in 10.00001 25 33.333 50 80 90 {
		foreach s in -1 1 {
			foreach e in -.5 -1e-2 -1e-4 -3e-6 -1e-6 -3e-7 -1e-7 -1e-8 -1e-10 0 1e-10 1e-8 1e-7 3e-7 1e-6 3e-6 1e-4 1e-2 .5 {
				quietly replace wt = `j'/(`p'/100 + `s'*(1+`e')*1e-7) - `j' in `=`j'+1'
				cb_tol `p'
			}
		}
	}
}

local tot 0
foreach d of local defs {
	di as txt "CALIB pctile `d': cells=${CB_N_`d'} mismatches=${CB_BAD_`d'} fallback=${CB_FB_`d'}"
	local tot = `tot' + ${CB_BAD_`d'}
	if ${CB_N_`d'} == 0 {
		di as err "no cells compared for `d'"
		local tot = `tot' + 1
	}
}
di as result "TEST_CALIB pctile mismatches=`tot'"
if `tot' exit 9
