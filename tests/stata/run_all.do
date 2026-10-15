* run_all.do -- fastata Stata test suite (needs stata/fastata.plugin, built by
* scripts/build_plugin.sh). From tests/stata:
*   stata-mp -b do run_all.do      -> last line of run_all.log: ALL TESTS PASSED
* It ends with 300 cases of test_random.do; the full 3000 run on their own (do test_random.do).
* The runtime directory goes to tests/stata/_plus/fastata/ (see fx_setup.ado). tests/startup_test.sh
* is a separate end-to-end check of net install, fastata enable and a fresh session.
version 16
clear all
set more off
local here `c(pwd)'
foreach t in test_framework test_fallback test_egen calib_egen test_dup test_strnum calib_strnum test_quant calib_pctile "test_random 300" {
	di as text _n "{hline 78}" _n "running `t'" _n "{hline 78}"
	quietly cd "`here'"
	do `t'
}
quietly cd "`here'"

* finish inside a program so that "ALL TESTS PASSED" is the last line of the batch log
capture program drop fx_finish
program fx_finish
	di as result "ALL TESTS PASSED"
	exit, STATA clear
end
fx_finish
