*! version 0.1.0  Leo Liu  15oct2026
*! _fx_isid: fastata's isid. Fast path: isid varlist [, sort missok] (not the using form) when
*! no string key value starts or ends with a blank or a non-ASCII byte. The plugin counts the
*! observations with a missing key and the distinct key tuples; the two errors of the original
*! (missing key, key not unique) are raised here with the original's messages. Everything else
*! runs the original.
program _fx_isid
	local caller = _caller()
	local rc0 = c(rc)
	version 16
	local cmdline `"`0'"'
	_fx gate isid
	if `fx_ok' {
		local fx_why
		foreach word of local 0 {
			if `"`word'"' == "using" local fx_why using
		}
		if "`fx_why'" == "" {
			capture syntax varlist [, Sort Missok]
			if _rc local fx_why syntax
		}
		if "`fx_why'" == "" {
			_fx threads
			local mok = ("`missok'" != "")
			_fx_call `varlist', isid "missok=`mok'" "threads=`fx_threads'"
			if `fx_plugrc' local fx_why "plugin r(`fx_plugrc')"
			else if `"`fx_fallback'"' != "" local fx_why `"`fx_fallback'"'
		}
		if "`fx_why'" == "" {
			_fx count isid fast
			local err
			if !`mok' & `fx_nmiss' > 0 local err missing
			else if `fx_nuniq' < _N local err unique
			else if "`sort'" != "" {
				local list : sortedby
				local sorted 1
				local i 1
				foreach name of local varlist {
					if "`name'" != "`: word `i' of `list''" {
						local sorted 0
						continue, break
					}
					local ++i
				}
				if `sorted' di as txt `"(data already sorted by {bf:`varlist'})"'
				else {
					sort `varlist'
					di as txt `"(data now sorted by {bf:`varlist'})"'
				}
			}
			local rc = cond("`err'" != "", 459, 0)
			* verify mode: the original on the snapshot taken by gate; its result is kept
			if "`fx_vpend'" == "1" {
				_fx verify isid `caller' `rc0' `rc' "" "" "" 0 "" `"`cmdline'"'
				local rc `fx_vrc'
			}
			if "`err'" == "missing" {
				_format_list `varlist', plural(variable)
				di as err `"`s(msg)' should never be missing"'
			}
			else if "`err'" == "unique" {
				_format_list `varlist', plural(variable)
				local does = cond(`s(k)'==1, "does", "do")
				di as err `"`s(msg)' `does' not uniquely identify the observations"'
			}
			if `rc' exit `rc'
			exit
		}
	}
	_fx count isid fallback `"`fx_why'"'
	_fx orig isid
	capture error `rc0'
	version `caller': `fx_prog' `0'
end
