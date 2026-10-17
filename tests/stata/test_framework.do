* test_framework.do -- fastata enable, disable, on, off and status; the profile.do search and
* block handling; rebuilding an outdated runtime directory; ado-path changes (PLUS with spaces,
* PLUS changed after activation); the caller version and the by prefix reaching the original;
* an unverified original; the mode surviving off/on; clear all and discard.
* No real profile.do is touched: enable and disable search for one only when the search (with
* PERSONAL pointed at a scratch folder) finds none; otherwise they get profile(<scratch file>).
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

* disable removes the block (keeping the user's line) and the runtime directory
fx_out fastata disable `popt'
fx_has `"fastata: disabled; removed the startup lines from `prof'"' disable
fx_nblock `"`prof'"' 0
mata: st_local("mine", strofreal(cat(st_local("prof")) == "* my line"))
assert `mine'
mata: st_local("rtgone", strofreal(!direxists(st_local("rt"))))
assert `rtgone'
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
* an outdated runtime directory is rebuilt by fastata on: stale renamed originals and plugins of
* other versions go
* ---------------------------------------------------------------------------------------------
fastata on
fastata off
mata: unlink(st_local("rt") + "fastata_runtime.txt"); fh = fopen(st_local("rt") + "fastata_runtime.txt", "w"); fput(fh, "0.0.9"); fclose(fh)
copy `"`rt'fastata_0.1.0.plugin"' `"`rt'fastata_0.0.9.plugin"'
copy `"`rt'egen.ado"' `"`rt'_fxo_00000000_egen.ado"'
fx_out fastata status
fx_has "built by version 0.0.9" status outdated
fastata on
_fx rtversion `"`rt'"'
assert "`fx_have'" == "0.1.0"
foreach f in fastata_0.0.9.plugin _fxo_00000000_egen.ado {
	capture confirm file `"`rt'`f'"'
	assert _rc
}
confirm file `"`rt'fastata_0.1.0.plugin"'
di as txt "rebuild ok"

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

fastata off
di as result "TEST_FRAMEWORK passed"
