* gen_gatelist.do -- writes stata/_fx_gatelist.ado, the gate list: for every gate key, the size
* and hash of each original file the key depends on, as installed in this Stata's BASE.
* fastata runs a command's fast path only when every file of its key matches a listed version
* (see _fx_verdict in stata/_fx.ado). Rows already in the list are kept, so running this under
* another Stata version (after the test suite passed there) adds that version's files.
* The list is an ado-file (one "* gate <key> <file> <bytes> <hash>" comment line per row)
* because net install installs ado-files but no .txt files.
* From the repository root:  stata-mp -b do scripts/gen_gatelist.do
version 16
clear all
set more off
adopath ++ "stata"

* Gate keys and the original files each depends on (helpers the original calls included).
local keys isid duplicates xtile pctile destring tostring
local files_isid       isid.ado _format_list.ado
local files_duplicates duplicates.ado
local files_xtile      xtile.ado pctile.ado _parsewt.ado
local files_pctile     pctile.ado _parsewt.ado
local files_destring   destring.ado _parse_ignore.ado
local files_tostring   tostring.ado _crcslbl.ado
* egen:<fn> keys: egen.ado, _g<fn>.ado and the helpers of _g<fn>.ado
local h_group  _egennoby.ado
local h_tag    _egennoby.ado
local h_total  _expression_to_variable.ado
local h_sum    _gtotal.ado _expression_to_variable.ado
local h_mean   _expression_to_variable.ado
local h_max    _expression_to_variable.ado
local h_min    _expression_to_variable.ado
local h_count
local h_median _egen_marksample.ado
local h_pctile _egen_marksample.ado
local h_iqr    _egen_marksample.ado
local h_sd     _expression_to_variable.ado
local h_std    _expression_to_variable.ado
local h_rank   _egen_marksample.ado _getnewlabelname.ado
foreach fn in group tag total sum mean max min count median pctile iqr sd std rank {
	local keys `keys' egen:`fn'
	local files_egen_`fn' egen.ado _g`fn'.ado `h_`fn''
}
foreach fn in rowtotal rowmean rowmax rowmin rowsd rowmiss rownonmiss {
	local keys `keys' egen:`fn'
	local files_egen_`fn' egen.ado _g`fn'.ado _egennoby.ado
}

mata:
fx_rows = J(0, 4, "")
fx_notes = J(0, 1, "")
end
foreach k of local keys {
	local kk = subinstr("`k'", ":", "_", .)
	foreach f of local files_`kk' {
		quietly findfile `f', path(BASE)
		local p `"`r(fn)'"'
		_fx filehash `"`p'"'
		mata: fx_rows = fx_rows \ ("`k'", "`f'", "`fx_bytes'", "`fx_hash'")
		mata: fx_notes = fx_notes \ ("*   " + "`f'" + ": " + strtrim(subinstr(subinstr(subinstr(subinstr(cat(st_local("p"))[1], char(13), ""), char(96), ""), char(39), ""), char(36), "")))
	}
}

mata:
void fx_write(string scalar out, string matrix rows, string colvector notes)
{
	string colvector old, lines
	string rowvector t
	string matrix g
	real scalar i, fh

	g = rows
	if (fileexists(out)) {
		old = cat(out)
		for (i = 1; i <= rows(old); i++) {
			if (substr(old[i], 1, 7) != "* gate ") continue
			t = tokens(substr(old[i], 8, .))
			if (cols(t) == 4) g = g \ t
		}
	}
	g = uniqrows(g)
	lines = "*! fastata gate list (written by scripts/gen_gatelist.do on " + c("current_date") + "; do not edit)" \
		"*! _fx_gates() in _fx.ado reads its * gate lines: gate key, original file, bytes and hash1 of" \
		"*! the file's text (lines without carriage returns, joined by newlines). The program does" \
		"*! nothing; the file is an ado-file so that net install installs it." \
		"* Files where the list was last written:" \
		uniqrows(notes)
	for (i = 1; i <= rows(g); i++) {
		lines = lines \ ("* gate " + g[i, 1] + " " + g[i, 2] + " " + g[i, 3] + " " + g[i, 4])
	}
	lines = lines \ "program _fx_gatelist" \ (char(9) + "version 16") \ "end"
	if (fileexists(out)) unlink(out)
	fh = fopen(out, "w")
	for (i = 1; i <= rows(lines); i++) fput(fh, lines[i])
	fclose(fh)
	printf("gen_gatelist: wrote %s (%g rows, %g keys)\n", out, rows(g), rows(uniqrows(g[., 1])))
}
fx_write("stata/_fx_gatelist.ado", fx_rows, fx_notes)
end
