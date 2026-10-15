* calib_strnum.do -- calibrations C3-C5 of fastata's destring and tostring (src/strnum/real.rs)
* against Stata itself. Run from tests/stata after scripts/build_plugin.sh:
*     stata-mp -b do calib_strnum.do
* Last line: TEST_CALIB strnum mismatches=<n> (0 required).
*   C3  real(): the plugin's emulation (destring "raw=1") against generate double/float =
*       real(s), bitwise, over every string of length <= 4 over 0 1 9 + - . e E d D x X a f and
*       space, every two-byte string of bytes 1-127, 50,000 random numeric-looking strings,
*       20,000 random hexadecimal-looking strings and edge values. Strings the emulation does
*       not cover (it falls back for them) are counted, not compared.
*   C4  compress after destring: the storage type the plugin picks against generate
*       double|float = real(s) then compress, for every range boundary +-1, missing codes,
*       -0, non-integers and all-missing columns.
*   C5  tostring: string(v, "%W.0g") and string(v, "%W.0f"), W = 1..24, against the plugin
*       for every integer within the plugin's digit bound (1 to 22 digits, both signs) and
*       every missing code. Values just beyond the bound that Stata still prints as plain
*       digits are counted (the bound is conservative), not mismatches.
version 16
clear all
set more off
fx_setup
quietly fastata on
_fx threads
local th `fx_threads'
local mism 0

* ------------------------------------------------------------------------------------ C3
mata:
string colvector _c3_strings()
{
	string rowvector al, dig, hx
	string colvector S
	string scalar s
	real scalar m, i, j, k, l, n, nd, u

	S = J(200000, 1, "")
	m = 1
	al = ("0","1","9","+","-",".","e","E","d","D","x","X","a","f"," ")
	for (i = 1; i <= cols(al); i++) {
		S[++m] = al[i]
		for (j = 1; j <= cols(al); j++) {
			S[++m] = al[i] + al[j]
			for (k = 1; k <= cols(al); k++) {
				S[++m] = al[i] + al[j] + al[k]
				for (l = 1; l <= cols(al); l++) S[++m] = al[i] + al[j] + al[k] + al[l]
			}
		}
	}
	for (i = 1; i <= 127; i++) {
		for (j = 1; j <= 127; j++) S[++m] = char(i) + char(j)
	}
	rseed(20261015)
	dig = ("0","1","2","3","4","5","6","7","8","9")
	for (n = 1; n <= 50000; n++) {
		s = ""
		if (runiform(1, 1) < .1) s = " "
		u = runiform(1, 1)
		if (u < .15) s = s + "-"
		else if (u < .25) s = s + "+"
		nd = floor(runiform(1, 1) * (runiform(1, 1) < .3 ? 25 : 10))
		for (k = 1; k <= nd; k++) s = s + dig[ceil(runiform(1, 1) * 10)]
		if (runiform(1, 1) < .6) {
			s = s + "."
			nd = floor(runiform(1, 1) * (runiform(1, 1) < .3 ? 25 : 8))
			for (k = 1; k <= nd; k++) s = s + dig[ceil(runiform(1, 1) * 10)]
		}
		if (runiform(1, 1) < .35) {
			s = s + ("e","E","d","D")[ceil(runiform(1, 1) * 4)]
			u = runiform(1, 1)
			if (u < .4) s = s + "-"
			else if (u < .55) s = s + "+"
			nd = ceil(runiform(1, 1) * 3)
			for (k = 1; k <= nd; k++) s = s + dig[ceil(runiform(1, 1) * 10)]
		}
		if (runiform(1, 1) < .1) s = s + " "
		if (runiform(1, 1) < .03) s = s + ("a","%",",","$","1","x")[ceil(runiform(1, 1) * 6)]
		S[++m] = s
	}
	hx = ("0","1","9","a","f","A","F",".","x","X","+","-")
	for (n = 1; n <= 20000; n++) {
		s = ""
		nd = 5 + floor(runiform(1, 1) * 6)
		for (k = 1; k <= nd; k++) s = s + hx[ceil(runiform(1, 1) * cols(hx))]
		S[++m] = s
	}
	S[++m] = "1e308"
	S[++m] = "-1e308"
	S[++m] = "8.98846567431158e307"
	S[++m] = "8.9884656743115e307"
	S[++m] = "-8.9884656743115e307"
	S[++m] = "1.7976931348623157e308"
	S[++m] = "4.9e-324"
	S[++m] = "2.4e-324"
	S[++m] = "2.2250738585072014e-308"
	S[++m] = "1e-310"
	S[++m] = "1.7e38"
	S[++m] = "1.70141173319e38"
	S[++m] = "1e-37"
	S[++m] = "-1e-37"
	S[++m] = "16777217"
	S[++m] = "9007199254740993"
	S[++m] = "-0"
	S[++m] = "-0.0e5"
	S[++m] = "0" * 70 + "1"
	S[++m] = "1" + "0" * 63
	S[++m] = ".5" + "0" * 62
	S[++m] = "1.0x+1"
	S[++m] = "-1.8X-2"
	for (i = 1; i <= 26; i++) S[++m] = "." + char(96 + i)
	for (i = 1; i <= 26; i++) S[++m] = " ." + char(96 + i) + " "
	return(S[2..m])
}

// Number of observations where variables a and b differ bitwise (rows with flag 1 skipped).
real scalar _c3_bitdiff(string scalar a, string scalar b, string scalar flag)
{
	real colvector A, B, F, C
	string scalar ba, bb
	real scalar i, n

	C = bufio()
	A = st_data(., a)
	B = st_data(., b)
	F = st_data(., flag)
	n = 0
	for (i = 1; i <= rows(A); i++) {
		if (F[i]) continue
		ba = " " * 8
		bb = " " * 8
		bufput(C, ba, 0, "%8z", A[i])
		bufput(C, bb, 0, "%8z", B[i])
		if (ba != bb) {
			n++
			if (n <= 10) printf("{err}C3 mismatch obs %f: [%s] %21x vs %21x\n", i, st_sdata(i, "s"), A[i], B[i])
		}
	}
	return(n)
}
end

mata: _c3_S = _c3_strings()
mata: st_addobs(rows(_c3_S))
quietly gen strL s = ""
mata: st_sstore(., "s", _c3_S)
quietly gen double r = real(s)
quietly gen float rf = real(s)
_fx_call s, destring "phase=compute" "threads=`th'" "raw=1"
if `"`fx_fallback'`fx_errmsg'"' != "" {
	di as err `"C3: plugin failed: `fx_fallback'`fx_errmsg'"'
	exit 9
}
_fx store `fx_token' double e double efb
_fx_call s, destring "phase=compute" "threads=`th'" "raw=1" "float=1"
_fx store `fx_token' float ef double effb
mata: st_local("m1", strofreal(_c3_bitdiff("r", "e", "efb")))
mata: st_local("m2", strofreal(_c3_bitdiff("rf", "ef", "effb")))
quietly count if efb
local fb1 = r(N)
quietly count if effb
local fb2 = r(N)
di as txt "C3 real(): `=_N' strings, mismatches double `m1', float `m2'; not covered (fallback): double `fb1', float `fb2'"
local mism = `mism' + `m1' + `m2'

* ------------------------------------------------------------------------------------ C4
clear
quietly set obs 3
local cases `" "100" "101" "-127" "-128" "32740" "32741" "-32767" "-32768" "2147483620" "2147483621" "-2147483647" "-2147483648" "0.5" "-0" "100000" "16777216" "16777217" "1e10" ".a" "" "1e-5" "-100" "-101" "32740.5" "'
local c4n 0
local c4bad 0
foreach t in double float {
	local fl = cond("`t'" == "float", 1, 0)
	foreach v of local cases {
		foreach other in "" "7" ".b" "-1.5" {
			clear
			quietly set obs 3
			quietly gen str20 s = "`v'"
			quietly replace s = "`other'" in 2
			quietly replace s = "" in 3
			quietly gen `t' d = real(s)
			quietly compress d
			local want : type d
			_fx_call s, destring "phase=compute" "threads=`th'" "force=1" "float=`fl'"
			local ++c4n
			if `"`fx_fallback'"' != "" local fx_type_1 "fallback (`fx_fallback')"
			if "`fx_type_1'" != "`want'" {
				di as err `"C4 mismatch: `t' ("`v'", "`other'", ""): plugin `fx_type_1', compress `want'"'
				local ++c4bad
			}
			if "`fx_token'" != "" {
				_fx store `fx_token' `fx_type_1' e
				quietly count if e != d | missing(e) != missing(d)
				if r(N) {
					di as err `"C4 value mismatch: `t' ("`v'", "`other'")"'
					local ++c4bad
				}
			}
		}
	}
}
di as txt "C4 compress: `c4n' cases, mismatches `c4bad'"
local mism = `mism' + `c4bad'

* ------------------------------------------------------------------------------------ C5
clear
mata:
real colvector _c5_values()
{
	real colvector V
	real scalar d, k, m, x

	V = J(5000, 1, .)
	m = 0
	rseed(5)
	for (d = 1; d <= 22; d++) {
		V[++m] = 10^d - 1
		V[++m] = 10^(d - 1)
		V[++m] = -(10^d - 1)
		V[++m] = -10^(d - 1)
		for (k = 1; k <= 40; k++) {
			x = floor(10^(d - 1) + runiform(1, 1) * (10^d - 10^(d - 1)))
			V[++m] = x
			V[++m] = -x
		}
	}
	V[++m] = 0
	V[++m] = -0
	V[++m] = 2^53
	V[++m] = 2^53 + 2
	V[++m] = -2^53
	V[++m] = 2^63
	return(V[1..m])
}
end
mata: _c5_V = _c5_values()
mata: st_addobs(rows(_c5_V) + 27)
quietly gen double v = .
mata: st_store((1::rows(_c5_V)), "v", _c5_V)
forvalues k = 1/26 {
	quietly replace v = .`=char(96 + `k')' in `=_N - 26 + `k''
}
* digits of |v| (exact for these integers)
quietly gen int nd = length(string(abs(v), "%24.0f")) if !missing(v)
local c5n 0
local c5bad 0
local c5loose 0
foreach k in g f {
	forvalues w = 1/24 {
		* the plugin's bound (src/strnum/real.rs, max_digits)
		if "`k'" == "g" {
			local bpos = cond(`w' >= 4, min(`w' - 2, 19), 0)
			local bneg = `bpos'
		}
		else {
			local bpos = min(max(8, `w'), 19)
			local bneg = min(max(7, `w' - 1), 19)
		}
		quietly gen double vv = v if missing(v) | (v >= 0 & nd <= `bpos') | (v < 0 & nd <= `bneg')
		quietly gen str30 want = string(vv, "%`w'.0`k'")
		quietly gen str30 plain = string(v, "%24.0f")
		quietly count if !missing(v) & missing(vv) & string(v, "%`w'.0`k'") == plain & ((v >= 0 & nd == `bpos' + 1) | (v < 0 & nd == `bneg' + 1))
		local c5loose = `c5loose' + r(N)
		_fx_call vv, tostring "phase=compute" "threads=`th'" "fmt=`k'" "width=`w'"
		if `"`fx_fallback'`fx_errmsg'"' != "" {
			di as err `"C5 %`w'.0`k': plugin fell back: `fx_fallback'`fx_errmsg'"'
			local ++c5bad
		}
		else {
			_fx store `fx_token' str`fx_len_1' got
			quietly count if got != want
			local nbad = r(N)
			if `nbad' {
				di as err "C5 %`w'.0`k': `nbad' mismatches"
				list v want got if got != want, noobs clean
				local c5bad = `c5bad' + `nbad'
			}
			local c5n = `c5n' + _N
			drop got
		}
		drop vv want plain
	}
}
di as txt "C5 integer formatting: `c5n' values, mismatches `c5bad'; values one digit beyond the bound still plain: `c5loose'"
local mism = `mism' + `c5bad'

capture program drop _c_finish
program _c_finish
	args m
	di as result "TEST_CALIB strnum mismatches=`m'"
end
_c_finish `mism'
