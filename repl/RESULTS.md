# fastata replication results

Generated 2026-10-16 00:21 by `repl report`. Arms: A original commands, B original with `set sortseed 20261015`, F fastata (installed and enabled in the sandbox).
A package counts when it was compared and arm F made at least one replaced-command call (fast or fallback).

## Totals

- counted packages: **3** (PASS 3, files with DIFF: 0)
- compared packages: 3; packages tried: 67
- file verdicts (all compared packages): SAME 62, NEAR 0, TIE 1, DIFF 0, SKIP 75, ERR 0

## Replaced commands (counted packages)

|command|packages|fast calls|fallback calls|call lines in source|
|---|---:|---:|---:|---:|
|`egen`|2|0|83|76|
|`isid`|0|0|0|0|
|`duplicates`|1|0|33|13|
|`xtile`|0|0|0|0|
|`pctile`|1|0|7|0|
|`destring`|2|0|91|75|
|`tostring`|2|0|4|22|

## Packages

|package|journal|year|DOI|title|A s|F s|F/A|calls (fast/fallback)|SAME|NEAR|TIE|DIFF|SKIP|verdict|
|---|---|---|---|---|---:|---:|---:|---|---:|---:|---:|---:|---:|---|
|dataverse-DCKKLW|REStat|2026|[10.7910/DVN/DCKKLW](https://doi.org/10.7910/DVN/DCKKLW)|Replication data for: When Transparency Fails: Financial Incentives for Local Banking Agen|0|0|1.00|destring 0/2, tostring 0/1|4|0|0|0|0|PASS|
|dataverse-F1MTEN|REStat|2026|[10.7910/DVN/F1MTEN](https://doi.org/10.7910/DVN/F1MTEN)|Replication data for: Firm Responses to Hiring and Investment Subsidies: Regression Discon|4|4|1.06|egen 0/4|6|0|0|0|3|PASS|
|dataverse-SHXCAH|REStat|2026|[10.7910/DVN/SHXCAH](https://doi.org/10.7910/DVN/SHXCAH)|Replication data for: How Credible are the Findings from Online Experiments?|113|103|0.91|destring 0/89, duplicates 0/33, egen 0/79, pctile 0/7, tostring 0/3|52|0|1|0|72|PASS|

## NEAR, TIE and DIFF files

|package|file|verdict|A vs F|A vs B|
|---|---|---|---|---|
|dataverse-SHXCAH|`<wrapper log>`|TIE|DIFF numbers differ (max reldif 0.003)|DIFF numbers differ (max reldif 0.0015)|

## Packages that dropped out

|stage: reason|packages|
|---|---:|
|scan: no master found|4|
|scan: dominated by other languages (4688 vs 831 lines)|1|
|scan: dominated by other languages (6956 vs 20 lines)|1|
|scan: no replaced-command call; dominated by other languages (11021 vs 0 lin|1|
|scan: no replaced-command call; dominated by other languages (10454 vs 0 lin|1|
|scan: no replaced-command call|1|
|scan: no replaced-command call; dominated by other languages (3271 vs 0 line|1|
|scan: no replaced-command call; dominated by other languages (5466 vs 0 line|1|
|scan: no replaced-command call; dominated by other languages (2683 vs 0 line|1|
|scan: no replaced-command call; dominated by other languages (4214 vs 0 line|1|
|scan: dominated by other languages (1515 vs 497 lines); no master found|1|
|scan: dominated by other languages (5164 vs 1714 lines); no master found|1|
|scan: no replaced-command call; dominated by other languages (3058 vs 0 line|1|
|scan: no replaced-command call; dominated by other languages (49986 vs 0 lin|1|
|scan: dominated by other languages (1150 vs 369 lines)|1|
|scan: no replaced-command call; dominated by other languages (6885 vs 0 line|1|
|scan: dominated by other languages (699 vs 23 lines)|1|
|scan: no replaced-command call; dominated by other languages (2127 vs 0 line|1|
|scan: dominated by other languages (10683 vs 4922 lines)|1|
|run_A: > <path> <path> not found r(601);|1|
|scan: dominated by other languages (6092 vs 1333 lines); no master found|1|
