*! fx_testdata: builds the fastata test dataset (30,000 obs, sorted by id) in the current frame.
*! Keys: id (unique), id2 (duplicated), g (40 groups, value-labelled), gbig (3 groups, so groups
*! cross the plugin's 8192-row blocks), str5 s (25 groups) and its strL copy sl, long zi (large
*! integer IDs). Values: x1 (with .a, .b and .z), x2 (~10% missing), float xf, byte xb, int xi,
*! long xl. Strings: str9 sn (numeric strings with 2% junk such as "NA" and "-"). Weights: w
*! (aw/pw), int fw (1-4), iw (some negative). th, u. x1 has a note and a characteristic.
program fx_testdata
	version 16
	clear
	set seed 20261015
	quietly {
		set obs 30000
		gen long id = _n
		gen long id2 = ceil(runiform()*20000)
		gen int g = ceil(runiform()*40)
		gen byte gbig = ceil(runiform()*3)
		gen str5 s = "s" + string(ceil(runiform()*25))
		gen strL sl = s
		gen long zi = 100000000 + floor(runiform()*2e9)
		gen double x1 = rnormal()*10 + 5
		replace x1 = .a if runiform() < .02
		replace x1 = .b if runiform() < .01
		replace x1 = .z if runiform() < .005
		gen double x2 = rnormal()*3 - 2 if runiform() > .1
		gen float xf = rnormal()*4 + 1
		gen byte xb = max(min(round(rnormal()*20), 100), -100)
		gen int xi = round(rnormal()*50)
		gen long xl = round(rnormal()*100)
		gen str9 sn = string(round(rnormal()*1000, .01))
		replace sn = cond(runiform() < .5, "NA", "-") if runiform() < .02
		gen double w = runiform() + .5
		gen int fw = ceil(runiform()*4)
		gen double iw = runiform() - .2
		gen double th = runiform()
		gen double u = runiform()
	}
	label define glab 1 "one" 2 "two" 3 "three"
	label values g glab
	label variable x1 "first x"
	label variable x2 "a long variable label, longer than sixty-five characters, to test truncation"
	label variable xb "byte x"
	note x1: a note on x1
	char x1[source] "simulated"
	sort id
end
