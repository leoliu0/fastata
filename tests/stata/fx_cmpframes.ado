*! fx_cmpframes fa fb, tol(#) [what(text) nosortcheck noordercheck zsfree(names)]
*! Fails (r(9)) unless frames fa and fb hold the same data:
*! - same N, same variables in the same order (unless noordercheck), same : sortedby (unless
*!   nosortcheck);
*! - per variable: same storage type, display format, variable label and value label;
*! - same characteristics (notes included) of _dta and of every variable, and the same value-label
*!   definitions;
*! - values: identical missing patterns and missing codes, identical strings, and reldif <= tol
*!   on nonmissing numbers. tol 0 demands bitwise-equal values (the sign of zero too). NaNs (a plugin or Mata can
*!   store one) must have the same bits. zsfree: variables whose sign of zero is not compared
*!   (it follows the random tie order of -0 and +0 in the original's sort).
program fx_cmpframes
	version 16
	syntax namelist(min=2 max=2), tol(real) [what(string) noSORTcheck noORDERcheck ZSfree(namelist)]
	gettoken fa fb : namelist
	local fb `fb'
	local cur = c(frame)
	foreach f in a b {
		frame change `f`f''
		quietly ds
		local v`f' `r(varlist)'
		local s`f' : sortedby
		local n`f' = _N
		foreach v of local v`f' {
			local t`f'_`v' : type `v'
			local f`f'_`v' : format `v'
			local l`f'_`v' : variable label `v'
			local vl`f'_`v' : value label `v'
		}
	}
	frame change `cur'
	local fail
	if `na' != `nb' {
		local fail N differs (`na' vs `nb')
	}
	else if "`ordercheck'"=="" & "`va'" != "`vb'" {
		local fail variables differ: (`va') vs (`vb')
	}
	else if "`ordercheck'"!="" & !`: list va === vb' {
		local fail variable sets differ: (`va') vs (`vb')
	}
	else if "`sortcheck'"=="" & "`sa'" != "`sb'" {
		local fail sortedby differs: (`sa') vs (`sb')
	}
	if "`fail'"!="" {
		di as error `"`what': `fail'"'
		exit 9
	}
	foreach v of local va {
		foreach p in t f vl {
			if "``p'a_`v''" != "``p'b_`v''" {
				di as error `"`what': `v': `p' differs (``p'a_`v'' vs ``p'b_`v'')"'
				exit 9
			}
		}
		if `"`la_`v''"' != `"`lb_`v''"' {
			di as error `"`what': `v': label differs (`la_`v'' vs `lb_`v'')"'
			exit 9
		}
	}
	mata: fx_cmpmeta("`fa'", "`fb'", `"`what'"')
	foreach v of local va {
		local zc = !`: list v in zsfree'
		mata: fx_cmpvals("`fa'", "`fb'", "`v'", `tol', `"`what'"', `zc')
	}
end

mata:
// Characteristics (notes are characteristics) of _dta and every variable, and value-label
// definitions, as text lines.
string colvector fx_meta(string scalar fr)
{
	string scalar cur
	string colvector out, vars, names, labs, txt
	real colvector vals
	real scalar i, j

	cur = st_framecurrent()
	st_framecurrent(fr)
	out = J(0, 1, "")
	vars = "_dta"
	if (st_nvar()) vars = vars \ st_varname(1..st_nvar())'
	for (i = 1; i <= rows(vars); i++) {
		names = sort(st_dir("char", vars[i], "*"), 1)
		for (j = 1; j <= rows(names); j++) {
			out = out \ ("char " + vars[i] + "[" + names[j] + "] = " + st_global(vars[i] + "[" + names[j] + "]"))
		}
	}
	stata("quietly label dir")
	labs = tokens(st_global("r(names)"))'
	for (i = 1; i <= rows(labs); i++) {
		st_vlload(labs[i], vals, txt)
		for (j = 1; j <= rows(vals); j++) {
			out = out \ ("label " + labs[i] + " " + strofreal(vals[j], "%21x") + " = " + txt[j])
		}
	}
	st_framecurrent(cur)
	return(out)
}

void fx_cmpmeta(string scalar fa, string scalar fb, string scalar what)
{
	string colvector a, b
	real scalar i

	a = fx_meta(fa)
	b = fx_meta(fb)
	if (a == b) return
	for (i = 1; i <= max((rows(a), rows(b))); i++) {
		if (i > rows(a) | i > rows(b)) break
		if (a[i] != b[i]) break
	}
	errprintf("%s: characteristics or value labels differ:\n", what)
	errprintf("  %s\n  %s\n", i <= rows(a) ? a[i] : "(none)", i <= rows(b) ? b[i] : "(none)")
	exit(9)
}

void fx_cmpvals(string scalar fa, string scalar fb, string scalar v, real scalar tol,
	string scalar what, real scalar zcheck)
{
	string scalar cur
	string colvector sa, sb
	real colvector a, b, ma, mb, d, na, nb, z
	real scalar str, bad

	cur = st_framecurrent()
	st_framecurrent(fa)
	str = st_isstrvar(v)
	if (str) sa = st_sdata(., v)
	else a = st_data(., v)
	st_framecurrent(fb)
	if (str) sb = st_sdata(., v)
	else b = st_data(., v)
	st_framecurrent(cur)
	if (str) {
		if (sa != sb) {
			errprintf("%s: %s: strings differ\n", what, v)
			exit(9)
		}
		return
	}
	// a NaN (a plugin or Mata's st_store() can store one; NaN != NaN) compares by its bits
	na = selectindex(a :!= a)
	nb = selectindex(b :!= b)
	if (length(na) | length(nb)) {
		bad = length(na) != length(nb)
		if (!bad) bad = na != nb
		if (!bad) bad = _fxc_raw(a[na]) != _fxc_raw(b[nb])
		if (bad) {
			errprintf("%s: %s: NaN values differ\n", what, v)
			exit(9)
		}
		a[na] = J(length(na), 1, 0)
		b[nb] = J(length(nb), 1, 0)
	}
	ma = a :>= .
	mb = b :>= .
	if (ma != mb) {
		errprintf("%s: %s: missing patterns differ in %g obs\n", what, v, sum(ma :!= mb))
		exit(9)
	}
	if (any(select(a, ma) :!= select(b, mb))) {
		errprintf("%s: %s: missing codes differ\n", what, v)
		exit(9)
	}
	if (sum(!ma) == 0) return
	d = reldif(select(a, !ma), select(b, !mb))
	if (tol == 0) bad = any(select(a, !ma) :!= select(b, !mb))
	else bad = max(d) > tol
	if (bad) {
		errprintf("%s: %s: max reldif %g > %g\n", what, v, max(d), tol)
		exit(9)
	}
	// bitwise: the sign of zero too (%21x shows -0 as +0)
	if (tol == 0 & zcheck) {
		z = selectindex(a :== 0)
		if (length(z)) {
			if (_fxc_raw(a[z]) != _fxc_raw(b[z])) {
				errprintf("%s: %s: sign of zero differs\n", what, v)
				exit(9)
			}
		}
	}
}

// The 8 bytes of every value of x, as stored.
string scalar _fxc_raw(real colvector x)
{
	string scalar s

	s = (8 * rows(x)) * " "
	bufput(bufio(), s, 0, "%8z", x)
	return(s)
}
end
