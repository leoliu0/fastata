*! version 0.1.0  Leo Liu  15oct2026
*! fastata: makes official Stata data commands fast without changing their syntax or results
*! (egen, isid, duplicates, xtile, pctile, destring, tostring).
*!   fastata enable | disable | on | off | status        (see help fastata)
program fastata
	if c(stata_version) < 16 {
		di as err "fastata requires Stata 16 or newer"
		exit 9
	}
	version 16
	local fx_version 0.1.0
	gettoken sub 0 : 0, parse(" ,")
	if `"`sub'"' == "" local sub status
	if !inlist(`"`sub'"', "enable", "disable", "on", "off", "status") {
		di as err `"fastata: unknown subcommand {bf:`sub'}; use enable, disable, on, off or status"'
		exit 198
	}
	* profile() is undocumented: the profile.do to use instead of searching for one (tests)
	if inlist("`sub'", "enable", "disable") syntax [, PROFile(string)]
	else syntax
	_fx rtpath
	_fxa_`sub' `fx_version' `"`fx_rt'"' `"`profile'"'
end

* Drops the shims, so that the next call of each command loads whichever file is first on the
* ado-path (a shim when fastata is on, the original when it is off).
program _fxa_dropshims
	foreach c in egen isid duplicates xtile pctile destring tostring {
		capture program drop `c'
	}
end

* Takes runtime directory rt, and any other runtime directory (one left from an earlier PLUS),
* off the ado-path and drops the shims.
program _fxa_deactivate
	args rt
	_fx pathpos `"`rt'"'
	foreach p of local fx_pos {
		quietly adopath - `p'
	}
	_fxa_dropshims
end

* Builds runtime directory rt unless it is complete for version ver. The build runs from the
* installed files: an old runtime directory is first taken off the ado-path, and the runtime
* programs it loaded are dropped (with their Mata functions, which belong to their files).
program _fxa_build
	args ver rt
	_fx rtversion `"`rt'"'
	if "`fx_have'" == "`ver'" {
		capture confirm file `"`rt'fastata_`ver'.plugin"'
		if !_rc exit
	}
	_fxa_deactivate `"`rt'"'
	foreach p in _fx _fx_call _fx_egen _fx_isid _fx_duplicates _fx_xtile _fx_pctile	///
		_fx_destring _fx_tostring {
		capture program drop `p'
	}
	_fx runtime `"`rt'"' `ver'
	_fx reset
end

* Makes runtime directory rt the only one on the ado-path, in first place; the shims load on
* the next call.
program _fxa_activate
	args rt
	_fxa_deactivate `"`rt'"'
	quietly adopath ++ `"`rt'"'
	_fx reset
end

* Locals envpath and home for the profile.do search.
program _fxa_searchdirs
	local envpath : env PATH
	local home
	if c(os) == "Windows" local home : env USERPROFILE
	else if c(os) == "MacOSX" local home "~/Documents/Stata"
	c_local envpath `"`envpath'"'
	c_local home `"`home'"'
end

program _fxa_enable
	args ver rt profile
	if `"`profile'"' == "" {
		_fxa_searchdirs
		_fx profile_first `"`envpath'"' `"`home'"' `"`rt'"'
		local profile `"`fx_profile'"'
		if `"`profile'"' == "" {
			_fx mkdirp `"`c(sysdir_personal)'"'
			local profile `"`c(sysdir_personal)'profile.do"'
		}
	}
	_fxa_build `ver' `"`rt'"'
	_fx profile_write `"`profile'"' 1
	if `fx_rc' {
		di as err `"fastata: could not write `profile'. Add these lines to a profile.do by hand:"'
		_fx block
		exit 603
	}
	_fxa_activate `"`rt'"'
	di as txt `"fastata: enabled; Stata loads it at startup through `profile'"'
	capture confirm file `"`c(pwd)'/profile.do"'
	if !_rc {
		mata: st_local("same", strofreal(pathjoin(c("pwd"), "profile.do") == st_local("profile")))
		if !`same' {
			di as txt `"note: Stata sessions started in `c(pwd)' run the profile.do there instead,"'
			di as txt "      so fastata is inactive in them unless {bf:capture fastata_init} is added to it"
		}
	}
end

program _fxa_disable
	args ver rt profile
	if `"`profile'"' != "" {
		_fx has_block `"`profile'"'
		local fx_profiles
		if `fx_hasblock' local fx_profiles `"`"`profile'"'"'
	}
	else {
		_fxa_searchdirs
		_fx profile_with_block `"`envpath'"' `"`home'"' `"`rt'"'
	}
	local done
	foreach f of local fx_profiles {
		_fx profile_write `"`f'"' 0
		if `fx_rc' {
			di as err `"fastata: could not write `f'; remove the fastata lines from it by hand"'
			exit 603
		}
		if `"`done'"' != "" local done `"`done', "'
		local done `"`done'`f'"'
	}
	_fxa_deactivate `"`rt'"'
	_fx rmruntime `"`rt'"'
	if `"`done'"' == "" di as txt "fastata: disabled (no profile.do had the fastata startup lines)"
	else di as txt `"fastata: disabled; removed the startup lines from `done'"'
end

program _fxa_on
	args ver rt
	_fxa_build `ver' `"`rt'"'
	_fxa_activate `"`rt'"'
	di as txt "fastata: on for this session"
end

program _fxa_off
	args ver rt
	_fxa_deactivate `"`rt'"'
	di as txt "fastata: off for this session"
end

program _fxa_status
	args ver rt
	_fx onpath `"`rt'"'
	_fx rtversion `"`rt'"'
	_fxa_searchdirs
	_fx profile_with_block `"`envpath'"' `"`home'"' `"`rt'"'
	_fx status
	if c(MP) local threads = c(processors)
	else local threads all logical CPUs
	di as txt "fastata " as res "`ver'"
	di as txt "  on now:      " as res cond(`"`fx_active'"' != "", "yes", "no")
	if `"`fx_profiles'"' == "" di as txt "  at startup:  " as res "no"
	else {
		foreach f of local fx_profiles {
			di as txt "  at startup:  " as res `"yes, through `f'"'
		}
	}
	if "`fx_have'" == "" local note " (not built)"
	else if "`fx_have'" != "`ver'" local note " (built by version `fx_have'; fastata on rebuilds it)"
	di as txt "  runtime:     " as res `"`rt'"' as txt "`note'"
	if `"`fx_active'"' != "" & !`fx_onpath' {
		di as txt "  in use:      " as res `"`fx_active'"' as txt " (built for an earlier PLUS)"
	}
	di as txt "  threads:     " as res "`threads'"
	di
	di as txt "  {ralign 10:command}  {lalign 9:verified}  {ralign 8:fast}  {ralign 8:fallback}  last fallback reason"
	foreach c in egen isid duplicates xtile pctile destring tostring {
		di as txt "  {ralign 10:`c'}  " as res "{lalign 9:`=word(`"`fx_ver_`c''"', 1)'}"	///
			"  {ralign 8:`fx_nfast_`c''}  {ralign 8:`fx_nfb_`c''}  " as txt `"`fx_last_`c''"'
	}
	di
	di as txt "  originals:"
	foreach c in egen isid duplicates xtile pctile destring tostring {
		if `"`fx_orig_`c''"' == "" local where "(not found; not replaced)"
		else local where `"`fx_orig_`c''"'
		di as txt "  {ralign 10:`c'}  " as res `"`where'"'
		if word(`"`fx_ver_`c''"', 1) != "yes" {
			di as txt "  {space 10}  not verified: " as res `"`fx_ver_`c''"'
		}
	}
end
