*! _fxrepl_cmpdta "<pairs.txt>" "<out.csv>": compares pairs of .dta files for the replication
*! harness. pairs.txt has lines id|fileA|fileB; out.csv gets id,verdict,detail with verdict
*!   SAME  identical: N, variable names and order, sort order, data label, storage types, formats,
*!         variable and value-label names, characteristics (notes included), value-label
*!         definitions, and every value (strings and missing codes exact, numbers bitwise);
*!   NEAR  identical except numbers within tolerance: float within 1 float ulp, double reldif
*!         <= 1e-9 (byte, int and long must be exact);
*!   DIFF  anything else (detail says what differs first);
*!   ERR   a file could not be read.
*! Based on fastata's tests/stata/fx_cmpframes.ado.
program _fxrepl_cmpdta
	version 16
	args pairs out
	tempname fi fo
	file open `fi' using `"`pairs'"', read text
	file open `fo' using `"`out'"', write text replace
	file write `fo' "id,verdict,detail" _n
	file read `fi' line
	while r(eof) == 0 {
		gettoken id rest : line, parse("|")
		gettoken bar rest : rest, parse("|")
		gettoken fa rest : rest, parse("|")
		gettoken bar fb : rest, parse("|")
		local verdict ERR
		local detail
		capture frame drop _fxa
		capture frame drop _fxb
		frame create _fxa
		frame create _fxb
		capture frame _fxa: use `"`fa'"', clear
		local rca = _rc
		capture frame _fxb: use `"`fb'"', clear
		local rcb = _rc
		if `rca' | `rcb' {
			local detail "use failed: r(`rca') r(`rcb')"
		}
		else {
			_fxrepl_cmp1 _fxa _fxb
			local verdict `fx_verdict'
			local detail `"`fx_detail'"'
		}
		local detail = subinstr(`"`detail'"', `"""', "'", .)
		file write `fo' `"`id',`verdict',"`detail'""' _n
		capture frame drop _fxa
		capture frame drop _fxb
		file read `fi' line
	}
	file close `fi'
	file close `fo'
end

program _fxrepl_cmp1
	args fa fb
	mata: _fxrepl_cmphead("`fa'", "`fb'")
	if "`fx_verdict'" == "" mata: _fxrepl_cmpall("`fa'", "`fb'")
	c_local fx_verdict `fx_verdict'
	c_local fx_detail `"`fx_detail'"'
end

mata:
// N, variables, sort order, data label, and per variable: type, format, value-label name,
// variable label. Sets fx_verdict DIFF and fx_detail on the first difference.
string matrix _fxrepl_head(string scalar fr)
{
	string scalar cur
	string matrix out
	real scalar i

	cur = st_framecurrent()
	st_framecurrent(fr)
	stata("local _fxs : sortedby")
	stata("local _fxd : data label")
	out = ("", "N", strofreal(st_nobs(), "%20.0f")) \ ("", "sort order", st_local("_fxs")) \
		("", "data label", st_local("_fxd")) \ ("", "variables", invtokens(st_nvar() ? st_varname(1..st_nvar()) : J(1, 0, "")))
	for (i = 1; i <= st_nvar(); i++) {
		out = out \ (st_varname(i), "type", st_vartype(i)) \ (st_varname(i), "format", st_varformat(i)) \
			(st_varname(i), "value label name", st_varvaluelabel(i)) \
			(st_varname(i), "variable label", st_varlabel(i))
	}
	st_framecurrent(cur)
	return(out)
}

// Sets fx_verdict DIFF and fx_detail when N, the variables, the sort order, the data label or a
// variable's type, format, value-label name or label differ; fx_verdict "" otherwise.
void _fxrepl_cmphead(string scalar fa, string scalar fb)
{
	string matrix a, b
	real scalar i

	a = _fxrepl_head(fa)
	b = _fxrepl_head(fb)
	st_local("fx_verdict", "")
	for (i = 1; i <= rows(a); i++) {
		if (a[i, 3] != b[i, 3]) {
			st_local("fx_verdict", "DIFF")
			st_local("fx_detail", (a[i, 1] != "" ? a[i, 1] + ": " : "") + a[i, 2] + " differs" +
				(i <= 2 ? " (" + a[i, 3] + " vs " + b[i, 3] + ")" : ""))
			return
		}
	}
}

string colvector _fxrepl_meta(string scalar fr)
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
	labs = sort(tokens(st_global("r(names)"))', 1)
	for (i = 1; i <= rows(labs); i++) {
		st_vlload(labs[i], vals, txt)
		for (j = 1; j <= rows(vals); j++) {
			out = out \ ("label " + labs[i] + " " + strofreal(vals[j], "%21x") + " = " + txt[j])
		}
	}
	st_framecurrent(cur)
	return(out)
}

// 0 same, 1 near, 2 differs
real scalar _fxrepl_cmpvar(string scalar fa, string scalar fb, string scalar v, string scalar detail)
{
	string scalar cur, typ
	string colvector sa, sb
	real colvector a, b, ma, mb, x, y, d
	real scalar str

	cur = st_framecurrent()
	st_framecurrent(fa)
	str = st_isstrvar(v)
	typ = st_vartype(v)
	if (str) sa = st_sdata(., v)
	else a = st_data(., v)
	st_framecurrent(fb)
	if (str) sb = st_sdata(., v)
	else b = st_data(., v)
	st_framecurrent(cur)
	if (str) {
		if (sa == sb) return(0)
		detail = v + ": strings differ in " + strofreal(sum(sa :!= sb)) + " obs"
		return(2)
	}
	if (a == b) return(0)
	ma = a :>= .
	mb = b :>= .
	if (ma != mb) {
		detail = v + ": missing patterns differ in " + strofreal(sum(ma :!= mb)) + " obs"
		return(2)
	}
	if (any(select(a, ma) :!= select(b, mb))) {
		detail = v + ": missing codes differ"
		return(2)
	}
	x = select(a, !ma)
	y = select(b, !mb)
	if (typ == "float") {
		d = abs(x - y) :<= rowmax((abs(x), abs(y))) * 2^-23
	}
	else if (typ == "double") {
		d = reldif(x, y) :<= 1e-9
	}
	else d = (x :== y)
	if (all(d)) {
		detail = v + ": " + typ + " values differ within tolerance in " + strofreal(sum(x :!= y)) + " obs"
		return(1)
	}
	detail = v + ": values differ in " + strofreal(sum(!d)) + " obs (max reldif "	+
		strofreal(max(reldif(x, y)), "%9.2g") + ")"
	return(2)
}

void _fxrepl_cmpall(string scalar fa, string scalar fb)
{
	string colvector ma, mb, vars
	string scalar detail, first_near, cur
	real scalar i, r, worst

	ma = _fxrepl_meta(fa)
	mb = _fxrepl_meta(fb)
	if (rows(ma) != rows(mb) || ma != mb) {
		st_local("fx_verdict", "DIFF")
		st_local("fx_detail", "characteristics, notes or value labels differ")
		return
	}
	cur = st_framecurrent()
	st_framecurrent(fa)
	vars = st_nvar() ? st_varname(1..st_nvar())' : J(0, 1, "")
	st_framecurrent(cur)
	worst = 0
	first_near = ""
	for (i = 1; i <= rows(vars); i++) {
		detail = ""
		r = _fxrepl_cmpvar(fa, fb, vars[i], detail)
		if (r == 2) {
			st_local("fx_verdict", "DIFF")
			st_local("fx_detail", detail)
			return
		}
		if (r == 1 & first_near == "") first_near = detail
		if (r > worst) worst = r
	}
	st_local("fx_verdict", worst ? "NEAR" : "SAME")
	st_local("fx_detail", first_near)
}
end
