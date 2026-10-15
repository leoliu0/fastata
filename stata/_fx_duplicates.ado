*! version 0.1.0  Leo Liu  15oct2026
*! _fx_duplicates: fastata's duplicates. Until its fast path exists, every call runs the original.
program _fx_duplicates, rclass
	local caller = _caller()
	local rc0 = c(rc)
	version 16
	_fx gate duplicates
	if `fx_ok' local fx_why "not implemented"
	_fx count duplicates fallback `"`fx_why'"'
	_fx orig duplicates
	capture error `rc0'
	version `caller': `fx_prog' `0'
	return add
end
