* test_dup.do -- fast paths of isid and duplicates against the originals (fx_both: data, sort
* marker, output, return code, r()). Keys: numeric, str#, strL, mixed, missing codes, -0, ties,
* case, prefixes and non-ASCII bytes; if/in; sorted and unsorted data; datasets around the
* plugin's 8192- and 65536-observation blocks; the tag type rule; error cases (fast for isid, the
* original for duplicates) and forms that must fall back. Ends with TEST_DUP passed <n> specs.
version 16
clear all
set more off
fx_setup
quietly fastata on

fx_testdata
quietly {
	* 0, 1 and -0 (Stata expressions turn -0 into 0; Mata stores it)
	gen double nz = mod(_n, 3) == 2
	mata: st_store(selectindex(mod(1::st_nobs(), 3) :== 0), "nz", J(floor(st_nobs()/3), 1, -(1e-300*1e-300)))
	mata: _b = bufio(); _s = 8*" "; bufput(_b, _s, 0, "%8z", st_data(3, "nz")); assert(ascii(_s)[8] == 128)
	gen str2 sc = cond(u < .25, "a", cond(u < .5, "A", cond(u < .75, "ab", "B")))
	gen str3 su = cond(th < .3, "e", cond(th < .6, "z", "é"))
	gen str2 sb = cond(th < .5, " a", "a")
	gen long idr = 30001 - id
	gen double xd = round(x2, .5)
	gen float ft = round(xf)
	gen str20 sw = "w" + string(mod(id2, 7)) + "-" + string(mod(id2, 3))
	* strL values longer than any str#
	gen strL sll = s*500 + string(mod(_n, 4))
}
char xb[varname] "BX"
frame copy default base
frame copy default bg
frame bg: sort g id
* sorted by a key holding both 0 and -0 (sort and by treat them as equal)
frame copy default bz
frame bz: sort nz su
* whole-row duplicates: every 7th observation twice
frame copy default bx
frame bx {
	quietly expand 2 if mod(_n, 7) == 0
}
frame create empty
frame empty {
	quietly set obs 5
	gen long id = _n
	gen str3 s = "a"
	quietly drop in 1/5
}

capture program drop ff
program ff
	args cmd ecmd kind frame
	if "`frame'" == "" local frame base
	local r
	if "`ecmd'" == "duplicates" local r allr
	fx_both `"`cmd'"', base(`frame') `r' expect(`ecmd' `kind')
	global FD_N = $FD_N + 1
end
global FD_N 0

* ---------------------------------------------------------------- isid: fast
ff "isid id" isid fast
ff "isid id2" isid fast
ff "isid g id" isid fast
ff "isid x2" isid fast
ff "isid x2, missok" isid fast
ff "isid x1 id, missok" isid fast
ff "isid x1 id" isid fast
ff "isid s sl id" isid fast
ff "isid s g" isid fast
ff "isid zi" isid fast
ff "isid idr" isid fast
ff "isid sc id" isid fast
ff "isid sw id2 g" isid fast
ff "isid nz" isid fast
ff "isid nz id" isid fast
ff "isid nz idr" isid fast bz
ff "isid nz sc" isid fast bz
ff "isid ft id, missok" isid fast
ff "isid id, sort" isid fast
ff "isid idr, sort" isid fast
ff "isid idr g, sort missok" isid fast
ff "isid g id, sort" isid fast bg
ff "isid g, sort" isid fast bg
ff "isid id g, sort" isid fast bg
ff "isid id, s m" isid fast bg
ff "version 12: isid id" isid fast
ff "isid id" isid fast empty
ff "isid s" isid fast empty
ff "isid id" isid fast bx
ff "isid i*" isid fast

* ---------------------------------------------------------------- isid: fallback
ff "isid id if u < .5" isid fallback
ff "isid id using nosuchfile" isid fallback
ff "isid sb id" isid fallback
ff "isid su id" isid fallback
ff "isid nosuchvar" isid fallback
ff "isid id, foo" isid fallback

* ---------------------------------------------------------------- duplicates report
ff "duplicates report g" duplicates fast
ff "duplicates report id" duplicates fast
ff "duplicates report g s" duplicates fast
ff "duplicates report" duplicates fast
ff "duplicates report" duplicates fast bx
ff "duplicates report gbig sc if u < .5" duplicates fast
ff "duplicates report x1 in 100/20000" duplicates fast
ff "duplicates report nz" duplicates fast
ff "duplicates report sl gbig" duplicates fast
ff "duplicates r g, whatever" duplicates fast
ff "duplicates rep id2 g" duplicates fast
ff "duplicates report id2" duplicates fast
ff "duplicates report xd ft su" duplicates fast
ff "version 12: duplicates report g" duplicates fast

* ---------------------------------------------------------------- duplicates tag
ff "duplicates tag g s, gen(dt)" duplicates fast
ff "duplicates tag id2 if u < .5, gen(dt)" duplicates fast
ff "duplicates tag, gen(dt)" duplicates fast
ff "duplicates tag, gen(dt)" duplicates fast bx
ff "duplicates tag gbig, gen(dt)" duplicates fast
ff "duplicates tag id, gen(dt)" duplicates fast
ff "duplicates tag x1 xd, g(dt)" duplicates fast
ff "duplicates t sc su nz in 10/29000, generate(dt)" duplicates fast
ff "duplicates tag g if g > 100, gen(dt)" duplicates fallback
ff "duplicates tag sl, gen(dt)" duplicates fast bg

* ---------------------------------------------------------------- duplicates drop
ff "duplicates drop g s, force" duplicates fast
ff "duplicates drop" duplicates fast
ff "duplicates drop" duplicates fast bx
ff "duplicates drop if u < .5" duplicates fast bx
ff "duplicates drop id2, force" duplicates fast
ff "duplicates drop id2 if u < .3, force" duplicates fast
ff "duplicates drop gbig sc in 5000/25000, force" duplicates fast
ff "duplicates drop id, force" duplicates fast
ff "duplicates drop x1 su, force" duplicates fast bg
ff "duplicates drop sl nz, force" duplicates fast
ff "duplicates drop nz sc, force" duplicates fast bz
ff "duplicates tag nz, gen(dt)" duplicates fast bz
ff "duplicates report nz su" duplicates fast bz

* ---------------------------------------------------------------- duplicates examples, list
ff "duplicates examples gbig" duplicates fast
ff "duplicates examples g s" duplicates fast
ff "duplicates examples gbig if gbig == 1" duplicates fast
ff "duplicates examples sc su xb" duplicates fast
ff "duplicates examples x1 nz, clean" duplicates fast
ff "duplicates examples nz sc if u < .2" duplicates fast bz
ff "duplicates e g, sep(0) ab(4)" duplicates fast
ff "duplicates examples id" duplicates fast
ff "duplicates list gbig s if id < 300" duplicates fast
ff "duplicates list id2 if id < 2000" duplicates fast
ff "duplicates list x1 xd in 1/500, sep(0)" duplicates fast
ff "duplicates list sl if id < 200" duplicates fast
ff "duplicates l su sc g if u < .01, noheader nolabel" duplicates fast
ff "duplicates list g gbig if id < 500, divider string(1)" duplicates fast bg
ff "duplicates list if id < 60" duplicates fast bx
ff "duplicates list id" duplicates fast

* ---------------------------------------------------------------- duplicates: fallback
ff "duplicates browse g" duplicates fallback
ff "duplicates drop g" duplicates fallback
ff "duplicates drop, force" duplicates fallback
ff "duplicates d g, force" duplicates fallback
ff "duplicates tag g, gen(id)" duplicates fallback
ff "duplicates tag g, gen(a b)" duplicates fallback
ff "duplicates tag g" duplicates fallback
ff "duplicates report if u > 2" duplicates fallback
ff "duplicates foo g" duplicates fallback
ff "duplicates" duplicates fallback
ff "duplicates list g if id < 50, sepby(gbig)" duplicates fallback
ff "duplicates list g g if id < 50" duplicates fallback
ff "duplicates examples g, noobs" duplicates fallback
ff "duplicates report nosuchvar" duplicates fallback

* ---------------------------------------------------------------- block boundaries
foreach n in 8191 8192 8193 65537 {
	frame create sz`n'
	frame sz`n' {
		set seed `n'
		quietly set obs `n'
		gen double u = runiform()
		gen long k = floor(_n/3)
		gen str4 ks = "k" + string(mod(_n, 50))
		gen double v = cond(mod(_n, 11) == 0, .a, mod(_n, 4))
		gen long id = _n
		sort u
	}
	ff "duplicates tag k, gen(dt)" duplicates fast sz`n'
	ff "duplicates drop k ks, force" duplicates fast sz`n'
	ff "duplicates report k v" duplicates fast sz`n'
	ff "duplicates report ks v if u < .7" duplicates fast sz`n'
	ff "duplicates list k ks if k < 7" duplicates fast sz`n'
	ff "isid k" isid fast sz`n'
	ff "isid id ks" isid fast sz`n'
	ff "isid k v ks, missok" isid fast sz`n'
}

* one group of 40000: tag stored as long
frame create big
frame big {
	quietly set obs 40000
	gen byte c = 1
	gen byte d = _n <= 33000
	* largest tag 100 (byte), 101 (int), 32740 (int), 32741 (long)
	foreach m in 101 102 32741 32742 {
		gen byte e`m' = _n <= `m'
	}
}
ff "duplicates tag c, gen(dt)" duplicates fast big
ff "duplicates tag d, gen(dt)" duplicates fast big
foreach m in 101 102 32741 32742 {
	ff "duplicates tag e`m' if _n <= `m' + 3, gen(dt)" duplicates fast big
}
ff "duplicates report d" duplicates fast big

* mixed storage types, long strL keys, in ranges from the end
ff "duplicates report xb xi" duplicates fast
ff "duplicates drop xl xb, force" duplicates fast
ff "duplicates examples sll gbig" duplicates fast
ff "duplicates tag g in -100/l, gen(dt)" duplicates fast
ff "isid xb xi xl id" isid fast
ff "isid sll id" isid fast
ff "isid sll gbig" isid fast

* quietly and capture around the command
ff "quietly duplicates drop g s, force" duplicates fast
ff "quietly duplicates report g" duplicates fast
ff "quietly duplicates report if u > 2" duplicates fallback
ff "quietly isid id2" isid fast
ff "capture isid id2" isid fast

* Group in double under set type double
set type double
ff "duplicates list g if id < 100" duplicates fast
ff "duplicates examples s" duplicates fast
set type float

* 50 observations: c(obs_t) is byte
frame create small
frame small {
	set seed 5
	quietly set obs 50
	gen byte k = ceil(runiform()*6)
	gen str1 t = cond(runiform() < .5, "x", "y")
}
ff "duplicates report k" duplicates fast small
ff "duplicates report k t" duplicates fast small
ff "duplicates examples k" duplicates fast small
ff "duplicates list k t" duplicates fast small
ff "duplicates tag k, gen(dt)" duplicates fast small
ff "duplicates drop k, force" duplicates fast small
frame copy base bnan
frame bnan {
	* NaN bit patterns (a plugin or Mata's st_store() can leave one in a variable): xn (x1)
	quietly gen double xn = x1
	mata: _tn_b = bufio(); bufbyteorder(_tn_b, 1)
	mata: _tn_nan = bufget(_tn_b, char((255, 254, 83, 248, 0, 0, 0, 0)), 0, "%8z", 1)
	mata: st_store((3 \ 25000), "xn", J(2, 1, _tn_nan))
}
* ---------------------------------------------------------------- NaN values
* a NaN in a key runs the original, whose sort then never returns (src/dup.rs tests; not run
* here); a NaN in a variable the call does not read changes nothing
ff "isid id" isid fast bnan
ff "isid g id, missok" isid fast bnan
ff "duplicates report g" duplicates fast bnan
ff "duplicates tag g s, gen(dt)" duplicates fast bnan
ff "duplicates drop g gbig, force" duplicates fast bnan


di as result "TEST_DUP passed $FD_N specs"
