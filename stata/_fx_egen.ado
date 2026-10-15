*! version 0.1.0  Leo Liu  15oct2026
*! _fx_egen: fastata's egen, called by the egen shim with the by prefix forwarded. Until its fast
*! path exists, every call runs the original.
program _fx_egen, byable(onecall)
	local caller = _caller()
	local rc0 = c(rc)
	version 16
	_fx count egen fallback "not implemented"
	_fx orig egen
	capture error `rc0'
	if _by() {
		version `caller': by `_byvars' `_byrc0': `fx_prog' `0'
	}
	else {
		version `caller': `fx_prog' `0'
	}
end
