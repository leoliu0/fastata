*! fx_setup: test environment. Run from tests/stata. Puts the repository's stata directory first
*! on the ado-path (as an absolute path) and points PLUS at tests/stata/_plus/, so that fastata's
*! runtime directory is tests/stata/_plus/fastata/ and the user's own PLUS is not searched. Erases
*! that runtime directory, so that the next fastata on builds it from the repository's current
*! files (ado-files and plugin). Turns the small-data cutoff off (_fx small off), so that calls on
*! small test data take the fast path; clear all turns it on again.
*! Sets global FX_STATA (the stata directory) and FX_TESTS (tests/stata), both with a trailing /.
program fx_setup
	version 16
	local here `"`c(pwd)'"'
	quietly cd "../../stata"
	global FX_STATA `"`c(pwd)'/"'
	quietly cd `"`here'"'
	global FX_TESTS `"`here'/"'
	quietly adopath ++ `"$FX_STATA"'
	capture mkdir `"`here'/_plus"'
	sysdir set PLUS `"`here'/_plus/"'
	_fx rmruntime `"`here'/_plus/fastata/"'
	_fx small off
end
