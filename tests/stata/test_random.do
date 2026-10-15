* test_random.do [N [first]] -- randomized differential test of fastata against the originals
* (plan Step 5). Case c (c = first, ..., first+N-1; defaults N = 3000, first = 1) draws, from seed
* 20261015 + c, a dataset (1-40,000 observations; numeric, str# and strL keys with ties, "" and
* missing codes; values with extended missing codes, -0, integers and non-integers of mixed
* magnitudes; sorted or unsorted) and one call of egen, isid, duplicates, xtile, pctile, destring
* or tostring with options drawn mostly from the fast-path sets and mixed with fallback options,
* and checks it with fx_both (data, output, return code; r() of duplicates, the only rclass
* command; the path is not fixed in advance). Tolerances only where the contract documents them:
* egen total/sum/mean/sd/std with by() on data not sorted by the by() keys (reldif 1e-13 for
* double results, 2^-23 for others).
* Prints one line per case (case, observations, command, path), a tally by command x path, and
* TEST_RANDOM passed <N> if every case matched. To rerun case 517 alone: do test_random.do 1 517
version 16
clear all
set more off
args N first
if "`N'" == "" local N 3000
if "`first'" == "" local first 1
local last = `first' + `N' - 1

fx_setup
quietly fastata on
_fx mode auto

mata:
// Sets a share p of the observations of numeric variable v to missing: . only, or (ext) any
// of . and .a-.z.
void rt_miss(string scalar v, real scalar p, real scalar ext)
{
	real colvector x, idx, codes

	x = st_data(., v)
	idx = selectindex(runiform(rows(x), 1) :< p)
	if (!length(idx)) return
	idx = vec(idx)
	if (ext) {
		codes = (., .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m, .n, .o, .p, .q, .r,
			.s, .t, .u, .v, .w, .x, .y, .z)'
		x[idx] = codes[runiformint(rows(idx), 1, 1, rows(codes))]
	}
	else x[idx] = J(rows(idx), 1, .)
	st_store(., v, x)
}

// Turns a share p of the zeros of numeric variable v into -0 (Stata expressions cannot make -0).
void rt_negzero(string scalar v, real scalar p)
{
	real colvector x, idx

	x = st_data(., v)
	idx = selectindex((x :== 0) :& (runiform(rows(x), 1) :< p))
	if (length(idx)) st_store(vec(idx), v, J(length(idx), 1, -(1e-300 * 1e-300)))
}

// Local name: k distinct words of list in random order.
void rt_picks(string scalar name, real scalar k, string scalar list)
{
	string rowvector w

	w = tokens(list)
	w = w[jumble(1::cols(w))']
	st_local(name, invtokens(w[1..min((k, cols(w)))]))
}
end

* pick <local> "<words>": one word at random (compound-quoted words stay whole)
capture program drop pick
program pick
	args name list
	local n : word count `list'
	local w : word `=runiformint(1, `n')' of `list'
	c_local `name' `"`w'"'
end

* rt_num <var> <type>: a numeric variable of one of seven value classes
capture program drop rt_num
program rt_num
	args v type
	local m = runiformint(1, 7)
	if `m' == 7 {
		quietly gen double `v' = runiformint(1, 6)
		quietly replace `v' = cond(`v' == 1, rnormal()*10, cond(`v' == 2, (2*(runiform() < .5) - 1)*10^(runiform()*16 - 8), cond(`v' == 3, floor(runiform()*10) - 5, cond(`v' == 4, round(rnormal()*4, .25), cond(`v' == 5, 3, round(rnormal()*1e8)))))) 
	}
	else if `m' == 1 quietly gen double `v' = rnormal()*10
	else if `m' == 2 quietly gen double `v' = (2*(runiform() < .5) - 1)*10^(runiform()*16 - 8)
	else if `m' == 3 {
		local k : word `=runiformint(1, 4)' of 2 5 30 1000
		quietly gen double `v' = floor(runiform()*`k') - floor(`k'/2)
	}
	else if `m' == 4 quietly gen double `v' = round(rnormal()*4, .25)
	else if `m' == 5 quietly gen double `v' = round(rnormal()*100)
	else quietly gen double `v' = round(rnormal()*1e8)
	if "`type'" != "double" quietly recast `type' `v', force
end

* rt_data: the case's dataset in the current frame
capture program drop rt_data
program rt_data
	clear
	local r = runiform()
	local n = cond(`r' < .01, 0, cond(`r' < .1, runiformint(1, 30), cond(`r' < .45, runiformint(31, 3000), runiformint(3001, 40000))))
	quietly set obs `n'
	quietly {
		gen long id = _n
		* numeric key k1: integers with ties, random storage type
		local t : word `=runiformint(1, 5)' of byte int long float double
		local k : word `=runiformint(1, 6)' of 1 2 3 10 100 1000
		gen `t' k1 = floor(runiform()*`k') - (runiform() < .2)*50
		if runiform() < .5 mata: rt_miss("k1", `=runiform()*.1', `=runiform() < .5')
		* numeric key k2: doubles, non-integers, -0, missing codes
		local k : word `=runiformint(1, 4)' of 3 20 500 100000
		gen double k2 = round(rnormal()*`k'/4, cond(runiform() < .5, 1, .5))
		mata: rt_negzero("k2", .5)
		if runiform() < .6 mata: rt_miss("k2", `=runiform()*.1', `=runiform() < .7')
		* string keys: ks str#, kl strL (sometimes str#); prefixes, case, "", rare blanks/non-ASCII
		local k : word `=runiformint(1, 4)' of 2 5 30 1000
		local w : word `=runiformint(1, 3)' of 8 12 30
		gen str`w' ks = substr("abAB", runiformint(1, 4), runiformint(0, 2)) + string(floor(runiform()*`k'))
		replace ks = "" if runiform() < `=runiform()*.08'
		if runiform() < .08 replace ks = " " + ks if runiform() < .05
		if runiform() < .05 replace ks = ks + "é" if runiform() < .05
		local k : word `=runiformint(1, 3)' of 3 40 2000
		if runiform() < .5 gen strL kl = "k" + string(floor(runiform()*`k'))
		else gen str10 kl = "k" + string(floor(runiform()*`k'))
		replace kl = "" if runiform() < .03
		if runiform() < .05 replace kl = kl + 300*"z" if runiform() < .1 & "`: type kl'" == "strL"
		* a binary strL value (rare)
		if runiform() < .03 & "`: type kl'" == "strL" & `n' > 0 mata: st_sstore(runiformint(1, 1, 1, `n'), "kl", "k" + char(0) + "1")
		* values
		rt_num x1 double
		rt_num x2 double
		foreach v in x1 x2 {
			if runiform() < .3 mata: rt_negzero("`v'", .5)
			if runiform() < .7 mata: rt_miss("`v'", `=runiform()*.2', `=runiform() < .7')
		}
		gen float xf = round(rnormal()*5, cond(runiform() < .5, .1, 1))
		if runiform() < .4 mata: rt_miss("xf", .05, 1)
		gen byte xb = floor(runiform()*30) - 10
		if runiform() < .4 mata: rt_miss("xb", .05, 1)
		gen int xi = round(rnormal()*300)
		gen long xl = round(rnormal()*1e6)
		if runiform() < .3 mata: rt_miss("xl", .05, 0)
		* weights
		gen double w = runiform() + cond(runiform() < .5, .01, 1)
		if runiform() < .2 replace w = . if runiform() < .02
		gen int fw = runiformint(1, 5)
		if runiform() < .1 replace fw = 0 if runiform() < .02
		if runiform() < .1 replace fw = . if runiform() < .02
		* integer values of large magnitude
		gen double zi = round((2*(runiform() < .3) - 1)*10^(runiform()*12))
		if runiform() < .3 mata: rt_miss("zi", .03, 1)
		* strings for destring: numbers with junk, spaces, leading zeros, signs, %, commas
		gen str16 sn = string(round(rnormal()*1000, cond(runiform() < .5, .01, 1)))
		local p = runiform()*.05
		replace sn = word("NA - n/a . .a .z 1e5 1,000 12% +3 0007 -.5", runiformint(1, 12)) if runiform() < `p'
		if runiform() < .2 replace sn = " " + sn + " " if runiform() < .1
		replace sn = "" if runiform() < .02
		if runiform() < .5 gen strL sl = string(runiformint(-500, 500))
		else gen str8 sl = string(runiformint(-500, 500))
		if runiform() < .3 replace sl = "00" + sl if runiform() < .1
		gen str12 sx = string(runiformint(0, 100000)) + "%"
		replace sx = string(runiformint(0, 999)) + "," + string(runiformint(100, 999)) if runiform() < .5
		gen double u = runiform()
	}
	if runiform() < .3 {
		label define k1lab 0 "zero" 1 "one" 2 "two"
		label values k1 k1lab
	}
	if runiform() < .3 {
		label variable x1 "first value"
		note x1: a note
		char x1[src] "random"
	}
	* order: by id, sorted by keys, or unsorted
	local r = runiform()
	if `r' < .2 sort k1
	else if `r' < .3 sort ks k1
	else if `r' < .35 sort k2
	else if `r' < .6 {
		quietly gen double _o = runiform()
		sort _o
		drop _o
	}
	else if `r' < .65 {
		* in order of the keys, without the sort marker
		quietly gen double _o = runiform()
		sort k1 _o
		drop _o
	}
	else sort id
end

* Shared pieces of commands --------------------------------------------------
* rt_if: an if condition (or none)
capture program drop rt_ifin
program rt_ifin
	args pif pin
	local ifs `""x2 > 0" "k1 < 3" "u < .5" "!missing(x1)" `"ks != "a1""' "x1" "xb >= ." "u < .1 | k2 >= ." "k2 == 0" "u < .02""'
	local ifc
	if runiform() < `pif' {
		pick ifc `"`ifs'"'
		local ifc `"if `ifc'"'
	}
	local inr
	if runiform() < `pin' & _N > 0 {
		local N = _N
		local a = runiformint(1, `N')
		local b = runiformint(`a', `N')
		local r = runiform()
		if `r' < .7 local inr "in `a'/`b'"
		else if `r' < .85 local inr "in -`=min(`N', 100)'/l"
		else local inr "in `a'"
	}
	c_local rt_if `"`ifc'"'
	c_local rt_in `"`inr'"'
end

* rt_exp: a numeric expression or variable
capture program drop rt_exp
program rt_exp
	local e `""x1" "x1" "x2" "x2" "xf" "xb" "xi" "xl" "k1" "k2" "zi" "x1+x2" "x1*2" "(x1)" "((x2))" "abs(x1)" "x1/3" "xf-xb" "k1*x1" "-x2" "x1 + 1e8" "cond(x2>0,x1,x2)" "x1-x2" "xl*1000""'
	if runiform() < .03 local e `"`e' "ks" "kl" "nosuchvar""'
	pick e `"`e'"'
	c_local rt_exp `"`e'"'
end

* Command generators: each sets locals rt_cmd (the command), rt_tol (tolerance) and rt_r (fx_both's
* r() option) ---------------------------------------------------------------
capture program drop rt_egen
program rt_egen
	local fns group group group tag tag total sum mean mean max min count median pctile iqr sd std rank rank
	local fns `fns' rowtotal rowmean rowmax rowmin rowsd rowmiss rownonmiss mode concat
	pick fn "`fns'"
	local isrow = substr("`fn'", 1, 3) == "row"
	local ty
	local r = runiform()
	if `r' < .2 local ty double
	else if `r' < .3 local ty float
	else if `r' < .4 pick ty "byte int long"
	local pre
	if runiform() < .05 pick pre `""version 12:" "version 19:" "quietly" "capture""'
	if "`fn'" == "group" & inlist("`ty'", "byte", "int", "long") & runiform() < .7 local pre "version 19:"

	* arguments
	if inlist("`fn'", "group", "tag", "concat") {
		picks args `=runiformint(1, 3)' "k1 k2 ks kl xb id"
	}
	else if `isrow' {
		local pool x1 x2 xf xb xi xl k2 zi
		if inlist("`fn'", "rowmiss", "rownonmiss") local pool `pool' ks kl
		picks args `=runiformint(1, 4)' "`pool'"
		if runiform() < .05 local args x1-xl
	}
	else if "`fn'" == "count" & runiform() < .3 {
		pick args "ks kl sn x1>0"
	}
	else {
		rt_exp
		local args `"`rt_exp'"'
	}

	* by form: none, by() option, by prefix on sorted data, bysort
	local byp
	local byo
	local keys
	if !inlist("`fn'", "group", "tag", "concat") & !`isrow' & runiform() < .65 {
		picks keys `=runiformint(1, 2)' "k1 k2 ks kl k1"
		local r = runiform()
		local sb : sortedby
		if `r' < .45 local byo "by(`keys')"
		else if `r' < .7 {
			local sb : sortedby
			local nk : word count `keys'
			local head
			forvalues i = 1/`nk' {
				local head `head' `: word `i' of `sb''
			}
			if "`head'" == "`keys'" | runiform() < .03 local byp "by `keys':"
			else local byp "bysort `keys':"
		}
		else if `r' < .95 local byp "bysort `keys':"
		else local byp "bysort `keys' (id):"
	}

	* sample: in only rarely with a by prefix (the original refuses it)
	rt_ifin .4 `=cond("`byp'" == "", .25, .03)'

	* options
	local opts `byo'
	if inlist("`fn'", "group", "tag", "total", "sum", "max", "min", "rowtotal") & runiform() < .35 local opts `opts' missing
	if "`fn'" == "pctile" & runiform() < .85 {
		pick p "1 5 10 25 33.3 50 66.6667 75 90 99 99.5 12.5 2.5 0 100"
		local opts `opts' p(`p')
	}
	if "`fn'" == "std" {
		if runiform() < .3 local opts `opts' mean(`=round(rnormal()*5, .5)')
		if runiform() < .3 local opts `opts' sd(`=runiformint(1, 4)')
		else if runiform() < .1 local opts `opts' std(2)
	}
	if "`fn'" == "rank" {
		local r = runiform()
		if `r' < .25 local opts `opts' field
		else if `r' < .5 local opts `opts' track
		else if `r' < .53 local opts `opts' unique
	}
	if "`fn'" == "rownonmiss" & runiform() < .5 local opts `opts' strok
	if "`fn'" == "group" & runiform() < .05 local opts `opts' label
	if inlist("`fn'", "median", "iqr") & runiform() < .03 local opts `opts' autotype
	if runiform() < .01 local opts `opts' nosuchopt
	local opts = strtrim(`"`opts'"')
	if `"`opts'"' != "" local opts `", `opts'"'

	local nm v
	if runiform() < .02 local nm x1
	c_local rt_cmd `"`pre' `byp' egen `ty' `nm' = `fn'(`args') `rt_if' `rt_in' `opts'"'

	* the accumulation class: by() on data not sorted by its keys
	local tol 0
	if inlist("`fn'", "total", "sum", "mean", "sd", "std") & "`byo'" != "" {
		local sb : sortedby
		local nk : word count `keys'
		local head
		forvalues i = 1/`nk' {
			local head `head' `: word `i' of `sb''
		}
		if "`head'" != "`keys'" {
			local tdef : set type
			local tt = cond("`ty'" == "", "`tdef'", "`ty'")
			local tol = cond("`tt'" == "double", 1e-13, 2^-23)
		}
	}
	c_local rt_tol `tol'
	c_local rt_r
end

capture program drop rt_isid
program rt_isid
	picks v `=runiformint(1, 3)' "id id k1 k2 ks kl x1 zi xb"
	local opts
	if runiform() < .3 local opts `opts' sort
	if runiform() < .3 local opts `opts' missok
	if runiform() < .03 local opts `opts' nosuchopt
	if `"`opts'"' != "" local opts `", `opts'"'
	local ifc
	if runiform() < .03 local ifc "if u < .5"
	local pre
	if runiform() < .1 pick pre `""capture" "quietly" "version 12:""'
	c_local rt_cmd `"`pre' isid `v' `ifc' `opts'"'
	c_local rt_tol 0
	c_local rt_r
end

capture program drop rt_dup
program rt_dup
	pick sub "report report report r tag tag t drop drop drop examples list"
	local v
	if runiform() < .8 picks v `=runiformint(1, 3)' "k1 k2 ks kl xb id x1 sl"
	local big = _N > 400
	if inlist("`sub'", "examples", "list") {
		* keep the listing short
		local ifc = cond(`big', "if id <= 300", "")
		local opts
		if runiform() < .3 pick opts `""clean" "sep(0)" "noheader" "ab(8)" "nolabel""'
	}
	else {
		rt_ifin .3 .2
		local ifc `"`rt_if' `rt_in'"'
		local opts
	}
	if inlist("`sub'", "tag", "t") & runiform() < .97 local opts `opts' gen(dt)
	if "`sub'" == "drop" & ("`v'" != "" & runiform() < .95 | "`v'" == "" & runiform() < .03) local opts `opts' force
	if runiform() < .02 local sub browse
	if `"`opts'"' != "" local opts `", `opts'"'
	local pre
	if runiform() < .05 pick pre `""quietly" "version 12:""'
	c_local rt_cmd `"`pre' duplicates `sub' `v' `ifc' `opts'"'
	c_local rt_tol 0
	c_local rt_r allr
end

* rt_weight: [aw/fw/pw] or none; untyped rarely
capture program drop rt_weight
program rt_weight
	local wt
	local r = runiform()
	if `r' < .1 local wt "[aw=w]"
	else if `r' < .2 local wt "[fw=fw]"
	else if `r' < .25 local wt "[pw=w]"
	else if `r' < .27 local wt "[aw=fw]"
	else if `r' < .28 local wt "[w=w]"
	else if `r' < .29 local wt "[fw=w]"
	c_local rt_wt "`wt'"
end

capture program drop rt_xtile
program rt_xtile
	rt_exp
	rt_weight
	rt_ifin .35 .2
	local opts
	local r = runiform()
	if `r' < .85 {
		pick nq "2 3 4 5 7 10 10 20 50 100 1000 1001 `=runiformint(2, 300)'"
		local opts nq(`nq')
	}
	if runiform() < .15 local opts `opts' altdef
	if runiform() < .02 local opts `opts' cutpoints(x2)
	if `"`opts'"' != "" local opts `", `opts'"'
	local ty
	if runiform() < .05 local ty double
	c_local rt_cmd `"xtile `ty' q = `rt_exp' `rt_wt' `rt_if' `rt_in' `opts'"'
	c_local rt_tol 0
	c_local rt_r
end

capture program drop rt_pctile
program rt_pctile
	rt_exp
	rt_weight
	rt_ifin .35 .2
	local opts
	if runiform() < .85 {
		pick nq "2 3 4 5 10 10 20 100 1000 `=runiformint(2, 300)'"
		local opts nq(`nq')
	}
	if runiform() < .15 local opts `opts' altdef
	if runiform() < .02 local opts `opts' genp(pp)
	if `"`opts'"' != "" local opts `", `opts'"'
	local ty
	local r = runiform()
	if `r' < .2 local ty double
	else if `r' < .3 local ty float
	else if `r' < .32 local ty int
	c_local rt_cmd `"pctile `ty' p = `rt_exp' `rt_wt' `rt_if' `rt_in' `opts'"'
	c_local rt_tol 0
	c_local rt_r
end

capture program drop rt_destring
program rt_destring
	picks v `=runiformint(1, 3)' "sn sn sl sx ks kl x1 xb"
	local nv : word count `v'
	local opts
	if runiform() < .6 local opts replace
	else {
		local g
		forvalues i = 1/`nv' {
			local g `g' n`i'
		}
		local opts gen(`g')
	}
	if runiform() < .5 local opts `opts' force
	if runiform() < .2 local opts `opts' float
	local r = runiform()
	if `r' < .1 local opts `opts' ignore(",")
	else if `r' < .15 local opts `opts' ignore("%")
	else if `r' < .18 local opts `opts' ignore("NA")
	if runiform() < .07 local opts `opts' percent
	if runiform() < .04 local opts `opts' dpcomma
	local pre
	if runiform() < .05 pick pre `""version 13:" "quietly""'
	c_local rt_cmd `"`pre' destring `v', `opts'"'
	c_local rt_tol 0
	c_local rt_r
end

capture program drop rt_tostring
program rt_tostring
	local pool k1 xi xl xb zi id
	if runiform() < .35 local pool `pool' x1 xf k2 ks
	picks v `=runiformint(1, 3)' "`pool'"
	local nv : word count `v'
	local opts
	if runiform() < .6 local opts replace
	else {
		local g
		forvalues i = 1/`nv' {
			local g `g' t`i'
		}
		local opts gen(`g')
	}
	if runiform() < .4 local opts `opts' force
	local r = runiform()
	if `r' < .25 local opts `opts' format(%`=runiformint(1, 24)'.0g)
	else if `r' < .4 local opts `opts' format(%`=runiformint(1, 22)'.0f)
	else if `r' < .43 local opts `opts' format(%9.2f)
	else if `r' < .45 local opts `opts' usedisplayformat
	c_local rt_cmd `"tostring `v', `opts'"'
	c_local rt_tol 0
	c_local rt_r
end

capture program drop picks
program picks
	args name k list
	mata: rt_picks("`name'", `k', "`list'")
	c_local `name' `"``name''"'
end

* ---------------------------------------------------------------- the cases
local cmds egen isid duplicates xtile pctile destring tostring
foreach c of local cmds {
	foreach p in fast fallback none {
		local T_`c'_`p' 0
	}
}
mata: rt_why = asarray_create()
local nfail 0
local failed
local t0 = clock(c(current_time), "hms")
forvalues c = `first'/`last' {
	set seed `=20261015 + `c''
	capture frame drop base
	frame create base
	frame base: rt_data
	local r = runiform()
	if `r' < .45 local g egen
	else if `r' < .55 local g isid
	else if `r' < .7 local g duplicates
	else if `r' < .78 local g xtile
	else if `r' < .85 local g pctile
	else if `r' < .93 local g destring
	else local g tostring
	local gen = cond("`g'" == "duplicates", "dup", "`g'")
	if runiform() < .05 set type double
	frame base: rt_`gen'
	local cmd = strtrim(stritrim(`"`rt_cmd'"'))
	frame base: local n = _N
	capture noisily fx_both `"`cmd'"', expect(`g' any) tol(`rt_tol') `rt_r'
	local rc = _rc
	set type float
	local path `fxb_path'
	if "`path'" == "fast+fallback" local path fallback
	if `rc' {
		local ++nfail
		local failed `failed' `c'
		di as err `"TEST_RANDOM FAIL case `c' [n=`n'] `g' `fxb_path': `cmd'"'
	}
	else {
		local T_`g'_`path' = `T_`g'_`path'' + 1
		if "`path'" == "fallback" {
			mata: rt_key = "`g': " + st_local("fxb_why")
			mata: asarray(rt_why, rt_key, (asarray_contains(rt_why, rt_key) ? asarray(rt_why, rt_key) : 0) + 1)
		}
		di as txt `"case `c' [n=`n'] `g' `fxb_path'`=cond("`fxb_why'" != "", " (`fxb_why')", "")': `cmd'"'
	}
}
local secs = (clock(c(current_time), "hms") - `t0')/1000
if `secs' < 0 local secs = `secs' + 86400

di _n as txt "{hline 50}" _n "TEST_RANDOM tally (cases `first'-`last', `secs' s)"
di as txt %-12s "command" %10s "fast" %10s "fallback" %10s "none"
local tf 0
local tb 0
local tn 0
foreach c of local cmds {
	di as txt %-12s "`c'" %10.0f `T_`c'_fast' %10.0f `T_`c'_fallback' %10.0f `T_`c'_none'
	local tf = `tf' + `T_`c'_fast'
	local tb = `tb' + `T_`c'_fallback'
	local tn = `tn' + `T_`c'_none'
}
di as txt %-12s "total" %10.0f `tf' %10.0f `tb' %10.0f `tn'
di _n as txt "fallback reasons:"
mata: rt_k = sort(asarray_keys(rt_why), 1); for (rt_i = 1; rt_i <= rows(rt_k); rt_i++) printf("{txt}  %6.0f  %s\n", asarray(rt_why, rt_k[rt_i]), rt_k[rt_i])
if `nfail' {
	di as err "TEST_RANDOM failed: `nfail' of `N' cases (`failed')"
	exit 9
}
di as result "TEST_RANDOM passed `N'"
