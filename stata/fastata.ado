*! version 0.1.0  Leo Liu  15oct2026
*! fastata: makes official Stata data commands fast without changing their syntax or results
*! (egen, isid, duplicates, xtile, pctile, destring, tostring).
*!   fastata enable | disable | on | off | status        (see help fastata)
*! Paths (runtime directory, profile.do files) are handled and printed by _fx's Mata code, so
*! that no path passes through a command line, where it would be expanded as macros.
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
	* undocumented: profile() is the profile.do to use instead of searching for one (tests);
	* on, init is what fastata_init runs at startup
	if inlist("`sub'", "enable", "disable") syntax [, PROFile(string)]
	else if "`sub'" == "on" syntax [, INIT]
	else syntax
	_fxa_`sub' `fx_version' `"`profile'"' `init'
end

* Takes every runtime directory off the ado-path and drops the shims, so that the next call of
* each command loads the original.
program _fxa_deactivate
	_fx pathpos
	foreach p of local fx_pos {
		quietly adopath - `p'
	}
	foreach c in egen isid duplicates xtile pctile destring tostring {
		capture program drop `c'
	}
end

* Rebuilds the runtime directory when _fx rtversion found it missing, incomplete or built from
* other installed files (build 1). The build runs from the installed files: the runtime
* directory is first taken off the ado-path, and the runtime programs it loaded are dropped
* (with their Mata functions, which belong to their files).
program _fxa_build
	args ver build
	if !`build' exit
	_fxa_deactivate
	foreach p in _fx _fx_call _fx_egen _fx_isid _fx_duplicates _fx_xtile _fx_pctile	///
		_fx_destring _fx_tostring {
		capture program drop `p'
	}
	_fx runtime "" `ver'
end

* enable: build when needed, write the startup lines (Mata prints the outcome), turn on.
program _fxa_enable
	args ver profile
	_fx rtversion
	_fxa_build `ver' `fx_build'
	_fx profile_write 1 `"`profile'"'
	if `fx_rc' exit `fx_rc'
	_fx runtime "" `ver' 0 1
end

* disable: flag and startup lines (Mata prints the outcome), then off. The runtime directory
* stays for the sessions that use it.
program _fxa_disable
	args ver profile
	_fx profile_write 0 `"`profile'"'
	if `fx_rc' exit `fx_rc'
	_fxa_deactivate
end

program _fxa_on
	args ver profile init
	_fx rtversion
	* at startup (fastata_init): nothing after fastata disable
	if "`init'" != "" & `fx_disabled' exit
	_fxa_build `ver' `fx_build'
	_fx runtime "" `ver' 0 1
	di as txt "fastata: on for this session"
end

program _fxa_off
	_fxa_deactivate
	di as txt "fastata: off for this session"
end

program _fxa_status
	args ver
	_fx status show `ver'
end
