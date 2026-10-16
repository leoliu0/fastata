*! version 0.1.0  Leo Liu  15oct2026
*! _fx_call [varlist] [if] [in], <cmd> "key=value" ...: the only program that calls the fastata
*! plugin (a plugin program defined in an ado-file is private to that file). Each key=value
*! token must be quoted: Stata splits unquoted plugin arguments at = | ; * -.
*!
*! Copies to the caller every local the plugin set (the plugin lists them in fx_locals), plus
*!   fx_plugrc   the plugin's return code (0 on success);
*!   fx_errmsg   its error message when fx_plugrc is not 0 (the call runs under capture, so the
*!               plugin prints nothing; the caller decides what a failure means);
*!   fx_fallback the reason when the input needs the original command.
*! Locals of earlier calls are not cleared, except these three. When the plugin cannot be loaded
*! or is not the version below, sets fx_fallback and does not run the command.
program _fx_call
	version 16
	local fx_version 0.1.0
	c_local fx_plugrc 0
	c_local fx_errmsg
	c_local fx_fallback
	local fx_plugver
	capture plugin call _fx_plugin, version
	if _rc {
		c_local fx_fallback "plugin unavailable (r(`=_rc'))"
		exit
	}
	if "`fx_plugver'" != "`fx_version'" {
		c_local fx_fallback "plugin version `fx_plugver' is not `fx_version'"
		exit
	}
	local fx_locals
	capture plugin call _fx_plugin `0'
	local rc = _rc
	foreach name of local fx_locals {
		c_local `name' `"``name''"'
	}
	c_local fx_plugrc `rc'
end

capture program _fx_plugin, plugin using("fastata_0.1.0.plugin")
