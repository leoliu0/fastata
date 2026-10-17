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
*! For the _fx_<cmd> programs (the first five are the per-call ones: each ends in exit, so that
*! Stata does not read through the rest of this program, which costs about 20 µs a call):
*!   gate <key> [1]                    with 1 (a call with few observations), first as small
*!                                     below; otherwise, or when that does not apply:
*!                                     fx_ok: 1 if every original file of key is verified; fx_why;
*!                                     fx_vpend: 1 in verify mode when fx_ok is 1 (gate has then
*!                                     copied the current frame to a frame of a name no other
*!                                     frame has; verify, a fallback, a failed store or Break in
*!                                     the plugin drop it, else the next gate. No tempname: one
*!                                     here would shift the temporary names the original then
*!                                     gets, which pctile's genp() label shows)
*!   count <cmd> fast|verify_ok|verify_mismatch|verify_skipped ["<reason>"]
*!   store <token> <type> <name> [<type> <name> ...]
*!                                     adds the variables (nofill) and fills them from the
*!                                     plugin's cache, under nobreak; on any failure (including a
*!                                     plugin that _fx_call could not use) drops them again (and
*!                                     a pending verify snapshot) and exits with the plugin's
*!                                     return code (9999 if it gave none)
*!   fallback <cmd> "<reason>"         counts a fallback of cmd and sets fx_prog (count + orig)
*!   small <cmd>                       the small-data cutoff, for a call with few observations:
*!                                     fx_small 1 and fx_prog when the caller is to run the
*!                                     original right away (the call is then counted as fallback
*!                                     "small data"); fx_small unset in verify mode and after
*!                                     small off
*!   vabort                            drops a pending verify snapshot (the fast path stops with
*!                                     an error; _fx_call on Break)
*!   orig <cmd>                        fx_prog: the program that runs cmd's original ado-file
*!   verify <cmd> <caller> <rc0> <frc> <fleft> "<byvars>" "<byrc0>" <tol> "<rspec>" "<args>"
*!                                     after a fast path that ran with fx_vpend 1, with frc its
*!                                     return code and fleft the c(rc) it left ("": not compared,
*!                                     the fast path does not reproduce it): runs the original
*!                                     (quietly) on the snapshot, as the shim would have (caller
*!                                     version, by prefix, arguments, c(rc) rc0 at entry) from the
*!                                     random-number states at gate, compares its result with the
*!                                     fast path's (rspec: "name value" pairs of r() scalars; tol:
*!                                     "<reldif> <variables>", the tolerance for those variables'
*!                                     values, whose sign of zero is not compared, every other
*!                                     variable bitwise; 0: all bitwise), counts
*!                                     verify_ok, verify_mismatch or verify_skipped, keeps the
*!                                     original's data (and r(), c(rc), random-number states)
*!                                     and sets fx_vrc to the original's return code
*! For fastata and the tests:
*!   mode auto|original|verify         original: every replaced command runs its original;
*!                                     verify: every fast path is checked against the original
*!                                     (see verify). Without a mode set this session (clear all
*!                                     forgets it), the mode is env FASTATA_MODE, else auto
*!   small on|off                      the small-data cutoff (on unless turned off this session;
*!                                     clear all turns it on again)
*!   counts_save "<file.csv>"          this session's counts as cmd,fast,fallback,last_reason
*!   reset                             forgets cached gate verdicts, file hashes and gate list
*!   runtime "<dir>" <version> [0|1 [0|1]]  builds runtime directory dir ("": the one for the
*!                                     current PLUS) unless the 3rd argument is 0; turns it on if
*!                                     the 4th is 1
*!   rtpath                            fx_rt: the runtime directory for the current PLUS
*!   rtversion ["<dir>"]               fx_have: the version dir was built for ("" if none);
*!                                     fx_build: 1 if dir needs a (re)build; fx_disabled: 1 after
*!                                     fastata disable
*!   onpath ["<dir>"]                  fx_onpath: 1 if dir is on the ado-path; fx_active: the
*!                                     runtime directory in use ("" if none); "" = the runtime
*!                                     directory for the current PLUS
*!   pathpos ["<dir>"]                 fx_pos: ado-path positions of dir and of every runtime
*!                                     directory, highest first; "" as for onpath
*!   rmruntime "<dir>"                 erases runtime directory dir
*!   mkdirp "<dir>"                    creates dir and missing parents
*!   profile_first "<PATH>" "<home>" "<rt>"      fx_profile: first existing profile.do, or ""
*!   profile_with_block "<PATH>" "<home>" "<rt>" fx_profiles: those with the startup lines
*!   has_block "<file>"                fx_hasblock: 1 if file has the startup lines
*!   profile_write 1|0 ["<file>"]      fastata enable (1) / disable (0) profile.do work; prints
*!                                     the outcome; fx_rc
*!   block                             displays the startup lines as an error message
*!   status [show <version>]           fx_mode; fx_orig_<c>, fx_ver_<c>, fx_nfast_<c>, fx_nfb_<c>,
*!                                     fx_last_<c>, fx_vok_<c>, fx_vmis_<c>, fx_vskip_<c> for
*!                                     every replaced command c; with show: prints the fastata
*!                                     status report
*!   filehash "<file>"                 fx_bytes, fx_hash: what the gate list records for file
*! For fast paths:
*!   threads                           fx_threads: the plugin's threads= value
program _fx
	version 16
	args sub
	if "`sub'" == "gate" {
		args sub key small
		local envm : env FASTATA_MODE
		quietly mata: _fx_gate_check(st_local("key"), st_local("envm"), "`small'" == "1")
		if "`fx_small'" == "1" {
			local f : env FASTATA_COUNTS
			if `"`f'"' != "" & !`fx_skip' CountFile `"`f'"' `"`fx_cmd',fallback,`fx_why'"'
			if `"`fx_err'"' != "" | "`fx_prog'" == "" _fx orig `fx_cmd'
			c_local fx_prog `fx_prog'
			c_local fx_small 1
			exit
		}
		c_local fx_ok `fx_ok'
		c_local fx_why `"`fx_why'"'
		if "`fx_vmode'" == "1" VSnap
		c_local fx_vpend `fx_vmode'
		exit
	}
	if "`sub'" == "count" {
		args sub cmd kind why
		quietly mata: _fx_count(st_local("cmd"), st_local("kind"), st_local("why"))
		local f : env FASTATA_COUNTS
		if `"`f'"' != "" & !`fx_skip' CountFile `"`f'"' `"`cmd',`kind',`why'"'
		exit
	}
	if "`sub'" == "small" {
		args sub cmd
		if inlist("`cmd'", "on", "off") {
			quietly mata: _fx_setsmall(st_local("cmd"))
			exit
		}
		local envm : env FASTATA_MODE
		quietly mata: _fx_small(st_local("cmd"), st_local("envm"))
		if "`fx_small'" == "1" {
			local f : env FASTATA_COUNTS
			if `"`f'"' != "" & !`fx_skip' CountFile `"`f'"' `"`cmd',fallback,`fx_why'"'
			if `"`fx_err'"' != "" | "`fx_prog'" == "" _fx orig `cmd'
			c_local fx_prog `fx_prog'
			c_local fx_small 1
		}
		exit
	}
	if "`sub'" == "fallback" {
		args sub cmd why
		quietly mata: _fx_fallback(st_local("cmd"), st_local("why"))
		local f : env FASTATA_COUNTS
		if `"`f'"' != "" & !`fx_skip' CountFile `"`f'"' `"`cmd',fallback,`why'"'
		if `"`fx_err'"' != "" | "`fx_prog'" == "" _fx orig `cmd'
		c_local fx_prog `fx_prog'
		exit
	}
	if "`sub'" == "store" {
		gettoken sub rest : 0
		Store `rest'
		exit
	}
	if "`sub'" == "vabort" {
		quietly mata: _fx_vabort()
		exit
	}
	if "`sub'" == "verify" {
		args sub cmd caller rc0 frc fleft byv byrc0 tol rspec cargs
		quietly mata: _fx_vtake()
		local orc `frc'
		* fleft "": the fast path does not reproduce the c(rc) that the original leaves
		local oleft = cond("`fleft'" == "", "0", "`fleft'")
		if "`fx_vframe'" != "" {
			capture _fx orig `cmd'
			local rc = _rc
			if `rc' {
				capture frame drop `fx_vframe'
				if `rc' == 1 exit 1
				local fx_vwhy "original r(`rc')"
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
			* Break while the original ran on the snapshot: stop, with the fast path's result
			if `orc' == 1 {
				capture frame drop `fx_vframe'
				exit 1
			}
			local sbf : sortedby
			local dlf : data label
			local fx_vdiff
			if `frc' != `orc' local fx_vdiff "return code `frc' vs `orc'"
			else {
				* (a Break or an error here must not leave the snapshot behind)
				capture VHash `fx_vframe'
				local rc = _rc
				if !`rc' {
					gettoken tolv tolvars : tol
					capture noisily quietly mata: _fx_vcompare("`fx_vframe'", `tolv', st_local("tolvars"), st_local("rspec"), st_local("fx_vhf"), st_local("fx_vho"))
					local rc = _rc
				}
				if `rc' {
					capture frame drop `fx_vframe'
					exit `rc'
				}
			}
			if `"`fx_vdiff'"' == "" & `orc' == 0 & "`fleft'" != "" & "`fleft'" != "`fx_oleft'" {
				local fx_vdiff "c(rc) left `fleft' vs `fx_oleft'"
			}
			if `orc' == 0 & "`fx_oleft'" != "" local oleft `fx_oleft'
			* keep the original's data: the frame it ran in takes the place of the current one
			* (under nobreak: a Break in between would leave the user's data in another frame)
			local cur = c(frame)
			quietly mata: st_local("vold", _fx_vuniq("__fx_vold"))
			nobreak {
				frame rename `cur' `vold'
				frame rename `fx_vframe' `cur'
				frame change `cur'
				frame drop `vold'
			}
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
		* build: 1 (default) builds or refreshes dir; on: 1 then turns dir on. dir "": the
		* runtime directory for the current PLUS. The build lock is released however it ends.
		args sub dir ver build on
		if "`build'" != "0" {
			capture noisily quietly mata: _fx_runtime_build(st_local("dir"), st_local("ver"))
			local rc = _rc
			quietly mata: _fx_unlock()
			if `rc' exit `rc'
		}
		if "`on'" == "1" quietly mata: _fx_activate(st_local("dir"))
	}
	else if "`sub'" == "rtpath" {
		quietly mata: st_local("fx_rt", _fx_rtpath())
		c_local fx_rt `"`fx_rt'"'
	}
	else if "`sub'" == "rtversion" {
		args sub dir
		quietly mata: _fx_rtcheck(st_local("dir"))
		c_local fx_have `"`fx_have'"'
		c_local fx_build `fx_build'
		c_local fx_disabled `fx_disabled'
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
		* fastata enable (add 1) or disable (add 0); prints the outcome
		args sub add file
		if `add' mata: _fx_enable_profile(st_local("file"))
		else mata: _fx_disable_profile(st_local("file"))
		c_local fx_rc `fx_rc'
	}
	else if "`sub'" == "block" {
		mata: printf("{err}%s\n", invtokens(_fx_block()', char(10)))
	}
	else if "`sub'" == "status" {
		args sub show ver
		local envm : env FASTATA_MODE
		if "`show'" == "show" {
			mata: _fx_status_show(st_local("ver"), st_local("envm"))
			exit
		}
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

* Verify mode, from gate: the snapshot that verify runs the original on, taken before the fast
* path changes anything. Copies the current frame to a frame whose name no frame has (so never
* a user's frame) and records it with the random-number states (reading them does not advance
* them), or records why it could not.
program VSnap
	local srs = c(sortrngstate)
	local rs = c(rngstate)
	local why
	quietly mata: st_local("vs", _fx_vuniq("__fx_vsnap"))
	capture frame copy `c(frame)' `vs'
	local rc = _rc
	if `rc' {
		capture frame drop `vs'
		if `rc' == 1 exit 1
		local why "snapshot r(`rc')"
	}
	else quietly mata: _fx_vlorder("`vs'")
	quietly mata: _fx_vset(st_local("why"), st_local("srs"), st_local("rs"), st_local("vs"))
end

* _fx store: adds the variables (nofill) and fills them from the plugin's cache, under nobreak.
* Nofill variables must never stay unwritten: any failure drops them (and the fast path's verify
* snapshot, which is no longer needed) and exits with the plugin's return code.
program Store
	gettoken token rest : 0
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
		capture _fx_call `names', store "token=`token'" "threads=`threads'"
		local rc = _rc
		if !`rc' local rc = `fx_plugrc'
		if !`rc' & `"`fx_fallback'"' != "" {
			local rc 9999
			local fx_errmsg `"fastata: internal error (store: `fx_fallback'); please report it"'
		}
		if `rc' {
			drop `names'
			quietly mata: _fx_vabort()
			if `"`fx_errmsg'"' != "" di as err `"`fx_errmsg'"'
			exit `rc'
		}
	}
end

* Appends line to the FASTATA_COUNTS file f, skipped if it cannot be opened (the replication
* harness reads the file; unlike the session counters it survives clear all). The handle has a
* fixed name: a tempname would shift the temporary names that the original then gets.
program CountFile
	args f line
	capture file open _fx_cfh using `"`f'"', write text append
	if !_rc {
		file write _fx_cfh `"`line'"' _n
		file close _fx_cfh
	}
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

* Verify mode: sets fx_vhf and fx_vho in the caller to the plugin's per-variable hashes (vhash) of
* the current frame and of frame snap, or to "" where the plugin could not hash (no variables,
* plugin unavailable); the comparison then reads every variable.
program VHash
	args snap
	local threads = cond(c(MP), c(processors), 0)
	foreach w in f o {
		local fx_vh
		if "`w'" == "o" {
			frame `snap' {
				VHash1 `threads'
			}
		}
		else VHash1 `threads'
		c_local fx_vh`w' `fx_vh'
	}
end

program VHash1
	args threads
	local fx_vh
	if c(k) {
		capture _fx_call _all, vhash "threads=`threads'"
		if _rc == 1 exit 1
		if _rc | `"`fx_fallback'"' != "" | "`fx_plugrc'" != "0" local fx_vh
	}
	c_local fx_vh `fx_vh'
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
// are cached per key and state. envm: the value of env FASTATA_MODE. small: 1 for a call with
// few observations, which first goes through the small-data cutoff (_fx_smallrun; fx_small 1 and
// nothing else set when it applies).
void _fx_gate_check(string scalar key, string scalar envm, | real scalar small)
{
	pointer(transmorphic scalar) scalar pv
	string scalar ck, mode
	string rowvector v

	st_local("fx_vmode", "0")
	mode = _fx_getmode(envm)
	if (args() == 3) {
		if (small) {
			if (_fx_smallrun(strpos(key, ":") ? substr(key, 1, strpos(key, ":") - 1) : key, mode)) return
		}
	}
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
		// no runtime directory on the ado-path (a do-file reset it after fastata's programs
		// were loaded): the fast path could not load the programs it calls (_fx_call)
		if (_fx_info()[1] == "") v = ("0", "runtime directory off the ado-path")
		else v = _fx_verdict(key)
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

// ---------------------------------------------------------------------------- small data

// The small-data cutoff: on unless turned off this session (_fx small off; clear all drops the
// external and so turns it on again).
void _fx_setsmall(string scalar v)
{
	pointer() scalar p

	if ((p = findexternal("_fx_small_v")) == NULL) p = crexternal("_fx_small_v")
	*p = v
}

// For a call of cmd with few observations (its _fx_<cmd> decides): unless in verify mode (every
// fast path is to be verified) or with the cutoff off, counts the call as a fallback (fx_why:
// "small data", or "mode original" in that mode), looks up the original (locals fx_prog and
// fx_err of _fx_orig_prog), sets locals fx_small 1 and fx_cmd, and returns 1, so that the caller
// runs the original right away; else sets fx_small 0 and returns 0.
real scalar _fx_smallrun(string scalar cmd, string scalar mode)
{
	pointer() scalar p
	string scalar why

	st_local("fx_small", "0")
	if (mode == "verify") return(0)
	if ((p = findexternal("_fx_small_v")) != NULL) {
		if (*p == "off") return(0)
	}
	why = (mode == "original" ? "mode original" : "small data")
	st_local("fx_why", why)
	st_local("fx_cmd", cmd)
	_fx_count(cmd, "fallback", why)
	_fx_orig_prog(cmd)
	st_local("fx_small", "1")
	return(1)
}

// _fx small <cmd>: _fx_smallrun for cmd. envm: the value of env FASTATA_MODE.
void _fx_small(string scalar cmd, string scalar envm)
{
	(void) _fx_smallrun(cmd, _fx_getmode(envm))
}

// A fallback of cmd: counts it and looks up the original (locals fx_prog and fx_err).
void _fx_fallback(string scalar cmd, string scalar why)
{
	_fx_count(cmd, "fallback", why)
	_fx_orig_prog(cmd)
}

// ---------------------------------------------------------------------------- verify mode

// Records the pending verification of the running fast path: why it cannot be verified ("" when
// frame snap holds the snapshot), and the sort and regular random-number states. Drops the
// snapshot of an earlier fast path that ended without verify, if it is still there.
void _fx_vset(string scalar why, string scalar srs, string scalar rs, string scalar snap)
{
	pointer() scalar p

	if ((p = findexternal("_fx_vrec")) == NULL) p = crexternal("_fx_vrec")
	else _fx_vdrop(*p)
	*p = (why, srs, rs, snap)
}

// A fast path that stops with an error (a failed store, Break in the plugin): forgets its
// pending verification and drops the snapshot, so that the copy of the data does not stay in
// memory.
void _fx_vabort()
{
	pointer() scalar p

	if ((p = findexternal("_fx_vrec")) == NULL) return
	_fx_vdrop(*p)
	rmexternal("_fx_vrec")
}

// prefix followed by the smallest number that gives a name no frame has.
string scalar _fx_vuniq(string scalar prefix)
{
	real scalar i

	i = 1
	while (st_frameexists(prefix + strofreal(i))) i++
	return(prefix + strofreal(i))
}

// Drops the snapshot frame of pending verification record r, if it has one and it exists.
void _fx_vdrop(string rowvector r)
{
	if (cols(r) < 4) return
	if (r[1] != "" | r[4] == "") return
	if (st_frameexists(r[4]) & r[4] != st_framecurrent()) st_framedrop(r[4])
}

// Takes the pending verification: locals fx_vframe (the snapshot frame, "" if none), fx_vwhy,
// fx_vsrs and fx_vrs.
void _fx_vtake()
{
	pointer() scalar p
	string rowvector r

	if ((p = findexternal("_fx_vrec")) == NULL) r = ("no snapshot", "", "", "")
	else {
		r = *p
		rmexternal("_fx_vrec")
	}
	if (r[1] == "") {
		if (!st_frameexists(r[4])) r[1] = "no snapshot"
	}
	st_local("fx_vframe", r[1] == "" ? r[4] : "")
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
// _dta and of the variables, and the definition of every value label in labs. Written into a
// vector of the final size (appending line by line takes time quadratic in the number of
// variables).
string colvector _fx_vmeta(string scalar sb, string scalar dl, string rowvector labs)
{
	string colvector out, names, txt
	string rowvector vars
	real colvector vals
	real scalar i, j, k, n, r

	k = st_nvar()
	vars = "_dta", (k ? st_varname(1..k) : J(1, 0, ""))
	n = 3 + k
	for (i = 1; i <= cols(vars); i++) n = n + rows(st_dir("char", vars[i], "*"))
	for (i = 1; i <= cols(labs); i++) {
		st_vlload(labs[i], vals, txt)
		n = n + rows(vals)
	}
	out = J(n, 1, "")
	out[1] = "N " + strofreal(st_nobs(), "%20.0f")
	out[2] = "sortedby " + sb
	out[3] = "data label " + dl
	r = 3
	for (i = 1; i <= k; i++) {
		out[++r] = ("variable " + strofreal(i) + " " + vars[i + 1] + " " + st_vartype(i) + " " +
			st_varformat(i) + " [" + st_varvaluelabel(i) + "] " + st_varlabel(i))
	}
	for (i = 1; i <= cols(vars); i++) {
		names = st_dir("char", vars[i], "*")
		for (j = 1; j <= rows(names); j++) {
			out[++r] = "char " + vars[i] + "[" + names[j] + "] " + st_global(vars[i] + "[" + names[j] + "]")
		}
	}
	for (i = 1; i <= cols(labs); i++) {
		st_vlload(labs[i], vals, txt)
		for (j = 1; j <= rows(vals); j++) {
			out[++r] = "label " + labs[i] + " " + strofreal(vals[j], "%21x") + " " + txt[j]
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
// left it. tol applies to the variables named in tolvars, and their sign of zero is not
// compared (the original's follows a random sort tie order); every other variable is compared
// bitwise. hf and ho: the plugin's per-variable hashes of the two frames (vhash; "" when the
// plugin could not hash them); a variable with the same hash in both is bitwise equal and needs
// no further comparison, every other one is compared in detail. Sets local fx_vdiff to "" or a
// short description of the first difference.
void _fx_vcompare(string scalar snap, real scalar tol0, string scalar tolvars,
	string scalar rspec, string scalar hf, string scalar ho)
{
	string scalar cur, d
	string colvector sa, sb
	string rowvector rs, ha, hb, tv
	real colvector a, b, ma, mb, z, nm, na, nb
	real matrix rv
	real scalar j, k, str, usehash, tol, zcheck

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
		tv = tokens(tolvars)
		ha = tokens(hf)
		hb = tokens(ho)
		usehash = (cols(ha) == st_nvar() & cols(hb) == st_nvar())
		// Stata's count if (in _fx_vquick) sets r(): kept around the loop
		stata("_return hold __fx_vq")
		for (j = 1; j <= st_nvar(); j++) {
			zcheck = !anyof(tv, st_varname(j))
			tol = (zcheck ? 0 : tol0)
			if (usehash) {
				if (ha[j] == hb[j] & ha[j] != "-") continue
				if (_fx_vquick(j, snap, tol, ha[j], hb[j])) continue
			}
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
					else if (na != nb) d = "NaN values of " + st_varname(j)
					else if (_fx_vraw(a[na]) != _fx_vraw(b[nb])) {
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
				else if (zcheck) {
					z = selectindex(a :== 0)
					if (length(z)) {
						// (%21x shows -0 as +0)
						if (_fx_vraw(a[z]) != _fx_vraw(b[z])) {
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
		stata("_return restore __fx_vq")
	}
	st_local("fx_vdiff", _fx_vclean(d))
}

// 1 when variable j of the current frame and of frame snap, whose plugin hashes (tokens ha, hb)
// differ, still pass the comparison by a Stata count over both frames (_frval), which is much
// faster than reading them into Mata: a string variable when every value has the same bytes (a
// strL's too, binary ones included); a numeric variable, under tolerance tol > 0 and when
// neither holds a NaN (which an expression reads as .), when every observation has the same
// missing code in both or numbers within reldif tol. 0 sends the variable to the detailed
// comparison, which finds and describes the difference.
real scalar _fx_vquick(real scalar j, string scalar snap, real scalar tol, string scalar ha,
	string scalar hb)
{
	string scalar v, f, cond
	real scalar rc

	v = st_varname(j)
	f = "_frval(" + snap + ", " + v + ", _n)"
	if (st_isstrvar(j)) cond = v + " != " + f
	else if (tol > 0 & substr(ha, -1, 1) != "n" & substr(hb, -1, 1) != "n") {
		cond = ("!(" + v + " == " + f + " | (" + v + " < . & " + f + " < . & reldif(" + v + ", " +
			f + ") <= " + strofreal(tol, "%21x") + "))")
	}
	else return(0)
	rc = _stata("quietly count if " + cond, 1)
	if (rc == 1) exit(1)
	if (rc) return(0)
	return(st_numscalar("r(N)") == 0)
}

// The 8 bytes of every value of x, as stored.
string scalar _fx_vraw(real colvector x)
{
	string scalar s

	s = (8 * rows(x)) * " "
	bufput(bufio(), s, 0, "%8z", x)
	return(s)
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
// local fx_skip (1: a call that an original makes while verify runs it, not counted). A fallback
// after gate took a snapshot (verify mode) drops the snapshot, which is no longer needed.
void _fx_count(string scalar cmd, string scalar kind, string scalar why)
{
	pointer(transmorphic scalar) scalar pc, pw
	pointer() scalar pr
	real rowvector v

	st_local("fx_skip", "0")
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
		if ((pr = findexternal("_fx_vrec")) != NULL) {
			_fx_vdrop(*pr)
			rmexternal("_fx_vrec")
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
// Paths stay in Mata: no file operation goes through a Stata command line, where dollar signs
// and backquotes in a path would be expanded as macros.

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

// Directory d with forward slashes and one trailing slash.
string scalar _fx_dirslash(string scalar d)
{
	string scalar s

	s = subinstr(d, char(92), "/", .)
	if (s != "" & substr(s, -1, 1) != "/") s = s + "/"
	return(s)
}

// A file path in comparable form: forward slashes, lower case on Windows.
string scalar _fx_normfile(string scalar f)
{
	string scalar s

	s = subinstr(f, char(92), "/", .)
	if (c("os") == "Windows") s = strlower(s)
	return(s)
}

// The value of environment variable name.
string scalar _fx_getenv(string scalar name)
{
	stata("local _fx_env : env " + name)
	return(st_local("_fx_env"))
}

// The bytes of the file at path; rc becomes 0, or 601 when it cannot be read.
string scalar _fx_readraw(string scalar path, real scalar rc)
{
	transmorphic matrix t
	real scalar fh, n

	rc = 601
	if ((fh = _fopen(path, "r")) < 0) return("")
	n = -1
	if (_fseek(fh, 0, 1) >= 0) n = ftell(fh)
	t = ""
	if (n > 0) {
		if (_fseek(fh, 0, -1) >= 0) t = fread(fh, n)
	}
	(void) _fclose(fh)
	if (n < 0 | !isstring(t)) return("")
	if (rows(t) != 1 | cols(t) != 1) return("")
	if (strlen(t) != n) return("")
	rc = 0
	return(t)
}

// Writes text s as file path. A file that holds s already is left alone. Any other existing
// file is erased first, so that a process that has it open or loaded keeps reading the old one:
// files are never rewritten in place. Returns 0, or a Stata return code.
real scalar _fx_put(string scalar path, string scalar s)
{
	string scalar old
	real scalar fh, rc, wrc

	if (fileexists(path)) {
		old = _fx_readraw(path, rc)
		if (rc == 0) {
			if (old == s) return(0)
		}
		(void) _unlink(path)
		if (fileexists(path)) return(608)
	}
	if ((fh = _fopen(path, "w")) < 0) return(603)
	wrc = 0
	if (strlen(s)) wrc = _fwrite(fh, s)
	if (_fclose(fh) < 0 | wrc < 0) {
		(void) _unlink(path)
		return(603)
	}
	return(0)
}

// _fx_put(), or exit with an error message.
void _fx_bput(string scalar path, string scalar s)
{
	real scalar rc

	if ((rc = _fx_put(path, s))) {
		errprintf("fastata: could not write %s\n", path)
		exit(rc)
	}
}

// Text of lines, each ended by a line feed.
string scalar _fx_text(string colvector l)
{
	if (rows(l) == 0) return("")
	return(invtokens(l', char(10)) + char(10))
}

void _fx_writelines(string scalar path, string colvector lines)
{
	_fx_bput(path, _fx_text(lines))
}

// ---------------------------------------------------------------------------- originals

// Sets local fx_prog to the program that runs cmd's original ado-file: a renamed copy of the
// file, _fxo_<hash of the original>_<cmd>, in the runtime directory or, when there is none on
// the ado-path or it cannot be written (read-only), in this session's directory under
// c(tmpdir), which is then added to the end of the ado-path (never -run-: that would make the
// original's subprograms public). Names are cached per command and state; a cached name is used
// while its file exists (another session's fastata disable or rebuild may have erased it).
// fx_prog is "" when the original is not found; fx_err says why no copy can be provided.
void _fx_orig_prog(string scalar cmd)
{
	pointer(transmorphic scalar) scalar pc
	string rowvector info, v
	string colvector lines
	string scalar ck, p, prog, txt, dst, sd
	real scalar rc

	st_local("fx_prog", "")
	st_local("fx_err", "")
	pc = _fx_ext("_fx_progs")
	ck = cmd + char(0) + _fx_state()
	if (asarray_contains(*pc, ck)) {
		v = asarray(*pc, ck)
		if (fileexists(v[2])) {
			st_local("fx_prog", v[1])
			return
		}
	}
	info = _fx_info()
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
	txt = _fx_text(_fx_renamed(lines, cmd, prog))
	rc = 1
	if (info[1] != "") {
		dst = info[1] + prog + ".ado"
		rc = _fx_put(dst, txt)
	}
	if (rc) {
		sd = _fx_sessdir()
		dst = sd + prog + ".ado"
		rc = 603
		if (sd != "") rc = _fx_put(dst, txt)
		if (rc) {
			st_local("fx_err", "could not write a copy of " + p + " to run it")
			return
		}
		_fx_pathadd(sd)
	}
	asarray(*pc, cmd + char(0) + _fx_state(), (prog, dst))
	st_local("fx_prog", prog)
}

// This session's directory for renamed originals, <c(tmpdir)>/fastata_<name of one of the
// session's temporary files>/, reused while it is on the ado-path; "" if it cannot be created.
string scalar _fx_sessdir()
{
	string rowvector t
	string scalar tmp, d
	real scalar i

	tmp = _fx_dirslash(c("tmpdir"))
	if (tmp == "") return("")
	t = _fx_adotokens()
	for (i = 1; i <= cols(t); i++) {
		d = _fx_dirslash(_fx_tokdir(t[i]))
		if (strpos(_fx_normdir(d), _fx_normdir(tmp) + "fastata_") == 1) {
			if (direxists(d)) return(d)
		}
	}
	d = tmp + "fastata_" + pathbasename(subinstr(st_tempfilename(), char(92), "/", .)) + "/"
	if (!direxists(d)) (void) _mkdir(d)
	return(direxists(d) ? d : "")
}

// Adds directory d at the end of the ado-path, as adopath + does, unless it is on it.
void _fx_pathadd(string scalar d)
{
	string rowvector t
	real scalar i

	t = _fx_adotokens()
	for (i = 1; i <= cols(t); i++) {
		if (_fx_normdir(_fx_tokdir(t[i])) == _fx_normdir(d)) return
	}
	st_global("S_ADO", st_global("S_ADO") + ";" + _fx_cq(d))
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

// The runtime ado-files, copied from the installed ones. fastata.ado and fastata_init.ado are
// among them so that fastata off and fastata status keep working when PLUS no longer holds them
// (sysdir set PLUS in a replication package's config.do, then clear all).
string rowvector _fx_rtfiles()
{
	return(("fastata.ado", "fastata_init.ado", "_fx.ado", "_fx_call.ado", "_fx_gatelist.ado",
		"_fx_egen.ado", "_fx_isid.ado", "_fx_duplicates.ado", "_fx_xtile.ado", "_fx_pctile.ado",
		"_fx_destring.ado", "_fx_tostring.ado"))
}

// The installed files the runtime directory is built from, as rows (name, path): the runtime
// ado-files, then the plugin. Found on ado-path src; a path is "" when the file is not found.
string matrix _fx_sources(string scalar src)
{
	string rowvector f
	string matrix s
	real scalar i

	f = _fx_rtfiles(), "fastata.plugin"
	s = J(cols(f), 2, "")
	for (i = 1; i <= cols(f); i++) s[i, .] = (f[i], findfile(f[i], src))
	return(s)
}

// One file's part of a fingerprint: name=size:hash of its bytes t.
string scalar _fx_fp1(string scalar name, string scalar t)
{
	return(name + "=" + strofreal(strlen(t), "%15.0f") + ":" + _fx_hex8(hash1(t)))
}

// The fingerprint of installed files s (rows of _fx_sources(), every path found); rc becomes
// 601 when one cannot be read.
string scalar _fx_fingerprint(string matrix s, real scalar rc)
{
	string scalar fp, t
	real scalar i

	fp = ""
	for (i = 1; i <= rows(s); i++) {
		t = _fx_readraw(s[i, 2], rc)
		if (rc) return("")
		fp = fp + (i > 1 ? " " : "") + _fx_fp1(s[i, 1], t)
	}
	return(fp)
}

// Runtime directory rd's record, fastata_runtime.txt: (version, fingerprint of the installed
// files it was built from, plugin file name), "" for what it lacks.
string rowvector _fx_rtrecord(string scalar rd)
{
	string colvector l
	string rowvector r
	real scalar i

	r = ("", "", "")
	if (!fileexists(rd + "fastata_runtime.txt")) return(r)
	l = _fx_lines(rd + "fastata_runtime.txt")
	if (rows(l)) r[1] = strtrim(l[1])
	for (i = 2; i <= rows(l); i++) {
		if (substr(l[i], 1, 12) == "fingerprint ") r[2] = strtrim(substr(l[i], 13, .))
		else if (substr(l[i], 1, 7) == "plugin ") r[3] = strtrim(substr(l[i], 8, .))
	}
	return(r)
}

// For runtime directory dir0 ("": the one for the current PLUS), sets locals fx_have (the
// version it was built for, "" if none), fx_build (1 when it is missing or incomplete, or the
// installed files differ from those it was built from, after a reinstall of the same version
// too) and fx_disabled (1 after fastata disable). Without the installed files (uninstalled, or
// PLUS changed) a complete directory stays as it is.
void _fx_rtcheck(string scalar dir0)
{
	string scalar rd
	string rowvector r, f
	string matrix s
	real scalar i, ok, rc

	rd = _fx_rtdirof(dir0)
	r = _fx_rtrecord(rd)
	st_local("fx_have", r[1])
	st_local("fx_disabled", strofreal(fileexists(rd + "fastata_disabled.txt")))
	ok = (r[1] != "" & r[2] != "" & r[3] != "")
	if (ok) ok = fileexists(rd + r[3])
	f = _fx_rtfiles()
	for (i = 1; ok & i <= cols(f); i++) ok = fileexists(rd + f[i])
	if (ok) {
		s = _fx_sources(_fx_pathminus(rd))
		if (all(s[., 2] :!= "")) {
			ok = (_fx_fingerprint(s, rc) == r[2])
			if (rc) ok = 1
		}
	}
	st_local("fx_build", ok ? "0" : "1")
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
		l = l \ (t + "local rc = _rc") \ (t + "return add")
		// the c(rc) the original leaves, when the fast path says (fx_left)
		l = l \ (t + "if " + _fx_q("rc") + " == 0 & " + char(34) + _fx_q("fx_left") + char(34)
			+ " != " + char(34) + char(34) + " capture error " + _fx_q("fx_left"))
		l = l \ (t + "exit " + _fx_q("rc"))
	}
	else {
		l = l \ (call + "_fx_" + cmd + " " + _fx_q("0"))
	}
	l = l \ "end"
	return(l)
}

// Builds or refreshes runtime directory dir0 ("": the one for the current PLUS; see help
// fastata) from the installed files: the runtime ado-files, the plugin as
// fastata_<version>_<hash>.plugin (a changed plugin gets a new name, so a plugin a session has
// loaded is never replaced under it, nor blocked by Windows' lock on it), the shims and, last,
// the record. Files that hold the right content already are left alone; others are replaced by
// new files (_fx_put), so a session reading the directory meanwhile never sees a file
// rewritten in place. One build at a time (_fx_lock; the caller runs _fx_unlock()). Renamed
// originals (_fxo_*) stay: their names hold their content's hash. ver0: the version when the
// installed fastata.ado does not show it.
void _fx_runtime_build(string scalar dir0, string scalar ver0)
{
	string scalar rd, src, plug, ver, t, f, old
	string rowvector cmds
	string colvector txt, stale
	string matrix s
	real scalar i, n, rc

	rd = _fx_rtdirof(dir0)
	_fx_mkdirp(rd)
	_fx_lock(rd)
	src = _fx_pathminus(rd)
	s = _fx_sources(src)
	n = rows(s)
	txt = J(n, 1, "")
	for (i = 1; i <= n; i++) {
		if (s[i, 2] == "") {
			_fx_reinstall(s[i, 1])
			exit(601)
		}
		txt[i] = _fx_readraw(s[i, 2], rc)
		if (rc) {
			errprintf("fastata: could not read %s\n", s[i, 2])
			exit(rc)
		}
	}
	ver = _fx_srcversion(txt[1])
	if (ver == "") ver = ver0
	plug = "fastata_" + ver + "_" + _fx_hex8(hash1(txt[n])) + ".plugin"
	_fx_bput(rd + plug, txt[n])
	for (i = 1; i < n; i++) {
		t = txt[i]
		if (s[i, 1] == "_fx_call.ado") t = _fx_plugname(t, plug)
		_fx_bput(rd + s[i, 1], t)
	}
	cmds = _fx_cmds()
	for (i = 1; i <= cols(cmds); i++) {
		f = rd + cmds[i] + ".ado"
		if (findfile(cmds[i] + ".ado", src) == "") (void) _unlink(f)
		else _fx_bput(f, _fx_text(_fx_shim_lines(cmds[i], ver)))
	}
	stale = dir(rd, "files", "fastata_*.plugin")
	for (i = 1; i <= rows(stale); i++) {
		if (stale[i] != plug) (void) _unlink(rd + stale[i])
	}
	t = ""
	for (i = 1; i <= n; i++) t = t + (i > 1 ? " " : "") + _fx_fp1(s[i, 1], txt[i])
	// Last, so that a directory without it, or with another fingerprint, is built again. In
	// place: the record marks the directory as a runtime directory (_fx_isrtdir()), so it must
	// never be missing, not even for a moment, while sessions use the directory; a session that
	// reads it half written only rebuilds the directory again.
	t = _fx_text(ver \ ("fingerprint " + t) \ ("plugin " + plug))
	old = _fx_readraw(rd + "fastata_runtime.txt", rc)
	if (rc | old != t) {
		if (_fx_overwrite(rd + "fastata_runtime.txt", t)) {
			errprintf("fastata: could not write %s\n", rd + "fastata_runtime.txt")
			exit(603)
		}
	}
}

// The version in fastata.ado's text t (its fx_version local), or "".
string scalar _fx_srcversion(string scalar t)
{
	string rowvector w
	real scalar i

	i = strpos(t, "local fx_version ")
	if (i == 0) return("")
	w = tokens(subinstr(subinstr(substr(t, i + 17, 40), char(13), " ", .), char(10), " ", .))
	if (cols(w) == 0) return("")
	return(w[1])
}

// Runtime directory dir0 with forward slashes and a trailing slash; "": the one for the current
// PLUS.
string scalar _fx_rtdirof(string scalar dir0)
{
	if (dir0 == "") return(_fx_rtpath())
	return(_fx_dirslash(dir0))
}

// The first word of s, or "".
string scalar _fx_word1(string scalar s)
{
	string rowvector w

	w = tokens(s)
	if (cols(w) == 0) return("")
	return(w[1])
}

// Text t of _fx_call.ado, loading plugin file plug instead of the name it was installed with.
string scalar _fx_plugname(string scalar t, string scalar plug)
{
	string scalar a
	real scalar i, j

	a = "_fx_plugin, plugin using(" + char(34)
	i = strpos(t, a)
	if (i == 0) return(t)
	i = i + strlen(a)
	j = strpos(substr(t, i, .), char(34))
	if (j == 0) return(t)
	return(substr(t, 1, i - 1) + plug + substr(t, i + j - 1, .))
}

// Takes the build lock of runtime directory rd (directory fastata_build.lock in it), waiting
// up to 10 seconds while another process builds it; a lock still there then, left by an
// interrupted build, is taken over. Without a lock (rd read-only) the build goes ahead and
// fails where it writes.
void _fx_lock(string scalar rd)
{
	pointer() scalar p
	string scalar lk
	real scalar i

	lk = rd + "fastata_build.lock"
	for (i = 1; i <= 200; i++) {
		if (_mkdir(lk) == 0) break
		if (!direxists(lk)) {
			lk = ""
			break
		}
		stata("sleep 50")
	}
	if ((p = findexternal("_fx_lockdir")) == NULL) p = crexternal("_fx_lockdir")
	*p = lk
}

// Releases the build lock taken by _fx_lock(), if any.
void _fx_unlock()
{
	pointer() scalar p

	if ((p = findexternal("_fx_lockdir")) == NULL) return
	if (*p != "") (void) _rmdir(*p)
	rmexternal("_fx_lockdir")
}

// Turns runtime directory dir0 ("": the one for the current PLUS) on: every runtime directory
// off the ado-path and dir0 first (as adopath ++ does), the shims dropped so that the next call
// of each command loads dir0's, cached lookups forgotten.
void _fx_activate(string scalar dir0)
{
	string rowvector t, cm
	string scalar rd, s
	real scalar i

	rd = _fx_rtdirof(dir0)
	t = _fx_adotokens()
	s = _fx_cq(rd)
	for (i = 1; i <= cols(t); i++) {
		if (!_fx_isrtdir(t[i], rd)) s = s + ";" + t[i]
	}
	st_global("S_ADO", s)
	cm = _fx_cmds()
	for (i = 1; i <= cols(cm); i++) (void) _stata("capture program drop " + cm[i], 1)
	_fx_reset()
}

// Error message for an installed file that is missing, with the command that reinstalls fastata.
void _fx_reinstall(string scalar file)
{
	errprintf("fastata: %s not found; reinstall fastata with\n", file)
	errprintf("  net install fastata, from(%shttps://leoliu0.github.io/fastata%s) replace\n",
		char(34), char(34))
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

// Sets local fx_onpath to 1 if directory dir0 ("": the runtime directory for the current PLUS)
// is on the ado-path, else 0, and local fx_active to the runtime directory in use (the first on
// the ado-path; "" if none).
void _fx_onpath(string scalar dir0)
{
	string rowvector t
	string scalar pdir
	real scalar i, on

	pdir = _fx_rtdirof(dir0)
	t = _fx_adotokens()
	on = 0
	for (i = 1; i <= cols(t); i++) {
		if (_fx_normdir(_fx_unq(t[i])) == _fx_normdir(pdir)) on = 1
	}
	st_local("fx_onpath", strofreal(on))
	st_local("fx_active", _fx_rtdir())
}

// Sets local fx_pos to the ado-path positions of dir0 ("": the runtime directory for the current
// PLUS) and of any other runtime directory, highest first (for adopath -).
void _fx_pathpos(string scalar dir0)
{
	string rowvector t
	string scalar out, pdir
	real scalar i

	pdir = _fx_rtdirof(dir0)
	t = _fx_adotokens()
	out = ""
	for (i = cols(t); i >= 1; i--) {
		if (_fx_isrtdir(t[i], pdir)) out = out + " " + strofreal(i)
	}
	st_local("fx_pos", strtrim(out))
}

// Erases runtime directory dir0: its files, the build lock, then the directory.
void _fx_rmruntime(string scalar dir0)
{
	string scalar d
	string colvector f
	real scalar i

	d = _fx_dirslash(dir0)
	if (!direxists(d)) return
	f = dir(d, "files", "*")
	for (i = 1; i <= rows(f); i++) (void) _unlink(d + f[i])
	(void) _rmdir(d + "fastata_build.lock")
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

// fastata status: prints the report (see help fastata). ver: the running fastata's version;
// envm: env FASTATA_MODE.
void _fx_status_show(string scalar ver, string scalar envm)
{
	string scalar rd, act, have, note, f, cw, p
	string rowvector cm
	real scalar i, nv, onp, build

	rd = _fx_rtpath()
	_fx_onpath(rd)
	act = st_local("fx_active")
	onp = (st_local("fx_onpath") == "1")
	_fx_rtcheck(rd)
	have = st_local("fx_have")
	build = (st_local("fx_build") == "1")
	_fx_status(envm)
	printf("{txt}fastata {res}%s\n", ver)
	printf("{txt}  on now:      {res}%s\n", act != "" ? "yes" : "no")
	f = _fx_startup(rd, st_local("fx_disabled") == "1")
	printf("{txt}  at startup:  {res}%s\n", st_local("fx_startup"))
	cw = _fx_cwdprofile(f)
	if (cw != "") {
		printf("{txt}  note:        Stata sessions started in %s run %s instead, which %s\n",
			c("pwd"), cw, _fx_has_block(cw) ? "has the startup lines" : "lacks the startup lines")
	}
	note = ""
	if (have == "") note = " (not built)"
	else if (build & have != ver) note = " (built by version " + have + "; fastata on rebuilds it)"
	else if (build) note = " (out of date; fastata on rebuilds it)"
	else if (have != ver) note = " (built by version " + have + ")"
	printf("{txt}  runtime:     {res}%s{txt}%s\n", rd, note)
	if (act != "" & !onp) printf("{txt}  in use:      {res}%s{txt} (built for an earlier PLUS)\n", act)
	printf("{txt}  threads:     {res}%s\n", c("MP") ? strofreal(c("processors")) : "all logical CPUs")
	if (st_local("fx_mode") != "auto") printf("{txt}  mode:        {res}%s\n", st_local("fx_mode"))
	printf("\n")
	printf("{txt}  {ralign 10:command}  {lalign 9:verified}  {ralign 8:fast}  {ralign 8:fallback}  last fallback reason\n")
	cm = _fx_cmds()
	nv = 0
	for (i = 1; i <= cols(cm); i++) {
		printf("{txt}  {ralign 10:%s}  {res}{lalign 9:%s}  {ralign 8:%s}  {ralign 8:%s}  {txt}%s\n",
			cm[i], _fx_word1(st_local("fx_ver_" + cm[i])), st_local("fx_nfast_" + cm[i]), st_local("fx_nfb_" + cm[i]),
			st_local("fx_last_" + cm[i]))
		nv = nv + strtoreal(st_local("fx_vok_" + cm[i])) + strtoreal(st_local("fx_vmis_" + cm[i])) +
			strtoreal(st_local("fx_vskip_" + cm[i]))
	}
	// verify mode (_fx mode verify or env FASTATA_MODE=verify): fast calls checked against the
	// original
	if (nv > 0 & nv < .) {
		printf("\n")
		printf("{txt}  {ralign 10:verify}  {ralign 9:ok}  {ralign 8:mismatch}  {ralign 8:skipped}\n")
		for (i = 1; i <= cols(cm); i++) {
			printf("{txt}  {ralign 10:%s}  {res}{ralign 9:%s}  {ralign 8:%s}  {ralign 8:%s}\n", cm[i],
				st_local("fx_vok_" + cm[i]), st_local("fx_vmis_" + cm[i]), st_local("fx_vskip_" + cm[i]))
		}
	}
	printf("\n")
	printf("{txt}  originals:\n")
	for (i = 1; i <= cols(cm); i++) {
		p = st_local("fx_orig_" + cm[i])
		printf("{txt}  {ralign 10:%s}  {res}%s\n", cm[i], p == "" ? "(not found; not replaced)" : p)
		if (_fx_word1(st_local("fx_ver_" + cm[i])) != "yes") {
			printf("{txt}  {space 10}  not verified: {res}%s\n", st_local("fx_ver_" + cm[i]))
		}
	}
}

// For fastata status, sets local fx_startup to whether fastata starts with Stata, and returns
// the profile.do Stata runs at startup ("" if none; the current directory's aside, see
// _fx_cwdprofile()): only that file counts. disabled: fastata disable set its flag, so that
// fastata_init does nothing.
string scalar _fx_startup(string scalar rd, real scalar disabled)
{
	string rowvector e
	string scalar f

	e = _fx_searchdirs()
	_fx_profile_first(e[1], e[2], rd)
	f = st_local("fx_profile")
	st_local("fx_startup", "no")
	if (f == "") return(f)
	if (_fx_has_block(f)) {
		if (disabled) st_local("fx_startup", "no (turned off by fastata disable; fastata enable turns it on)")
		else st_local("fx_startup", "yes, through " + f)
		return(f)
	}
	_fx_profile_with_block(e[1], e[2], rd)
	if (st_local("fx_profiles") != "") st_local("fx_startup", "no (" + f + " runs first)")
	return(f)
}

// The PATH and home-folder parts of the profile.do search: (PATH, home folder: Windows
// USERPROFILE, Mac ~/Documents/Stata, else "").
string rowvector _fx_searchdirs()
{
	string scalar home

	home = ""
	if (c("os") == "Windows") home = _fx_getenv("USERPROFILE")
	else if (c("os") == "MacOSX") home = "~/Documents/Stata"
	return((_fx_getenv("PATH"), home))
}

// The current directory's profile.do when a Stata started here runs it instead of file f (the
// one the search finds): it exists, is another file, and no profile.do in the Stata directory
// runs before it. Else "".
string scalar _fx_cwdprofile(string scalar f)
{
	string scalar cw

	cw = _fx_dirslash(c("pwd")) + "profile.do"
	if (!fileexists(cw)) return("")
	if (fileexists(c("sysdir_stata") + "profile.do")) return("")
	if (_fx_normfile(cw) == _fx_normfile(f)) return("")
	return(cw)
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

// 1 if file path has the startup lines' first line (leading and trailing blanks aside).
real scalar _fx_has_block(string scalar path)
{
	if (!fileexists(path)) return(0)
	return(any(strtrim(_fx_lines(path)) :== _fx_block()[1]))
}

// Text s as rows (line, its end): the end is char(10), or char(13)+char(10) (the line then
// without its char(13)), or "" for a last line without one.
string matrix _fx_splitlines(string scalar s)
{
	string matrix out
	string scalar l, e
	real scalar i, j, n

	out = J(0, 2, "")
	n = strlen(s)
	i = 1
	while (i <= n) {
		j = strpos(substr(s, i, .), char(10))
		if (j == 0) {
			l = substr(s, i, .)
			e = ""
			i = n + 1
		}
		else {
			l = substr(s, i, j - 1)
			e = char(10)
			i = i + j
		}
		if (e != "" & substr(l, -1, 1) == char(13)) {
			l = substr(l, 1, strlen(l) - 1)
			e = char(13) + char(10)
		}
		out = out \ (l, e)
	}
	return(out)
}

// The fastata blocks in lines l, as rows (first, last): the start line, then the capture
// fastata_init line if it comes next, then the end line if it comes next, each compared without
// leading and trailing blanks. No other line, edited or the user's, is ever part of a block.
real matrix _fx_blockrows(string colvector l)
{
	string colvector b
	real matrix out
	real scalar i, j, n

	b = _fx_block()
	n = rows(l)
	out = J(0, 2, .)
	for (i = 1; i <= n; i++) {
		if (strtrim(l[i]) != b[1]) continue
		j = i
		if (j < n) {
			if (strtrim(l[j + 1]) == b[2]) j++
		}
		if (j < n) {
			if (strtrim(l[j + 1]) == b[3]) j++
		}
		out = out \ (i, j)
		i = j
	}
	return(out)
}

// Profile text s without its fastata blocks and, if add, with the startup lines where the first
// block was (at the end when there was none). Every other line stays as it is, line ends
// included (CRLF stays CRLF); added lines get the file's line end (else the system's), and a
// text that ends without a line end still does.
string scalar _fx_profile_edit(string scalar s, real scalar add)
{
	string matrix l
	string colvector b
	string scalar eol, out
	real matrix br
	real scalar i, k, n, last, strip, from

	l = _fx_splitlines(s)
	n = rows(l)
	eol = ""
	for (i = 1; i <= n & eol == ""; i++) eol = l[i, 2]
	if (eol == "") eol = (c("os") == "Windows" ? char(13) + char(10) : char(10))
	b = _fx_block()
	br = _fx_blockrows(n ? l[., 1] : J(0, 1, ""))
	out = ""
	last = 0
	strip = 0
	from = 0
	k = 1
	for (i = 1; i <= n; i++) {
		if (k <= rows(br)) {
			if (i == br[k, 1]) {
				if (add & k == 1) {
					out = out + b[1] + eol + b[2] + eol + b[3] + l[br[k, 2], 2]
					last = br[k, 2]
				}
				else if (br[k, 2] == n & l[n, 2] == "") {
					strip = 1
					from = br[k, 1]
				}
				i = br[k, 2]
				k++
				continue
			}
		}
		out = out + l[i, 1] + l[i, 2]
		last = i
	}
	// a removed block ended the text without a line end: so does the line before it now
	if (strip & last >= 1 & last == from - 1) out = substr(out, 1, strlen(out) - strlen(l[last, 2]))
	if (add & rows(br) == 0) {
		if (n == 0) out = b[1] + eol + b[2] + eol + b[3] + eol
		else if (l[n, 2] == "") out = out + eol + b[1] + eol + b[2] + eol + b[3]
		else out = out + b[1] + eol + b[2] + eol + b[3] + eol
	}
	return(out)
}

// Writes text s as file path. An existing file is rewritten in place (a link stays a link, the
// file keeps its permissions) after its old text old is saved as <path>.fastata.bak. Returns 0,
// or 603 when it cannot be written.
real scalar _fx_profile_put(string scalar path, string scalar old, string scalar s)
{
	real scalar fh

	if (!fileexists(path)) return(_fx_put(path, s) ? 603 : 0)
	// writable? (no backup next to a file that cannot be changed)
	if ((fh = _fopen(path, "rw")) < 0) return(603)
	(void) _fclose(fh)
	if (_fx_put(path + ".fastata.bak", old)) return(603)
	return(_fx_overwrite(path, s))
}

// Writes text s over file path in place (creates it when missing): the file is never missing
// and keeps its inode, links and permissions, but a reader may see it half written. Returns 0,
// or 603 when it cannot be written.
real scalar _fx_overwrite(string scalar path, string scalar s)
{
	real scalar fh, rc

	if (!fileexists(path)) return(_fx_put(path, s) ? 603 : 0)
	if ((fh = _fopen(path, "rw")) < 0) return(603)
	rc = _fseek(fh, 0, -1)
	if (rc >= 0 & strlen(s)) rc = _fwrite(fh, s)
	if (rc >= 0) rc = _ftruncate(fh)
	if (_fclose(fh) < 0 | rc < 0) return(603)
	return(0)
}

// Takes the fastata blocks out of profile.do path and, if add, puts the startup lines in
// (_fx_profile_edit()); a file that needs no change is not touched. Returns 0, or 603 when the
// file cannot be read or written.
real scalar _fx_profile_edit_file(string scalar path, real scalar add)
{
	string scalar old, s
	real scalar rc, ex

	ex = fileexists(path)
	if (!ex & !add) return(0)
	old = ""
	if (ex) {
		old = _fx_readraw(path, rc)
		if (rc) return(603)
	}
	s = _fx_profile_edit(old, add)
	if (ex & s == old) return(0)
	return(_fx_profile_put(path, old, s))
}

// fastata enable: puts the startup lines into profile.do file, or (file "") into the first
// profile.do Stata runs at startup (_fx_profile_cands(); without one, PERSONAL/profile.do), and
// removes the flag fastata disable set. Prints the outcome; local fx_rc: 0, or 603 when the file
// cannot be written (the lines to add by hand are printed).
void _fx_enable_profile(string scalar file)
{
	string rowvector e
	string colvector b
	string scalar rd, f, cw
	real scalar i

	rd = _fx_rtpath()
	f = file
	if (f == "") {
		e = _fx_searchdirs()
		_fx_profile_first(e[1], e[2], rd)
		f = st_local("fx_profile")
		if (f == "") {
			_fx_mkdirp(c("sysdir_personal"))
			f = c("sysdir_personal") + "profile.do"
		}
	}
	b = _fx_block()
	if (_fx_profile_edit_file(f, 1)) {
		errprintf("fastata: could not write %s. Add these lines to a profile.do by hand:\n", f)
		for (i = 1; i <= rows(b); i++) errprintf("%s\n", b[i])
		st_local("fx_rc", "603")
		return
	}
	(void) _unlink(rd + "fastata_disabled.txt")
	printf("{txt}fastata: enabled; Stata loads it at startup through %s\n", f)
	cw = _fx_cwdprofile(f)
	if (cw != "") {
		if (!_fx_has_block(cw)) {
			printf("{txt}note: Stata sessions started in %s run the profile.do there instead,\n", c("pwd"))
			printf("{txt}      so fastata is inactive in them unless these lines are added to it:\n")
			for (i = 1; i <= rows(b); i++) printf("{txt}      %s\n", b[i])
		}
	}
	st_local("fx_rc", "0")
}

// fastata disable: sets the flag that keeps fastata_init from turning fastata on at startup
// (fastata_disabled.txt in the runtime directory: a profile.do the search does not reach may
// still run it), then takes the startup lines out of profile.do file, or (file "") out of every
// profile.do of the search that has them, and out of the current directory's profile.do
// (enable's note suggests adding them there). The runtime directory stays: other open sessions
// may be using it. Prints the outcome; local fx_rc: 0, or 603 when a file cannot be written.
void _fx_disable_profile(string scalar file)
{
	string rowvector e
	string colvector cand, done
	string scalar rd, f
	real scalar i, j, seen

	rd = _fx_rtpath()
	if (!direxists(rd)) (void) _mkdir(rd)
	(void) _fx_put(rd + "fastata_disabled.txt", "set by fastata disable; fastata enable removes it" + char(10))
	if (file != "") cand = file
	else {
		e = _fx_searchdirs()
		cand = _fx_profile_cands(e[1], e[2], rd)
	}
	cand = cand \ (_fx_dirslash(c("pwd")) + "profile.do")
	done = J(0, 1, "")
	for (i = 1; i <= rows(cand); i++) {
		f = cand[i]
		if (!_fx_has_block(f)) continue
		seen = 0
		for (j = 1; j <= rows(done); j++) {
			if (_fx_normfile(done[j]) == _fx_normfile(f)) seen = 1
		}
		if (seen) continue
		if (_fx_profile_edit_file(f, 0)) {
			errprintf("fastata: could not write %s; remove the fastata lines from it by hand\n", f)
			st_local("fx_rc", "603")
			return
		}
		done = done \ f
	}
	if (rows(done) == 0) printf("{txt}fastata: disabled (no profile.do had the fastata startup lines)\n")
	else printf("{txt}fastata: disabled; removed the startup lines from %s\n", invtokens(done', ", "))
	st_local("fx_rc", "0")
}

end
