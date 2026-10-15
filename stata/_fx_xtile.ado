*! version 0.1.0  Leo Liu  15oct2026
*! _fx_xtile: fastata's xtile. Fast path: xtile newvar = exp [if] [in] [aw fw pw] [, nquantiles(#)
*! altdef] with the weight a numeric variable and nquantiles() a plain integer up to 1001 (the
*! plugin's quant command computes the percentiles and categories; see src/xtile.rs). Every
*! other form, and every error condition of xtile.ado, runs the original.
program _fx_xtile
	local caller = _caller()
	local rc0 = c(rc)
	version 16
	_fx gate xtile
	if `fx_ok' {
		local fx_done 0
		Fast `0'
		if `fx_done' {
			_fx count xtile fast
			* xtile.ado leaves c(rc) at 0 (from pctile's capture confirm variable)
			capture error 0
			exit
		}
	}
	_fx count xtile fallback `"`fx_why'"'
	_fx orig xtile
	capture error `rc0'
	version `caller': `fx_prog' `0'
end

* Sets fx_done to 1 after creating the variable exactly as xtile.ado does, or leaves the data
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
	if `"`p_cut'"' != "" {
		c_local fx_why "cutpoints"
		exit
	}
	if `"`p_wt'"' != "" & "`p_alt'" != "" {
		c_local fx_why "error"
		exit
	}
	if `"`p_nq'"' == "" {
		local nq 2
	}
	else {
		if !ustrregexm(`"`p_nq'"', "^[1-9][0-9]{0,5}$") {
			c_local fx_why "nq"
			exit
		}
		local nq `p_nq'
	}
	if `nq' < 2 {
		c_local fx_why "error"
		exit
	}
	* above 1001, pctile.ado computes the percentiles from p() lists in chunks
	if `nq' > 1001 {
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
	* xtile.ado labels the variable "<nq> quantiles of <exp>" inside double quotes
	if index(`"`p_exp'"', `"""') {
		c_local fx_why "exp"
		exit
	}
	local xv
	if ustrregexm(`"`p_exp'"', "^[A-Za-z_][A-Za-z0-9_]*$") {
		capture confirm numeric variable `p_exp'
		if !_rc {
			unab xv : `p_exp'
		}
	}
	tempvar touse x
	local hastouse 0
	if `"`p_if'`p_in'"' != "" | "`xv'" == "" {
		capture Mark6 `touse' `p_wt' `p_if' `p_in'
		if _rc {
			c_local fx_why "error"
			exit
		}
		local hastouse 1
	}
	if "`xv'" == "" {
		capture Gen6 `x' `touse' `p_exp'
		if _rc {
			c_local fx_why "exp"
			exit
		}
		local xv `x'
	}
	local tv = cond(`hastouse', "`touse'", "")
	quietly _fx threads
	_fx_call `xv' `wv' `tv', quant "phase=compute" "threads=`fx_threads'" "kind=xtile" /*
		*/ "nq=`nq'" "wtype=`wtype'" "altdef=`=("`p_alt'" != "")'" "touse=`hastouse'"
	if `fx_plugrc' {
		c_local fx_why `"plugin error r(`fx_plugrc')"'
		exit
	}
	if `"`fx_fallback'"' != "" {
		c_local fx_why `"`fx_fallback'"'
		exit
	}
	local type = cond(`fx_max' <= 100, "byte", cond(`fx_max' <= 32740, "int", "long"))
	capture drop `touse'
	capture drop `x'
	_fx store `fx_token' `type' `p_var'
	label var `p_var' "`nq' quantiles of `p_exp'"
	c_local fx_done 1
end

* xtile.ado's parsing, under its version (where local names longer than 7 characters do not
* work). Sets p_rc (0 or 1) and p_var, p_exp, p_if, p_in, p_nq, p_cut, p_alt, p_wt.
program Parse6
	version 6.0, missing
	capture _parsewt "aweight fweight pweight" `0'
	if _rc {
		c_local p_rc 1
		exit
	}
	local 0  "`s(newcmd)'"
	local wt "`s(weight)'"
	capture syntax newvarname =/exp [if] [in] [, Nquantiles(string) Cutpoints(string) ALTdef ]
	if _rc {
		c_local p_rc 1
		exit
	}
	c_local p_rc 0
	c_local p_var `varlist'
	c_local p_exp `"`exp'"'
	c_local p_if `"`if'"'
	c_local p_in `"`in'"'
	c_local p_nq `"`nquanti'"'
	c_local p_cut `"`cutpoin'"'
	c_local p_alt `altdef'
	c_local p_wt `"`wt'"'
end

* mark <touse> [weight] [if] [in], under xtile.ado's version
program Mark6
	version 6.0, missing
	mark `0'
end

* gen double <x> = <exp> if <touse>, under xtile.ado's version
program Gen6
	version 6.0, missing
	gettoken x 0 : 0
	gettoken t 0 : 0
	quietly gen double `x' = `0' if `t'
end
