*! version 0.1.0  Leo Liu  15oct2026
*! _fx_egen: fastata's egen, called by the egen shim with the by prefix forwarded. The fast path
*! (Fast below) covers the 21 official functions listed in help fastata for the inputs it has
*! been tested on; every other call, and every input it is not sure about, runs the original
*! egen. Protocol with the plugin: src/egen/spec.rs.
program _fx_egen, byable(onecall)
	local caller = _caller()
	local rc0 = c(rc)
	version 16
	local byv
	if _by() local byv `_byvars'
	local fx_done 0
	local fx_reason
	Fast `caller' `"`byv'"' `0'
	if "`fx_done'" == "1" {
		_fx count egen fast
		capture error 0
		exit
	}
	_fx count egen fallback `"`fx_reason'"'
	_fx orig egen
	capture error `rc0'
	if _by() {
		version `caller': by `_byvars' `_byrc0': `fx_prog' `0'
	}
	else {
		version `caller': `fx_prog' `0'
	}
end

* Fast <caller> "<by variables>" <egen arguments>
* Runs the fast path and sets c_local fx_done 1, or leaves the data untouched and sets c_local
* fx_reason (the fallback reason). Every check mirrors what the original egen.ado and its
* _g<fcn>.ado would do with the same text.
program Fast
	gettoken caller 0 : 0
	gettoken byv 0 : 0
	if c(N) == 0 {
		c_local fx_reason "no observations"
		exit
	}

	* ---- egen.ado's tokenizer
	gettoken type 0 : 0, parse(" =(")
	gettoken name 0 : 0, parse(" =(")
	if `"`name'"' == "=" {
		local name `"`type'"'
		local type : set type
	}
	else {
		gettoken eqsign 0 : 0, parse(" =(")
		if `"`eqsign'"' != "=" {
			c_local fx_reason syntax
			exit
		}
	}
	capture confirm new variable `name'
	if _rc {
		c_local fx_reason name
		exit
	}
	gettoken fcn 0 : 0, parse(" =(")
	gettoken args 0 : 0, parse(" ,") match(par)
	if `"`par'"' != "(" {
		c_local fx_reason syntax
		exit
	}
	local fns group tag total sum mean max min count median pctile iqr sd std rank
	local rowfns rowtotal rowmean rowmax rowmin rowsd rowmiss rownonmiss
	local fns `fns' `rowfns'
	if !`: list fcn in fns' {
		c_local fx_reason function
		exit
	}
	if `"`args'"' == "_all" | `"`args'"' == "*" {
		c_local fx_reason allvars
		exit
	}
	if !inlist(`"`type'"', "byte", "int", "long", "float", "double") {
		if substr(`"`type'"', 1, 3) == "str" c_local fx_reason strtype
		else c_local fx_reason type
		exit
	}
	capture version 6: syntax [if] [in] [, *]
	if _rc {
		c_local fx_reason syntax
		exit
	}

	_fx gate egen:`fcn'
	if !`fx_ok' {
		c_local fx_reason `"`fx_why'"'
		exit
	}

	* ---- text the fast path does not evaluate like the original
	* _n, _N, subscripts and time-series operators: the original evaluates them in its own
	* (sorted) order. Other names starting with _ and wildcards starting with *, ? or ~ could
	* also match the temporary variable the original's sortpreserve adds. Random numbers, r(),
	* s() and sum() depend on when and in which order the original evaluates them.
	local txt `"`args' `if' `options'"'
	if ustrregexm(`"`txt'"', "\[") | ustrregexm(`"`txt'"', "(^|[^A-Za-z0-9_])[LFDSlfds][0-9]*[.(]") {
		c_local fx_reason subscript
		exit
	}
	if ustrregexm(`"`txt'"', "(^|[^A-Za-z0-9_])_") {
		c_local fx_reason underscore
		exit
	}
	local wtxt `"`options'"'
	if inlist("`fcn'", "group", "tag") | `: list fcn in rowfns' local wtxt `"`args' `options'"'
	if ustrregexm(`"`wtxt'"', "(^|[\s(,])[*?~]") {
		c_local fx_reason wildcard
		exit
	}
	local rfn runiform|rnormal|rbeta|rbinomial|rcauchy|rchi2|rexponential|rgamma|rhypergeometric
	local rfn `rfn'|rigaussian|rlaplace|rlogistic|rnbinomial|rpoisson|rt|rweibull|rweibullph
	local rfn `rfn'|runiformint|rdiscrete|uniform|uniform0|r|s|sum
	if ustrregexm(`"`txt'"', "(^|[^A-Za-z0-9_])(`rfn')\s*\(") {
		c_local fx_reason "state"
		exit
	}
	if `"`byv'"' != "" {
		if ustrregexm(`"`options'"', "(^|[^A-Za-z0-9_])[bB][yY]\s*\(") {
			c_local fx_reason "by twice"
			exit
		}
		if `"`in'"' != "" {
			c_local fx_reason "by in"
			exit
		}
	}

	* ---- the call the original makes, parsed as the original _g<fcn>.ado parses it
	local cma
	local byopt
	if `"`byv'"' != "" {
		local byopt "by(`byv')"
		local cma ","
	}
	else if `"`options'"' != "" local cma ","
	tempname dum
	local egif `"`if'"'
	local egin `"`in'"'
	local 0 `"`type' `dum' = (`args') `if' `in' `cma' `byopt' `options'"'
	local isrow : list fcn in rowfns
	local by
	local missing
	local field
	local track
	if "`fcn'" == "group" {
		gettoken t 0 : 0
		gettoken t 0 : 0
		gettoken t 0 : 0
		capture version 16.1: syntax [varlist (default=none)] [if] [in] [, Missing BY(string) *]
	}
	else if "`fcn'" == "tag" {
		gettoken t 0 : 0
		gettoken t 0 : 0
		gettoken t 0 : 0
		capture version 6: syntax varlist [if] [in] [, Missing BY(string) *]
	}
	else if `isrow' {
		gettoken t 0 : 0
		gettoken t 0 : 0
		gettoken t 0 : 0
		if "`fcn'" == "rowtotal" capture version 6: syntax varlist [if] [in] [, BY(string) Missing *]
		else if "`fcn'" == "rownonmiss" capture version 6: syntax varlist [if] [in] [, Strok BY(string) *]
		else if "`fcn'" == "rowsd" capture version 6: syntax varlist(min=2) [if] [in] [, BY(string) *]
		else capture version 6: syntax varlist [if] [in] [, BY(string) *]
	}
	else if "`fcn'" == "count" {
		gettoken t 0 : 0
		gettoken t 0 : 0
		gettoken t 0 : 0
		capture version 16.1: syntax anything [if/] [in] [, BY(varlist) *]
		local exp `"`anything'"'
	}
	else if inlist("`fcn'", "total", "sum") {
		capture version 16.1: syntax newvarname =/exp [if/] [in] [, BY(varlist) Missing *]
	}
	else if inlist("`fcn'", "mean", "sd") {
		capture version 16.1: syntax newvarname =/exp [if/] [in] [, BY(varlist) *]
	}
	else if inlist("`fcn'", "max", "min") {
		capture version 16.1: syntax newvarname =/exp [if/] [in] [, BY(varlist) MISSing *]
	}
	else if inlist("`fcn'", "median", "iqr") {
		capture version 16.1: syntax newvarname =/exp [if] [in] [, BY(varlist) AUTOTYPE *]
	}
	else if "`fcn'" == "pctile" {
		capture version 16.1: syntax newvarname =/exp [if] [in] [, BY(varlist) P(real 50) AUTOTYPE *]
	}
	else if "`fcn'" == "std" {
		capture version 16.1: syntax newvarname =/exp [if/] [in] [, Mean(real 0) Sd(numlist max=1 >0) STd(numlist max=1 >0) BY(varlist) *]
	}
	else if "`fcn'" == "rank" {
		capture version 16.1: syntax newvarname =/exp [if] [in] [, BY(varlist) Field Track Unique Suffix(string) *]
	}
	if _rc {
		c_local fx_reason syntax
		exit
	}
	if `"`options'"' != "" | "`autotype'" != "" | "`unique'" != "" | `"`suffix'"' != "" {
		c_local fx_reason option
		exit
	}
	if "`field'" != "" & "`track'" != "" {
		c_local fx_reason option
		exit
	}
	if inlist("`fcn'", "group", "tag") | `isrow' {
		if `"`by'"' != "" {
			c_local fx_reason by
			exit
		}
	}
	if "`fcn'" == "group" & "`varlist'" == "" {
		c_local fx_reason syntax
		exit
	}
	if "`fcn'" == "group" & inlist("`type'", "byte", "int", "long") & `caller' <= 16.1 {
		c_local fx_reason caller
		exit
	}
	if "`fcn'" == "pctile" {
		if `p' <= 0 | `p' >= 100 {
			c_local fx_reason option
			exit
		}
	}
	if "`fcn'" == "std" {
		if "`sd'" != "" & "`std'" != "" {
			c_local fx_reason option
			exit
		}
		if "`sd'" == "" & "`std'" != "" local sd `std'
		if "`sd'" == "" local sd 1
	}
	if inlist("`fcn'", "rank", "std") & strpos(`"`exp'"', `"""') {
		c_local fx_reason quote
		exit
	}
	if inlist("`fcn'", "max", "min") & "`missing'" != "" & `"`egif'"' != "" & `"`egin'"' == "" {
		c_local fx_reason "if missing"
		exit
	}

	* ---- inputs: keys, values, sample
	local keys
	local vals
	local extra
	local cntflag 0
	if inlist("`fcn'", "group", "tag") {
		local keys `varlist'
	}
	else if `isrow' {
		foreach v of local varlist {
			capture confirm numeric variable `v'
			if _rc & !(inlist("`fcn'", "rowmiss", "rownonmiss") & ("`fcn'" == "rowmiss" | "`strok'" != "")) {
				c_local fx_reason string
				exit
			}
		}
		local vals `varlist'
	}
	else {
		local keys `by'
		* Where the original reads a variable directly (_expression_to_variable: up to 10
		* outer parentheses stripped, then unab) and where it evaluates the expression.
		local unabpath 0
		if inlist("`fcn'", "total", "sum", "mean", "sd", "std") & "`by'" == "" local unabpath 1
		if inlist("`fcn'", "max", "min") & "`by'" == "" & "`missing'" == "" local unabpath 1
		if inlist("`fcn'", "median", "pctile", "iqr", "rank") & `"`egif'`egin'"' == "" local unabpath 1
		local e `"`exp'"'
		gettoken x y : e, match(pp)
		forvalues i = 1/10 {
			if "`pp'" == "(" & ustrtrim(`"`y'"') == "" {
				local e : copy local x
				gettoken x y : e, match(pp)
			}
			else continue, break
		}
		local simple = ustrregexm(`"`e'"', "^\s*[A-Za-z][A-Za-z0-9_]*\s*$")
		local xv
		if "`fcn'" == "count" {
			if `simple' {
				capture unab xv : `e', max(1)
				if _rc local xv
			}
			if "`xv'" == "" {
				tempvar xt
				capture quietly gen byte `xt' = !missing(`exp')
				if _rc {
					c_local fx_reason exp
					exit
				}
				local xv `xt'
				local cntflag 1
			}
		}
		else {
			capture unab xv : `e', max(1)
			if !_rc {
				if !`unabpath' & !`simple' {
					c_local fx_reason exp
					exit
				}
				capture confirm numeric variable `xv'
				if _rc {
					c_local fx_reason exp
					exit
				}
			}
			else {
				tempvar xt
				capture quietly gen double `xt' = (`e')
				if _rc {
					c_local fx_reason exp
					exit
				}
				local xv `xt'
			}
		}
		local vals `xv'
		if "`fcn'" == "pctile" {
			local h : di %21x `p'
			local extra `"`extra' "p=`h'""'
		}
		if "`fcn'" == "std" {
			local h : di %21x `mean'
			local extra `"`extra' "mean=`h'""'
			local h : di %21x `sd'
			local extra `"`extra' "sd=`h'""'
		}
		if "`fcn'" == "rank" {
			local rk default
			if "`field'" != "" local rk field
			if "`track'" != "" local rk track
			local extra `"`extra' "rank=`rk'""'
		}
	}
	local tu
	if `"`egif'`egin'"' != "" {
		tempvar touse
		capture mark `touse' `egif' `egin'
		if _rc {
			c_local fx_reason if
			exit
		}
		local tu `touse'
	}

	* ---- compute (plugin), then the output under its final name
	local nk : list sizeof keys
	local nv : list sizeof vals
	local sorted = `"`byv'"' != ""
	local hasmiss = "`missing'" != ""
	_fx threads
	_fx_call `keys' `vals' `tu', egen "phase=compute" "threads=`fx_threads'" "fcn=`fcn'" "type=`type'" "nkeys=`nk'" "sorted=`sorted'" "nvals=`nv'" "touse=`=`"`tu'"' != ""'" "missing=`hasmiss'" "cntflag=`cntflag'" `extra'
	if `fx_plugrc' {
		c_local fx_reason "plugin r(`fx_plugrc')"
		exit
	}
	if `"`fx_fallback'"' != "" {
		c_local fx_reason `"`fx_fallback'"'
		exit
	}
	local otype `type'
	if "`fcn'" == "tag" local otype byte
	_fx store `fx_token' `otype' `name'

	* ---- messages, labels and notes, as the original
	if inlist("`fcn'", "median", "pctile", "iqr") & "`by'" == "" & "`fx_n'" == "0" {
		di as err "no observations"
	}
	if "`fcn'" != "tag" & `fx_nmiss' > 0 {
		local s = cond(`fx_nmiss' > 1, "s", "")
		local N : di %11.0fc `fx_nmiss'
		local N `N'
		di in bl "(`N' missing value`s' generated)"
	}
	if "`fcn'" == "group" {
		local varlist `varlist'
		if udstrlen("group(`varlist')") > 80 {
			note `name' : group(`varlist')
			label var `name' "see notes"
		}
		else label var `name' "group(`varlist')"
	}
	else if "`fcn'" == "tag" {
		if length("tag(`varlist')") > 80 {
			note `name' : tag(`varlist')
		}
		label var `name' "tag(`varlist')"
	}
	else if "`fcn'" == "rank" {
		local space
		if "`field'`track'" != "" local space " "
		local by2
		if "`by'" != "" local by2 = `"by `by'"'
		label var `name' "`field'`track'`space'rank of `exp' `by2'"
	}
	else if "`fcn'" == "std" {
		gettoken newexp empty : exp, match(pp)
		if "`pp'" == "(" & ustrtrim(`"`empty'"') == "" {
			local exp = ustrtrim(`"`newexp'"')
		}
		label var `name' `"Standardized values of `exp'"'
	}
	c_local fx_done 1
end
