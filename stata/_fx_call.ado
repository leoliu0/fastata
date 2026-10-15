*! version 0.1.0  Leo Liu  15oct2026
*! _fx_call [varlist] [if] [in], <cmd> "key=value" ...: the only program that calls the fastata
*! plugin (a plugin program defined in an ado-file is private to that file). Each key=value
*! token must be quoted: Stata splits unquoted plugin arguments at = | ; * -.
*!
*! Copies the plugin's result locals to the caller, plus
*!   fx_plugrc   the plugin's return code (0 on success; 1 means Break),
*!   fx_errmsg   its error message when fx_plugrc is not 0.
*! The plugin call runs under capture, so the plugin prints nothing; the caller decides what a
*! failure means (a compute phase falls back to the original, a store phase is an error).
*! When the plugin cannot be loaded or its version differs from fx_version below, sets
*! fx_fallback and does not call it.
program _fx_call
	version 16
	local fx_version 0.1.0
	local forward fx_plugver fx_fallback fx_errmsg fx_token fx_n fx_nmiss fx_min fx_max
	local forward `forward' fx_allint fx_type fx_strlen fx_ngroups fx_nuniq fx_ndrop fx_table
	local forward `forward' fx_msgs
	foreach name of local forward {
		local `name'
		c_local `name'
	}
	c_local fx_plugrc 0
	capture plugin call _fx_plugin, version
	if _rc {
		c_local fx_fallback "plugin unavailable (r(`=_rc'))"
		exit
	}
	if "`fx_plugver'" != "`fx_version'" {
		c_local fx_fallback "plugin version `fx_plugver' is not `fx_version'"
		exit
	}
	local fx_plugver
	capture plugin call _fx_plugin `0'
	local rc = _rc
	foreach name of local forward {
		c_local `name' `"``name''"'
	}
	c_local fx_plugrc `rc'
end

capture program _fx_plugin, plugin using("fastata_0.1.0.plugin")
