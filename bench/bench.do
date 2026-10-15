* bench.do -- original vs fastata timings and speed gates (plan Step 6).
* From bench/ (after scripts/build_plugin.sh): stata-mp -b do bench.do [observations]
* (default 10,000,000; a smaller count only checks the mechanics).
* Writes RESULTS.md and prints one BENCH_GATE line per scenario.
*
* Every timed run starts from a fresh frame copy (the copy is not timed). The original runs once
* (fastata off), fastata best of 3 (fastata on). A fastata time counts only when fastata's
* counters show that every one of its runs took the fast path; otherwise the scenario FAILs as
* "fallback". Floor (scenarios that create variables): best of 3 of one nofill st_addvar of the
* same output variables, the cost Stata charges any implementation for creating them. A failed
* gate is floor-bound when fastata's time minus the floor is at most 0.3 s.
version 16
clear all
set more off
set seed 20261015
args nobs
if "`nobs'" == "" local nobs 10000000

* fastata from this repository, with a fresh runtime under bench/_plus/
local here `"`c(pwd)'"'
quietly cd "../stata"
local fxstata `"`c(pwd)'/"'
quietly cd `"`here'"'
quietly adopath ++ `"`fxstata'"'
capture mkdir `"`here'/_plus"'
sysdir set PLUS `"`here'/_plus/"'
_fx rmruntime `"`here'/_plus/fastata/"'

* ------------------------------------------------------------------------------------------- data
* D10: id, g (100k groups), year, x1-x5, w, sn (numeric strings, 1% "NA"), z; D10s sorted by g
quietly {
	set obs `nobs'
	gen long id = _n
	gen long g = floor(runiform()*100000)
	gen int year = 2000 + floor(runiform()*20)
	forvalues j = 1/5 {
		gen double x`j' = rnormal()
	}
	gen double w = runiform() + .5
	gen str9 sn = cond(runiform() < .01, "NA", string(round(runiform()*1e5, .01), "%9.2f"))
	gen long z = floor(runiform()*1e8)
	* unique but not in ascending order: isid takes the hash path
	gen long idr = _N + 1 - id
}
frame rename default D10
frame copy D10 D10s
frame D10s: sort g

* ------------------------------------------------------------------------------------- helpers
capture program drop fx_brun
program fx_brun, rclass
	* fx_brun <frame> <reps> <command>: best time of reps runs, each on a fresh copy of frame
	args fr reps cmd
	local best .
	forvalues r = 1/`reps' {
		capture frame drop work
		frame copy `fr' work
		frame work {
			timer clear 99
			timer on 99
			`cmd'
			timer off 99
		}
		quietly timer list 99
		local best = min(`best', r(t99))
	}
	capture frame drop work
	return scalar t = `best'
end

capture program drop fx_nfast
program fx_nfast, rclass
	* fx_nfast <cmd>: how many calls of cmd took the fast path this session, and the reason of
	* the last fallback
	args c
	_fx status
	return scalar n = `fx_nfast_`c''
	return local why `"`fx_last_`c''"'
end

frame create res str4 id str60 desc str4 frm double(to tf floor gate) byte fast str80 why
capture program drop fx_scen
program fx_scen
	* fx_scen <id> <frame> <replaced command> <gate or .> "<output types>" "<output names>" <cmd>
	args id fr c gate otypes onames cmd
	* the original's ado-files are loaded by an untimed run on the first 1000 observations (which
	* may fail, e.g. with no observations satisfying the if)
	quietly fastata off
	capture frame drop warm
	frame copy `fr' warm
	frame warm {
		quietly keep in 1/1000
		capture quietly `cmd'
	}
	frame drop warm
	fx_brun `fr' 1 `"`cmd'"'
	local to = r(t)
	quietly fastata on
	fx_nfast `c'
	local n0 = r(n)
	fx_brun `fr' 3 `"`cmd'"'
	local tf = r(t)
	fx_nfast `c'
	local fast = r(n) - `n0' == 3
	local why `"`r(why)'"'
	local floor 0
	if `"`onames'"' != "" {
		fx_brun `fr' 3 `"mata: (void) st_addvar(tokens("`otypes'"), tokens("`onames'"), 1)"'
		local floor = r(t)
	}
	frame post res ("`id'") (`"`cmd'"') ("`fr'") (`to') (`tf') (`floor') (`gate') (`fast') (`"`why'"')
	di as txt "`id' `fr': " `"`cmd'"' as res "  original " %7.3f `to' " s, fastata " %7.3f `tf' ///
		" s (" cond(`fast', "fast", `"fallback: `why'"') "), floor " %6.3f `floor' " s"
end

* ----------------------------------------------------------------------------------- scenarios
fx_scen E1 D10  egen 15 "byte"   "t"  "egen t = tag(g)"
fx_scen E2 D10  egen 10 "float"  "gg" "egen gg = group(g)"
fx_scen E3 D10  egen 8  "double" "m"  "egen double m = mean(x1), by(g)"
fx_scen E4 D10s egen 5  "double" "m"  "bys g: egen double m = mean(x1)"
fx_scen E5 D10  egen 8  "double" "md" "egen double md = median(x1), by(g)"
fx_scen E6 D10  egen 8  "float"  "r"  "egen r = rank(x1), by(g)"
fx_scen E7 D10  egen .  "double" "s"  "egen double s = total(x1)"
fx_scen E8 D10  egen 5  "double" "rt" "egen double rt = rowtotal(x1-x5)"
fx_scen E9 D10  egen 5  "double" "m"  "egen double m = mean(x1) if year > 2005, by(g)"
fx_scen E10 D10 egen 8  "float"  "c"  "egen c = count(x1), by(g year)"
fx_scen K1 D10  isid 20 "" "" "isid id"
fx_scen K2 D10  duplicates 10 "byte" "dt" "duplicates tag g year, gen(dt)"
fx_scen K3 D10  duplicates 8 "" "" "duplicates drop g year, force"
fx_scen K4 D10  duplicates 10 "" "" "duplicates report g"
fx_scen K1b D10 isid 20 "" "" "isid idr"
fx_scen K5 D10  isid 8 "" "" "isid sn id"
fx_scen K6 D10  duplicates 20 "" "" "duplicates examples g year if x1 > 3.7"
fx_scen Q1 D10  xtile 20 "byte"  "q" "xtile q = x1, nq(10)"
fx_scen Q2 D10  pctile 10 "double" "p" "pctile double p = x1, nq(100)"
fx_scen Q3 D10  xtile . "byte"  "q" "xtile q = x1 [aw=w], nq(10)"
fx_scen Q4 D10  xtile 10 "byte"  "q" "xtile q = x1 if year > 2005, nq(10)"
fx_scen S1 D10  destring 2 "double" "sn2" "destring sn, replace force"
fx_scen S2 D10  tostring 2 "str8" "z2" "tostring z, replace"
fx_scen S1g D10 destring . "double" "n2" "destring sn, gen(n2) force"

* ------------------------------------------------------------------------ gates and RESULTS.md
frame change res
gen double speedup = to / tf
gen str120 verdict = cond(missing(gate), "report only", ///
	cond(fast & speedup >= gate, "PASS", cond(fast & tf - floor <= .3, "floor-bound", "FAIL")))
replace verdict = verdict + " (fallback: " + why + ")" if !fast
forvalues i = 1/`=_N' {
	di as result "BENCH_GATE " id[`i'] " " verdict[`i'] " " %6.1f speedup[`i'] "x (gate " ///
		cond(missing(gate[`i']), "none", string(gate[`i']) + "x") ")"
}

* Stata strings cannot hold backquotes: code spans are written with _char(96)
tempname fh
file open `fh' using "RESULTS.md", write text replace
file write `fh' "# fastata benchmark results" _n _n
file write `fh' "Generated by bench/bench.do on `c(current_date)' `c(current_time)': Stata " ///
	"`c(stata_version)' `c(edition_real)', `c(os)', `c(processors)' processors (" ///
	"`c(processors_mach)' on the machine)." _n _n
file write `fh' "Data: D10 = " %12.0fc (`nobs') " obs (long id, long g with 100,000 groups, " ///
	"int year, double x1-x5 and w, str9 sn numeric strings with 1% NA, long z); D10s = D10 " ///
	"sorted by g. The original runs once (fastata off), fastata best of 3 (fastata on), each " ///
	"run on a fresh frame copy (not timed). Floor: one nofill st_addvar of the same output " ///
	"variables (best of 3). A gate that is missed counts as floor-bound when fastata takes at " ///
	"most 0.3 s more than the floor." _n _n
file write `fh' "| id | data | scenario | original s | fastata s | speed-up | floor s | gate | result |" _n
file write `fh' "|---|---|---|---:|---:|---:|---:|---:|---|" _n
forvalues i = 1/`=_N' {
	file write `fh' "| " (id[`i']) " | " (frm[`i']) " | " _char(96) (desc[`i']) _char(96) " | " ///
		%7.3f (to[`i']) " | " %7.3f (tf[`i']) " | " %6.1f (speedup[`i']) "x | " %6.3f (floor[`i']) ///
		" | " (cond(missing(gate[`i']), "-", string(gate[`i']) + "x")) " | " (verdict[`i']) " |" _n
}
file close `fh'
list id frm to tf speedup floor gate verdict, noobs abbreviate(12)
di as result "BENCH_DONE"
