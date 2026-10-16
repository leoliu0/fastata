{smcl}
{* *! version 0.1.0  15oct2026}{...}
{vieweralsosee "[D] egen" "help egen"}{...}
{vieweralsosee "[D] isid" "help isid"}{...}
{vieweralsosee "[D] duplicates" "help duplicates"}{...}
{vieweralsosee "[D] pctile" "help xtile"}{...}
{vieweralsosee "[D] destring" "help destring"}{...}
{viewerjumpto "Syntax" "fastata##syntax"}{...}
{viewerjumpto "Description" "fastata##description"}{...}
{viewerjumpto "What runs fast" "fastata##coverage"}{...}
{viewerjumpto "Same results" "fastata##contract"}{...}
{viewerjumpto "Remarks" "fastata##remarks"}{...}
{title:Title}

{phang}
{bf:fastata} {hline 2} Fast official Stata data commands, with the same syntax and results


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:fastata} {opt enable}

{p 8 16 2}
{cmd:fastata} {opt disable}

{p 8 16 2}
{cmd:fastata} {opt on}

{p 8 16 2}
{cmd:fastata} {opt off}

{p 8 16 2}
{cmd:fastata} {opt status}


{marker description}{...}
{title:Description}

{pstd}
{cmd:fastata} makes these official commands fast: {helpb egen}, {helpb isid},
{helpb duplicates}, {helpb xtile}, {helpb pctile}, {helpb destring} and {helpb tostring}.
You keep typing the commands as before, in do-files, interactively, and when other
ado-files call them; the results, messages and errors are those of the original commands.
The computation runs in a compiled plugin that uses all processors.

{pstd}
For every call, {cmd:fastata} checks that the input is one it has been verified to handle.
Anything else (an option outside the supported set, an error condition, an unusual input)
runs the original command, which then gives its exact results and errors. {cmd:fastata} also
checks the original ado-files: if your Stata has versions of them other than the ones
{cmd:fastata} was verified against (for example after an update), it runs the originals until
a {cmd:fastata} update verifies the new versions.

{phang}
{opt enable} turns {cmd:fastata} on now and in every future Stata session, by adding a few
lines to your {cmd:profile.do} (the one Stata runs at startup; if you have none, it is created in
your PERSONAL directory). Run it once after installing.

{phang}
{opt disable} turns {cmd:fastata} off and removes those lines from {cmd:profile.do}.

{phang}
{opt on} and {opt off} turn {cmd:fastata} on or off for the current session only. With
{cmd:fastata off}, every command is the original.

{phang}
{opt status} shows whether {cmd:fastata} is on, how it starts, and for each command the
original file, whether that file is a verified version, and how many calls took the fast path
or ran the original in this session, with the reason for the last original run.


{marker coverage}{...}
{title:What runs fast}

{pstd}
The fast path covers the common forms of each command, with {cmd:if} and {cmd:in}, the
{cmd:by} prefix where the command allows it, and every numeric storage type. The original runs
in particular for:

{p2colset 5 20 22 2}{...}
{p2col:{helpb egen}}functions other than {cmd:count}, {cmd:group}, {cmd:iqr}, {cmd:max},
{cmd:mean}, {cmd:median}, {cmd:min}, {cmd:pctile}, {cmd:rank}, {cmd:rowmax}, {cmd:rowmean},
{cmd:rowmin}, {cmd:rowmiss}, {cmd:rownonmiss}, {cmd:rowsd}, {cmd:rowtotal}, {cmd:sd},
{cmd:std}, {cmd:sum}, {cmd:tag} and {cmd:total}; expressions with {cmd:_n}, {cmd:_N},
subscripts, time-series operators, random numbers, {cmd:r()} or {cmd:sum()}; string results;
integer result types that the values do not fit; options {cmd:autotype}, {cmd:label},
{cmd:lname}, {cmd:truncate}, {cmd:unique}, {cmd:suffix}{p_end}
{p2col:{helpb isid}}the {cmd:using} form{p_end}
{p2col:{helpb duplicates}}{cmd:browse}, and the error cases of the other subcommands{p_end}
{p2col:{helpb xtile}, {helpb pctile}}{cmd:cutpoints()}, {cmd:genp()}, {cmd:iweight}s,
{cmd:nquantiles()} above 1001, and weighted percentiles within rounding distance of a
cumulative weight{p_end}
{p2col:{helpb destring}}non-ASCII values, values Stata reads as hexadecimal numbers,
numbers longer than 64 characters or beyond Stata's range, calls under {cmd:version} 10 or
older{p_end}
{p2col:{helpb tostring}}{cmd:usedisplayformat}, formats other than {cmd:%}{it:W}{cmd:.0g}
and {cmd:%}{it:W}{cmd:.0f}, and non-integer values{p_end}
{p2colreset}{...}

{pstd}
Binary strL values, NaN values (which a plugin or Mata can store) in a variable the command
reads, and datasets with 2^32 or more observations always run the original.


{marker contract}{...}
{title:Same results}

{pstd}
On the fast path, {cmd:fastata} gives the same data as the original command (number and order
of observations and variables; storage types, display formats, variable and value labels,
notes and characteristics; values bitwise, including which missing code), the same sort order
marker, the same output in the Results window, the same errors and return codes, and the same
documented stored results. There are three documented exceptions:

{phang2}
1. The original commands sort the data internally, and Stata orders ties in a sort randomly.
{cmd:fastata} does not sort, so a later command that depends on the order of ties (for
example a {cmd:sort} with ties followed by {cmd:_n}) may give a different, equally valid
order. For the same reason, when a variable holds both -0 and +0 (both display as 0;
{cmd:gen double y = -x}, for example, stores -0 where {cmd:x} is 0), the sign of a zero that
{cmd:egen}'s {cmd:max}, {cmd:min}, {cmd:median}, {cmd:pctile} or {cmd:iqr} returns within groups
may differ: the original's follows the random order of these ties.

{phang2}
2. Results that commands not documented as storing results leave behind in {cmd:r()} (for
example after {cmd:egen}, {cmd:xtile} or {cmd:destring}) are not reproduced.

{phang2}
3. {cmd:egen}'s {cmd:total}, {cmd:sum}, {cmd:mean}, {cmd:sd} and {cmd:std} computed within
groups: the original adds the values in the order of its internal sort, whose ties are random,
so its own results vary in the last digits from run to run. {cmd:fastata}'s results are
within 1 unit in the last place (float) or a relative difference of 1e-13 (double) of the
original's.


{marker remarks}{...}
{title:Remarks}

{pstd}
{cmd:fastata} uses all processors of your Stata/MP licence, or all logical processors with
Stata/SE and Stata/BE. Results do not depend on the number of processors.

{pstd}
{cmd:fastata} replaces the commands through Stata's ado-path: {cmd:fastata on} puts a
directory with its versions of the seven ado-files first on the ado-path, so that
{cmd:which egen} shows {cmd:fastata}'s file. Programs that call the commands use them too.
A {cmd:profile.do} in the directory where Stata starts takes precedence over the one
{cmd:fastata enable} writes; {cmd:fastata enable} tells you when this happens.

{pstd}
If you suspect {cmd:fastata} in a result, run the command again after {cmd:fastata off}.
Please report any difference at {browse "https://github.com/leoliu0/fastata/issues"}.

{pstd}
To check {cmd:fastata} on your own code, set the environment variable {cmd:FASTATA_MODE} to
{cmd:verify} before you start Stata. Every call that takes the fast path then also runs the
original command, quietly, on a copy of the data made before the call, compares the two
results and keeps the original's, so the whole run gives the original's results;
{cmd:fastata status} shows how many calls agreed. If the environment variable
{cmd:FASTATA_COUNTS} names a file, every call also appends a line to that file, and a call
that disagrees records the first difference. Verify mode is slower than the original.


{title:Author}

{pstd}
Leo Liu, auleo.liu@gmail.com{break}
{browse "https://github.com/leoliu0/fastata"}
