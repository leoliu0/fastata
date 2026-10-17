*! version 0.1.1  Leo Liu  17oct2026
*! _fx_call [varlist] [if] [in], <cmd> "key=value" ...: the only program that calls the fastata
*! plugin (a plugin program defined in an ado-file is private to that file). Each key=value
*! token must be quoted: Stata splits unquoted plugin arguments at = | ; * -.
*!
*! Copies to the caller every local the plugin set (the plugin lists them in fx_locals), plus
*!   fx_plugrc   the plugin's return code (0 on success);
*!   fx_errmsg   its error message when fx_plugrc is not 0 (the call runs under capture, so the
*!               plugin prints nothing; the caller decides what a failure means);
*!   fx_fallback the reason when the input needs the original command.
*! Locals of earlier calls are not cleared, except these three. Sets fx_fallback, runs no plugin
*! command and copies nothing when the dataset has more than 2,147,483,647 observations (the
*! plugin interface passes only the low 32 bits of _N), and copies nothing when the plugin cannot
*! be loaded or is not the version below: every plugin command sets local fx_plugver first, so
*! the version is checked on the call itself, without a separate call. Break (return code 1)
*! exits 1.
program _fx_call
	version 16
	local fx_version 0.1.1
	c_local fx_plugrc 0
	c_local fx_errmsg
	if c(N) > 2147483647 {
		c_local fx_fallback "over 2147483647 observations"
		exit
	}
	c_local fx_fallback
	local fx_plugver
	local fx_locals
	capture plugin call _fx_plugin `0'
	local rc = _rc
	if `rc' == 1 {
		* Break: the fast path stops; a verify snapshot is not needed
		capture _fx vabort
		exit 1
	}
	if "`fx_plugver'" != "`fx_version'" {
		if "`fx_plugver'" != "" c_local fx_fallback "plugin version `fx_plugver' is not `fx_version'"
		else if `rc' c_local fx_fallback "plugin unavailable (r(`rc'))"
		else c_local fx_fallback "plugin version unknown (not `fx_version')"
		exit
	}
	foreach name of local fx_locals {
		c_local `name' `"``name''"'
	}
	c_local fx_plugrc `rc'
end

capture program _fx_plugin, plugin using("fastata_0.1.1.plugin")
