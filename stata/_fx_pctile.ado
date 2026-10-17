*! version 0.1.0  Leo Liu  15oct2026
*! _fx_pctile: fastata's pctile. Fast path: pctile [float|double] newvar = exp [if] [in]
*! [aw fw pw] [, nquantiles(#) altdef] with the weight a numeric variable and nquantiles() up to
*! 1001 (the plugin's quant command computes the percentiles; see src/xtile.rs). Every other
*! form (genp(), an integer type, ...), and every error condition of pctile.ado, runs the
*! original.
program _fx_pctile
	local caller : display _caller()
	local rc0 = c(rc)
	version 16
	* small data (below 300 observations): the original right away (see _fx gate)
	_fx gate pctile `=c(N) < 300'
	if "`fx_small'" == "1" {
		capture error `rc0'
		version `caller': `fx_prog' `0'
		exit
	}
	if `fx_ok' {
		local fx_done 0
		Fast `0'
		if `fx_done' {
			_fx count pctile fast
			* pctile.ado leaves c(rc) from its capture confirm variable <exp>
			capture confirm variable `fx_exp'
			* verify mode: the original on the snapshot taken by gate; its result is kept
			if "`fx_vpend'" == "1" {
				_fx verify pctile `caller' `rc0' 0 `=c(rc)' "" "" 0 "" `"`0'"'
				if `fx_vrc' exit `fx_vrc'
			}
			exit
		}
	}
	_fx fallback pctile `"`fx_why'"'
	capture error `rc0'
	version `caller': `fx_prog' `0'
end

* Sets fx_done to 1 after creating the variable exactly as pctile.ado does, or leaves the data
* unchanged and sets fx_why.
program Fast
	version 16
	if ustrregexm(`"`0'"', "\[\s*(w|we|wei|weig|weigh|weight)\s*=") {
		c_local fx_why "weight"
		exit
	}
	Parse6 `0'
	if `p_rc' {
		c_local fx_why "syntax"
		exit
	}
	* pctile.ado fills the variable with replace, which promotes integer types
	if !inlist("`p_typ'", "float", "double") {
		c_local fx_why "type"
		exit
	}
	if `"`p_genp'"' != "" {
		c_local fx_why "genp"
		exit
	}
	if (`"`p_wt'"' != "" & "`p_alt'" != "") | `p_nq' < 2 | `p_nq' > _N + 1 {
		c_local fx_why "error"
		exit
	}
	* above 1001, pctile.ado computes the percentiles from p() lists in chunks
	if `p_nq' > 1001 {
		c_local fx_why "nq"
		exit
	}
	local wtype none
	local wv
	if `"`p_wt'"' != "" {
		if !ustrregexm(`"`p_wt'"', "^\[(aweight|fweight|pweight)= ([A-Za-z_][A-Za-z0-9_]*)\]$") {
			c_local fx_why "weight"
			exit
		}
		local wtype = usubstr(ustrregexs(1), 1, 1) + "w"
		local wname = ustrregexs(2)
		capture confirm numeric variable `wname'
		if _rc {
			c_local fx_why "weight"
			exit
		}
		unab wv : `wname'
	}
	* pctile.ado labels the variable "percentiles of <exp>" inside double quotes
	if index(`"`p_exp'"', `"""') {
		c_local fx_why "exp"
		exit
	}
	tempvar touse x
	local xv
	if ustrregexm(`"`p_exp'"', "^[A-Za-z_][A-Za-z0-9_]*$") {
		capture confirm variable `p_exp'
		if !_rc {
			capture confirm numeric variable `p_exp'
			if _rc {
				c_local fx_why "exp"
				exit
			}
			unab xv : `p_exp'
		}
	}
	if "`xv'" == "" {
		capture Gen6 `x' `p_exp'
		if _rc {
			c_local fx_why "exp"
			exit
		}
		local xv `x'
	}
	local hastouse 0
	if `"`p_if'`p_in'"' != "" {
		capture Mark6 `touse' `p_if' `p_in'
		if _rc {
			c_local fx_why "error"
			exit
		}
		local hastouse 1
	}
	local tv = cond(`hastouse', "`touse'", "")
	quietly _fx threads
	_fx_call `xv' `wv' `tv', quant "phase=compute" "threads=`fx_threads'" "kind=pctile" /*
		*/ "nq=`p_nq'" "wtype=`wtype'" "altdef=`=("`p_alt'" != "")'" /*
		*/ "touse=`hastouse'" "float=`=("`p_typ'" == "float")'"
	if `fx_plugrc' {
		c_local fx_why `"plugin error r(`fx_plugrc')"'
		exit
	}
	if `"`fx_fallback'"' != "" {
		c_local fx_why `"`fx_fallback'"'
		exit
	}
	capture drop `touse'
	capture drop `x'
	_fx store `fx_token' `p_typ' `p_var'
	label var `p_var' "percentiles of `p_exp'"
	c_local fx_exp `"`p_exp'"'
	c_local fx_done 1
end

* pctile.ado's parsing, under its version (where local names longer than 7 characters do not
* work). Sets p_rc (0 or 1) and p_var, p_typ, p_exp, p_if, p_in, p_nq, p_alt, p_genp, p_wt.
program Parse6
	version 6.0, missing
	capture _parsewt "aweight fweight pweight" `0'
	if _rc {
		c_local p_rc 1
		exit
	}
	local wt "`s(weight)'"
	local 0 `"`s(newcmd)'"'
	capture syntax newvarname =/exp [if] [in] [, Nquantiles(integer 2) ALTdef Genp(string) ]
	if _rc {
		c_local p_rc 1
		exit
	}
	c_local p_rc 0
	c_local p_var `varlist'
	c_local p_typ `typlist'
	c_local p_exp `"`exp'"'
	c_local p_if `"`if'"'
	c_local p_in `"`in'"'
	c_local p_nq `nquanti'
	c_local p_alt `altdef'
	c_local p_genp `"`genp'"'
	c_local p_wt `"`wt'"'
end

* mark <touse> [if] [in], under pctile.ado's version
program Mark6
	version 6.0, missing
	mark `0'
end

* gen double <x> = <exp>, under pctile.ado's version
program Gen6
	version 6.0, missing
	gettoken x 0 : 0
	quietly gen double `x' = `0'
end
