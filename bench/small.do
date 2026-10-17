* small.do -- per-call cost of fastata vs the original commands on small data (milliseconds
* per call), the case of do-files that call egen, isid, ... in loops over small datasets.
* From bench/ (after scripts/build_plugin.sh): stata-mp -b do small.do [sizes...]
* (default sizes: 74 1000 10000 100000). Writes SMALL.md and one SMALL line per case.
*
* Data of size N: id, g (N/10 groups), year, x1-x5, sn (numeric strings, 1% "NA"), z; a copy
* sorted by g for the by-prefix cases. Each command runs reps times (more for smaller N), quietly;
* only the command is timed (the variable it creates is dropped, and commands that change the
* data run on a fresh frame copy, outside the timer). Modes: the original (fastata off); fastata
* as users run it (fastata on: small data may go straight to the original); fastata with its
* fast path forced (_fx small off), where that switch exists. The counters show which path ran.
version 16
clear all
set more off
set seed 20261015
local sizes `0'
if `"`sizes'"' == "" local sizes 74 1000 10000 100000

* fastata from this repository, with a fresh runtime under bench/_plus/
local here `"`c(pwd)'"'
quietly cd "../stata"
local fxstata `"`c(pwd)'/"'
quietly cd `"`here'"'
quietly adopath ++ `"`fxstata'"'
capture mkdir `"`here'/_plus"'
sysdir set PLUS `"`here'/_plus/"'
_fx rmruntime `"`here'/_plus/fastata/"'
quietly fastata on
capture _fx small on
local haveforce = (_rc == 0)

capture program drop fx_mkdata
program fx_mkdata
	args n
	clear
	quietly {
		set obs `n'
		gen long id = _n
		gen long g = floor(runiform()*max(2, floor(`n'/10)))
		gen int year = 2000 + floor(runiform()*20)
		forvalues j = 1/5 {
			gen double x`j' = rnormal()
		}
		gen str9 sn = cond(runiform() < .01, "NA", string(round(runiform()*1e5, .01), "%9.2f"))
		gen long z = floor(runiform()*1e8)
	}
end

capture program drop fx_percall
program fx_percall, rclass
	* fx_percall <frame> <reps> <kind> <var> <command>: ms per call; kind inplace (fresh copy
	* per call), newvar (var dropped after each call) or none
	args fr reps kind var cmd
	timer clear 98
	if "`kind'" == "inplace" {
		forvalues r = 1/`reps' {
			capture frame drop work
			frame copy `fr' work
			frame work {
				timer on 98
				quietly `cmd'
				timer off 98
			}
		}
	}
	else {
		capture frame drop work
		frame copy `fr' work
		frame work {
			forvalues r = 1/`reps' {
				timer on 98
				quietly `cmd'
				timer off 98
				if "`kind'" == "newvar" drop `var'
			}
		}
	}
	capture frame drop work
	quietly timer list 98
	return scalar ms = r(t98) / `reps' * 1000
end

capture program drop fx_paths
program fx_paths, rclass
	* fx_paths <cmd>: this session's fast and fallback counts of cmd
	args c
	_fx status
	return scalar fast = `fx_nfast_`c''
	return scalar fb = `fx_nfb_`c''
	return local why `"`fx_last_`c''"'
end

frame create res long n str4 id str48 desc double(to tf tff) str40 path str40 pathf
capture program drop fx_case
program fx_case
	* fx_case <n> <id> <frame> <replaced command> <kind> <var> <reps> <command>
	args n id fr c kind var reps cmd haveforce
	* untimed warm-up of both versions (loads ado-files and the plugin)
	foreach m in off on {
		quietly fastata `m'
		frame copy `fr' warm
		frame warm: capture quietly `cmd'
		frame drop warm
	}
	quietly fastata off
	fx_percall `fr' `reps' `kind' "`var'" `"`cmd'"'
	local to = r(ms)
	quietly fastata on
	local tff .
	local pathf
	if `haveforce' {
		quietly _fx small off
		fx_paths `c'
		local f0 = r(fast)
		local b0 = r(fb)
		fx_percall `fr' `reps' `kind' "`var'" `"`cmd'"'
		local tff = r(ms)
		fx_paths `c'
		local pathf = cond(r(fast) - `f0' == `reps', "fast", "fast " + string(r(fast) - `f0') + ///
			", fallback " + string(r(fb) - `b0') + `" (`r(why)')"')
		quietly _fx small on
	}
	fx_paths `c'
	local f0 = r(fast)
	local b0 = r(fb)
	fx_percall `fr' `reps' `kind' "`var'" `"`cmd'"'
	local tf = r(ms)
	fx_paths `c'
	local path = cond(r(fast) - `f0' == `reps', "fast", cond(r(fb) - `b0' == `reps', ///
		`"fallback (`r(why)')"', "fast " + string(r(fast) - `f0') + ", fallback " + string(r(fb) - `b0')))
	frame post res (`n') ("`id'") (`"`cmd'"') (`to') (`tf') (`tff') (`"`path'"') (`"`pathf'"')
	di as txt "SMALL `n' `id' " `"`cmd'"' as res "  original " %8.3f `to' " ms, fastata " %8.3f `tf' ///
		" ms [`path'], forced " %8.3f `tff' " ms [`pathf']"
end

foreach n of local sizes {
	local reps = cond(`n' <= 1000, 300, cond(`n' <= 10000, 60, 10))
	fx_mkdata `n'
	frame rename default D
	frame copy D Ds
	frame Ds: sort g
	frame create default
	frame change default
	fx_case `n' E1 D egen newvar t `reps' "egen t = tag(g)" `haveforce'
	fx_case `n' E2 D egen newvar gg `reps' "egen gg = group(g)" `haveforce'
	fx_case `n' E3 D egen newvar v `reps' "egen double v = mean(x1), by(g)" `haveforce'
	fx_case `n' E4 Ds egen newvar v `reps' "by g: egen double v = mean(x1)" `haveforce'
	fx_case `n' E5 D egen newvar v `reps' "egen double v = median(x1), by(g)" `haveforce'
	fx_case `n' E6 D egen newvar v `reps' "egen v = rank(x1), by(g)" `haveforce'
	fx_case `n' E7 D egen newvar v `reps' "egen double v = max(x1), by(g)" `haveforce'
	fx_case `n' E8 D egen newvar v `reps' "egen double v = total(x1), by(g)" `haveforce'
	fx_case `n' E9 D egen newvar v `reps' "egen double v = sd(x1), by(g)" `haveforce'
	fx_case `n' E10 D egen newvar v `reps' "egen v = count(x1), by(g)" `haveforce'
	fx_case `n' E11 Ds egen newvar v `reps' "by g: egen double v = total(x1)" `haveforce'
	fx_case `n' E12 D egen newvar rt `reps' "egen double rt = rowtotal(x1-x5)" `haveforce'
	fx_case `n' K1 D isid none "" `reps' "isid id" `haveforce'
	fx_case `n' K2 D duplicates newvar d `reps' "duplicates tag g, gen(d)" `haveforce'
	fx_case `n' K3 D duplicates inplace "" `reps' "duplicates drop g year, force" `haveforce'
	fx_case `n' K4 D duplicates none "" `reps' "duplicates report g" `haveforce'
	fx_case `n' Q1 D xtile newvar q `reps' "xtile q = x1, nq(4)" `haveforce'
	fx_case `n' Q2 D pctile newvar p `reps' "pctile double p = x1, nq(4)" `haveforce'
	fx_case `n' S1 D destring inplace "" `reps' "destring sn, replace force" `haveforce'
	fx_case `n' S2 D tostring inplace "" `reps' "tostring z, replace" `haveforce'
	frame drop D
	frame drop Ds
}

frame change res
gen double ratio = to / tf
gen double ratiof = to / tff
tempname fh
file open `fh' using "SMALL.md", write text replace
file write `fh' "# fastata on small data: milliseconds per call" _n _n
file write `fh' "Generated by bench/small.do on `c(current_date)' `c(current_time)': Stata " ///
	"`c(stata_version)' `c(edition_real)', `c(os)', `c(processors)' processors (" ///
	"`c(processors_mach)' on the machine)." _n _n
file write `fh' "Each command runs quietly, 300 times at N <= 1,000, 60 at N <= 10,000, else 10; only " ///
	"the command is timed. Speed-up = original / fastata. *fastata* is fastata as users run it " ///
	"(small data may run the original directly: path fallback (small data)); *forced* has the " ///
	"fast path forced." _n _n
file write `fh' "| N | id | command | original ms | fastata ms | speed-up | path | forced ms | forced speed-up |" _n
file write `fh' "|---:|---|---|---:|---:|---:|---|---:|---:|" _n
forvalues i = 1/`=_N' {
	file write `fh' "| " %9.0fc (n[`i']) " | " (id[`i']) " | " _char(96) (desc[`i']) _char(96) " | " ///
		%8.3f (to[`i']) " | " %8.3f (tf[`i']) " | " %5.2f (ratio[`i']) "x | " (path[`i']) " | " ///
		(cond(missing(tff[`i']), "-", string(tff[`i'], "%8.3f"))) " | " ///
		(cond(missing(ratiof[`i']), "-", string(ratiof[`i'], "%5.2f") + "x")) " |" _n
}
file close `fh'
list n id to tf ratio path tff ratiof, noobs abbreviate(10) sepby(n)
di as result "SMALL_DONE"
