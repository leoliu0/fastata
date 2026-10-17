* test_framework.do -- fastata enable, disable, on, off and status; the profile.do search and
* block handling (only an exact block is removed, line ends kept, the block replaced in place,
* a backup written); status and the profile.do Stata runs first; the current directory's
* profile.do; rebuilding an outdated runtime directory and refreshing it after a reinstall of
* the same version (files replaced, never rewritten in place; one build at a time, also across
* processes); ado-path changes (PLUS with spaces or a dollar sign, PLUS changed after
* activation, then clear all); the caller version and the by prefix reaching the original; an
* unverified original; running the original when the runtime directory was rebuilt or erased by
* another session, is read-only or is off the ado-path; the mode surviving off/on; clear all
* and discard.
* No real profile.do is touched: enable and disable search for one only when the search (with
* PERSONAL pointed at a scratch folder) finds none; otherwise they get profile(<scratch file>).
* Other Stata sessions are separate Stata processes started through shell (Linux, macOS).
version 16
clear all
set more off
set linesize 250
fx_setup
local plus0 `"`c(sysdir_plus)'"'
local personal0 `"`c(sysdir_personal)'"'

* scratch folder (its path contains spaces)
tempfile tf
local tmp `"`tf'_fx tmp/"'
mkdir `"`tmp'"'

* fx_out <command>: runs command, keeping its output lines in global FX_OUT (joined by |)
capture program drop fx_out
program fx_out
	tempfile f
	quietly log using `"`f'"', text name(_fxo) nomsg replace
	`0'
	quietly log close _fxo
	mata: st_global("FX_OUT", invtokens(strtrim(cat(st_local("f")))', "|"))
end
* fx_has "<text>" ["<what>"]: FX_OUT must contain text
capture program drop fx_has
program fx_has
	args text what
	mata: st_local("ok", strofreal(strpos(st_global("FX_OUT"), st_local("text")) > 0))
	if !`ok' {
		di as err `"`what': output lacks "`text'""'
		di as err `"output: $FX_OUT"'
		exit 9
	}
end
* fx_nblock "<file>" n: file must hold the startup lines n times and nothing else of fastata's
capture program drop fx_nblock
program fx_nblock
	args file n
	mata: l = cat(st_local("file")) \ ""; st_local("k1", strofreal(sum(l :== "capture fastata_init"))); st_local("k2", strofreal(sum(strpos(l, "fastata") :> 0)))
	if `k1' != `n' | `k2' != 3*`n' {
		di as err `"`file': `k1' startup lines and `k2' fastata lines, expected `n' and `=3*`n''"'
		exit 9
	}
end
* fx_where cmd "<path>": the ado-file Stata would load for cmd
capture program drop fx_where
program fx_where
	args cmd want
	quietly findfile `cmd'.ado
	if `"`r(fn)'"' != `"`want'"' {
		di as err `"`cmd' resolves to `r(fn)', expected `want'"'
		exit 9
	}
end
* fx_runchild <name> [<name> ...]: runs the do-files <name>.do written by tf_childdo() at the
* same time, each in its own Stata process, and waits for them; each must print CHILD_OK
capture program drop fx_runchild
program fx_runchild
	local cmd
	foreach n of local 0 {
		capture erase `n'.log
		local cmd `"`cmd' "$FX_EXE" -b do `n'.do &"'
	}
	shell (`cmd' wait)
	foreach n of local 0 {
		mata: st_local("ok", strofreal(fileexists(st_local("n") + ".log")))
		if `ok' mata: st_local("ok", strofreal(anyof(cat(st_local("n") + ".log"), "CHILD_OK")))
		if !`ok' {
			capture type `n'.log
			di as err "`n'.do failed (its log above)"
			exit 9
		}
		erase `n'.do
		erase `n'.log
	}
end

mata:
// writes text s as file path (replacing it)
void tf_write(string scalar path, string scalar s)
{
	real scalar fh

	if (fileexists(path)) unlink(path)
	fh = fopen(path, "w")
	if (strlen(s)) fwrite(fh, s)
	fclose(fh)
}

// the bytes of file path, or "<none>"
string scalar tf_read(string scalar path)
{
	real scalar fh, n
	string scalar s

	if (!fileexists(path)) return("<none>")
	fh = fopen(path, "r")
	fseek(fh, 0, 1)
	n = ftell(fh)
	fseek(fh, 0, -1)
	s = ""
	if (n) s = fread(fh, n)
	fclose(fh)
	return(s)
}

string scalar tf_show(string scalar s)
{
	return(subinstr(subinstr(s, char(13), "<CR>", .), char(10), "<LF>", .))
}

// profile.do path holds before; fastata cmd (enable or disable) with profile(path) must leave
// after in it and, when that differs from before, before in path.fastata.bak (else no backup)
void tf_case(string scalar path, string scalar cmd, string scalar before, string scalar after,
	string scalar what)
{
	string scalar bak, got

	bak = path + ".fastata.bak"
	if (fileexists(bak)) unlink(bak)
	tf_write(path, before)
	stata("quietly fastata " + cmd + ", profile(" + char(96) + char(34) + path + char(34) + char(39) + ")")
	got = tf_read(path)
	if (got != after) {
		errprintf("%s: profile.do is [%s], expected [%s]\n", what, tf_show(got), tf_show(after))
		exit(9)
	}
	if (before != after) {
		if (tf_read(bak) != before) {
			errprintf("%s: the backup is [%s], expected [%s]\n", what, tf_show(tf_read(bak)), tf_show(before))
			exit(9)
		}
	}
	else if (fileexists(bak)) {
		errprintf("%s: an unchanged profile.do got a backup\n", what)
		exit(9)
	}
}

// writes name.do for fx_runchild: the test environment (the repository's ado-files first on
// the ado-path, PLUS tests/stata/_plus/), the lines of body, then di "CHILD_OK"
void tf_childdo(string scalar name, string colvector body)
{
	string colvector l

	l = "version 16" \ "clear all" \ "set more off"
	l = l \ ("quietly adopath ++ " + char(96) + char(34) + st_global("FX_STATA") + char(34) + char(39))
	l = l \ ("sysdir set PLUS " + char(96) + char(34) + st_global("FX_TESTS") + "_plus/" + char(34) + char(39))
	l = l \ body \ ("di " + char(34) + "CHILD_OK" + char(34))
	tf_write(name + ".do", invtokens(l', char(10)) + char(10))
}

// 1 if a file can be created in directory d
real scalar tf_writable(string scalar d)
{
	real scalar fh

	fh = _fopen(d + "tf_probe", "w")
	if (fh < 0) return(0)
	fclose(fh)
	unlink(d + "tf_probe")
	return(1)
}

// erases the directories under c(tmpdir) that this session's fastata wrote renamed originals to
void tf_rmsessdirs()
{
	string colvector d, f
	string scalar s, t
	real scalar i, j

	s = pathbasename(st_tempfilename())
	s = substr(s, 1, strpos(s, ".") - 1)
	t = c("tmpdir") + "/"
	d = dir(t, "dirs", "fastata_" + s + ".*")
	for (i = 1; i <= rows(d); i++) {
		f = dir(t + d[i], "files", "*")
		for (j = 1; j <= rows(f); j++) unlink(t + d[i] + "/" + f[j])
		rmdir(t + d[i])
	}
}

// a path in compound double quotes, for a command line
string scalar tf_cq(string scalar s)
{
	return(char(96) + char(34) + s + char(34) + char(39))
}
end
mata: tf_sb = "* >>> fastata (added by fastata enable; remove with fastata disable)"; tf_ib = "capture fastata_init"; tf_eb = "* <<< fastata"; LF = char(10); CR = char(13)

* the Stata to start other sessions with: the stata-mp launcher on PATH (it may be a wrapper that
* sets up libraries), else the binary in c(sysdir_stata)
local unix = c(os) != "Windows"
if `unix' {
	tempfile onpath
	shell command -v stata-mp > "`onpath'" 2>/dev/null
	mata: st_global("FX_EXE", fileexists(st_local("onpath")) && rows(cat(st_local("onpath"))) ? "stata-mp" : c("sysdir_stata") + "stata-mp")
}

* auto data for single commands
frame create tfp
frame tfp: quietly sysuse auto
frame tfp: egen m0 = mode(rep78)

_fx rtpath
local rt `"`fx_rt'"'
quietly findfile egen.ado, path(BASE)
local base_egen `"`r(fn)'"'

* ---------------------------------------------------------------------------------------------
* enable through the profile.do search: with a fresh PERSONAL, enable creates
* PERSONAL/profile.do; repeated enables keep one block and the user's lines
* ---------------------------------------------------------------------------------------------
mkdir `"`tmp'pers"'
sysdir set PERSONAL `"`tmp'pers/"'
local prof `"`tmp'pers/profile.do"'
local envpath : env PATH
_fx profile_first `"`envpath'"' "" `"`rt'"'
local search = `"`fx_profile'"' == ""
local popt
if !`search' {
	di as txt `"note: `fx_profile' exists, so enable and disable get profile() instead of searching"'
	local popt `", profile(`"`prof'"')"'
}
fx_out fastata enable `popt'
fx_has `"fastata: enabled; Stata loads it at startup through `prof'"' enable
fx_nblock `"`prof'"' 1
fx_where egen `"`rt'egen.ado"'
mata: l = cat(st_local("prof")); unlink(st_local("prof")); fh = fopen(st_local("prof"), "w"); fput(fh, "* my line"); for (i = 1; i <= rows(l); i++) fput(fh, l[i]); fclose(fh)
fastata enable `popt'
fastata enable `popt'
fx_nblock `"`prof'"' 1
mata: st_local("mine", strofreal(cat(st_local("prof"))[1] == "* my line"))
assert `mine'
fx_out fastata status
fx_has "on now:      yes" status
if `search' fx_has `"at startup:  yes, through `prof'"' status
fx_has "egen  yes" status
* status says at startup: yes only for the profile.do Stata runs first: one ahead on the
* ado-path runs instead
if `search' {
	mkdir `"`tmp'early"'
	mata: tf_write(st_local("tmp") + "early/profile.do", "* early" + LF)
	quietly adopath ++ `"`tmp'early/"'
	fx_out fastata status
	fx_has `"at startup:  no (`tmp'early/profile.do runs first)"' "status, earlier profile.do"
	quietly adopath - `"`tmp'early/"'
	fx_out fastata status
	fx_has `"at startup:  yes, through `prof'"' "status, earlier profile.do gone"
}
di as txt "enable ok"

* off and on change which file each command resolves to
foreach c in egen isid duplicates xtile pctile destring tostring {
	fx_where `c' `"`rt'`c'.ado"'
}
fx_out fastata off
fx_has "fastata: off for this session" off
fx_where egen `"`base_egen'"'
fx_out fastata status
fx_has "on now:      no" status off
fastata on
fx_where egen `"`rt'egen.ado"'
di as txt "on/off ok"

* the mode set by _fx mode survives off and on
_fx mode original
fastata off
fastata on
_fx gate isid
assert "`fx_ok'" == "0" & "`fx_why'" == "mode original"
_fx mode auto
_fx gate isid
assert "`fx_ok'" == "1"
di as txt "mode ok"

* disable removes the block (keeping the user's line) and takes fastata off. The runtime
* directory stays (other open sessions may be using it), with a flag that keeps fastata_init
* from turning fastata on again at startup.
fx_out fastata disable `popt'
fx_has `"fastata: disabled; removed the startup lines from `prof'"' disable
fx_nblock `"`prof'"' 0
mata: st_local("mine", strofreal(cat(st_local("prof")) == "* my line"))
assert `mine'
mata: st_local("kept", strofreal(fileexists(st_local("rt") + "egen.ado") & fileexists(st_local("rt") + "fastata_disabled.txt")))
assert `kept'
fx_where egen `"`base_egen'"'
fastata_init
fx_where egen `"`base_egen'"'
fx_out fastata disable `popt'
fx_has "fastata: disabled (no profile.do had the fastata startup lines)" disable again
di as txt "disable ok"

* profile() overrides the search
local other `"`tmp'other profile.do"'
fastata enable, profile(`"`other'"')
fx_nblock `"`other'"' 1
fx_nblock `"`prof'"' 0
fastata disable, profile(`"`other'"')
fx_nblock `"`other'"' 0
sysdir set PERSONAL `"`personal0'"'
di as txt "profile() ok"

* ---------------------------------------------------------------------------------------------
* profile.do editing: only an exact block is removed (its start line, then capture fastata_init
* and the end line where they follow), so edited blocks never cost the user's lines; line ends
* stay as they are; an existing block is replaced where it is; a changed file is first saved as
* <file>.fastata.bak, an unchanged one is not touched
* ---------------------------------------------------------------------------------------------
local pf `"`tmp'case profile.do"'
mata: pf = st_local("pf"); u = "set more off" + LF; v = "global MYDATA /data/project" + LF + "sysdir set PLUS /data/ado/plus" + LF
mata: tf_case(pf, "disable", u + tf_sb + LF + tf_ib + LF + v, u + v, "end line missing, disable")
mata: tf_case(pf, "enable", u + tf_sb + LF + tf_ib + LF + v, u + tf_sb + LF + tf_ib + LF + tf_eb + LF + v, "end line missing, enable")
mata: tf_case(pf, "disable", "a" + LF + tf_sb + LF + tf_ib + LF + tf_eb + " " + LF + "global MYDATA x" + LF, "a" + LF + "global MYDATA x" + LF, "end line edited")
mata: tf_case(pf, "disable", tf_sb + LF + "global MYDATA x" + LF + tf_ib + LF + tf_eb + LF, "global MYDATA x" + LF + tf_ib + LF + tf_eb + LF, "user line inside the block")
mata: w = CR + LF; tf_case(pf, "enable", "a" + w + tf_sb + w + tf_ib + w + tf_eb + w + "b" + w, "a" + w + tf_sb + w + tf_ib + w + tf_eb + w + "b" + w, "CRLF, enable again")
mata: tf_case(pf, "disable", "a" + w + tf_sb + w + tf_ib + w + tf_eb + w + "b" + w, "a" + w + "b" + w, "CRLF, disable")
mata: tf_case(pf, "enable", "a" + w + "b" + w, "a" + w + "b" + w + tf_sb + w + tf_ib + w + tf_eb + w, "CRLF, enable")
mata: tf_case(pf, "enable", "a" + LF + "b", "a" + LF + "b" + LF + tf_sb + LF + tf_ib + LF + tf_eb, "no last line end, enable")
mata: tf_case(pf, "disable", "a" + LF + "b" + LF + tf_sb + LF + tf_ib + LF + tf_eb, "a" + LF + "b", "no last line end, disable")
mata: tf_case(pf, "enable", "a" + LF + tf_sb + "  " + LF + tf_ib + LF + tf_eb + LF + "b" + LF, "a" + LF + tf_sb + LF + tf_ib + LF + tf_eb + LF + "b" + LF, "block in the middle stays there")
mata: tf_case(pf, "enable", tf_sb + LF + tf_ib + LF + tf_eb + LF + "x" + LF + tf_sb + LF + tf_ib + LF + tf_eb + LF, tf_sb + LF + tf_ib + LF + tf_eb + LF + "x" + LF, "two blocks")
di as txt "profile.do editing ok"

* ---------------------------------------------------------------------------------------------
* the current directory's profile.do runs instead of the one enable writes (unless a profile.do
* in the Stata directory runs before both): enable's note offers the whole block, status
* reports it, and disable removes the block from it too
* ---------------------------------------------------------------------------------------------
local cwd0 `"`c(pwd)'"'
mkdir `"`tmp'cwd"'
quietly cd `"`tmp'cwd"'
mata: tf_write("profile.do", "* mine" + LF)
capture confirm file `"`c(sysdir_stata)'profile.do"'
local stataprof = !_rc
fx_out fastata enable, profile(`"`other'"')
if !`stataprof' {
	fx_has "so fastata is inactive in them unless these lines are added to it:" "enable, cwd note"
	fx_has "* >>> fastata (added by fastata enable; remove with fastata disable)|capture fastata_init|* <<< fastata" "enable, cwd note"
}
mata: tf_write("profile.do", "* mine" + LF + tf_sb + LF + tf_ib + LF + tf_eb + LF)
if !`stataprof' {
	fx_out fastata status
	fx_has "cwd/profile.do instead, which has the startup lines" "status, cwd profile.do"
}
fx_out fastata disable, profile(`"`other'"')
fx_has "cwd/profile.do" "disable, cwd profile.do"
mata: st_local("ok", strofreal(tf_read("profile.do") == "* mine" + LF))
assert `ok'
* a later start (a profile.do elsewhere still runs fastata_init) leaves fastata off
fastata_init
fx_where egen `"`base_egen'"'
* enable clears that
fastata enable, profile(`"`other'"')
capture confirm file `"`rt'fastata_disabled.txt"'
assert _rc
fastata off
fastata_init
fx_where egen `"`rt'egen.ado"'
fastata disable, profile(`"`other'"')
erase `"`rt'fastata_disabled.txt"'
erase profile.do
quietly cd `"`cwd0'"'
di as txt "current directory profile.do ok"

* ---------------------------------------------------------------------------------------------
* an outdated runtime directory is rebuilt by fastata on: plugins of other names go, renamed
* originals stay (their names hold their content's hash, so they never go stale)
* ---------------------------------------------------------------------------------------------
fastata on
fastata off
* the version this repository's files build
_fx rtversion
local fxver `fx_have'
local pl0 : dir `"`rt'"' files "fastata_*.plugin"
assert `: word count `pl0'' == 1
local pl0 `pl0'
mata: st_local("ok", strofreal(ustrregexm(st_local("pl0"), "^fastata_" + subinstr(st_local("fxver"), ".", "[.]") + "_[0-9a-f]{8}[.]plugin$")))
assert `ok'
mata: tf_write(st_local("rt") + "fastata_runtime.txt", "0.0.9" + LF)
copy `"`rt'`pl0'"' `"`rt'fastata_0.0.9.plugin"'
copy `"`rt'egen.ado"' `"`rt'_fxo_00000000_egen.ado"'
fx_out fastata status
fx_has "built by version 0.0.9" status outdated
fastata on
_fx rtversion
assert "`fx_have'" == "`fxver'" & "`fx_build'" == "0"
capture confirm file `"`rt'fastata_0.0.9.plugin"'
assert _rc
erase `"`rt'_fxo_00000000_egen.ado"'
local pl1 : dir `"`rt'"' files "fastata_*.plugin"
assert `: word count `pl1'' == 1
local pl1 `pl1'
assert `"`pl1'"' == `"`pl0'"'
di as txt "rebuild ok"

* ---------------------------------------------------------------------------------------------
* a reinstall of the same version with changed files (a hotfix, a regenerated gate list)
* refreshes the runtime directory at the next fastata on. Unchanged files are left alone and a
* changed one is replaced by a new file, never rewritten in place (a session reading it or
* having loaded it keeps the old one): checked through hard links. A changed plugin gets a new
* name. The installed files are copies in a scratch folder ahead on the ado-path.
* ---------------------------------------------------------------------------------------------
local inst `"`tmp'inst/"'
mkdir `"`inst'"'
local fs : dir `"$FX_STATA"' files "*.ado"
foreach f of local fs {
	copy `"$FX_STATA`f'"' `"`inst'`f'"'
}
copy `"${FX_STATA}fastata.plugin"' `"`inst'fastata.plugin"'
* the gate list without isid's rows, and the plugin with one more byte
mata: l = cat(st_local("inst") + "_fx_gatelist.ado"); l = select(l, strpos(l, "* gate isid ") :!= 1); tf_write(st_local("inst") + "_fx_gatelist.ado", invtokens(l', LF) + LF)
mata: tf_write(st_local("inst") + "fastata.plugin", tf_read(st_local("inst") + "fastata.plugin") + char(0))
mata: gate0 = tf_read(st_local("rt") + "_fx_gatelist.ado")
* (hard links in PLUS, on the runtime directory's file system)
local hl `"${FX_TESTS}_plus/tf_hl_"'
if `unix' {
	capture erase `"`hl'gate"'
	capture erase `"`hl'fx"'
	shell ln "`rt'_fx_gatelist.ado" "`hl'gate"
	shell ln "`rt'_fx.ado" "`hl'fx"
}
quietly adopath ++ `"`inst'"'
fastata on
_fx gate isid
assert "`fx_ok'" == "0"
mata: st_local("ok", strofreal(tf_read(st_local("rt") + "_fx_gatelist.ado") == tf_read(st_local("inst") + "_fx_gatelist.ado")))
assert `ok'
if `unix' {
	mata: st_local("ok", strofreal(tf_read(st_local("hl") + "gate") == gate0))
	assert `ok'
	tempfile same
	shell test "`rt'_fx.ado" -ef "`hl'fx" && echo same > "`same'"
	confirm file `"`same'"'
	erase `"`hl'gate"'
	erase `"`hl'fx"'
}
local pl1 : dir `"`rt'"' files "fastata_*.plugin"
assert `: word count `pl1'' == 1
local pl1 `pl1'
assert `"`pl1'"' != `"`pl0'"'
* the new plugin is the one in use (isid is not verified with this gate list: egen)
_fx status
local e0 = `fx_nfast_egen'
frame tfp: egen double mz = mean(price), by(foreign)
_fx status
assert `fx_nfast_egen' == `e0' + 1
frame tfp: drop mz
* back to the repository's files
quietly adopath - `"`inst'"'
fastata on
_fx gate isid
assert "`fx_ok'" == "1"
local pl2 : dir `"`rt'"' files "fastata_*.plugin"
local pl2 `pl2'
assert `"`pl2'"' == `"`pl0'"'
di as txt "refresh ok"

* a build waits while another process holds the build lock, and takes over a lock left by an
* interrupted build after 10 seconds
mata: tf_write(st_local("rt") + "fastata_runtime.txt", st_local("fxver") + LF)
mkdir `"`rt'fastata_build.lock"'
fastata off
timer clear 99
timer on 99
fastata on
timer off 99
quietly timer list 99
assert r(t99) >= 9
mata: st_local("ok", strofreal(!direxists(st_local("rt") + "fastata_build.lock")))
assert `ok'
_fx rtversion
assert "`fx_build'" == "0"
di as txt "build lock ok"

* three sessions that start at once after an update all rebuild the runtime directory, one at a
* time, and run the commands meanwhile
if `unix' {
	mata: tf_write(st_local("rt") + "fastata_runtime.txt", st_local("fxver") + LF)
	mata: b = "quietly fastata on" \ "sysuse auto, clear" \ "egen m = mode(rep78)" \ "egen double t = mean(price), by(foreign)" \ "isid make" \ "_fx rtversion" \ ("assert " + char(96) + "fx_build" + char(39) + " == 0")
	mata: tf_childdo("tf_build1", b); tf_childdo("tf_build2", b); tf_childdo("tf_build3", b)
	fx_runchild tf_build1 tf_build2 tf_build3
	_fx rtversion
	assert "`fx_build'" == "0"
	di as txt "concurrent builds ok"
}
fastata on

* ---------------------------------------------------------------------------------------------
* test data for the command checks below
* ---------------------------------------------------------------------------------------------
fx_testdata
frame copy default base
frame copy default bg
frame bg: sort g id

* ---------------------------------------------------------------------------------------------
* PLUS changed after activation (replication packages run sysdir set PLUS): the runtime
* directory stays on the ado-path and keeps working, also after its programs are dropped. The
* results equal those of the originals, run directly in another frame.
* ---------------------------------------------------------------------------------------------
mkdir `"`tmp'empty plus"'
sysdir set PLUS `"`tmp'empty plus/"'
fx_where egen `"`rt'egen.ado"'
foreach p in egen _fx_egen _fx isid _fx_isid {
	capture program drop `p'
}
_fx status
* calls through fastata, fast or fallback
local e0 = `fx_nfast_egen' + `fx_nfb_egen'
local i0 = `fx_nfast_isid' + `fx_nfb_isid'
capture frame drop fa
capture frame drop fb
frame copy base fa
frame copy base fb
set sortseed 1
frame fa: egen m = mode(g)
frame fa: capture noisily isid id2
assert _rc == 459
_fx status
assert `fx_nfast_egen' + `fx_nfb_egen' == `e0' + 1 & `fx_nfast_isid' + `fx_nfb_isid' == `i0' + 1
_fx orig egen
set sortseed 1
frame fb: `fx_prog' m = mode(g)
fx_cmpframes fa fb, tol(0) what(egen after PLUS changed)
sysdir set PLUS `"`plus0'"'
di as txt "PLUS changed ok"

* ---------------------------------------------------------------------------------------------
* a runtime directory whose path contains spaces
* ---------------------------------------------------------------------------------------------
fastata off
mkdir `"`tmp'a b"'
sysdir set PLUS `"`tmp'a b/"'
fastata on
_fx rtpath
local rt2 `"`fx_rt'"'
assert strpos(`"`rt2'"', "a b/fastata/") > 0
fx_where egen `"`rt2'egen.ado"'
fx_both "egen t = concat(g s)" , expect(egen fallback) allr
* leftover r() of the non-rclass egen, xtile, tostring and isid is a documented exception: no allr
fx_both "egen t = tag(g s)" , expect(egen fast)
fx_both "xtile q = x1, nq(10)" , expect(xtile fast)
fx_both "tostring zi, gen(zs)" , expect(tostring fast)
fx_both "isid id" , expect(isid fast)
fastata off
_fx rmruntime `"`rt2'"'
sysdir set PLUS `"`plus0'"'
fastata on
di as txt "spaces ok"

* ---------------------------------------------------------------------------------------------
* a PLUS whose path has a dollar sign: paths never pass through a command line, where it would
* be expanded as a macro
* ---------------------------------------------------------------------------------------------
fastata off
mata: tf_dol = st_local("tmp") + "d" + char(36) + "x/"; (void) _mkdir(tf_dol)
sysdir set PLUS `"`tmp'd\$x/"'
mata: st_local("ok", strofreal(c("sysdir_plus") == tf_dol))
assert `ok'
fastata on
mata: st_local("ok", strofreal(findfile("egen.ado") == tf_dol + "fastata/egen.ado"))
assert `ok'
frame tfp: egen md = mode(rep78)
frame tfp: assert md == m0
_fx orig egen
mata: st_local("ok", strofreal(fileexists(tf_dol + "fastata/" + st_local("fx_prog") + ".ado")))
assert `ok'
frame tfp: isid make
fx_out fastata status
mata: st_local("ok", strofreal(strpos(st_global("FX_OUT"), "d" + char(36) + "x/fastata/") > 0))
assert `ok'
fastata off
sysdir set PLUS `"`plus0'"'
fastata on
frame tfp: drop md
di as txt "dollar sign ok"

* ---------------------------------------------------------------------------------------------
* the by prefix and the caller version reach the original: a stand-in egen.ado placed after the
* runtime directory (so it is the original fastata runs) prints what it receives
* ---------------------------------------------------------------------------------------------
fastata off
mkdir `"`tmp'fake"'
mata: fh = fopen(st_local("tmp") + "fake/egen.ado", "w"); fput(fh, "program egen, byable(onecall)"); fput(fh, char(9) + "version 16"); fput(fh, char(9) + "di " + char(34) + "stand-in egen: caller " + char(34) + " _caller() " + char(34) + " by [" + char(96) + "_byvars" + char(39) + "] rc0 [" + char(96) + "_byrc0" + char(39) + "] args [" + char(96) + "0" + char(39) + "]" + char(34)); fput(fh, "end"); fclose(fh)
quietly adopath ++ `"`tmp'fake/"'
fastata on
frame copy bg vb
frame vb {
	fx_out version 12: by g: egen z = mean(x1)
	fx_has "stand-in egen: caller 12 by [g] rc0 [] args [z = mean(x1)]" "version 12 + by"
	fx_out by g, rc0: egen z = mean(x1), by(s)
	fx_has "stand-in egen: caller 16 by [g] rc0 [, rc0] args [z = mean(x1), by(s)]" "by, rc0"
	fx_out version 9: egen z = mean(x1)
	fx_has "stand-in egen: caller 9 by [] rc0 [] args [z = mean(x1)]" "version 9"
}
frame drop vb
fx_out fastata status
fx_has "egen  no" "status, stand-in egen"
_fx pathpos `"`tmp'fake/"'
foreach p of local fx_pos {
	quietly adopath - `p'
}
fastata on
fx_where egen `"`rt'egen.ado"'
* non-integer caller versions (ado-files under version 9.2, 11.2, ...): a caller of 9.2 must not
* reach the original as "version 9.199999999999999" (invalid syntax). mean() by groups is in the
* accumulation class (summation order follows the original's sort ties), hence tol(1e-13).
foreach v in 9.2 11.2 13.1 16.1 {
	fx_both "version `v': by g, sort: egen double t = total(x1)" , expect(egen any)
	fx_both "version `v': egen double m = mean(x1), by(g)" , expect(egen any) tol(1e-13)
	fx_both "version `v': isid id" , expect(isid any)
	fx_both "version `v': duplicates report g" , expect(duplicates any) allr
	fx_both "version `v': xtile q = x1, nq(4)" , expect(xtile any)
	fx_both "version `v': pctile double p = x1, nq(4)" , expect(pctile any)
	fx_both "version `v': tostring zi, gen(zs)" , expect(tostring any)
	fx_both "version `v': destring sn, gen(snn) force" , expect(destring any)
}
di as txt "caller version and by ok"

* ---------------------------------------------------------------------------------------------
* an unverified original: a copy of isid.ado with one added comment line, placed after the
* runtime directory. The gate refuses it and isid still runs it, unchanged.
* ---------------------------------------------------------------------------------------------
fastata off
mkdir `"`tmp'mod"'
quietly findfile isid.ado, path(BASE)
copy `"`r(fn)'"' `"`tmp'mod/isid.ado"'
mata: fh = fopen(st_local("tmp") + "mod/isid.ado", "a"); fput(fh, "* a local change"); fclose(fh)
quietly adopath ++ `"`tmp'mod/"'
fastata on
_fx gate isid
assert "`fx_ok'" == "0" & "`fx_why'" == "unverified isid.ado"
fx_both "isid id" , expect(isid fallback) allr
fx_both "isid id2" , expect(isid fallback) allr
_fx status
assert `"`fx_last_isid'"' == "unverified isid.ado"
assert `"`fx_ver_isid'"' == "no (unverified isid.ado)"
_fx pathpos `"`tmp'mod/"'
foreach p of local fx_pos {
	quietly adopath - `p'
}
fastata on
_fx gate isid
assert "`fx_ok'" == "1"
di as txt "unverified original ok"

* ---------------------------------------------------------------------------------------------
* running the original keeps working when the renamed copy cannot stay in the runtime
* directory: (a) another session rebuilt the directory (its copies gone) and this one reloads
* its programs; (b) another session ran fastata disable; (c) another session erased the
* directory; (d) the directory is read-only; (e) a do-file reset the ado-path. In (c)-(e) the
* copy goes to a directory of this session under c(tmpdir), added to the end of the ado-path.
* The results equal the original's (m0, from the start).
* ---------------------------------------------------------------------------------------------
fastata on
local sado0 `"$S_ADO"'
frame tfp: egen double mm0 = mean(price), by(foreign)
if `unix' {
	* (a)
	mata: tf_childdo("tf_rebuild", ("_fx rmruntime " + tf_cq(st_local("rt"))) \ "quietly fastata on")
	fx_runchild tf_rebuild
	foreach p in egen _fx_egen _fx _fx_call {
		capture program drop `p'
	}
	frame tfp: egen ma = mode(rep78)
	frame tfp: assert ma == m0
	_fx orig egen
	confirm file `"`rt'`fx_prog'.ado"'
	* (b)
	mata: tf_childdo("tf_disable", "fastata disable, profile(" + tf_cq(st_local("tmp") + "child profile.do") + ")")
	fx_runchild tf_disable
	foreach p in egen _fx_egen _fx _fx_call {
		capture program drop `p'
	}
	frame tfp: egen mb = mode(rep78)
	frame tfp: assert mb == m0
	frame tfp: egen double mm = mean(price), by(foreign)
	frame tfp: assert mm == mm0
	fx_where egen `"`rt'egen.ado"'
	erase `"`rt'fastata_disabled.txt"'
	* (c)
	mata: tf_childdo("tf_erase", "_fx rmruntime " + tf_cq(st_local("rt")))
	fx_runchild tf_erase
	mata: st_local("ok", strofreal(!direxists(st_local("rt"))))
	assert `ok'
	frame tfp: egen mc = mode(rep78)
	frame tfp: assert mc == m0
	frame tfp: egen double mm2 = mean(price), by(foreign)
	frame tfp: assert mm2 == mm0
	_fx orig egen
	quietly findfile `fx_prog'.ado
	assert strpos(`"`r(fn)'"', `"`c(tmpdir)'"') == 1 & strpos(`"`r(fn)'"', "/fastata_") > 0
	global S_ADO `"`sado0'"'
	fastata on
	* (d)
	local f : dir `"`rt'"' files "_fxo_*"
	foreach x of local f {
		erase `"`rt'`x'"'
	}
	_fx reset
	shell chmod a-w "`rt'"
	mata: st_local("ro", strofreal(!tf_writable(st_local("rt"))))
	if `ro' {
		frame tfp: egen md = mode(rep78)
		frame tfp: assert md == m0
		_fx orig egen
		quietly findfile `fx_prog'.ado
		assert strpos(`"`r(fn)'"', `"`c(tmpdir)'"') == 1
	}
	else {
		di as txt "note: the runtime directory stays writable after chmod (root?); (d) skipped"
	}
	shell chmod u+w "`rt'"
	global S_ADO `"`sado0'"'
}
* (e) (the shim and fastata's programs are loaded, as after any earlier call)
frame tfp: egen double mm4 = mean(price), by(foreign)
_fx status
local nfb = `fx_nfb_egen'
global S_ADO "BASE;SITE;.;PERSONAL;PLUS;OLDPLACE"
frame tfp: egen me = mode(rep78)
frame tfp: assert me == m0
_fx status
assert `fx_nfb_egen' == `nfb' + 1
frame tfp: egen double mm3 = mean(price), by(foreign)
frame tfp: assert mm3 == mm0
global S_ADO `"`sado0'"'
fastata on
fx_where egen `"`rt'egen.ado"'
mata: tf_rmsessdirs()
di as txt "original without the runtime directory ok"

* ---------------------------------------------------------------------------------------------
* clear all and discard drop every program (the helpers above too) and clear all also clears
* Mata; the next call reloads what fastata needs
* ---------------------------------------------------------------------------------------------
foreach how in "clear all" discard {
	`how'
	* (clear all turns the small-data cutoff on again; these calls are on 74 observations)
	_fx small off
	quietly findfile egen.ado
	assert `"`r(fn)'"' == `"`rt'egen.ado"'
	_fx status
	local e0 = `fx_nfast_egen' + `fx_nfb_egen'
	local i0 = `fx_nfast_isid' + `fx_nfb_isid'
	sysuse auto, clear
	egen m = mode(foreign)
	isid make
	_fx status
	assert `fx_nfast_egen' + `fx_nfb_egen' == `e0' + 1 & `fx_nfast_isid' + `fx_nfb_isid' == `i0' + 1
}
di as txt "clear all and discard ok"

* counts_save writes every command's counts
_fx counts_save `"`tmp'counts.csv"'
_fx status
mata: l = cat(st_local("tmp") + "counts.csv"); st_local("ok", strofreal(rows(l) == 8 & l[1] == "cmd,fast,fallback,last_reason" & l[2] == "egen,0," + st_local("fx_nfb_egen") + "," + char(34) + "function" + char(34)))
assert `ok'
di as txt "counts_save ok"

* a cold gate check (and status) leaves the random numbers that break Stata's sort ties alone,
* so that a fallback breaks the original's ties as the original alone would (test_random cases
* 346, 1184 and 1594: egen rank(), unique and min(), missing after fastata on)
clear
quietly set obs 1000
gen byte x = mod(_n, 3)
gen long id = _n
foreach k in "" "gate egen:rank" "gate isid" "gate duplicates" "gate xtile" "gate pctile" "gate destring" "gate tostring" "orig egen" "status" {
	preserve
	_fx reset
	set sortseed 5
	if "`k'" != "" _fx `k'
	sort x
	mata: st_local("h", strofreal(hash1(invtokens(strofreal(st_data(., "id"), "%9.0f")')), "%12.0f"))
	restore
	if "`k'" == "" local h0 `h'
	else assert "`h'" == "`h0'"
}
di as txt "sort ties ok"

* ---------------------------------------------------------------------------------------------
* after sysdir set PLUS elsewhere and clear all (a replication package's config.do), fastata is
* still on through its runtime directory, which also holds fastata.ado, so fastata status and
* fastata off work. The repository's stata directory is taken off the ado-path first, so that
* the runtime directory is the only place fastata.ado can come from.
* ---------------------------------------------------------------------------------------------
fastata on
quietly adopath - `"$FX_STATA"'
mkdir `"`tmp'other plus"'
sysdir set PLUS `"`tmp'other plus/"'
clear all
quietly findfile fastata.ado
assert `"`r(fn)'"' == `"`rt'fastata.ado"'
capture noisily fastata status
assert _rc == 0
capture noisily fastata off
assert _rc == 0
quietly findfile egen.ado
assert `"`r(fn)'"' == `"`base_egen'"'
sysdir set PLUS `"`plus0'"'
quietly adopath ++ `"$FX_STATA"'
di as txt "PLUS changed and clear all ok"

fastata off
di as result "TEST_FRAMEWORK passed"
