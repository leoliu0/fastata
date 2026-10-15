# fastata replication results

Generated 2026-10-16 06:30 by `repl report`. Arms: A original commands; V fastata in verify mode (every fast call is checked against the original, which also decides the session state), compared strictly with A; A2 a second A run, for packages that are nondeterministic themselves (NONDET files). Packages compared with arm F (fastata as users run it, with tolerance; B = A with `set sortseed 20261015` for TIE files) are marked F.
A package counts when it was compared and its fastata arm made at least one replaced-command call (fast or fallback). A package fails on any DIFF or ERR file or any verify mismatch.

## Totals

- counted packages: **0** (PASS 0, files with DIFF: 0, verify mismatches: 0)
- verified calls (counted packages): ok 0, mismatch 0, skipped 0
- compared packages: 0; packages tried: 83
- file verdicts (all compared packages): SAME 0, NEAR 0, TIE 0, NONDET 0, DIFF 0, SKIP 0, ERR 0

## Replaced commands (counted packages)

|command|packages|fast calls|fallback calls|verify ok|verify mismatch|verify skipped|call lines in source|
|---|---:|---:|---:|---:|---:|---:|---:|
|`egen`|0|0|0|0|0|0|0|
|`isid`|0|0|0|0|0|0|0|
|`duplicates`|0|0|0|0|0|0|0|
|`xtile`|0|0|0|0|0|0|0|
|`pctile`|0|0|0|0|0|0|0|
|`destring`|0|0|0|0|0|0|0|
|`tostring`|0|0|0|0|0|0|0|

## Packages

|package|journal|year|DOI|title|arm|A s|arm s|arm/A|calls (fast/fallback)|verify ok/mismatch/skipped|SAME|NEAR|TIE|NONDET|DIFF|SKIP|verdict|
|---|---|---|---|---|---|---:|---:|---:|---|---|---:|---:|---:|---:|---:|---:|---|

## Verify mismatches

None.

## NEAR, TIE, NONDET and DIFF files

None.

## Packages that dropped out

|stage: reason|packages|
|---|---:|
|run_A: > <path> not found r(601);|9|
|run_A: file <path> not found r(601);|9|
|run_A: not found r(601);|3|
|run_A: <path> not found r(601);|2|
|run_A: > <path> <path> not found r(601);|2|
|run_A: found r(601);|2|
|run_A: > w_Comprehensive_October_21_2021.dta not found r(601);|1|
|run_A: > re.dta not found r(601);|1|
|run_A: file base_file_added.dta not found r(601);|1|
|run_A: <istmt>:  3499  fastile() not found r(3499);|1|
|run_A: unable to save PDF file r(691);|1|
|run_A: > I084_CB_A_YFRM_2014_JUN21_COMB_V01.dta not found r(601);|1|
|run_A: (error occurred while loading _gtools_internal.ado) r(3000);|1|
|run_A: command coefplot is unrecognized r(199);|1|
|run_A: file usa_00300.do not found r(601);|1|
|run_A: variable home not found r(111);|1|
|run_A: clearglobs not found r(111);|1|
|run_A: > up_insurance_bar.dta not found r(601);|1|
|run_A: > <path> could not be opened r(603);|1|
|run_A: <path> MS_20180234_AppendixTableA1.do not found r(601);|1|
|run_A: > inal.dta not found r(601);|1|
|run_A: command standardize_env is unrecognized r(199);|1|
|run_A: .     exit 601 r(601);|1|
|run_A: > d.tex could not be opened r(603);|1|
|run_A: file uber_usage_dataset.dta not found r(601);|1|
|run_A: > _performance.do not found r(601);|1|
|run_A: > baseline.do not found r(601);|1|
|run_A: file temp_supply_agg.dta not found r(601);|1|
|run_A: .     exit 111 r(111);|1|
|run_V: invalid syntax r(198);|1|
|run_A: empirical <path> not found r(601);|1|
|run_A: > on +string() r(133);|1|
|run_A: > ic345789_hes_apc_201299.dta not found r(601);|1|
|run_A: > dta not found r(601);|1|
|run_A: .     exit 499 r(499);|1|
|run_A: could not be opened r(603);|1|
|run_A: no FX_REPL_DONE in the log|1|
