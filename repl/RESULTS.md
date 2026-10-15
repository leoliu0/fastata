# fastata replication results

Generated 2026-10-16 01:27 by `repl report`. Arms: A original commands, B original with `set sortseed 20261015`, F fastata (installed and enabled in the sandbox).
A package counts when it was compared and arm F made at least one replaced-command call (fast or fallback).

## Totals

- counted packages: **9** (PASS 8, files with DIFF: 2)
- compared packages: 10; packages tried: 147
- file verdicts (all compared packages): SAME 216, NEAR 0, TIE 5, DIFF 2, SKIP 157, ERR 13

## Replaced commands (counted packages)

|command|packages|fast calls|fallback calls|call lines in source|
|---|---:|---:|---:|---:|
|`egen`|8|0|874|219|
|`isid`|2|0|11|11|
|`duplicates`|2|0|35|23|
|`xtile`|0|0|0|4|
|`pctile`|1|0|7|0|
|`destring`|4|0|95|168|
|`tostring`|3|0|5|32|

## Packages

|package|journal|year|DOI|title|A s|F s|F/A|calls (fast/fallback)|SAME|NEAR|TIE|DIFF|SKIP|verdict|
|---|---|---|---|---|---:|---:|---:|---|---:|---:|---:|---:|---:|---|
|dataverse-AQJWOH|QJE|2026|[10.7910/DVN/AQJWOH](https://doi.org/10.7910/DVN/AQJWOH)|Replication Data for: 'How Does Wage Inequality Affect the Labor Movement?'|6|7|1.06|destring 0/1, egen 0/21, tostring 0/1|3|0|0|0|31|PASS|
|dataverse-DCKKLW|REStat|2026|[10.7910/DVN/DCKKLW](https://doi.org/10.7910/DVN/DCKKLW)|Replication data for: When Transparency Fails: Financial Incentives for Local Banking Agen|0|0|1.00|destring 0/2, tostring 0/1|4|0|0|0|0|PASS|
|dataverse-F1MTEN|REStat|2026|[10.7910/DVN/F1MTEN](https://doi.org/10.7910/DVN/F1MTEN)|Replication data for: Firm Responses to Hiring and Investment Subsidies: Regression Discon|4|4|1.06|egen 0/4|6|0|0|0|3|PASS|
|dataverse-ICNB18|JPE Micro|2026|[10.7910/DVN/ICNB18](https://doi.org/10.7910/DVN/ICNB18)|Replication Data for: Attention as a First-Order Barrier to Adoption of Evidence-based Pro|8|3|0.41|egen 0/3|23|0|0|0|0|PASS|
|dataverse-JD0W1S|RFS|2026|[10.7910/DVN/JD0W1S](https://doi.org/10.7910/DVN/JD0W1S)|Replication Package for: Financial Advice and Investor Beliefs: Experimental Evidence on A|5|5|1.02|egen 0/96, isid 0/1|28|0|0|0|10|PASS|
|dataverse-KIDK6R|RFS|2026|[10.7910/DVN/KIDK6R](https://doi.org/10.7910/DVN/KIDK6R)|Replication Package for: The Coherence Side of Rationality: Theory and Evidence from Firm |311|305|0.98|duplicates 0/2, egen 0/627, isid 0/10|37|0|0|2|4|FAIL|
|dataverse-NYXW03|JPE|2026|[10.7910/DVN/NYXW03](https://doi.org/10.7910/DVN/NYXW03)|Replication Data for: Not Learning from Others|17|15|0.93|egen 0/10|22|0|0|0|30|PASS|
|dataverse-SHXCAH|REStat|2026|[10.7910/DVN/SHXCAH](https://doi.org/10.7910/DVN/SHXCAH)|Replication data for: How Credible are the Findings from Online Experiments?|113|103|0.91|destring 0/89, duplicates 0/33, egen 0/79, pctile 0/7, tostring 0/3|52|0|1|0|72|PASS|
|dataverse-YXWBGX|JPE Macro|2026|[10.7910/DVN/YXWBGX](https://doi.org/10.7910/DVN/YXWBGX)|Replication Data for: Size Matters: Matching Externalities and the Advantages of Large Lab|0|0|||3|0|0|0|0|PASS (not counted)|
|dataverse-ZIXTGH|REStat|2026|[10.7910/DVN/ZIXTGH](https://doi.org/10.7910/DVN/ZIXTGH)|Replication data for: Gender Discrimination in Access to Capital: A Field Experiment in Et|80|89|1.11|destring 0/3, egen 0/34|38|0|4|0|7|PASS|

## NEAR, TIE and DIFF files

|package|file|verdict|A vs F|A vs B|
|---|---|---|---|---|
|dataverse-KIDK6R|`<wrapper log>`|DIFF|DIFF line 45: '[2]  (BASE)      "/home/leo/.local/bin/ado/base/"' vs '[2]              "<RUN>/_fxrepl_home/ado/plus/fastata/"'|SAME |
|dataverse-KIDK6R|`InCoherence_replication_portable_code/data/analysis/compustat_dukecfo_9919_mergedwide_aug.dta`|ERR|ERR use failed: r(900) r(900)|ERR use failed: r(900) r(900)|
|dataverse-KIDK6R|`InCoherence_replication_portable_code/data/analysis/compustat_dukecfo_9919_mergedwide_aug_augmented.dta`|ERR|ERR use failed: r(900) r(900)|ERR use failed: r(900) r(900)|
|dataverse-KIDK6R|`InCoherence_replication_portable_code/data/analysis/compustat_dukecfo_9919_mergedwide_aug_augmented2.dta`|ERR|ERR use failed: r(900) r(900)|ERR use failed: r(900) r(900)|
|dataverse-KIDK6R|`InCoherence_replication_portable_code/data/analysis/compustat_dukecfo_9919_mergedwide_aug_augmented3.dta`|ERR|ERR use failed: r(900) r(900)|ERR use failed: r(900) r(900)|
|dataverse-KIDK6R|`InCoherence_replication_portable_code/data/analysis/compustat_dukecfo_9919_mergedwide_aug_augmentedregvars.dta`|ERR|ERR use failed: r(900) r(900)|ERR use failed: r(900) r(900)|
|dataverse-KIDK6R|`InCoherence_replication_portable_code/data/analysis/compustat_dukecfo_9919_mergedwide_aug_augmentedregvars_adv.dta`|ERR|ERR use failed: r(900) r(900)|ERR use failed: r(900) r(900)|
|dataverse-KIDK6R|`InCoherence_replication_portable_code/data/analysis/compustat_dukecfo_9919_mergedwide_aug_augmentedregvars_cpx.dta`|ERR|ERR use failed: r(900) r(900)|ERR use failed: r(900) r(900)|
|dataverse-KIDK6R|`InCoherence_replication_portable_code/data/analysis/compustat_dukecfo_9919_mergedwide_aug_augmentedregvars_panel.dta`|ERR|ERR use failed: r(900) r(900)|ERR use failed: r(900) r(900)|
|dataverse-KIDK6R|`InCoherence_replication_portable_code/data/analysis/compustat_dukecfo_9919_mergedwide_aug_augmentedregvars_panel_adv.dta`|ERR|ERR use failed: r(900) r(900)|ERR use failed: r(900) r(900)|
|dataverse-KIDK6R|`InCoherence_replication_portable_code/data/analysis/compustat_dukecfo_9919_mergedwide_aug_augmentedregvars_panel_allCFOs.dta`|ERR|ERR use failed: r(900) r(900)|ERR use failed: r(900) r(900)|
|dataverse-KIDK6R|`InCoherence_replication_portable_code/data/analysis/compustat_dukecfo_9919_mergedwide_aug_augmentedregvars_singleCFOs.dta`|ERR|ERR use failed: r(900) r(900)|ERR use failed: r(900) r(900)|
|dataverse-KIDK6R|`InCoherence_replication_portable_code/data/analysis/compustat_dukecfo_9919_mergedwide_aug_augmentedregvars_singleCFOs2.dta`|ERR|ERR use failed: r(900) r(900)|ERR use failed: r(900) r(900)|
|dataverse-KIDK6R|`InCoherence_replication_portable_code/data/analysis/compustat_dukecfo_9919_mergedwide_aug_augmentedregvars_singleCFOs_cpx.dta`|ERR|ERR use failed: r(900) r(900)|ERR use failed: r(900) r(900)|
|dataverse-KIDK6R|`InCoherence_replication_portable_code/results/log/main.log`|DIFF|DIFF line 34: '[2]  (BASE)      "/home/leo/.local/bin/ado/base/"' vs '[2]              "<RUN>/_fxrepl_home/ado/plus/fastata/"'|SAME |
|dataverse-SHXCAH|`<wrapper log>`|TIE|DIFF numbers differ (max reldif 0.003)|DIFF numbers differ (max reldif 0.0015)|
|dataverse-ZIXTGH|`<wrapper log>`|TIE|DIFF line 10181: 'F(35, 9)          =       .' vs 'F(34, 9)          =       .'|DIFF line 10301: 'F(35, 9)          =       .' vs 'F(36, 9)          =       .'|
|dataverse-ZIXTGH|`EDC Replication Package/Data/Datasets/applicant_endline.dta`|TIE|DIFF month: missing patterns differ in 311 obs|DIFF month: missing patterns differ in 288 obs|
|dataverse-ZIXTGH|`EDC Replication Package/Data/Datasets/evaluations.dta`|TIE|DIFF A3: missing patterns differ in 36 obs|DIFF A3: missing patterns differ in 36 obs|
|dataverse-ZIXTGH|`EDC Replication Package/Data/Datasets/loan_officers.dta`|TIE|DIFF A3: missing patterns differ in 36 obs|DIFF A3: missing patterns differ in 36 obs|

## Packages that dropped out

|stage: reason|packages|
|---|---:|
|scan: dominated by other languages|48|
|scan: no replaced-command call|34|
|scan: no do-files|29|
|fetch: no Stata do-file|13|
|scan: no master found|12|
|run_A: file <path> not found r(601);|8|
|run_A: - install from GitHub r(9);|5|
|run_A: > <path> <path> not found r(601);|2|
|run_A: > <path> r(170);|2|
|run_A: not found r(601);|2|
|run_A: > <path> not found r(601);|1|
|run_A: > w_Comprehensive_October_21_2021.dta not found r(601);|1|
|run_A: > re.dta not found r(601);|1|
|run_A: command cls is unrecognized r(199);|1|
|run_A: > ubmission <path> <path> r(170);|1|
|run_A: <istmt>:  3499  fastile() not found r(3499);|1|
|run_A: unable to save PDF file r(691);|1|
|run_A: > I084_CB_A_YFRM_2014_JUN21_COMB_V01.dta not found r(601);|1|
|run_A: (error occurred while loading _gtools_internal.ado) r(3000);|1|
|run_A: file usa_00300.do not found r(601);|1|
|run_A: variable home not found r(111);|1|
|run_A: command texsave is unrecognized r(199);|1|
|run_A: scheme tufte not found r(111);|1|
|run_A: > <path> could not be opened r(603);|1|
|run_A: <path> MS_20180234_AppendixTableA1.do not found r(601);|1|
|run_A: > inal.dta not found r(601);|1|
|run_A: command standardize_env is unrecognized r(199);|1|
|run_A: .     exit 601 r(601);|1|
|run_A: command renvars is unrecognized r(199);|1|
|run_A: file uber_usage_dataset.dta not found r(601);|1|
|run_A: scheme cblind1 not found r(111);|1|
|run_A: > _performance.do not found r(601);|1|
|run_A: found r(601);|1|
|run_A: > baseline.do not found r(601);|1|
|run_A: host not found r(631);|1|
|run_A: translator Graph2tif not found r(111);|1|
|run_A: Run once:  do <path> not allowed when e(b) is not present r(111);|1|
|run_A: file temp_supply_agg.dta not found r(601);|1|
|run_A: .     exit 111 r(111);|1|
|run_A: unable to change to <path> r(170);|1|
|run_A: empirical <path> not found r(601);|1|
