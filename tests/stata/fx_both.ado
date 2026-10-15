*! fx_both "<command>" [, base(frame) tol(#) r(names) allr expect(<cmd> fast|fallback|any) nosortcheck nosmcl]
*! Runs <command> twice from the same state: in frame fa with fastata off (the original command
*! runs) and in frame fb with fastata on, both on copies of frame base (default: base), both from
*! the same sort seed and with r() cleared. Fails (r(9)) unless the two runs give
*! - the same return code;
*! - the same output, as captured by log using ..., text, and the same SMCL log (log using ...,
*!   smcl: every style tag too, line by line; nosmcl skips it);
*! - the same r() results named in r() (all r() results with allr);
*! - the same data (fx_cmpframes; tolerance tol, default 0: bitwise).
*! expect(cmd kind) also checks that the second run went through fastata's cmd as kind (fast or
*! fallback; any: either, or neither when cmd is not reached in either run, e.g. a by prefix on
*! unsorted data fails first) and that the first did not; the path taken comes back in local
*! fxb_path (fast, fallback, fast+fallback for several calls, or none) and the last fallback
*! reason of cmd in local fxb_why, set before the comparisons. fastata is on afterwards.
program fx_both
	version 16
	gettoken cmd 0 : 0
	syntax [, Base(name) TOL(real 0) R(string) ALLR EXPect(string) noSORTcheck noSMCL]
	if "`base'" == "" local base base
	gettoken ecmd ekind : expect
	local ekind `ekind'
	if "`ecmd'" != "" & !inlist("`ekind'", "fast", "fallback", "any") {
		di as err "fx_both: expect(<cmd> fast|fallback|any)"
		exit 198
	}
	c_local fxb_path
	c_local fxb_why
	capture frame drop fa
	capture frame drop fb
	frame copy `base' fa
	frame copy `base' fb
	tempfile la lb sa sb

	quietly fastata off
	mata: _fxb_count0 = _fxb_counts("`ecmd'")
	frame fa: _fxb_run `"`cmd'"' `"`la'"' `"`sa'"' a
	local rca `fxb_rc'
	mata: _fxb_count1 = _fxb_counts("`ecmd'")
	quietly fastata on
	frame fb: _fxb_run `"`cmd'"' `"`lb'"' `"`sb'"' b
	local rcb `fxb_rc'
	mata: _fxb_count2 = _fxb_counts("`ecmd'")

	if "`ecmd'" != "" {
		mata: st_local("used0", strofreal(any(_fxb_count1 :!= _fxb_count0)))
		mata: st_local("nfast", strofreal(_fxb_count2[1] - _fxb_count1[1]))
		mata: st_local("nfb", strofreal(_fxb_count2[2] - _fxb_count1[2]))
		local path = cond(`nfast' & `nfb', "fast+fallback", cond(`nfast', "fast", cond(`nfb', "fallback", "")))
		c_local fxb_path `path'
		if `nfb' {
			mata: st_local("why", asarray_contains(*findexternal("_fx_why"), "`ecmd'") ? asarray(*findexternal("_fx_why"), "`ecmd'") : "")
			c_local fxb_why `"`why'"'
		}
		if "`ekind'" == "any" {
			local used = `nfast' + `nfb'
			* cmd not reached in either run (a by prefix on unsorted data fails first): path none
			if `used' == 0 {
				local used 1
				c_local fxb_path none
			}
		}
		else local used = cond("`ekind'" == "fast", `nfast', `nfb')
		if `used0' | `used' < 1 {
			di as err `"`cmd': expected `ecmd' to run through fastata as `ekind' only in the second run"'
			di as err "  counts (fast, fallback) before: " _c
			mata: printf("{err}%g %g, after original: %g %g, after fastata: %g %g\n", _fxb_count0[1], _fxb_count0[2], _fxb_count1[1], _fxb_count1[2], _fxb_count2[1], _fxb_count2[2])
			exit 9
		}
	}
	if `rca' != `rcb' {
		di as err `"`cmd': return code `rca' with fastata off, `rcb' with fastata on"'
		exit 9
	}
	mata: _fxb_cmplogs(st_local("la"), st_local("lb"), st_local("cmd"), "output")
	if "`smcl'" == "" mata: _fxb_cmplogs(st_local("sa"), st_local("sb"), st_local("cmd"), "SMCL log")
	mata: _fxb_cmpr(st_local("r"), "`allr'" != "", st_local("cmd"))
	fx_cmpframes fa fb, tol(`tol') what(`"`cmd'"') `sortcheck'
end

* Runs cmd in the current frame from sort seed 20261015 with r() cleared, logging its output
* to file log (text) and file slog (SMCL); saves r() under tag and returns the return code in
* fxb_rc.
program _fxb_run
	args cmd log slog tag
	* Stata keeps sort state beyond c(sortrngstate): after an original that sorts internally
	* (e.g. xtile), the next by-sort into a sortpreserve original orders ties differently, even
	* in another frame (documented exception 1: fastata does not sort). Any sort resets it, so
	* both runs start from a sort of a scratch frame, then from the same seed.
	frame create _fxb_reset
	frame _fxb_reset {
		quietly set obs 3
		quietly gen byte x = 1
		sort x
	}
	frame drop _fxb_reset
	set sortseed 20261015
	quietly log using `"`log'"', text name(_fxb) nomsg replace
	quietly log using `"`slog'"', smcl name(_fxbs) nomsg replace
	_fxb_rclear
	capture noisily `cmd'
	local rc = _rc
	mata: _fxb_rsave("`tag'")
	quietly log close _fxb
	quietly log close _fxbs
	c_local fxb_rc `rc'
end

* Calling an rclass program that returns nothing clears r().
program _fxb_rclear, rclass
	version 16
end

mata:
// (fast, fallback) calls of fastata's cmd this session ((0, 0) if none or no cmd).
real rowvector _fxb_counts(string scalar cmd)
{
	pointer() scalar p

	if (cmd == "") return((0, 0))
	if ((p = findexternal("_fx_cnt")) == NULL) return((0, 0))
	if (!asarray_contains(*p, cmd)) return((0, 0))
	return(asarray(*p, cmd))
}

// r() as rows (kind name, value); numbers in %21x so that equal means bitwise equal.
void _fxb_rsave(string scalar tag)
{
	pointer() scalar p
	string colvector n
	string matrix out
	real matrix m
	real scalar i

	out = J(0, 2, "")
	n = sort(st_dir("r()", "numscalar", "*"), 1)
	for (i = 1; i <= rows(n); i++) {
		out = out \ ("scalar " + n[i], strofreal(st_numscalar("r(" + n[i] + ")"), "%21x"))
	}
	n = sort(st_dir("r()", "macro", "*"), 1)
	for (i = 1; i <= rows(n); i++) out = out \ ("macro " + n[i], st_global("r(" + n[i] + ")"))
	n = sort(st_dir("r()", "matrix", "*"), 1)
	for (i = 1; i <= rows(n); i++) {
		m = st_matrix("r(" + n[i] + ")")
		out = out \ ("matrix " + n[i], strofreal(rows(m)) + "x" + strofreal(cols(m)) + ":" +
			(length(m) ? invtokens(strofreal(vec(m)', "%21x")) : ""))
	}
	if ((p = findexternal("_fxb_r_" + tag)) == NULL) p = crexternal("_fxb_r_" + tag)
	*p = out
}

void _fxb_cmpr(string scalar names, real scalar all, string scalar what)
{
	string matrix a, b
	string rowvector nm
	string colvector va, vb
	real scalar i

	a = *findexternal("_fxb_r_a")
	b = *findexternal("_fxb_r_b")
	if (all) {
		if (a == b) return
		errprintf("%s: r() differs\n", what)
		for (i = 1; i <= rows(a); i++) errprintf("  off: %s = %s\n", a[i, 1], a[i, 2])
		for (i = 1; i <= rows(b); i++) errprintf("  on:  %s = %s\n", b[i, 1], b[i, 2])
		exit(9)
	}
	nm = tokens(names)
	for (i = 1; i <= cols(nm); i++) {
		va = select(a[., 2], regexm(a[., 1], "^[a-z]+ " + nm[i] + char(36)))
		vb = select(b[., 2], regexm(b[., 1], "^[a-z]+ " + nm[i] + char(36)))
		if (rows(va) != 1 | rows(vb) != 1) {
			errprintf("%s: r(%s) missing (%g with fastata off, %g on)\n", what, nm[i], rows(va), rows(vb))
			exit(9)
		}
		if (va != vb) {
			errprintf("%s: r(%s) differs: %s vs %s\n", what, nm[i], va, vb)
			exit(9)
		}
	}
}

void _fxb_cmplogs(string scalar fa, string scalar fb, string scalar what, string scalar kind)
{
	string colvector a, b
	real scalar i

	a = cat(fa)
	b = cat(fb)
	if (a == b) return
	for (i = 1; i <= min((rows(a), rows(b))); i++) {
		if (a[i] != b[i]) break
	}
	errprintf("%s: %s differs at line %g:\n", what, kind, i)
	errprintf("  off: %s\n", _fxb_esc(i <= rows(a) ? a[i] : "(end)"))
	errprintf("  on:  %s\n", _fxb_esc(i <= rows(b) ? b[i] : "(end)"))
	exit(9)
}

// s with SMCL braces escaped, so that tags show in the message
string scalar _fxb_esc(string scalar s)
{
	return(subinstr(subinstr(subinstr(s, "{", char(1), .), "}", "{c )-}", .), char(1), "{c -(}"))
}
end
