*! version 0.1.0  Leo Liu  15oct2026
*! _fx_tostring: fastata's tostring. The fast path formats every numeric variable in the plugin
*! (src/strnum: integers within the calibrated digit bound of a %W.0g or %W.0f format, and
*! missing codes, exactly as string() writes them), then runs tostring.ado's (3.0.0) own commands
*! and messages on the new variables. Everything else runs the original.
program _fx_tostring
	local caller = _caller()
	local rc0 = c(rc)
	version 16
	_fx gate tostring
	if `fx_ok' {
		local fx_why
		* the original's parsing and error checks; any error runs the original, which reports it
		capture version `caller': Parse `0'
		if _rc local fx_why error
		if "`fx_why'" == "" & _N == 0 local fx_why "no observations"
		if "`fx_why'" == "" {
			* the variables that get converted (every value converts reversibly: the plugin
			* falls back otherwise)
			local convvars
			foreach v of local varlist {
				capture confirm string variable `v'
				if !_rc continue
				if "`replace'" != "" & `"`: value label `v''"' != "" & "`force'" == "" continue
				local convvars `convvars' `v'
			}
			if "`convvars'" != "" {
				_fx threads
				_fx_call `convvars', tostring "phase=compute" "threads=`fx_threads'" "fmt=`fmtkind'" "width=`fmtwidth'"
				if `"`fx_fallback'"' != "" local fx_why `"`fx_fallback'"'
				else if `fx_plugrc' local fx_why "plugin r(`fx_plugrc')"
			}
		}
		if "`fx_why'" == "" {
			* the new variables, in one store: under their final names for generate, under
			* temporary names for replace
			local spec
			local j 0
			local i 0
			foreach v of local varlist {
				local ++i
				if !`: list v in convvars' continue
				local ++j
				if "`generate'" != "" local new`i' : word `i' of `generate'
				else tempvar new`i'
				local spec `spec' str`fx_len_`j'' `new`i''
			}
			if "`spec'" != "" _fx store `fx_token' `spec'

			* tostring.ado lines 71-160, with the stored variables in place of its temporary ones
			if "`generate'" != "" {
				tokenize `generate'
				local i = 0
				foreach v of local varlist {
					local ++i
					capture confirm string variable `v'
					if _rc == 0 {
						di as txt "`v' already string; no " ///
							as res "generate"
					}
					else {
				di as txt "``i'' generated as {res:`: type ``i'''}"
						_crcslbl ``i'' `v'
						move ``i'' `v'
						move `v' ``i''
						Charcopy `v' ``i''
						char ``i''[tostring] ///
						"converted to string"
					}
				}
			}
			else {
				local i 0
				foreach v of local varlist {
					local ++i
					capture confirm string variable `v'
					if _rc == 0 {
						di as txt "`v' already string; no " ///
							as res "replace"
					}
					else if `"`: value label `v''"' != "" & "`force'" == "" {
						di as txt "`v' has value label; no " ///
						as res "replace"
					}
					else {
						local temp `new`i''
						local oldtype : type `v'
						char rename `v' `temp'
						move `temp' `v'
						local vl: variable label `v'
						drop `v'
						rename `temp' `v'
						label variable `v' `"`vl'"'
		di as txt "`v' was {res:`oldtype'} now {res:`: type `v''}"
						char `v'[tostring] ///
						"converted to string"
					}
				}
			}
			_fx count tostring fast
			exit
		}
	}
	_fx count tostring fallback `"`fx_why'"'
	_fx orig tostring
	capture error `rc0'
	version `caller': `fx_prog' `0'
end

* tostring.ado's parsing and checks (lines 8-65), run under the caller's version. Returns its
* results to _fx_tostring with c_local; sets fx_why for input the fast path does not cover.
program Parse
	version 8.0
	syntax varlist, [Generate(string) replace] [force] ///
	[format(str) Usedisplayformat]

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

	if "`usedisplayformat'" != "" & "`format'" != "" exit 198
	if "`usedisplayformat'" != "" {
		c_local fx_why usedisplayformat
		exit
	}

	if "`format'" != "" {
		if index("`format'", "s") exit 198
		capture di `format' 12345.67890
		if _rc exit 198
		local fmt "`format'"
	}
	else {
		local fmt "%12.0g"
	}
	* %W.0g or %W.0f with W <= 24 (calibration C5)
	if !regexm("`fmt'", "^%([1-9][0-9]?)\.0([fg])$") {
		c_local fx_why format
		exit
	}
	local fmtwidth = regexs(1)
	local fmtkind = regexs(2)
	if `fmtwidth' > 24 {
		c_local fx_why format
		exit
	}

	foreach x in varlist generate replace force fmtwidth fmtkind {
		c_local `x' `"``x''"'
	}
end

* tostring.ado's Charcopy
program Charcopy
	syntax varlist(min=2 max=2)
	tokenize `varlist'
	args from to

	local chfrom : char `from'[]
	if "`chfrom'" == "" {
		exit
	}

	tokenize `chfrom'
	while "`1'" != "" {
		local fchar : char `from'[`1']
		char `to'[`1'] `"`fchar'"'
		mac shift
	}
end
