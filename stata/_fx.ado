*! version 0.1.0  Leo Liu  15oct2026
*! _fx: the fastata runtime. Mata functions defined in an ado-file are private to that file, so
*! everything that needs the functions below goes through this program:
*!     _fx <subcommand> <arguments>
*! Results come back as locals of the caller. No subcommand touches the data, the sort order or
*! the random-number generators, except verify (below). Mata names are prefixed _fx_. Backquotes
*! and single quotes in Mata strings are built with char(96) and char(39): macros are expanded in
*! ado-file Mata code. Mata lines that print nothing run under quietly: a non-quiet mata: line
*! switches an SMCL log to {res}, which the original commands' logs would not show.
*!
*! For the _fx_<cmd> programs:
*!   gate <key>                        fx_ok: 1 if every original file of key is verified; fx_why;
*!                                     fx_vpend: 1 in verify mode when fx_ok is 1 (gate has then
*!                                     copied the current frame to frame __fx_vsnap)
*!   count <cmd> fast|fallback ["<reason>"]
*!   orig <cmd>                        fx_prog: the program that runs cmd's original ado-file
*!   verify <cmd> <caller> <rc0> <frc> <fleft> "<byvars>" "<byrc0>" <tol> "<rspec>" "<args>"
*!                                     after a fast path that ran with fx_vpend 1, with frc its
*!                                     return code and fleft the c(rc) it left ("": not compared,
*!                                     the fast path does not reproduce it): runs the original
*!                                     (quietly) on the snapshot, as the shim would have (caller
*!                                     version, by prefix, arguments, c(rc) rc0 at entry) from the
*!                                     random-number states at gate, compares its result with the
*!                                     fast path's (rspec: "name value" pairs of r() scalars; tol:
*!                                     reldif for values, 0 bitwise), counts verify_ok,
*!                                     verify_mismatch or verify_skipped, keeps the original's
*!                                     data (and r(), c(rc), random-number states) and sets
*!                                     fx_vrc to the original's return code
*! For fastata and the tests:
*!   mode auto|original|verify         original: every replaced command runs its original;
*!                                     verify: every fast path is checked against the original
*!                                     (see verify). Without a mode set this session (clear all
*!                                     forgets it), the mode is env FASTATA_MODE, else auto
*!   counts_save "<file.csv>"          this session's counts as cmd,fast,fallback,last_reason
*!   reset                             forgets cached gate verdicts, file hashes and gate list
*!   runtime "<dir>" <version>         builds runtime directory dir
*!   rtpath                            fx_rt: the runtime directory for the current PLUS
*!   rtversion "<dir>"                 fx_have: the version dir was built for ("" if none)
*!   onpath "<dir>"                    fx_onpath: 1 if dir is on the ado-path; fx_active: the
*!                                     runtime directory in use ("" if none)
*!   pathpos "<dir>"                   fx_pos: ado-path positions of dir and of every runtime
*!                                     directory, highest first
*!   rmruntime "<dir>"                 erases runtime directory dir
*!   mkdirp "<dir>"                    creates dir and missing parents
*!   profile_first "<PATH>" "<home>" "<rt>"      fx_profile: first existing profile.do, or ""
*!   profile_with_block "<PATH>" "<home>" "<rt>" fx_profiles: those with the startup lines
*!   has_block "<file>"                fx_hasblock: 1 if file has the startup lines
*!   profile_write "<file>" 0|1        fx_rc: removes the startup lines, then adds them if 1
*!   block                             displays the startup lines as an error message
*!   status                            fx_mode; fx_orig_<c>, fx_ver_<c>, fx_nfast_<c>, fx_nfb_<c>,
*!                                     fx_last_<c>, fx_vok_<c>, fx_vmis_<c>, fx_vskip_<c> for
*!                                     every replaced command c
*!   filehash "<file>"                 fx_bytes, fx_hash: what the gate list records for file
*! For fast paths (two-phase protocol, see src/cache.rs):
*!   threads                           fx_threads: the plugin's threads= value
*!   store <token> <type> <name> [<type> <name> ...]
*!                                     adds the variables (nofill) and fills them from the
*!                                     plugin's cache, under nobreak; on failure drops them again
*!                                     and exits with the plugin's return code
program _fx
	version 16
	args sub
	if "`sub'" == "gate" {
		args sub key
		local envm : env FASTATA_MODE
		quietly mata: _fx_gate_check(st_local("key"), st_local("envm"))
		c_local fx_ok `fx_ok'
		c_local fx_why `"`fx_why'"'
		* verify mode: the snapshot that verify runs the original on, taken before the fast path
		* changes anything
		if "`fx_vmode'" == "1" VSnap
		c_local fx_vpend `fx_vmode'
	}
	else if "`sub'" == "count" {
		args sub cmd kind why
		quietly mata: _fx_count(st_local("cmd"), st_local("kind"), st_local("why"))
		* a fallback does not need the snapshot that gate took in verify mode
		if `fx_vdrop' capture frame drop __fx_vsnap
		* FASTATA_COUNTS names a file that gets one line per call (the replication harness reads
		* it; unlike the session counters it survives clear all)
		local f : env FASTATA_COUNTS
		if `"`f'"' != "" & !`fx_skip' {
			tempname fh
			capture file open `fh' using `"`f'"', write text append
			if !_rc {
				file write `fh' `"`cmd',`kind',`why'"' _n
				file close `fh'
			}
		}
	}
	else if "`sub'" == "verify" {
		args sub cmd caller rc0 frc fleft byv byrc0 tol rspec cargs
		quietly mata: _fx_vtake()
		local orc `frc'
		* fleft "": the fast path does not reproduce the c(rc) that the original leaves
		local oleft = cond("`fleft'" == "", "0", "`fleft'")
		if "`fx_vframe'" != "" {
			capture _fx orig `cmd'
			if _rc {
				local fx_vwhy "original r(`=_rc')"
				capture frame drop `fx_vframe'
				local fx_vframe
			}
		}
		if "`fx_vframe'" == "" {
			_fx count `cmd' verify_skipped `"`fx_vwhy'"'
		}
		else {
			* the original from the random-number states at the start of the call, so that it
			* leaves them as a run without fastata would; nothing below draws from them. The fast
			* paths draw from neither, so the states are set back only if one changed: setting
			* the sort state (even to its current value) also restarts a stream that c(sortrngstate)
			* does not show (collapse breaks ties from it), which a run without fastata would
			* continue
			if c(rngstate) != `"`fx_vrs'"' set rngstate `fx_vrs'
			if c(sortrngstate) != `"`fx_vsrs'"' set sortrngstate `fx_vsrs'
			local fx_oleft
			quietly mata: _fx_vinset(1)
			frame `fx_vframe' {
				capture quietly VRun `fx_prog' `caller' `rc0' `"`byv'"' `"`byrc0'"' `"`cargs'"'
				local orc = _rc
				local sbo : sortedby
				local dlo : data label
			}
			quietly mata: _fx_vinset(0)
			local sbf : sortedby
			local dlf : data label
			local fx_vdiff
			if `frc' != `orc' local fx_vdiff "return code `frc' vs `orc'"
			else quietly mata: _fx_vcompare("`fx_vframe'", `tol', st_local("rspec"))
			if `"`fx_vdiff'"' == "" & `orc' == 0 & "`fleft'" != "" & "`fleft'" != "`fx_oleft'" {
				local fx_vdiff "c(rc) left `fleft' vs `fx_oleft'"
			}
			if `orc' == 0 & "`fx_oleft'" != "" local oleft `fx_oleft'
			* keep the original's data: the frame it ran in takes the place of the current one
			local cur = c(frame)
			frame rename `cur' __fx_vold
			frame rename `fx_vframe' `cur'
			frame change `cur'
			frame drop __fx_vold
			if `"`fx_vdiff'"' == "" _fx count `cmd' verify_ok
			else {
				* egen: the function first, then the call (its start), so a line identifies the case
				if "`cmd'" == "egen" {
					local fx_vfcn
					if ustrregexm(`"`cargs'"', "=\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(") local fx_vfcn = ustrregexs(1) + "(): "
					local fx_vdiff `"`fx_vfcn'`fx_vdiff' | `=usubstr(strtrim(`"`cargs'"'), 1, 70)'"'
				}
				quietly mata: st_local("fx_vdiff", _fx_vclean(st_local("fx_vdiff")))
				_fx count `cmd' verify_mismatch `"`fx_vdiff'"'
			}
		}
		c_local fx_vrc `orc'
		* c(rc) as the original left it
		capture error `oleft'
	}
	else if "`sub'" == "orig" {
		args sub cmd
		quietly mata: _fx_orig_prog(st_local("cmd"))
		if `"`fx_err'"' != "" {
			di as err `"fastata: `fx_err'"'
			exit 198
		}
		if "`fx_prog'" == "" {
			di as err "command `cmd' is unrecognized"
			exit 199
		}
		c_local fx_prog `fx_prog'
	}
	else if "`sub'" == "threads" {
		local t = cond(c(MP), c(processors), 0)
		c_local fx_threads `t'
	}
	else if "`sub'" == "store" {
		gettoken sub rest : 0
		gettoken token rest : rest
		local types
		local names
		while `"`rest'"' != "" {
			gettoken t rest : rest
			gettoken n rest : rest
			local types `types' `t'
			local names `names' `n'
		}
		local threads = cond(c(MP), c(processors), 0)
		nobreak {
			quietly mata: (void) st_addvar(tokens(st_local("types")), tokens(st_local("names")), 1)
			_fx_call `names', store "token=`token'" "threads=`threads'"
			if `fx_plugrc' {
				drop `names'
				if `"`fx_errmsg'"' != "" di as err `"`fx_errmsg'"'
				exit `fx_plugrc'
			}
		}
	}
	else if "`sub'" == "mode" {
		args sub mode
		if !inlist("`mode'", "auto", "original", "verify") {
			di as err "_fx mode: specify auto, original or verify"
			exit 198
		}
		quietly mata: _fx_setmode(st_local("mode"))
	}
	else if "`sub'" == "counts_save" {
		args sub path
		quietly mata: _fx_counts_save(st_local("path"))
	}
	else if "`sub'" == "reset" {
		quietly mata: _fx_reset()
	}
	else if "`sub'" == "runtime" {
		args sub dir ver
		quietly mata: _fx_runtime_build(st_local("dir"), st_local("ver"))
	}
	else if "`sub'" == "rtpath" {
		quietly mata: st_local("fx_rt", _fx_rtpath())
		c_local fx_rt `"`fx_rt'"'
	}
	else if "`sub'" == "rtversion" {
		args sub dir
		quietly mata: st_local("fx_have", _fx_rtversion(st_local("dir")))
		c_local fx_have `"`fx_have'"'
	}
	else if "`sub'" == "onpath" {
		args sub dir
		quietly mata: _fx_onpath(st_local("dir"))
		c_local fx_onpath `fx_onpath'
		c_local fx_active `"`fx_active'"'
	}
	else if "`sub'" == "pathpos" {
		args sub dir
		quietly mata: _fx_pathpos(st_local("dir"))
		c_local fx_pos `fx_pos'
	}
	else if "`sub'" == "rmruntime" {
		args sub dir
		quietly mata: _fx_rmruntime(st_local("dir"))
	}
	else if "`sub'" == "mkdirp" {
		args sub dir
		quietly mata: _fx_mkdirp(st_local("dir"))
	}
	else if inlist("`sub'", "profile_first", "profile_with_block") {
		args sub envpath home rt
		quietly mata: _fx_`sub'(st_local("envpath"), st_local("home"), st_local("rt"))
		if "`sub'" == "profile_first" c_local fx_profile `"`fx_profile'"'
		else c_local fx_profiles `"`fx_profiles'"'
	}
	else if "`sub'" == "has_block" {
		args sub file
		quietly mata: st_local("fx_hasblock", strofreal(_fx_has_block(st_local("file"))))
		c_local fx_hasblock `fx_hasblock'
	}
	else if "`sub'" == "profile_write" {
		args sub file add
		quietly mata: _fx_profile_write(st_local("file"), `add')
		c_local fx_rc `fx_rc'
	}
	else if "`sub'" == "block" {
		mata: printf("{err}%s\n", invtokens(_fx_block()', char(10)))
	}
	else if "`sub'" == "status" {
		local envm : env FASTATA_MODE
		quietly mata: _fx_status(st_local("envm"))
		c_local fx_mode `fx_mode'
		foreach c in egen isid duplicates xtile pctile destring tostring {
			foreach s in orig ver nfast nfb last vok vmis vskip {
				c_local fx_`s'_`c' `"`fx_`s'_`c''"'
			}
		}
	}
	else if "`sub'" == "filehash" {
		args sub file
		quietly mata: _fx_hash_locals(st_local("file"))
		c_local fx_bytes `fx_bytes'
		c_local fx_hash `fx_hash'
	}
	else {
		di as err `"_fx: unknown subcommand `sub'"'
		exit 198
	}
end

* Verify mode, from gate: copies the current frame to frame __fx_vsnap and records the
* random-number states (reading them does not advance them), or records why it could not.
program VSnap
	capture frame drop __fx_vsnap
	local srs = c(sortrngstate)
	local rs = c(rngstate)
	local why
	capture frame copy `c(frame)' __fx_vsnap
	if _rc {
		local why "snapshot r(`=_rc')"
		capture frame drop __fx_vsnap
	}
	else quietly mata: _fx_vlorder("__fx_vsnap")
	quietly mata: _fx_vset(st_local("why"), st_local("srs"), st_local("rs"))
end

* Verify mode: runs original program prog as the shim would have run it (caller version, by
* prefix, arguments, c(rc) at entry); sets fx_oleft in the caller to the c(rc) it leaves.
program VRun
	args prog caller rc0 byv byrc0 cargs
	capture error `rc0'
	if `"`byv'"' != "" {
		version `caller': by `byv' `byrc0': `prog' `cargs'
	}
	else {
		version `caller': `prog' `cargs'
	}
	c_local fx_oleft `=c(rc)'
end

version 16
mata:

// ---------------------------------------------------------------------------- strings

// `name' (a macro reference, as text)
string scalar _fx_q(string scalar name)
{
	return(char(96) + name + char(39))
}

// `"s"' (compound double quotes)
string scalar _fx_cq(string scalar s)
{
	return(char(96) + char(34) + s + char(34) + char(39))
}

// Lines of a text file, with a trailing carriage return removed from each line.
string colvector _fx_lines(string scalar path)
{
	string colvector l
	real scalar i

	l = cat(path)
	for (i = 1; i <= rows(l); i++) {
		if (strlen(l[i])) {
			if (substr(l[i], -1, 1) == char(13)) l[i] = substr(l[i], 1, strlen(l[i]) - 1)
		}
	}
	return(l)
}

string scalar _fx_join(string colvector l)
{
	if (rows(l) == 0) return("")
	return(invtokens(l', char(10)))
}

// (bytes, hash1) of the normalised text of a file: its lines joined with char(10).
real rowvector _fx_texthash(string scalar path)
{
	string scalar t

	t = _fx_join(_fx_lines(path))
	return((strlen(t), hash1(t)))
}

// Sets locals fx_bytes and fx_hash of the file at path.
void _fx_hash_locals(string scalar path)
{
	real rowvector bh

	bh = _fx_texthash(path)
	st_local("fx_bytes", strofreal(bh[1], "%20.0f"))
	st_local("fx_hash", strofreal(bh[2], "%20.0f"))
}

string scalar _fx_hex8(real scalar h)
{
	string scalar s

	s = inbase(16, h)
	if (strlen(s) < 8) s = (8 - strlen(s)) * "0" + s
	return(s)
}

// ---------------------------------------------------------------------------- externals

// Pointer to the external asarray `name', created on first use.
pointer(transmorphic scalar) scalar _fx_ext(string scalar name)
{
	pointer(transmorphic scalar) scalar p

	if ((p = findexternal(name)) == NULL) {
		p = crexternal(name)
		*p = asarray_create()
	}
	return(p)
}

// ---------------------------------------------------------------------------- adopath

// Strips compound or plain double quotes around an adopath entry.
string scalar _fx_unq(string scalar t)
{
	if (substr(t, 1, 2) == char(96) + char(34) & substr(t, -2, 2) == char(34) + char(39)) {
		return(substr(t, 3, strlen(t) - 4))
	}
	if (strlen(t) >= 2 & substr(t, 1, 1) == char(34) & substr(t, -1, 1) == char(34)) {
		return(substr(t, 2, strlen(t) - 2))
	}
	return(t)
}

// A directory in comparable form: forward slashes, one trailing slash, lower case on Windows.
string scalar _fx_normdir(string scalar d)
{
	string scalar s

	s = subinstr(strtrim(d), char(92), "/", .)
	if (s != "" & substr(s, -1, 1) != "/") s = s + "/"
	if (c("os") == "Windows") s = strlower(s)
	return(s)
}

// The entries of the ado-path ($S_ADO) in order, as written there. Once the ado-path has been
// changed, Stata writes every entry in compound quotes, codewords included ("BASE").
string rowvector _fx_adotokens()
{
	string scalar s, tok
	string rowvector out
	real scalar i, n, j

	s = st_global("S_ADO")
	out = J(1, 0, "")
	i = 1
	n = strlen(s)
	while (i <= n) {
		if (substr(s, i, 2) == char(96) + char(34)) {
			j = strpos(substr(s, i + 2, .), char(34) + char(39))
			if (j == 0) {
				tok = substr(s, i, .)
				i = n + 1
			}
			else {
				tok = substr(s, i, j + 3)
				i = i + j + 3
			}
		}
		else {
			j = strpos(substr(s, i, .), ";")
			if (j == 0) {
				tok = substr(s, i, .)
				i = n + 1
			}
			else {
				tok = substr(s, i, j - 1)
				i = i + j - 1
			}
		}
		if (strtrim(tok) != "") out = out, strtrim(tok)
		while (i <= n) {
			if (substr(s, i, 1) != ";") break
			i++
		}
	}
	return(out)
}

// An adopath entry as a directory: quotes removed, codewords resolved through c(sysdir_*).
string scalar _fx_tokdir(string scalar t)
{
	string scalar u

	u = strupper(_fx_unq(t))
	if (u == "BASE") return(c("sysdir_base"))
	if (u == "SITE") return(c("sysdir_site"))
	if (u == "PLUS") return(c("sysdir_plus"))
	if (u == "PERSONAL") return(c("sysdir_personal"))
	if (u == "OLDPLACE") return(c("sysdir_oldplace"))
	if (u == "STATA") return(c("sysdir_stata"))
	return(_fx_unq(t))
}

// 1 if ado-path entry tok is directory rt or any fastata runtime directory (one that holds
// fastata_runtime.txt). A second runtime directory appears when PLUS changes after fastata was
// turned on; its shims must never be taken for originals.
real scalar _fx_isrtdir(string scalar tok, string scalar rt)
{
	string scalar d

	d = _fx_normdir(_fx_tokdir(tok))
	if (rt != "") {
		if (d == _fx_normdir(rt)) return(1)
	}
	return(fileexists(d + "fastata_runtime.txt"))
}

// The ado-path without directory rt and any other runtime directory (as a findfile() path).
string scalar _fx_pathminus(string scalar rt)
{
	string rowvector t
	string scalar out
	real scalar i

	t = _fx_adotokens()
	out = ""
	for (i = 1; i <= cols(t); i++) {
		if (_fx_isrtdir(t[i], rt)) continue
		out = out + (out == "" ? "" : ";") + t[i]
	}
	return(out)
}

// The active runtime directory: where the first fastata_runtime.txt on the ado-path is, or "".
string scalar _fx_rtdir()
{
	string scalar p

	p = findfile("fastata_runtime.txt")
	if (p == "") return("")
	return(substr(p, 1, strlen(p) - strlen("fastata_runtime.txt")))
}

// Everything that changes which file a name resolves to.
string scalar _fx_state()
{
	return(st_global("S_ADO") + char(1) + c("sysdir_base") + char(1) + c("sysdir_site") + char(1)
		+ c("sysdir_plus") + char(1) + c("sysdir_personal") + char(1) + c("sysdir_oldplace")
		+ char(1) + c("pwd"))
}

// (runtime directory, ado-path without it) for the current state; cached per state.
string rowvector _fx_info()
{
	pointer(transmorphic scalar) scalar p
	string scalar st, rt
	string rowvector v

	p = _fx_ext("_fx_infos")
	st = _fx_state()
	if (asarray_contains(*p, st)) return(asarray(*p, st))
	rt = _fx_rtdir()
	v = (rt, _fx_pathminus(rt))
	asarray(*p, st, v)
	return(v)
}

// Where the original file fn resolves, ignoring the runtime directory ("" if nowhere).
string scalar _fx_findorig(string scalar fn)
{
	return(findfile(fn, _fx_info()[2]))
}

// ---------------------------------------------------------------------------- gate

// The gate list: rows (key, file, bytes, hash) from the "* gate <key> <file> <bytes> <hash>"
// lines of _fx_gatelist.ado (written by scripts/gen_gatelist.do; an ado-file because net install
// installs no .txt files), read on first use. No list means nothing is verified.
string matrix _fx_gates()
{
	pointer() scalar p
	string colvector l
	string rowvector t
	string matrix g
	string scalar path
	real scalar i

	if ((p = findexternal("_fx_gl")) != NULL) return(*p)
	g = J(0, 4, "")
	path = findfile("_fx_gatelist.ado")
	if (path != "") {
		l = _fx_lines(path)
		for (i = 1; i <= rows(l); i++) {
			if (substr(l[i], 1, 7) != "* gate ") continue
			t = tokens(substr(l[i], 8, .))
			if (cols(t) == 4) g = g \ t
		}
	}
	p = crexternal("_fx_gl")
	*p = g
	return(g)
}

// Forgets the cached gate list, gate verdicts, file hashes and ado-path lookups (after the
// runtime directory was rebuilt). Counters and the mode stay.
void _fx_reset()
{
	string rowvector e
	real scalar i

	e = ("_fx_gl", "_fx_verdicts", "_fx_hashes", "_fx_infos", "_fx_progs")
	for (i = 1; i <= cols(e); i++) rmexternal(e[i])
}

// (bytes, hash) of the file at path; cached by path for the session.
real rowvector _fx_filehash(string scalar path)
{
	pointer(transmorphic scalar) scalar p
	real rowvector v

	p = _fx_ext("_fx_hashes")
	if (asarray_contains(*p, path)) return(asarray(*p, path))
	v = _fx_texthash(path)
	asarray(*p, path, v)
	return(v)
}

// The distinct elements of x in order of first appearance. Unlike uniqrows(), sort() and
// order(), it does not draw from the random-number generator that breaks Stata's sort ties
// (sortseed), so that checking the gate leaves later sort ties, and so the results of an
// original that depends on them, as they would be without fastata.
string colvector _fx_uniq(string colvector x)
{
	transmorphic scalar seen
	string colvector out
	real scalar i

	seen = asarray_create()
	out = J(0, 1, "")
	for (i = 1; i <= rows(x); i++) {
		if (!asarray_contains(seen, x[i])) {
			asarray(seen, x[i], 1)
			out = out \ x[i]
		}
	}
	return(out)
}

// ("1", "") when every file of key resolves to a verified version, else ("0", reason).
string rowvector _fx_verdict(string scalar key)
{
	string matrix g, gr, acc
	string colvector files
	string scalar f, p
	real rowvector bh
	real scalar i

	g = _fx_gates()
	gr = select(g, g[., 1] :== key)
	if (rows(gr) == 0) return(("0", "no gate for " + key))
	files = _fx_uniq(gr[., 2])
	for (i = 1; i <= rows(files); i++) {
		f = files[i]
		p = _fx_findorig(f)
		if (p == "") return(("0", "missing " + f))
		bh = _fx_filehash(p)
		acc = select(gr, gr[., 2] :== f)
		if (!any(acc[., 3] :== strofreal(bh[1], "%20.0f") :& acc[., 4] :== strofreal(bh[2], "%20.0f"))) {
			return(("0", "unverified " + f))
		}
	}
	return(("1", ""))
}

// Sets locals fx_ok and fx_why, and fx_vmode (1 when the fast path is to be verified). Verdicts
// are cached per key and state. envm: the value of env FASTATA_MODE.
void _fx_gate_check(string scalar key, string scalar envm)
{
	pointer(transmorphic scalar) scalar pv
	string scalar ck, mode
	string rowvector v

	st_local("fx_vmode", "0")
	mode = _fx_getmode(envm)
	if (mode == "original") {
		st_local("fx_ok", "0")
		st_local("fx_why", "mode original")
		return
	}
	// a replaced command that an original calls while verify runs it: the original's call
	if (_fx_vin()) {
		st_local("fx_ok", "0")
		st_local("fx_why", "verify run")
		return
	}
	pv = _fx_ext("_fx_verdicts")
	ck = key + char(0) + _fx_state()
	if (asarray_contains(*pv, ck)) v = asarray(*pv, ck)
	else {
		v = _fx_verdict(key)
		asarray(*pv, ck, v)
	}
	st_local("fx_ok", v[1])
	st_local("fx_why", v[2])
	if (mode == "verify" & v[1] == "1") st_local("fx_vmode", "1")
}

void _fx_setmode(string scalar mode)
{
	pointer() scalar p

	if ((p = findexternal("_fx_mode_v")) == NULL) p = crexternal("_fx_mode_v")
	*p = mode
}

// The mode: the one set by _fx mode, else envm (env FASTATA_MODE, which survives clear all; clear
// all drops Mata externals) when it is auto, original or verify, else auto.
string scalar _fx_getmode(string scalar envm)
{
	pointer() scalar p
	string scalar e

	if ((p = findexternal("_fx_mode_v")) != NULL) {
		if (*p != "") return(*p)
	}
	e = strlower(strtrim(envm))
	if (e == "original" | e == "verify") return(e)
	return("auto")
}

// ---------------------------------------------------------------------------- verify mode

// Records the pending verification of the running fast path: why it cannot be verified ("" when
// frame __fx_vsnap holds the snapshot), and the sort and regular random-number states.
void _fx_vset(string scalar why, string scalar srs, string scalar rs)
{
	pointer() scalar p

	if ((p = findexternal("_fx_vrec")) == NULL) p = crexternal("_fx_vrec")
	*p = (why, srs, rs)
}

// Takes the pending verification: locals fx_vframe (the snapshot frame, "" if none), fx_vwhy,
// fx_vsrs and fx_vrs.
void _fx_vtake()
{
	pointer() scalar p
	string rowvector r

	if ((p = findexternal("_fx_vrec")) == NULL) r = ("no snapshot", "", "")
	else {
		r = *p
		rmexternal("_fx_vrec")
	}
	st_local("fx_vframe", r[1] == "" ? "__fx_vsnap" : "")
	st_local("fx_vwhy", r[1])
	st_local("fx_vsrs", r[2])
	st_local("fx_vrs", r[3])
}

// 1 while verify runs an original.
real scalar _fx_vin()
{
	pointer() scalar p

	if ((p = findexternal("_fx_vin_v")) == NULL) return(0)
	return(*p)
}

void _fx_vinset(real scalar on)
{
	pointer() scalar p

	if ((p = findexternal("_fx_vin_v")) == NULL) p = crexternal("_fx_vin_v")
	*p = on
}

// Text for a FASTATA_COUNTS field: no commas, quotes or line breaks, at most 200 characters.
string scalar _fx_vclean(string scalar s)
{
	string scalar t

	t = subinstr(subinstr(subinstr(s, ",", ";", .), char(34), "'", .), char(96), "'", .)
	t = subinstr(subinstr(t, char(10), " ", .), char(13), " ", .)
	return(usubstr(t, 1, 200))
}

// Metadata lines of the current frame: N, sortedby sb, data label dl, every variable (position,
// name, type, format, value label, variable label), every characteristic (notes included) of
// _dta and of the variables, and the definition of every value label in labs.
string colvector _fx_vmeta(string scalar sb, string scalar dl, string rowvector labs)
{
	string colvector out, names, txt
	string rowvector vars
	real colvector vals
	real scalar i, j

	out = ("N " + strofreal(st_nobs(), "%20.0f")) \ ("sortedby " + sb) \ ("data label " + dl)
	vars = st_nvar() ? st_varname(1..st_nvar()) : J(1, 0, "")
	for (i = 1; i <= cols(vars); i++) {
		out = out \ ("variable " + strofreal(i) + " " + vars[i] + " " + st_vartype(i) + " "
			+ st_varformat(i) + " [" + st_varvaluelabel(i) + "] " + st_varlabel(i))
	}
	vars = "_dta", vars
	for (i = 1; i <= cols(vars); i++) {
		names = st_dir("char", vars[i], "*")
		for (j = 1; j <= rows(names); j++) {
			out = out \ ("char " + vars[i] + "[" + names[j] + "] "
				+ st_global(vars[i] + "[" + names[j] + "]"))
		}
	}
	for (i = 1; i <= cols(labs); i++) {
		st_vlload(labs[i], vals, txt)
		for (j = 1; j <= rows(vals); j++) {
			out = out \ ("label " + labs[i] + " " + strofreal(vals[j], "%21x") + " " + txt[j])
		}
	}
	return(out)
}

// "" when a and b hold the same lines (in any order), else a line of one missing from the other.
// (No sort: sorting can draw from the sort random-number generator.)
string scalar _fx_vlinediff(string colvector a, string colvector b)
{
	transmorphic scalar ca
	real scalar i, n

	ca = asarray_create()
	asarray_notfound(ca, 0)
	for (i = 1; i <= rows(a); i++) asarray(ca, a[i], asarray(ca, a[i]) + 1)
	for (i = 1; i <= rows(b); i++) {
		n = asarray(ca, b[i])
		if (n == 0) return("original has: " + b[i])
		asarray(ca, b[i], n - 1)
	}
	for (i = 1; i <= rows(a); i++) {
		if (asarray(ca, a[i]) > 0) return("fast path has: " + a[i])
	}
	return("")
}

// Names of the value labels defined in the current frame (r() is kept).
string rowvector _fx_vlabs()
{
	string rowvector l

	stata("_return hold __fx_vr")
	stata("quietly label dir")
	l = tokens(st_global("r(names)"))
	stata("_return restore __fx_vr")
	return(l)
}

// Defines the value labels of frame snap again, oldest first, so that they come in the order of
// the current frame: frame copy reverses that order, which later commands show (append's and
// merge's "label ... already defined" notes follow it). A label with an empty text, no values or
// a value listed twice (files written by other software; dataverse-6KG67M) is left alone:
// st_vlmodify() would drop those entries or not create the label.
void _fx_vlorder(string scalar snap)
{
	string rowvector l
	string colvector txt
	string scalar cur
	real colvector vals
	real scalar i

	l = _fx_vlabs()
	if (cols(l) < 2) return
	cur = st_framecurrent()
	st_framecurrent(snap)
	if (_fx_vlabs() != l) {
		for (i = cols(l); i >= 1; i--) {
			st_vlload(l[i], vals, txt)
			if (rows(vals) == 0 | anyof(txt, "") | _fx_hasdup(vals)) continue
			st_vldrop(l[i])
			st_vlmodify(l[i], vals, txt)
		}
	}
	st_framecurrent(cur)
}

// 1 if v holds a value more than once. (No sort: sorting can draw from the sort random-number
// generator.)
real scalar _fx_hasdup(real colvector v)
{
	transmorphic scalar a
	real scalar i

	a = asarray_create("real")
	for (i = 1; i <= rows(v); i++) {
		if (asarray_contains(a, v[i])) return(1)
		asarray(a, v[i], 1)
	}
	return(0)
}

// Compares the current frame (the fast path's result) with frame snap (the original's result):
// metadata (_fx_vmeta, with locals sbf, dlf, sbo, dlo), then values: strings and missing codes
// exactly, numbers bitwise (the sign of zero included), or within reldif tol when tol > 0. rspec
// lists "name value" pairs of the fast path's r() scalars, compared with r() as the original
// left it. Sets local fx_vdiff to "" or a short description of the first difference.
void _fx_vcompare(string scalar snap, real scalar tol, string scalar rspec)
{
	string scalar cur, d
	string colvector sa, sb
	string rowvector rs
	real colvector a, b, ma, mb, z, nm, na, nb
	real matrix rv
	real scalar j, k, str

	d = ""
	rs = tokens(rspec)
	for (k = 1; k + 1 <= cols(rs); k = k + 2) {
		rv = st_numscalar("r(" + rs[k] + ")")
		if (rows(rv) == 0) {
			d = "r(" + rs[k] + ") not set by the original"
			break
		}
		if (rv != strtoreal(rs[k + 1])) {
			d = "r(" + rs[k] + ") " + rs[k + 1] + " vs " + strofreal(rv, "%20.0g")
			break
		}
	}
	cur = st_framecurrent()
	if (d == "") {
		sa = _fx_vmeta(st_local("sbf"), st_local("dlf"), _fx_vlabs())
		st_framecurrent(snap)
		sb = _fx_vmeta(st_local("sbo"), st_local("dlo"), _fx_vlabs())
		st_framecurrent(cur)
		d = _fx_vlinediff(sa, sb)
	}
	if (d == "") {
		for (j = 1; j <= st_nvar(); j++) {
			str = st_isstrvar(j)
			if (str) sa = st_sdata(., j)
			else a = st_data(., j)
			st_framecurrent(snap)
			if (str) sb = st_sdata(., j)
			else b = st_data(., j)
			st_framecurrent(cur)
			// NaN (a plugin or Mata's st_store() can store one; NaN != NaN) compares by its bits;
			// equal NaNs then count as equal values below
			if (!str) {
				na = selectindex(a :!= a)
				nb = selectindex(b :!= b)
				if (length(na) | length(nb)) {
					if (length(na) != length(nb)) d = "NaN values of " + st_varname(j)
					else if (na != nb | any(strofreal(a[na], "%21x") :!= strofreal(b[nb], "%21x"))) {
						d = "NaN values of " + st_varname(j)
					}
					else {
						a[na] = J(length(na), 1, 0)
						b[nb] = J(length(nb), 1, 0)
					}
				}
				if (d != "") break
			}
			if (str) {
				if (sa != sb) d = "strings of " + st_varname(j) + " (" + strofreal(sum(sa :!= sb), "%20.0f") + " obs; first " +
					_fx_vfirst(sa :!= sb) + ")"
			}
			else if (tol == 0) {
				if (a != b) d = "values of " + st_varname(j) + " (" + strofreal(sum(a :!= b), "%20.0f") + " obs; first " +
					_fx_vfirst(a :!= b, a, b) + ")"
				else {
					z = selectindex(a :== 0)
					if (length(z)) {
						if (any(strofreal(a[z], "%21x") :!= strofreal(b[z], "%21x"))) {
							d = "sign of zero in " + st_varname(j)
						}
					}
				}
			}
			else {
				ma = a :>= .
				mb = b :>= .
				if (ma != mb) d = "missing values of " + st_varname(j)
				else {
					if (any(select(a, ma) :!= select(b, mb))) d = "missing codes of " + st_varname(j)
					else {
						nm = selectindex(!ma)
						if (length(nm)) {
							if (max(reldif(a[nm], b[nm])) > tol) {
								d = ("values of " + st_varname(j) + " beyond the tolerance (max reldif "
									+ strofreal(max(reldif(a[nm], b[nm])), "%9.2e") + "; first "
									+ _fx_vfirst(reldif(a, b) :> tol :& !ma, a, b) + ")")
							}
						}
					}
				}
			}
			if (d != "") break
		}
	}
	st_local("fx_vdiff", _fx_vclean(d))
}

// "obs <i>" of the first observation flagged in diff, and for numbers "<fast> vs <original>"
// (%24.0g, or %21x when that does not show the difference).
string scalar _fx_vfirst(real colvector diff, | real colvector a, real colvector b)
{
	real colvector ix
	real scalar i
	string scalar fa, fb

	ix = selectindex(diff)
	i = ix[1]
	if (args() < 3) return("obs " + strofreal(i, "%20.0f"))
	fa = strofreal(a[i], "%24.0g")
	fb = strofreal(b[i], "%24.0g")
	if (fa == fb) {
		fa = strofreal(a[i], "%21x")
		fb = strofreal(b[i], "%21x")
	}
	return("obs " + strofreal(i, "%20.0f") + ": " + strtrim(fa) + " vs " + strtrim(fb))
}

// ---------------------------------------------------------------------------- counters

// Counts a call of cmd: kind fast, fallback, or verify_ok, verify_mismatch, verify_skipped. Sets
// locals fx_skip (1: a call that an original makes while verify runs it, not counted) and
// fx_vdrop (1: a fallback after gate took a snapshot, which is no longer needed).
void _fx_count(string scalar cmd, string scalar kind, string scalar why)
{
	pointer(transmorphic scalar) scalar pc, pw
	real rowvector v

	st_local("fx_skip", "0")
	st_local("fx_vdrop", "0")
	if (_fx_vin()) {
		st_local("fx_skip", "1")
		return
	}
	if (substr(kind, 1, 7) == "verify_") {
		pc = _fx_ext("_fx_vcnt")
		v = asarray_contains(*pc, cmd) ? asarray(*pc, cmd) : (0, 0, 0)
		if (kind == "verify_ok") v[1] = v[1] + 1
		else if (kind == "verify_mismatch") v[2] = v[2] + 1
		else v[3] = v[3] + 1
		asarray(*pc, cmd, v)
		return
	}
	pc = _fx_ext("_fx_cnt")
	pw = _fx_ext("_fx_why")
	v = asarray_contains(*pc, cmd) ? asarray(*pc, cmd) : (0, 0)
	if (kind == "fast") v[1] = v[1] + 1
	else {
		v[2] = v[2] + 1
		asarray(*pw, cmd, why)
		if (findexternal("_fx_vrec") != NULL) {
			rmexternal("_fx_vrec")
			st_local("fx_vdrop", "1")
		}
	}
	asarray(*pc, cmd, v)
}

// Sets locals fx_nfast, fx_nfb and fx_last for cmd, and its verify-mode counts fx_vok, fx_vmis
// and fx_vskip.
void _fx_count_get(string scalar cmd)
{
	pointer(transmorphic scalar) scalar pc, pw, pv
	real rowvector v, w

	pc = _fx_ext("_fx_cnt")
	pw = _fx_ext("_fx_why")
	pv = _fx_ext("_fx_vcnt")
	v = asarray_contains(*pc, cmd) ? asarray(*pc, cmd) : (0, 0)
	w = asarray_contains(*pv, cmd) ? asarray(*pv, cmd) : (0, 0, 0)
	st_local("fx_nfast", strofreal(v[1], "%20.0f"))
	st_local("fx_nfb", strofreal(v[2], "%20.0f"))
	st_local("fx_last", asarray_contains(*pw, cmd) ? asarray(*pw, cmd) : "")
	st_local("fx_vok", strofreal(w[1], "%20.0f"))
	st_local("fx_vmis", strofreal(w[2], "%20.0f"))
	st_local("fx_vskip", strofreal(w[3], "%20.0f"))
}

string rowvector _fx_cmds()
{
	return(("egen", "isid", "duplicates", "xtile", "pctile", "destring", "tostring"))
}

// Writes cmd,fast,fallback,last_reason for every replaced command.
void _fx_counts_save(string scalar path)
{
	string rowvector cm
	string colvector out
	real scalar i

	cm = _fx_cmds()
	out = "cmd,fast,fallback,last_reason"
	for (i = 1; i <= cols(cm); i++) {
		_fx_count_get(cm[i])
		out = out \ (cm[i] + "," + st_local("fx_nfast") + "," + st_local("fx_nfb") + ","
			+ char(34) + subinstr(st_local("fx_last"), char(34), char(34) + char(34), .) + char(34))
	}
	_fx_writelines(path, out)
}

// ---------------------------------------------------------------------------- files

// Creates directory d and any missing parents.
void _fx_mkdirp(string scalar d)
{
	string scalar s, cur
	string rowvector parts
	real scalar i

	s = subinstr(d, char(92), "/", .)
	if (s == "" | direxists(s)) return
	parts = ustrsplit(s, "/")
	cur = parts[1]
	for (i = 2; i <= cols(parts); i++) {
		cur = cur + "/" + parts[i]
		if (parts[i] != "" & !direxists(cur)) (void) _mkdir(cur)
	}
	if (!direxists(s)) {
		errprintf("fastata: could not create directory %s\n", d)
		exit(603)
	}
}

// Copies src to dst (replacing it). Returns Stata's return code.
real scalar _fx_copy(string scalar src, string scalar dst)
{
	return(_stata("copy " + _fx_cq(src) + " " + _fx_cq(dst) + ", replace", 1))
}

// Writes lines to path through a temporary file. Returns 0 or a return code.
real scalar _fx_writelines_rc(string scalar path, string colvector lines)
{
	string scalar tmp
	real scalar fh, i, rc

	tmp = st_tempfilename()
	fh = _fopen(tmp, "w")
	if (fh < 0) return(603)
	for (i = 1; i <= rows(lines); i++) fput(fh, lines[i])
	fclose(fh)
	rc = _fx_copy(tmp, path)
	(void) _unlink(tmp)
	return(rc)
}

void _fx_writelines(string scalar path, string colvector lines)
{
	real scalar rc

	if ((rc = _fx_writelines_rc(path, lines))) {
		errprintf("fastata: could not write %s\n", path)
		exit(rc)
	}
}

// ---------------------------------------------------------------------------- originals

// Sets local fx_prog to the name of the renamed copy of cmd's original ado-file, writing the
// copy into the runtime directory if needed. fx_prog is "" when the original is not found;
// fx_err is set when there is no runtime directory. Names are cached per command and state.
void _fx_orig_prog(string scalar cmd)
{
	pointer(transmorphic scalar) scalar pc
	string rowvector info
	string colvector lines
	string scalar ck, p, prog, dst

	st_local("fx_prog", "")
	st_local("fx_err", "")
	pc = _fx_ext("_fx_progs")
	ck = cmd + char(0) + _fx_state()
	if (asarray_contains(*pc, ck)) {
		st_local("fx_prog", asarray(*pc, ck))
		return
	}
	info = _fx_info()
	if (info[1] == "") {
		st_local("fx_err", "no fastata runtime directory on the ado-path")
		return
	}
	p = findfile(cmd + ".ado", info[2])
	if (p == "") return
	lines = _fx_lines(p)
	// Never take a shim for the original (that would recurse until Stata's nesting limit).
	if (rows(lines)) {
		if (strpos(lines[1], "*! fastata ") == 1 & strpos(lines[1], " shim for ")) {
			st_local("fx_err", "the original of " + cmd + " resolves to a fastata shim, " + p)
			return
		}
	}
	prog = "_fxo_" + _fx_hex8(hash1(_fx_join(lines))) + "_" + cmd
	dst = info[1] + prog + ".ado"
	if (!fileexists(dst)) _fx_writelines(dst, _fx_renamed(lines, cmd, prog))
	asarray(*pc, ck, prog)
	st_local("fx_prog", prog)
}

// The lines with every definition or drop of program cmd renamed to prog.
string colvector _fx_renamed(string colvector lines, string scalar cmd, string scalar prog)
{
	string colvector out
	string scalar re
	real scalar i

	re = "^(\s*(?:(?:cap(?:t(?:u(?:r(?:e)?)?)?)?|qui(?:e(?:t(?:l(?:y)?)?)?)?|noi(?:s(?:i(?:l(?:y)?)?)?)?)\s+)*"
	re = re + "pr(?:o(?:g(?:r(?:a(?:m)?)?)?)?)?\s+(?:(?:de(?:f(?:i(?:n(?:e)?)?)?)?|drop)\s+)?)"
	re = re + cmd + "(?![A-Za-z0-9_])"
	out = lines
	for (i = 1; i <= rows(out); i++) {
		if (ustrregexm(out[i], re)) {
			out[i] = ustrregexs(1) + prog + usubstr(out[i], ustrlen(ustrregexs(0)) + 1, .)
		}
	}
	return(out)
}

// ---------------------------------------------------------------------------- runtime

string rowvector _fx_rtfiles()
{
	return(("_fx.ado", "_fx_call.ado", "_fx_gatelist.ado", "_fx_egen.ado", "_fx_isid.ado",
		"_fx_duplicates.ado", "_fx_xtile.ado", "_fx_pctile.ado", "_fx_destring.ado",
		"_fx_tostring.ado"))
}

// The shim that takes over cmd: it calls _fx_<cmd> under the caller's version.
string colvector _fx_shim_lines(string scalar cmd, string scalar ver)
{
	string colvector l
	string scalar t, call

	t = char(9)
	l = "*! fastata " + ver + " shim for " + cmd + " (written by fastata; do not edit)"
	call = t + "version " + _fx_q("caller") + ": "
	if (cmd == "egen") {
		l = l \ "program egen, byable(onecall)"
	}
	else if (cmd == "duplicates") {
		l = l \ "program duplicates, rclass properties(twopart)"
	}
	else {
		l = l \ ("program " + cmd)
	}
	l = l \ (t + "local caller : display _caller()") \ (t + "version 16")
	if (cmd == "egen") {
		l = l \ (t + "local byp")
		l = l \ (t + "if _by() local byp by " + _fx_q("_byvars") + " " + _fx_q("_byrc0") + ":")
		l = l \ (call + _fx_q("byp") + " _fx_egen " + _fx_q("0"))
	}
	else if (cmd == "duplicates") {
		// rclass: an error exit would post this program's empty r() over the r() that the
		// original set before failing (r(N) before error 2000), so run under capture noisily
		// (same output and messages) and exit with the return code after return add
		l = l \ (t + "capture noisily version " + _fx_q("caller") + ": _fx_duplicates " + _fx_q("0"))
		l = l \ (t + "local rc = _rc") \ (t + "return add") \ (t + "exit " + _fx_q("rc"))
	}
	else {
		l = l \ (call + "_fx_" + cmd + " " + _fx_q("0"))
	}
	l = l \ "end"
	return(l)
}

// Builds or refreshes runtime directory dir for fastata version ver (see help fastata).
void _fx_runtime_build(string scalar dir0, string scalar ver)
{
	string scalar rd, src, f, p, old, plug
	string rowvector files, cmds
	string colvector stale
	real scalar i

	rd = subinstr(dir0, char(92), "/", .)
	if (substr(rd, -1, 1) != "/") rd = rd + "/"
	_fx_mkdirp(rd)
	src = _fx_pathminus(rd)

	files = _fx_rtfiles()
	for (i = 1; i <= cols(files); i++) {
		p = findfile(files[i], src)
		if (p == "") {
			errprintf("fastata: %s not found; reinstall fastata\n", files[i])
			exit(601)
		}
		if (_fx_copy(p, rd + files[i])) {
			errprintf("fastata: could not copy %s to %s\n", files[i], rd)
			exit(603)
		}
	}

	// The plugin under a versioned name. A copy can fail on Windows while a session has that
	// same file loaded; the loaded file is then the right one.
	p = findfile("fastata.plugin", src)
	if (p == "") {
		errprintf("fastata: fastata.plugin not found; reinstall fastata\n")
		exit(601)
	}
	plug = "fastata_" + ver + ".plugin"
	if (_fx_copy(p, rd + plug)) {
		if (!fileexists(rd + plug)) {
			errprintf("fastata: could not copy fastata.plugin to %s\n", rd)
			exit(603)
		}
	}

	cmds = _fx_cmds()
	for (i = 1; i <= cols(cmds); i++) {
		f = rd + cmds[i] + ".ado"
		if (findfile(cmds[i] + ".ado", src) == "") {
			if (fileexists(f)) (void) _unlink(f)
		}
		else _fx_writelines(f, _fx_shim_lines(cmds[i], ver))
	}

	old = ""
	if (fileexists(rd + "fastata_runtime.txt")) {
		old = strtrim(_fx_join(_fx_lines(rd + "fastata_runtime.txt")))
	}
	if (old != ver) {
		stale = dir(rd, "files", "_fxo_*.ado")
		for (i = 1; i <= rows(stale); i++) (void) _unlink(rd + stale[i])
	}
	stale = dir(rd, "files", "fastata_*.plugin")
	for (i = 1; i <= rows(stale); i++) {
		if (stale[i] != plug) (void) _unlink(rd + stale[i])
	}
	// Last, so that a runtime directory without it (or with another version) is rebuilt.
	_fx_writelines(rd + "fastata_runtime.txt", ver)
}

// The runtime directory for the current PLUS: <PLUS>fastata/ as an absolute path with forward
// slashes (PLUS may be written with ~). PLUS is created if it is missing.
string scalar _fx_rtpath()
{
	string scalar plus, cur, abs

	plus = c("sysdir_plus")
	_fx_mkdirp(plus)
	cur = pwd()
	if (_chdir(plus)) {
		errprintf("fastata: cannot access the PLUS directory %s\n", plus)
		exit(603)
	}
	abs = pwd()
	chdir(cur)
	abs = subinstr(abs, char(92), "/", .)
	if (substr(abs, -1, 1) != "/") abs = abs + "/"
	return(abs + "fastata/")
}

// Version recorded in runtime directory dir ("" if none).
string scalar _fx_rtversion(string scalar rdir)
{
	string scalar d

	d = subinstr(rdir, char(92), "/", .)
	if (substr(d, -1, 1) != "/") d = d + "/"
	if (!fileexists(d + "fastata_runtime.txt")) return("")
	return(strtrim(_fx_join(_fx_lines(d + "fastata_runtime.txt"))))
}

// Sets local fx_onpath to 1 if directory dir is on the ado-path, else 0, and local fx_active
// to the runtime directory in use (the first on the ado-path; "" if none).
void _fx_onpath(string scalar pdir)
{
	string rowvector t
	real scalar i, on

	t = _fx_adotokens()
	on = 0
	for (i = 1; i <= cols(t); i++) {
		if (_fx_normdir(_fx_unq(t[i])) == _fx_normdir(pdir)) on = 1
	}
	st_local("fx_onpath", strofreal(on))
	st_local("fx_active", _fx_rtdir())
}

// Sets local fx_pos to the ado-path positions of dir and of any other runtime directory,
// highest first (for adopath -).
void _fx_pathpos(string scalar pdir)
{
	string rowvector t
	string scalar out
	real scalar i

	t = _fx_adotokens()
	out = ""
	for (i = cols(t); i >= 1; i--) {
		if (_fx_isrtdir(t[i], pdir)) out = out + " " + strofreal(i)
	}
	st_local("fx_pos", strtrim(out))
}

// Erases runtime directory dir: its files, then the directory.
void _fx_rmruntime(string scalar rdir)
{
	string scalar d
	string colvector f
	real scalar i

	d = subinstr(rdir, char(92), "/", .)
	if (substr(d, -1, 1) != "/") d = d + "/"
	if (!direxists(d)) return
	f = dir(d, "files", "*")
	for (i = 1; i <= rows(f); i++) (void) _unlink(d + f[i])
	(void) _rmdir(d)
}

// For fastata status, sets fx_mode (the mode; envm: env FASTATA_MODE) and per replaced command
// c: fx_orig_c (path of the original), fx_ver_c (whether the gate accepts it), fx_nfast_c,
// fx_nfb_c and fx_last_c (session counters), fx_vok_c, fx_vmis_c and fx_vskip_c (verify mode:
// verified, mismatched, skipped calls).
void _fx_status(string scalar envm)
{
	string rowvector cm, v, first
	string colvector keys
	string matrix g
	real scalar i, j, nok

	st_local("fx_mode", _fx_getmode(envm))
	cm = _fx_cmds()
	g = _fx_gates()
	for (i = 1; i <= cols(cm); i++) {
		st_local("fx_orig_" + cm[i], _fx_findorig(cm[i] + ".ado"))
		if (cm[i] == "egen") {
			keys = _fx_uniq(select(g[., 1], strpos(g[., 1], "egen:") :== 1))
			nok = 0
			first = ("1", "")
			for (j = 1; j <= rows(keys); j++) {
				v = _fx_verdict(keys[j])
				if (v[1] == "1") nok++
				else if (first[1] == "1") first = v
			}
			if (rows(keys) == 0) st_local("fx_ver_egen", "no (no gate)")
			else if (nok == rows(keys)) st_local("fx_ver_egen", "yes")
			else if (nok == 0) st_local("fx_ver_egen", "no (" + first[2] + ")")
			else st_local("fx_ver_egen", strofreal(nok) + "/" + strofreal(rows(keys)) + " functions")
		}
		else {
			v = _fx_verdict(cm[i])
			st_local("fx_ver_" + cm[i], v[1] == "1" ? "yes" : "no (" + v[2] + ")")
		}
		_fx_count_get(cm[i])
		st_local("fx_nfast_" + cm[i], st_local("fx_nfast"))
		st_local("fx_nfb_" + cm[i], st_local("fx_nfb"))
		st_local("fx_last_" + cm[i], st_local("fx_last"))
		st_local("fx_vok_" + cm[i], st_local("fx_vok"))
		st_local("fx_vmis_" + cm[i], st_local("fx_vmis"))
		st_local("fx_vskip_" + cm[i], st_local("fx_vskip"))
	}
}

// ---------------------------------------------------------------------------- profile.do

string colvector _fx_block()
{
	return(("* >>> fastata (added by fastata enable; remove with fastata disable)" \
		"capture fastata_init" \
		"* <<< fastata"))
}

// Candidate profile.do files in Stata's search order, without the current directory.
string colvector _fx_profile_cands(string scalar envpath, string scalar home, string scalar rt)
{
	string colvector cand
	string rowvector parts, t
	string scalar sep, d
	real scalar i

	cand = c("sysdir_stata") + "profile.do"
	sep = (c("os") == "Windows" ? ";" : ":")
	parts = ustrsplit(envpath, sep)
	for (i = 1; i <= cols(parts); i++) {
		if (strtrim(parts[i]) != "") {
			d = subinstr(parts[i], char(92), "/", .)
			if (substr(d, -1, 1) != "/") d = d + "/"
			cand = cand \ (d + "profile.do")
		}
	}
	if (home != "") {
		d = subinstr(home, char(92), "/", .)
		if (substr(d, -1, 1) != "/") d = d + "/"
		cand = cand \ (d + "profile.do")
	}
	t = _fx_adotokens()
	for (i = 1; i <= cols(t); i++) {
		if (_fx_unq(t[i]) == ".") continue
		d = _fx_tokdir(t[i])
		if (rt != "") {
			if (_fx_normdir(d) == _fx_normdir(rt)) continue
		}
		d = subinstr(d, char(92), "/", .)
		if (substr(d, -1, 1) != "/") d = d + "/"
		cand = cand \ (d + "profile.do")
	}
	return(cand)
}

// Sets local fx_profile to the first existing candidate, or "".
void _fx_profile_first(string scalar envpath, string scalar home, string scalar rt)
{
	string colvector cand
	real scalar i

	cand = _fx_profile_cands(envpath, home, rt)
	for (i = 1; i <= rows(cand); i++) {
		if (fileexists(cand[i])) {
			st_local("fx_profile", cand[i])
			return
		}
	}
	st_local("fx_profile", "")
}

// Sets local fx_profiles to the candidates that contain the fastata block (compound-quoted list).
void _fx_profile_with_block(string scalar envpath, string scalar home, string scalar rt)
{
	string colvector cand
	string scalar out
	real scalar i

	cand = _fx_profile_cands(envpath, home, rt)
	out = ""
	for (i = 1; i <= rows(cand); i++) {
		if (fileexists(cand[i])) {
			if (_fx_has_block(cand[i])) out = out + " " + _fx_cq(cand[i])
		}
	}
	st_local("fx_profiles", strtrim(out))
}

real scalar _fx_has_block(string scalar path)
{
	if (!fileexists(path)) return(0)
	return(any(_fx_lines(path) :== _fx_block()[1]))
}

// Rewrites path without the fastata block, then appends it if add. Sets local fx_rc.
void _fx_profile_write(string scalar path, real scalar add)
{
	string colvector l, out
	real scalar i, inblock

	l = fileexists(path) ? _fx_lines(path) : J(0, 1, "")
	out = J(0, 1, "")
	inblock = 0
	for (i = 1; i <= rows(l); i++) {
		if (l[i] == _fx_block()[1]) inblock = 1
		if (!inblock) out = out \ l[i]
		if (l[i] == _fx_block()[3]) inblock = 0
	}
	if (add) out = out \ _fx_block()
	st_local("fx_rc", strofreal(_fx_writelines_rc(path, out)))
}

end
