*! version 0.1.0  Leo Liu  15oct2026
*! _fx_isid: fastata's isid. Until its fast path exists, every call runs the original.
program _fx_isid
	local caller = _caller()
	local rc0 = c(rc)
	version 16
	_fx gate isid
	if `fx_ok' local fx_why "not implemented"
	_fx count isid fallback `"`fx_why'"'
	_fx orig isid
	capture error `rc0'
	version `caller': `fx_prog' `0'
end
