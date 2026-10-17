* stress_strread.do -- parallel string-read probe of the fastata plugin.
* strprobe is not in the shipped plugin: build it with the cargo feature probes first, and rebuild
* without it afterwards (from the repository root):
*   bash scripts/build_plugin.sh --features probes
* then from tests/stata:   stata-mp -b do stress_strread.do
*
* Part 1: read throughput of strprobe over 2e7 obs (str20, strL, both): one thread against all.
* Part 2: 200 reps of strprobe with all threads, each checksum compared with the one-thread
*         checksum. Parallel string reads could become the plugin's default only if all 200
*         reps matched without a crash.
* Result on StataNow 19.5 MP (Linux), 15oct2026: Stata crashed ("double free or corruption")
* in part 1, so the plugin reads strings on Stata's thread only (see src/io.rs). Rerun this on
* a new Stata version before reconsidering; it may crash Stata.

version 16
clear all
set more off
set seed 20261015

capture program drop _fxp
program _fxp, plugin using("../../stata/fastata.plugin")

set obs 20000000
* a leading string variable makes varlist positions differ from dataset positions
gen str1 pad = "a"
gen str20 s20 = string(runiformint(1, 1e9)) + char(65 + runiformint(0, 25)) * runiformint(0, 10)
replace s20 = "" in 5/100
gen strL sl = "L" + string(_n) + cond(mod(_n, 7) == 0, 300 * "z", "")
replace sl = "" in 200/300

* ---------------------------------------------------------------- part 1
timer clear
forvalues r = 1/3 {
	foreach v in s20 sl "s20 sl" {
		local t = cond("`v'" == "s20", 1, cond("`v'" == "sl", 3, 5))
		timer on `t'
		plugin call _fxp `v', strprobe "threads=1"
		timer off `t'
		local c1 `fx_chk'
		local ++t
		timer on `t'
		plugin call _fxp `v', strprobe "threads=0"
		timer off `t'
		if "`fx_chk'" != "`c1'" {
			di as err "part 1: `v': parallel checksum `fx_chk', one thread `c1'"
		}
	}
}
quietly timer list
di as result "STRREAD_THROUGHPUT str20: onethread=" %7.3f r(t1)/3 " parallel=" %7.3f r(t2)/3	///
	"  strL: onethread=" %7.3f r(t3)/3 " parallel=" %7.3f r(t4)/3	///
	"  both: onethread=" %7.3f r(t5)/3 " parallel=" %7.3f r(t6)/3 " (seconds per 2e7 obs)"

* ---------------------------------------------------------------- part 2
plugin call _fxp s20 sl, strprobe "threads=1"
local serial `fx_chk'
local reps 200
local fails 0
forvalues r = 1/`reps' {
	plugin call _fxp s20 sl, strprobe "threads=0"
	if "`fx_chk'" != "`serial'" {
		local ++fails
		di as err "rep `r': parallel checksum `fx_chk', one thread `serial'"
	}
	if `r' == 1 | mod(`r', 50) == 0 {
		di as txt "rep `r' done"
	}
}
di as result "STRESS_STRREAD_RESULT fails=`fails' reps=`reps'"
