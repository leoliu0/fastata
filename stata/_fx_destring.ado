*! version 0.1.0  Leo Liu  15oct2026
*! _fx_destring: fastata's destring. Until its fast path exists, every call runs the original.
program _fx_destring
	local caller = _caller()
	local rc0 = c(rc)
	version 16
	_fx gate destring
	if `fx_ok' local fx_why "not implemented"
	_fx count destring fallback `"`fx_why'"'
	_fx orig destring
	capture error `rc0'
	version `caller': `fx_prog' `0'
end
