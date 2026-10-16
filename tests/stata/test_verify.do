* test_verify.do -- verify mode (_fx mode verify; env FASTATA_MODE=verify). Every fast call also
* runs the original, quietly, on a snapshot taken before the fast path changed anything, compares
* the two results and keeps the original's. Checks:
* (i)   a sequence of fast calls followed by code that depends on sort ties (sort with ties, _n,
*       x[1] within by-groups, runiform()), printing the sort and regular random-number states
*       after each call, gives the same data, text log, SMCL log and final random-number states
*       with fastata off and with fastata on in verify mode (and, in auto mode, a different sort
*       random-number state: the sequence does depend on the original's internal sorts), and
*       collapses between verified calls sum in the same order as without fastata (collapse
*       breaks ties from a sort stream that c(sortrngstate) does not show);
* (ii)  in a separate Stata process (verify_child.do) with FASTATA_MODE=verify and FASTATA_COUNTS
*       set: the mode survives clear all, _fx mode auto overrides the env var, and a fast path
*       broken on purpose (a copy of _fx_xtile that changes one value) is reported as
*       verify_mismatch while the original's value is kept, and a call whose snapshot cannot be
*       made (no frame left) is verify_skipped and keeps the fast path's result;
* (iii) the FASTATA_COUNTS lines written by (ii), and the session counts of _fx status.
* Ends with TEST_VERIFY passed.
version 16
clear all
set more off
fx_setup
quietly fastata on
_fx mode auto

fx_testdata
quietly {
	gen str9 sx = string(xi)
	replace sx = "" in 5
}
frame copy default vbase

* the sort and regular random-number states, as hashes
capture program drop tv_h
program tv_h
	quietly mata: st_local("h1", strofreal(hash1(c("sortrngstate")), "%12.0f"))
	quietly mata: st_local("h2", strofreal(hash1(c("rngstate")), "%12.0f"))
	di as txt "states `h1' `h2'"
end

* fast calls of every command, each followed by the random-number states, then code that
* depends on the order of sort ties
capture program drop tv_seq
program tv_seq
	egen double m = mean(x1), by(g)
	tv_h
	egen t = total(x2), by(gbig)
	tv_h
	egen gg = group(s g)
	tv_h
	egen tg = tag(id2)
	tv_h
	egen r = rank(x1), by(g)
	tv_h
	egen double md = median(x2), by(gbig)
	tv_h
	bysort g: egen double mx = max(x1)
	tv_h
	isid id, sort
	tv_h
	capture isid id2
	di as txt "isid rc " _rc
	tv_h
	duplicates tag id2, gen(dt)
	tv_h
	duplicates report g gbig
	di as txt "unique " r(unique_value)
	tv_h
	xtile q = x1, nq(7)
	tv_h
	pctile double p = x2, nq(9)
	tv_h
	destring sx, gen(nx)
	tv_h
	tostring xl, gen(sxl)
	tv_h
	duplicates drop g gbig s, force
	di as txt "dropped " r(N_drop)
	tv_h
	sort gbig
	gen long ord = _n
	by gbig: gen double firstx = x1[1]
	sort g
	by g: gen long within = _n
	gen double u2 = runiform()
	tv_h
end

* Runs tv_seq in frame fr (a copy of vbase) from fixed seeds, logging to tv_<tag>.log (text) and
* tv_<tag>.smcl; leaves the final random-number states in globals TV_SRS_<tag>, TV_RS_<tag>.
capture program drop tv_run
program tv_run
	args tag
	capture frame drop f`tag'
	frame copy vbase f`tag'
	frame f`tag' {
		set sortseed 4242
		set seed 777
		quietly log using "tv_`tag'.log", text name(tvt) replace nomsg
		quietly log using "tv_`tag'.smcl", smcl name(tvs) replace nomsg
		tv_seq
		quietly log close tvt
		quietly log close tvs
		global TV_SRS_`tag' = c(sortrngstate)
		global TV_RS_`tag' = c(rngstate)
	}
end

mata:
void tv_samefile(string scalar a, string scalar b)
{
	string colvector la, lb
	real scalar i

	la = cat(a)
	lb = cat(b)
	if (la == lb) return
	for (i = 1; i <= min((rows(la), rows(lb))); i++) {
		if (la[i] != lb[i]) break
	}
	errprintf("%s and %s differ at line %g\n", a, b, i)
	exit(9)
}
end

* (i) fastata off, then on in verify mode
quietly fastata off
tv_run a
quietly fastata on
_fx status
foreach c in egen isid duplicates xtile pctile destring tostring {
	local f0_`c' `fx_nfast_`c''
	local ok0_`c' `fx_vok_`c''
	local bad0_`c' = `fx_vmis_`c'' + `fx_vskip_`c''
}
_fx mode verify
tv_run b
_fx mode auto
_fx status
foreach c in egen isid duplicates xtile pctile destring tostring {
	local nf = `fx_nfast_`c'' - `f0_`c''
	local nok = `fx_vok_`c'' - `ok0_`c''
	local nbad = `fx_vmis_`c'' + `fx_vskip_`c'' - `bad0_`c''
	di as txt "`c': `nf' fast calls, `nok' verified, `nbad' mismatched or skipped"
	assert `nf' >= 1
	assert `nok' == `nf'
	assert `nbad' == 0
}
fx_cmpframes fa fb, tol(0) what(verify sequence)
mata: tv_samefile("tv_a.log", "tv_b.log")
mata: tv_samefile("tv_a.smcl", "tv_b.smcl")
assert `"$TV_SRS_a"' == `"$TV_SRS_b"'
assert `"$TV_RS_a"' == `"$TV_RS_b"'
* in auto mode the fast paths skip the originals' internal sorts
tv_run c
assert `"$TV_SRS_a"' != `"$TV_SRS_c"'
di as txt "verify sequence ok"

* collapse breaks sort ties from a stream that c(sortrngstate) does not show: it continues from
* one collapse to the next, and set sortseed or set sortrngstate (even to the current value)
* restarts it. Verify mode must leave it alone (zenodo-23223970: collapse (sum) after verified
* calls summed in another order than without fastata). Each collapse sums 10,000 observations
* per group, so another tie order changes the sums' last bits.
capture program drop tv_coll
program tv_coll
	args tag
	capture frame drop hc
	frame copy vbase hc
	frame hc {
		collapse (sum) x1 x2, by(gbig)
		quietly mata: st_local("h", strofreal(hash1(invtokens(strofreal(vec(st_data(., .))', "%21x"))), "%12.0f"))
	}
	frame drop hc
	global TV_C_`tag' ${TV_C_`tag'} `h'
end
capture program drop tv_hidden
program tv_hidden
	args tag
	global TV_C_`tag'
	capture frame drop h`tag'
	frame copy vbase h`tag'
	frame h`tag' {
		set sortseed 11
		tv_coll `tag'
		egen double m = mean(x1), by(g)
		tv_coll `tag'
		isid id
		tv_coll `tag'
		xtile q = x2, nq(5)
		tv_coll `tag'
	}
end
quietly fastata off
tv_hidden a
quietly fastata on
_fx mode verify
tv_hidden b
_fx mode auto
di as txt "collapse sums without fastata: $TV_C_a"
di as txt "collapse sums in verify mode:  $TV_C_b"
* the stream matters: consecutive collapses of the same data differ
assert word("$TV_C_a", 1) != word("$TV_C_a", 2)
assert "$TV_C_a" == "$TV_C_b"
di as txt "verify hidden sort stream ok"

* frame copy reverses the order of the value labels (label dir), which append and merge show in
* their "label ... already defined" notes: verify mode keeps the order (dataverse-AOY4D6,
* dataverse-A9ZFFF, zenodo-19562339)
capture program drop tv_labs
program tv_labs
	args tag
	global TV_L_`tag'
	capture frame drop l`tag'
	frame create l`tag'
	frame l`tag' {
		sysuse auto, clear
		foreach l in zl al ml {
			label define `l' 0 "`l'0" 1 "`l'1"
		}
		gen byte z = mod(_n, 2)
		label values z zl
		foreach c in "egen double m = mean(price), by(foreign)" "isid make" "xtile q = price, nq(4)" {
			`c'
			quietly label dir
			global TV_L_`tag' ${TV_L_`tag'} | `r(names)'
		}
	}
	frame drop l`tag'
end
quietly fastata off
tv_labs a
quietly fastata on
_fx mode verify
tv_labs b
_fx mode auto
di as txt "value labels without fastata: $TV_L_a"
di as txt "value labels in verify mode:  $TV_L_b"
assert "$TV_L_a" == "$TV_L_b"
di as txt "verify value label order ok"

* verify mode needs no data: a fast call on a frame other than default, and an error of the
* fast path (isid) with the original's return code
frame create other
frame other {
	sysuse auto, clear
	_fx mode verify
	egen double mp = mean(price), by(rep78)
	capture isid rep78
	assert _rc == 459
	_fx mode auto
	assert c(frame) == "other"
	confirm variable mp
}
frame drop other
capture frame drop __fx_vsnap
assert _rc == 111

* (ii) and (iii): a separate process with FASTATA_MODE and FASTATA_COUNTS
local counts `"`c(pwd)'/tv_counts.csv"'
capture erase `"`counts'"'
capture erase verify_child.log
local exe `"`c(sysdir_stata)'stata-mp"'
capture confirm file `"`exe'"'
if _rc local exe stata-mp
shell FASTATA_MODE=verify FASTATA_COUNTS="`counts'" "`exe'" -b do verify_child.do
mata: st_local("done", strofreal(anyof(cat("verify_child.log"), "VERIFY_CHILD passed")))
if !`done' {
	type verify_child.log
	di as err "verify_child.do failed (verify_child.log above)"
	exit 9
}
mata: tv_counts = cat(st_local("counts"))
mata: tv_counts
* the line of a verification without snapshot ends with the frame copy's return code
mata: st_local("ok", strofreal(rows(tv_counts) == 10))
assert `ok'
mata: st_local("ok", strofreal(regexm(tv_counts[9], "^xtile,verify_skipped,snapshot r[(][0-9]+[)]$")))
assert `ok'
mata: tv_counts[9] = "skipped"
mata: st_local("ok", strofreal(tv_counts == ("egen,fast," \ "egen,verify_ok," \ "xtile,fast," \ "xtile,verify_ok," \ "xtile,fast," \ "xtile,fast," \ "xtile,verify_mismatch,values of q3 (1 obs; first obs 1: 2 vs 1)" \ "xtile,fast," \ "skipped" \ "isid,fallback,mode original")))
assert `ok'
erase `"`counts'"'
erase verify_child.log
foreach f in tv_a.log tv_b.log tv_a.smcl tv_b.smcl tv_c.log tv_c.smcl {
	erase `f'
}
di as txt "counts ok"

di as result "TEST_VERIFY passed"
