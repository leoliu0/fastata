*! version 0.1.0  Leo Liu  15oct2026
*! _fx_destring: fastata's destring. The fast path (caller 11 or later) converts every string
*! variable in the plugin (src/strnum: the calibrated emulations of what destring.ado 2.4.4 does
*! before and in real(), and of compress), then runs destring.ado's own commands and messages on
*! the new variables. Callers 11-13 get destring.ado's older branch (the old ignore() parsing,
*! strtrim() and regexr(), "bytes" in the messages; calibration C3p). Everything else (callers
*! before 11), and any value outside the calibrated classes, runs the original.
program _fx_destring
	local caller : display _caller()
	local rc0 = c(rc)
	version 16
	_fx gate destring
	if `fx_ok' {
		local fx_why
		if `caller' < 11 local fx_why caller
		else {
			* the original's parsing and error checks; any error runs the original, which
			* reports it
			capture version `caller': Parse `0'
			if _rc == 1 exit 1
			if _rc local fx_why error
		}
		if "`fx_why'" == "" & _N == 0 local fx_why "no observations"
		if "`fx_why'" == "" {
			local strvars
			foreach var of local varlist {
				capture confirm string variable `var'
				if !_rc local strvars `strvars' `var'
			}
			if "`strvars'" != "" {
				local fx_threads = cond(c(MP), c(processors), 0)
				_fx_call `strvars', destring "phase=compute" "threads=`fx_threads'" "force=`=("`force'"!="")'" "float=`=("`float'"!="")'" "percent=`=("`percent'"!="")'" "dpcomma=`=("`dpcomma'"!="")'" "ign=`codes'" "old=`=(`caller' < 14)'"
				if `"`fx_fallback'"' != "" local fx_why `"`fx_fallback'"'
				else if `fx_plugrc' local fx_why "plugin r(`fx_plugrc')"
			}
		}
		if "`fx_why'" == "" {
			* c(rc) as destring.ado leaves it: its last capture is "capture drop" of a
			* temporary variable it never creates (111) when the last variable is a string
			* variable, "capture confirm string variable" (7) when it is numeric
			local fx_lastrc 7
			capture confirm string variable `: word `: word count `varlist'' of `varlist''
			if !_rc local fx_lastrc 111
			* the converted variables, in one store: under their final names for generate,
			* under temporary names for replace
			local j 0
			local varno 0
			local spec
			local names
			foreach var of local varlist {
				local ++varno
				capture confirm string variable `var'
				if _rc continue
				local ++j
				if !`fx_conv_`j'' continue
				if "`genrep'" == "generate" local new`j' : word `varno' of `generate'
				else tempvar new`j'
				local spec `spec' `fx_type_`j'' `new`j''
				local names `names' `new`j''
			}
			* the store and everything destring.ado does to the new variables, as one step: a
			* Break cannot leave variables without their labels, characteristics or position
			nobreak {
				if "`names'" != "" {
					_fx store `fx_token' `spec'
					* compress keeps the format of the double (float) destring generates
					format `names' `=cond("`float'" != "", "%9.0g", "%10.0g")'
				}
				* destring.ado lines 134-346, with the plugin's results in place of its temporary
				* variables
				local j 0
				local varno 0
				foreach var of local varlist {
					local varno = `varno' + 1
					if "`generate'"!="" {
						local finalvarname : word `varno' of `generate'
						local finalprint "`finalvarname' "
					}
					else {
						local finalvarname "`var'"
						local finalprint ""
					}
					capture confirm string variable `var'
					if _rc != 0 {
						di as txt "`var' already numeric; no " ///
						  as res "`genrep'"
						continue
					}
					local ++j
					local flag `fx_flag_`j''
					local newmiss `fx_newmiss_`j''
					local b
					local bcnt = 0
					local k 0
					foreach code of local codes {
						local ++k
						if `: word `k' of `fx_found_`j''' {
							local t = char(`code')
							if `"`t'"' == " " {
								local b `"`b' space"'
							}
							else {
								local b `"`b' `t'"'
							}
							local ++bcnt
						}
					}
					if `flag' & ("`force'" == "") {
						if `"`ignore'"' != "" {
							di as txt "`var': contains " ///
							  "`aswhat's not specified in " ///
							  as res "ignore()" ///
							  as txt "; no " as res "`genrep'"
						}
						else {
							di as txt "`var': contains " ///
							  "nonnumeric `aswhat's; no " ///
							  as res "`genrep'"
						}
						continue
					}
					local NEWVAR `new`j''
					order `NEWVAR', after(`var')
					if `aschars' {
						local dispb `"`b'"'
					}
					else {
						local dispb = printablebytes(`"`b'"')
					}
					local c = ///
					    plural(`bcnt',strproper("`aswhat'")) + ///
					    " removed " + ///
					    plural(`bcnt',"was","were") + `":`dispb'"'
					local type : type `NEWVAR'

					if `flag' {
						di as txt ///
					    "`var': contains nonnumeric `aswhat's" ///
					    _continue
						if `"`ignore'"'!="" {
							display " not specified in " ///
							  as result "ignore()" _continue
						}
						if `"`b'"'=="" {
							display "; `finalprint'" ///
							  as res "`genrep'd " ///
							  as txt "as " ///
							  as res "`type'" _continue
						}
						display
					}
					if `"`b'"' != "" {
						di as txt "`var': " ///
						  plural(`bcnt',"`aswhat'") ///
						  as res `"`dispb'"' ///
						  as txt " removed; `finalprint'" ///
						  as res "`genrep'd " as txt "as " ///
						  as res "`type'"
					}
					else if `"`b'"' == "" & !`flag' {
						di as txt ///
						  "`var': all characters numeric; " ///
						  "`finalprint'" ///
						  as res "`genrep'd " ///
						  as txt "as " as res "`type'"
					}

					if `newmiss' != 0 {
						di as txt "(`newmiss' missing " ///
						plural(`newmiss',"value") " generated)"
					}
					label variable `NEWVAR' ///
						`"`: variable label `var''"'
					char `NEWVAR'[destring] `c'
					char `NEWVAR'[destring_cmd] ///
						`"destring `cmdargs'"'
					char `var'[destring]
					char `var'[destring_cmd]
					if "`genrep'"=="generate" {
						Charcopy `var' `NEWVAR'
						* destring.ado renames its new variable to the generate() name here.
						* rename runs a non-quiet mata: line, which switches an SMCL log to
						* {res}; the variable already has its name, so this reproduces only
						* that (deliberately not quiet)
						mata: (void) st_nvar()
					}
					else {
						char rename `var' `NEWVAR'
						drop `var'
						rename `NEWVAR' `var'
					}
				}
			}
			_fx count destring fast
			* verify mode: the original on the snapshot taken by gate; its result is kept
			if "`fx_vpend'" == "1" {
				_fx verify destring `caller' `rc0' 0 "" "" "" 0 "" `"`0'"'
				if `fx_vrc' exit `fx_vrc'
			}
			capture error `fx_lastrc'
			exit
		}
	}
	_fx count destring fallback `"`fx_why'"'
	_fx orig destring
	capture error `rc0'
	version `caller': `fx_prog' `0'
end

* destring.ado's parsing and checks (lines 5-126), run under the caller's version. Returns its
* results to _fx_destring with c_local; sets fx_why for input the fast path does not cover.
program Parse
	version 14

	local cmdargs = `"`0'"'

	local verpre : display "version " %4.1f _caller() ":"

	syntax [varlist], [Generate(string) replace] [force] [float] ///
	  [Ignore(string asis)] [percent] [dpcomma]

	if _caller() >= 14 {
		if ustrpos(`"`ignore'"',",") & ///
		  !ustrpos(`"`ignore'"',`"""')  { // " required if , used
			exit 198
		}
	}

	`verpre' _parse_ignore `ignore'
	if _caller() < 14 {
		local aschars 0
		syntax [varlist], [Generate(string) replace] [force] [float] ///
		  [Ignore(string)] [percent] [dpcomma]
	}
	else {
		if `"`s(ignore)'"'!="" {
			local ignore `"`s(ignore)'"'
		}
		local aschars `s(aschars)'
		if `s(illegal)' {
			c_local fx_why ignore
			exit
		}
	}

	if "`percent'" == "percent" {
		if !ustrpos(`"`ignore'"', "%") {
			local ignore `"`ignore'%"'
		}
	}

	if "`generate'" != "" & "`replace'" != "" exit 198
	if "`generate'" == "" & "`replace'" == "" exit 198

	if "`generate'" != "" {
		local ct1: word count `varlist'
		local save "`varlist'"
		local 0 "`generate'"
		syntax newvarlist
		local generate "`varlist'"
		local varlist "`save'"
		local ct2: word count `generate'
		if `ct1' != `ct2' exit 198
		if "`: list dups generate'" != "" {
			c_local fx_why varlist
			exit
		}
	}
	if "`: list dups varlist'" != "" {
		c_local fx_why varlist
		exit
	}

	local m 1
	if `"`ignore'"' == "" {
		local ignore ""
	}
	if `aschars' {
		local l = ustrlen(`"`ignore'"')
	}
	else {
		local l = length(`"`ignore'"')
	}
	while `m' <= `l' {
		if `aschars' {
			local char`m' = usubstr(`"`ignore'"', `m', 1)
		}
		else {
			local char`m' = substr(`"`ignore'"', `m', 1)
		}
		local m = `m' + 1
	}

	* the characters destring's removal loop visits, as codes: printable ASCII other than
	* quotes and backslash (no exit inside the loop: under version 16, exit inside a loop does
	* not leave the program)
	local codes
	local badign 0
	local jj 1
	while `"`char`jj''"' != "" {
		local t `"`char`jj''"'
		quietly mata: st_local("code", strlen(st_local("t")) == 1 ? strofreal(ascii(st_local("t"))) : "")
		if "`code'" == "" local badign 1
		else if `code' < 32 | `code' > 126 | inlist(`code', 34, 39, 92, 96) local badign 1
		local codes `codes' `code'
		local jj = `jj' + 1
	}
	if `badign' {
		c_local fx_why ignore
		exit
	}

	if `aschars' {
		local aswhat "character"
	}
	else {
		local aswhat "byte"
	}
	if "`generate'"!="" {
		local genrep "generate"
	}
	else {
		local genrep "replace"
	}

	foreach x in varlist generate force float percent dpcomma codes aschars aswhat genrep {
		c_local `x' `"``x''"'
	}
	c_local ignore `"`ignore'"'
	c_local cmdargs `"`cmdargs'"'
end


* destring.ado's Charcopy
program def Charcopy
	syntax varlist(min=2 max=2)
	tokenize `varlist'
	args from to

	local chfrom : char `from'[]
	if "`chfrom'" == "" {
		exit
	}

	foreach char of local chfrom {
		local fchar : char `from'[`char']
		char `to'[`char'] `"`fchar'"'
	}
end
