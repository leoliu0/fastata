*! version 0.1.0  Leo Liu  15oct2026
*! _fx_duplicates: fastata's duplicates. Fast path: the subcommands report, examples, list, tag
*! and drop with the original's syntax, whenever the original would not fail; examples and list
*! only with list options that do not name variables (see ListOK below). The plugin groups the
*! sample by the key tuple without sorting; the output is produced with the original's commands:
*! tabdisp on a frame holding the report table, list on a frame holding the listed observations,
*! drop if on a marker. Everything else runs the original.
program _fx_duplicates, rclass
	local caller : display _caller()
	local rc0 = c(rc)
	version 16
	local cmdline `"`0'"'
	* small data (below 500 observations): the original right away (see _fx gate)
	_fx gate duplicates `=c(N) < 500'
	if "`fx_small'" == "1" {
		capture error `rc0'
		capture noisily version `caller': `fx_prog' `0'
		local rc = _rc
		return add
		exit `rc'
	}
	if `fx_ok' {
		local fx_why
		local sub
		gettoken cmd rest : 0, parse(" ,")
		local l = length(`"`cmd'"')
		if `l' == 0 local fx_why syntax
		else if bsubstr("report", 1, max(1, `l')) == `"`cmd'"' local sub report
		else if bsubstr("examples", 1, max(1, `l')) == `"`cmd'"' local sub examples
		else if bsubstr("list", 1, max(1, `l')) == `"`cmd'"' local sub list
		else if bsubstr("tag", 1, max(1, `l')) == `"`cmd'"' local sub tag
		else if `"`cmd'"' == "drop" local sub drop
		else local fx_why subcommand
		if "`fx_why'" == "" {
			local 0 `"`rest'"'
			if "`sub'" == "drop" {
				capture syntax [varlist(default=none)] [if] [in] [, force]
				if _rc local fx_why syntax
				else if ("`varlist'" == "") != ("`force'" == "") local fx_why error
			}
			else if "`sub'" == "tag" {
				capture syntax [varlist(default=none)] [if] [in], Generate(str)
				if _rc local fx_why syntax
				else {
					capture confirm new variable `generate'
					if _rc local fx_why error
					else if `: word count `generate'' != 1 local fx_why error
				}
			}
			else {
				capture syntax [varlist(default=none)] [if] [in] [, *]
				if _rc local fx_why syntax
				else if "`sub'" != "report" {
					ListOK, `options'
					if !`fx_listok' local fx_why option
					else {
						local dups : list dups varlist
						if "`dups'" != "" local fx_why "repeated variable"
					}
				}
			}
		}
		if "`fx_why'" == "" {
			if "`varlist'" == "" {
				capture unab varlist : _all
				if _rc local fx_why syntax
				local vartext "{txt} all variables"
			}
			else local vartext "{res} `varlist'"
		}
		* state-dependent functions in if: s() and regexs()/ustrregexs() (the last match of
		* regexm()/ustrregexm()) may differ between here and the original; random-number functions
		* draw again when the original runs after marksample, so their state is put back first
		local rng
		if "`fx_why'" == "" & `"`if'"' != "" {
			if ustrregexm(`"`if'"', "(^|[^A-Za-z0-9_])(s|regexs|ustrregexs)\s*\(") local fx_why state
			else if ustrregexm(`"`if'"', "(^|[^A-Za-z0-9_])(r[A-Za-z0-9_]*|uniform[A-Za-z0-9_]*)\s*\(") {
				local rng = c(rngstate)
			}
		}
		local tu 0
		local tv
		if "`fx_why'" == "" & `"`if'`in'"' != "" {
			capture marksample touse, novarlist
			if _rc == 1 exit 1
			if _rc local fx_why syntax
			else {
				local tu 1
				local tv `touse'
			}
		}
		if "`fx_why'" == "" {
			local fx_threads = cond(c(MP), c(processors), 0)
			_fx_call `varlist' `tv', dup "phase=compute" "sub=`sub'" "touse=`tu'" "threads=`fx_threads'"
			if `fx_plugrc' == 1 exit 1
			if `fx_plugrc' local fx_why "plugin r(`fx_plugrc')"
			else if `"`fx_fallback'"' != "" local fx_why `"`fx_fallback'"'
			else if `fx_n' == 0 local fx_why error
			else if inlist("`sub'", "examples", "list") & "`c(type)'" == "float" {
				if `fx_ndup' > 16777216 local fx_why "groups beyond float"
			}
		}
		* report, examples and list display from a frame: create it before anything is printed
		* (at most 100 frames may exist, and the original creates none)
		if "`fx_why'" == "" & "`sub'" != "tag" & "`sub'" != "drop" {
			tempname fr
			capture frame create `fr'
			if _rc == 1 exit 1
			if _rc local fx_why frames
		}
		if "`fx_why'" == "" {
			_fx count duplicates fast
			return scalar N = `fx_n'
			di _n "{p 0 4}{txt}Duplicates in terms of `vartext'{p_end}"
			if "`sub'" == "tag" {
				local type = cond(`fx_max' <= 100, "byte", cond(`fx_max' <= 32740, "int", "long"))
				_fx store `fx_token' `type' `generate'
				format `generate' %12.0g
			}
			else if "`sub'" == "report" {
				Report `fr' `"`fx_table'"' `c(obs_t)'
				return scalar unique_value = `fx_nuniq'
			}
			else if "`sub'" == "drop" {
				if `fx_ndrop' == 0 di _n as txt "(0 observations are duplicates)"
				else {
					tempvar dm
					_fx store `fx_token' byte `dm'
					di
					drop if `dm'
					drop `dm'
				}
				return scalar N_drop = `fx_ndrop'
			}
			else {
				if `fx_ndup' == 0 {
					frame drop `fr'
					di _n as txt "(0 observations are duplicates)"
				}
				else List `fr' `sub' `fx_token' `fx_ndup' `fx_nlist' `c(obs_t)' `c(type)' `"`varlist'"' `"`options'"'
			}
			* c(rc) as duplicates.ado leaves it: as it was (tag: 0, from its capture confirm new
			* variable). The shim runs this program under capture, so it sets c(rc) again from
			* fx_left.
			local left = cond("`sub'" == "tag", 0, `rc0')
			capture error `left'
			* verify mode: the original on the snapshot taken by gate (without the sample
			* marker, which the original never sees); its data are kept
			if "`fx_vpend'" == "1" {
				if "`tv'" != "" drop `tv'
				local rspec N `fx_n'
				if "`sub'" == "report" local rspec `rspec' unique_value `fx_nuniq'
				if "`sub'" == "drop" local rspec `rspec' N_drop `fx_ndrop'
				_fx verify duplicates `caller' `rc0' 0 `left' "" "" 0 "`rspec'" `"`cmdline'"'
				if `fx_vrc' exit `fx_vrc'
			}
			c_local fx_left `=c(rc)'
			exit
		}
		* the original must see the data as the user left them, and draw the same random numbers
		if "`tv'" != "" drop `tv'
		if `"`rng'"' != "" & `"`rng'"' != c(rngstate) set rngstate `rng'
	}
	_fx fallback duplicates `"`fx_why'"'
	local 0 `"`cmdline'"'
	capture error `rc0'
	* under capture, so that r() set by the original before an error (r(N) before error 2000)
	* survives as it does without fastata; capture noisily keeps its output and error messages
	capture noisily version `caller': `fx_prog' `0'
	local rc = _rc
	return add
	exit `rc'
end

* Sets fx_listok to 1 when every option is a list option that behaves the same on the frame of
* listed observations as on the data: none that names variables or expressions (sepby(),
* sepbyexp(), mean(), sum(), N(), labvar(), constant()) or observation numbers.
program ListOK
	capture syntax [, noCompress FAST ABbreviate(string) STRing(string) Table Display noHeader CLEAN ///
		DIVider SEParator(string) DS noLabel noTRim LINEsize(string)]
	c_local fx_listok = !_rc
end

* Displays the report table: one observation per group size in frame fr (created empty by the
* caller), then the original's tabdisp. Types are c(obs_t) of the data, as in the original.
program Report
	args fr table obst
	frame `fr' {
		quietly set obs `= `: word count `table''/3'
		foreach v in Ngroup freq surplus {
			quietly gen `obst' `v' = .
		}
		quietly mata: st_store(., ("Ngroup", "freq", "surplus"), colshape(strtoreal(tokens(st_local("table"))), 3))
		label var Ngroup "Copies"
		label var freq "Observations"
		label var surplus "Surplus"
		tabdisp Ngroup, cell(freq surplus)
	}
	frame drop `fr'
end

* Lists the duplicated observations (list) or one example per group (examples) as the original
* does after sorting by group: the listed observations of varlist go to frame fr (created empty
* by the caller, replaced here), in listing order, with the original's Group, # and
* observation-number columns.
program List
	args fr sub token ndup nlist obst ctype varlist options
	local main = c(frame)
	tempvar order dgroup Ngroup
	frame drop `fr'
	frame put `varlist' in 1, into(`fr')
	frame `fr' {
		quietly set obs `nlist'
		if "`sub'" == "examples" _fx store `token' `obst' `order' `ctype' `dgroup' `obst' `Ngroup'
		else _fx store `token' `obst' `order' `ctype' `dgroup'
		foreach v of local varlist {
			quietly replace `v' = _frval(`main', `v', `order')
		}
		char `dgroup'[varname] "Group"
		if "`sub'" == "examples" {
			char `order'[varname] "e.g. obs:"
			char `Ngroup'[varname] "#"
			if `ndup' > 1 list `dgroup' `Ngroup' `order' `varlist', subvarname noobs `options'
			else list `Ngroup' `order' `varlist', subvarname noobs `options'
		}
		else {
			char `order'[varname] "Obs"
			if `ndup' > 1 list `dgroup' `order' `varlist', subvarname noobs `options'
			else list `order' `varlist', subvarname noobs `options'
		}
	}
	frame drop `fr'
end
