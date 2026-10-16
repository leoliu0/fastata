# fastata replication results

Generated 2026-10-17 00:58 by `repl report`. Arms: A original commands; V fastata in verify mode (every fast call is checked against the original, which also decides the session state), compared strictly with A; A2 a second A run, for packages that are nondeterministic themselves (NONDET files). Packages compared with arm F (fastata as users run it, with tolerance; B = A with `set sortseed 20261015` for TIE files) are marked F.
A package counts when it was compared and its fastata arm made at least one fast call. A package fails on any DIFF or ERR file or any verify mismatch.

## Totals

- counted packages: **100** (PASS 100, files with DIFF: 0, verify mismatches: 0)
- verified calls (counted packages): ok 375039, mismatch 0, skipped 0
- compared packages: 114; packages tried: 1777
- file verdicts (all compared packages): SAME 3023, NEAR 0, TIE 0, NONDET 60, DIFF 0, SKIP 1174, ERR 0
- fastata the counted packages were verified with: `e124768 plugin 48249ced076c`: 100 (current)

## Replaced commands (counted packages)

|command|packages|fast calls|fallback calls|verify ok|verify mismatch|verify skipped|call lines in source|
|---|---:|---:|---:|---:|---:|---:|---:|
|`egen`|98|363458|68956|363458|0|0|3671|
|`isid`|11|122|0|122|0|0|59|
|`duplicates`|40|329|0|329|0|0|474|
|`xtile`|7|28|1|28|0|0|54|
|`pctile`|4|13|0|13|0|0|3|
|`destring`|44|10416|2059|10416|0|0|690|
|`tostring`|25|673|554|673|0|0|438|

## Packages

|package|journal|year|DOI|title|arm|fastata|A s|arm s|arm/A|calls (fast/fallback)|verify ok/mismatch/skipped|SAME|NEAR|TIE|NONDET|DIFF|SKIP|verdict|
|---|---|---|---|---|---|---|---:|---:|---:|---|---|---:|---:|---:|---:|---:|---:|---|
|dataverse-0TXDTW|REStat|2026|[10.7910/DVN/0TXDTW](https://doi.org/10.7910/DVN/0TXDTW)|Replication Data for: Globalization, Innovation, and Margins of Sourcing|V|e124768 plugin 48249ced076c|1|1|0.60|destring 1/0|1/0/0|4|0|0|0|0|0|PASS|
|dataverse-2BADW3|JPE|2023|[10.7910/DVN/2BADW3](https://doi.org/10.7910/DVN/2BADW3)|Replication Data for: The Effect of Incentives in Non-Routine Analytical Team Tasks|V|e124768 plugin 48249ced076c|76|84|1.11|destring 8/0, egen 721/0|729/0/0|50|0|0|0|0|22|PASS|
|dataverse-2BVMKX|QJE|2026|[10.7910/DVN/2BVMKX](https://doi.org/10.7910/DVN/2BVMKX)|Replication Data for: 'In Their Shoes: Empathy Through Information'|V|e124768 plugin 48249ced076c|0|0|1.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|dataverse-58OI0B|REStat|2026|[10.7910/DVN/58OI0B](https://doi.org/10.7910/DVN/58OI0B)|Replication Data for: Good News Is Not a Sufficient Condition for Motivated Reasoning|V|e124768 plugin 48249ced076c|11|12|1.12|egen 24/3|24/0/0|6|0|0|0|0|6|PASS|
|dataverse-5GRHLO|RFS|2024|[10.7910/DVN/5GRHLO](https://doi.org/10.7910/DVN/5GRHLO)|Replication Data for "Teams and Bankruptcy"|V|e124768 plugin 48249ced076c|267|313|1.17|duplicates 4/0, egen 3/2|7/0/0|12|0|0|0|0|5|PASS|
|dataverse-5JGHDM|REStat|2026|[10.7910/DVN/5JGHDM](https://doi.org/10.7910/DVN/5JGHDM)|DRV, SOEP, SAVE|V|e124768 plugin 48249ced076c|17|13|0.73|destring 138/8, egen 24/0|162/0/0|160|0|0|0|0|3|PASS|
|dataverse-6KG67M|JPE|2025|[10.7910/DVN/6KG67M](https://doi.org/10.7910/DVN/6KG67M)|Replication Data for: "The Origin of the State: Land Productivity or Appropriability? Comm|V|e124768 plugin 48249ced076c|10|22|2.15|egen 337/0|337/0/0|4|0|0|0|0|1|PASS|
|dataverse-77YTLD|RFS|2026|[10.7910/DVN/77YTLD](https://doi.org/10.7910/DVN/77YTLD)|Replication Package for: Capital Controls, Corporate Debt and Real Effects: Evidence from |V|e124768 plugin 48249ced076c|759|1403|1.85|destring 27/0, duplicates 20/0, egen 292/135, tostring 11/0|350/0/0|62|0|0|9|0|8|PASS|
|dataverse-8MKKPO|RFS|2023|[10.7910/DVN/8MKKPO](https://doi.org/10.7910/DVN/8MKKPO)|Replication Data for: Size Discount and Size Penalty: Trading Costs in Bond Markets|V|e124768 plugin 48249ced076c|47|61|1.30|duplicates 9/0, egen 764/249|773/0/0|40|0|0|0|0|8|PASS|
|dataverse-9KNRFO|JPE|2025|[10.7910/DVN/9KNRFO](https://doi.org/10.7910/DVN/9KNRFO)|Replication Data for: Exchange Rates and Asset Prices in a Global Demand System|V|e124768 plugin 48249ced076c|0|0|1.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|dataverse-A9ZFFF|QJE|2026|[10.7910/DVN/A9ZFFF](https://doi.org/10.7910/DVN/A9ZFFF)|Replication Data for: '(Not) Thinking About the Future: Financial Information and Maternal|V|e124768 plugin 48249ced076c|243|813|3.34|destring 26/11, duplicates 3/0, egen 162739/41, tostring 4/0|162772/0/0|98|0|0|0|0|55|PASS|
|dataverse-AOY4D6|QJE|2026|[10.7910/DVN/AOY4D6](https://doi.org/10.7910/DVN/AOY4D6)|Replication Data for: 'Stories, Statistics, and Memory'|V|e124768 plugin 48249ced076c|18|25|1.36|destring 14/14, duplicates 39/0, egen 55/14, pctile 4/0|112/0/0|80|0|0|0|0|34|PASS|
|dataverse-AQDEXY|REStat|2025|[10.7910/DVN/AQDEXY](https://doi.org/10.7910/DVN/AQDEXY)|Replication Data for: Minimum Wages and Poverty: New Evidence from Dynamic Difference-in-D|V|e124768 plugin 48249ced076c|0|0|1.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|dataverse-AQJWOH|QJE|2026|[10.7910/DVN/AQJWOH](https://doi.org/10.7910/DVN/AQJWOH)|Replication Data for: 'How Does Wage Inequality Affect the Labor Movement?'|V|e124768 plugin 48249ced076c|12|14|1.20|destring 1/0, egen 21/0, tostring 1/0|23/0/0|2|0|0|0|0|31|PASS|
|dataverse-BF4W3E|REStat|2025|[10.7910/DVN/BF4W3E](https://doi.org/10.7910/DVN/BF4W3E)|Replication data for: The Response of Wages to Rejected Offers|V|e124768 plugin 48249ced076c|260|368|1.41|egen 7/6, xtile 1/0|8/0/0|12|0|0|0|0|6|PASS|
|dataverse-BG3V8P|REStat|2024|[10.7910/DVN/BG3V8P](https://doi.org/10.7910/DVN/BG3V8P)|Replication data for: Peer Effects in the Adoption of a Youth Employment Subsidy|V|e124768 plugin 48249ced076c|22|32|1.47|egen 2/0|2/0/0|1|0|0|0|0|5|PASS|
|dataverse-BYAMQ6|RFS|2025|[10.7910/DVN/BYAMQ6](https://doi.org/10.7910/DVN/BYAMQ6)|Replication Data for: Data-driven Investors|V|e124768 plugin 48249ced076c|19|17|0.88|egen 18/0, xtile 7/0|25/0/0|2|0|0|0|0|0|PASS|
|dataverse-CRXOAN|JPE Micro|2024|[10.7910/DVN/CRXOAN](https://doi.org/10.7910/DVN/CRXOAN)|Replication Data for: "Delegation in Hiring: Evidence from a Two-Sided Audit"|V|e124768 plugin 48249ced076c|2446|2678|1.09|destring 108/0, egen 115/3, tostring 20/0, xtile 1/0|244/0/0|126|0|0|0|0|2|PASS|
|dataverse-CYF1X4|JPE|2025|[10.7910/DVN/CYF1X4](https://doi.org/10.7910/DVN/CYF1X4)|Replication Data for: "A Model of Social Duties"|V|e124768 plugin 48249ced076c|20|24|1.20|destring 8/0, egen 0/372|8/0/0|59|0|0|0|0|26|PASS|
|dataverse-DCKKLW|REStat|2026|[10.7910/DVN/DCKKLW](https://doi.org/10.7910/DVN/DCKKLW)|Replication data for: When Transparency Fails: Financial Incentives for Local Banking Agen|V|e124768 plugin 48249ced076c|0|0|1.50|destring 2/0, tostring 1/0|3/0/0|3|0|0|0|0|0|PASS|
|dataverse-DWKN2J|RFS|2026|[10.7910/DVN/DWKN2J](https://doi.org/10.7910/DVN/DWKN2J)|Replication Package for: How Private Equity Fuels Non-Bank Lending|V|e124768 plugin 48249ced076c|10|16|1.57|duplicates 4/0, egen 28/1|32/0/0|31|0|0|0|0|3|PASS|
|dataverse-DZBURR|REStat|2024|[10.7910/DVN/DZBURR](https://doi.org/10.7910/DVN/DZBURR)|Replication data for: The Unintended Consequences of Infrastructure Development|V|e124768 plugin 48249ced076c|0|0|1.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|dataverse-E7HAPA|REStat|2024|[10.7910/DVN/E7HAPA](https://doi.org/10.7910/DVN/E7HAPA)|Replication Data for:Human Capital and Climate Change|V|e124768 plugin 48249ced076c|678|998|1.47|egen 40/12|40/0/0|31|0|0|0|0|2|PASS|
|dataverse-EHXLE4|JPE|2023|[10.7910/DVN/EHXLE4](https://doi.org/10.7910/DVN/EHXLE4)|Replication Data for: Estimation of a Life-Cycle Model with Human Capital, Labor Supply, a|V|e124768 plugin 48249ced076c|161|245|1.52|egen 14/0|14/0/0|40|0|0|0|0|68|PASS|
|dataverse-EP9TGW|RFS|2026|[10.7910/DVN/EP9TGW](https://doi.org/10.7910/DVN/EP9TGW)|Replication Package for: Mutual Fund Flows and the Supply of Capital in Municipal Financin|V|e124768 plugin 48249ced076c|37|36|0.96|duplicates 2/0, egen 23/6, tostring 1/0|26/0/0|55|0|0|0|0|7|PASS|
|dataverse-ERHYH7|RFS|2025|[10.7910/DVN/ERHYH7](https://doi.org/10.7910/DVN/ERHYH7)|Replication Data for: Risk Managers in Banks|V|e124768 plugin 48249ced076c|8|12|1.47|egen 98/0|98/0/0|4|0|0|1|0|0|PASS|
|dataverse-F1MTEN|REStat|2026|[10.7910/DVN/F1MTEN](https://doi.org/10.7910/DVN/F1MTEN)|Replication data for: Firm Responses to Hiring and Investment Subsidies: Regression Discon|V|e124768 plugin 48249ced076c|8|8|0.96|egen 4/0|4/0/0|5|0|0|0|0|3|PASS|
|dataverse-FTVDNH|JPE Macro|2023|[10.7910/DVN/FTVDNH](https://doi.org/10.7910/DVN/FTVDNH)|Replication Data for: "'Golden Ages': A Tale of the Labor Markets in China and the United |V|e124768 plugin 48249ced076c|284|637|2.25|destring 1/0, egen 542/1468|543/0/0|41|0|0|0|0|15|PASS|
|dataverse-GOORY3|REStat|2026|[10.7910/DVN/GOORY3](https://doi.org/10.7910/DVN/GOORY3)|Replication Data for: Contracting structures in public procurement: Evidence from donor-fu|V|e124768 plugin 48249ced076c|120|151|1.25|destring 1/0, duplicates 2/0, egen 14/0, isid 10/0|27/0/0|8|0|0|0|0|26|PASS|
|dataverse-GOXYYT|RFS|2026|[10.7910/DVN/GOXYYT](https://doi.org/10.7910/DVN/GOXYYT)|Replication Package for: United They Fall: Bank Risk After the Financial Crisis|V|e124768 plugin 48249ced076c|23|30|1.34|egen 29/0|29/0/0|14|0|0|0|0|2|PASS|
|dataverse-H5CWEP|REStat|2024|[10.7910/DVN/H5CWEP](https://doi.org/10.7910/DVN/H5CWEP)|Replication data for: The Impact of Children’s Health Shocks on Parents’ Labor Earnings an|V|e124768 plugin 48249ced076c|0|0|1.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|dataverse-HIY143|JPE|2025|[10.7910/DVN/HIY143](https://doi.org/10.7910/DVN/HIY143)|Replication Data for: Black Empowerment and White Mobilization: The Effects of the Voting |V|e124768 plugin 48249ced076c|19|21|1.12|egen 32/0|32/0/0|8|0|0|0|0|22|PASS|
|dataverse-HYJFCL|RFS|2024|[10.7910/DVN/HYJFCL](https://doi.org/10.7910/DVN/HYJFCL)|Replication Data for: "Financial Effects of Remote Product Delivery: Evidence from Hospita|V|e124768 plugin 48249ced076c|13|16|1.23|egen 3/0|3/0/0|2|0|0|0|0|14|PASS|
|dataverse-ICNB18|JPE Micro|2026|[10.7910/DVN/ICNB18](https://doi.org/10.7910/DVN/ICNB18)|Replication Data for: Attention as a First-Order Barrier to Adoption of Evidence-based Pro|V|e124768 plugin 48249ced076c|2|2|1.26|egen 3/0|3/0/0|22|0|0|0|0|0|PASS|
|dataverse-JD0W1S|RFS|2026|[10.7910/DVN/JD0W1S](https://doi.org/10.7910/DVN/JD0W1S)|Replication Package for: Financial Advice and Investor Beliefs: Experimental Evidence on A|V|e124768 plugin 48249ced076c|9|10|1.20|egen 95/1, isid 1/0|96/0/0|27|0|0|0|0|10|PASS|
|dataverse-JFEZXC|RFS|2025|[10.7910/DVN/JFEZXC](https://doi.org/10.7910/DVN/JFEZXC)|Replication Data for: The Impact of Consolidation on Credit Supply and Performance (RFS MS|V|e124768 plugin 48249ced076c|14|19|1.39|destring 6/0, duplicates 20/0, egen 130/0, tostring 2/0, xtile 3/0|161/0/0|39|0|0|0|0|6|PASS|
|dataverse-JOXAFP|QJE|2024|[10.7910/DVN/JOXAFP](https://doi.org/10.7910/DVN/JOXAFP)|Replication Data for: 'Economic Consequences of Kinship: Evidence from U.S. Bans on Cousin|V|e124768 plugin 48249ced076c|741|1088|1.47|egen 3/1, isid 5/0, tostring 1/0|9/0/0|27|0|0|21|0|29|PASS|
|dataverse-KIDK6R|RFS|2026|[10.7910/DVN/KIDK6R](https://doi.org/10.7910/DVN/KIDK6R)|Replication Package for: The Coherence Side of Rationality: Theory and Evidence from Firm |V|e124768 plugin 48249ced076c|355|728|2.05|duplicates 2/0, egen 627/0, isid 10/0|639/0/0|51|0|0|0|0|4|PASS|
|dataverse-LSBHQJ|JPE Macro|2026|[10.7910/DVN/LSBHQJ](https://doi.org/10.7910/DVN/LSBHQJ)|Replication Data for: We Think That They Think: Political Affiliation and Higher-Order Bel|V|e124768 plugin 48249ced076c|81|100|1.24|duplicates 5/0, egen 11/8|16/0/0|71|0|0|0|0|88|PASS|
|dataverse-MSQE6U|QJE|2023|[10.7910/DVN/MSQE6U](https://doi.org/10.7910/DVN/MSQE6U)|Replication Data for: "Measuring Welfare and Inequality with Incomplete Price Information"|V|e124768 plugin 48249ced076c|0|0|2.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|dataverse-NYXW03|JPE|2026|[10.7910/DVN/NYXW03](https://doi.org/10.7910/DVN/NYXW03)|Replication Data for: Not Learning from Others|V|e124768 plugin 48249ced076c|26|31|1.18|egen 7/3|7/0/0|21|0|0|0|0|30|PASS|
|dataverse-O4AUDQ|QJE|2026|[10.7910/DVN/O4AUDQ](https://doi.org/10.7910/DVN/O4AUDQ)|Replication Data for: 'The Macroeconomic Impact of Climate Change: Global Versus Local Tem|V|e124768 plugin 48249ced076c|618|7921|12.81|duplicates 1/0, egen 151807/0|151808/0/0|49|0|0|0|0|122|PASS|
|dataverse-OBH3KV|RFS|2024|[10.7910/DVN/OBH3KV](https://doi.org/10.7910/DVN/OBH3KV)|Replication Data for: The Fed and the Secular Decline in Interest Rates|V|e124768 plugin 48249ced076c|21|24|1.14|egen 2/0|2/0/0|8|0|0|0|0|20|PASS|
|dataverse-OQ8UYN|RFS|2023|[10.7910/DVN/OQ8UYN](https://doi.org/10.7910/DVN/OQ8UYN)|Replication code for: Freeze! Financial Sanctions and Bank Responses|V|e124768 plugin 48249ced076c|132|212|1.61|duplicates 1/0, egen 9/0|10/0/0|12|0|0|0|0|4|PASS|
|dataverse-P7AQKG|RFS|2025|[10.7910/DVN/P7AQKG](https://doi.org/10.7910/DVN/P7AQKG)|The Effect of Primary Dealer Constraints on Intermediation in the Treasury Market|V|e124768 plugin 48249ced076c|127|124|0.98|destring 3/0, duplicates 13/0, egen 122/3, isid 1/0, tostring 2/0|141/0/0|22|0|0|0|0|35|PASS|
|dataverse-PDFDKR|QJE|2025|[10.7910/DVN/PDFDKR](https://doi.org/10.7910/DVN/PDFDKR)|Replication Data for: 'Can Pollution Markets Work in Developing Countries? Experimental Ev|V|e124768 plugin 48249ced076c|197|1030|5.23|duplicates 9/0, egen 2155/12|2164/0/0|37|0|0|0|0|9|PASS|
|dataverse-PMVKXH|JPE Micro|2024|[10.7910/DVN/PMVKXH](https://doi.org/10.7910/DVN/PMVKXH)|Replication Data for: "The Thrill of Gradual Learning"|V|e124768 plugin 48249ced076c|2|2|1.20|egen 8/1|8/0/0|2|0|0|0|0|1|PASS|
|dataverse-QA1IDU|REStat|2023|[10.7910/DVN/QA1IDU](https://doi.org/10.7910/DVN/QA1IDU)|Replication Data for: Discrimination, narratives and family history: An experiment with Jo|V|e124768 plugin 48249ced076c|20|22|1.10|destring 1/0, duplicates 1/0, egen 4/0|6/0/0|9|0|0|3|0|3|PASS|
|dataverse-R2AM7F|RFS|2024|[10.7910/DVN/R2AM7F](https://doi.org/10.7910/DVN/R2AM7F)|Replication Data for: Finance, Advertising, and Race|V|e124768 plugin 48249ced076c|8|14|1.75|destring 1/0, duplicates 1/0, egen 4/6|6/0/0|1|0|0|0|0|0|PASS|
|dataverse-RXWKTV|QJE|2023|[10.7910/DVN/RXWKTV](https://doi.org/10.7910/DVN/RXWKTV)|Replication Data for: 'Labor Market Dynamics and Development'|V|e124768 plugin 48249ced076c|3|4|1.06|egen 24/0|24/0/0|5|0|0|0|0|0|PASS|
|dataverse-SHXCAH|REStat|2026|[10.7910/DVN/SHXCAH](https://doi.org/10.7910/DVN/SHXCAH)|Replication data for: How Credible are the Findings from Online Experiments?|V|e124768 plugin 48249ced076c|149|200|1.35|destring 66/23, duplicates 33/0, egen 50/29, pctile 7/0, tostring 1/2|157/0/0|52|0|0|0|0|72|PASS|
|dataverse-TZ7OOV|REStat|2026|[10.7910/DVN/TZ7OOV](https://doi.org/10.7910/DVN/TZ7OOV)|Replication data for: The Factor Bias of External Inputs: Implications for Substitution be|V|e124768 plugin 48249ced076c|225|299|1.33|destring 8503/0, duplicates 40/0, egen 281/203|8824/0/0|191|0|0|0|0|6|PASS|
|dataverse-VYPKDJ|RFS|2024|[10.7910/DVN/VYPKDJ](https://doi.org/10.7910/DVN/VYPKDJ)|Replication Data for: "Return Predictability, Expectations, and Investment: Experimental E|V|e124768 plugin 48249ced076c|9|14|1.56|egen 153/0, tostring 0/2|153/0/0|34|0|0|0|0|0|PASS|
|dataverse-VZDBQF|REStat|2024|[10.7910/DVN/VZDBQF](https://doi.org/10.7910/DVN/VZDBQF)|Replication Data for: [Improving Workers' Performance in Small Firms: A Randomized Experim|V|e124768 plugin 48249ced076c|0|2|5.67|egen 8/2|8/0/0|4|0|0|0|0|0|PASS|
|dataverse-XNV6CY|RFS|2025|[10.7910/DVN/XNV6CY](https://doi.org/10.7910/DVN/XNV6CY)|Replication Code and Pseudo-Data for "The Intangibles Song in Takeover Announcements: Good|V|e124768 plugin 48249ced076c|0|0|1.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|dataverse-XUJGCK|QJE|2026|[10.7910/DVN/XUJGCK](https://doi.org/10.7910/DVN/XUJGCK)|Replication Data for: 'Beliefs About the Economy Are Excessively Sensitive to Household-Le|V|e124768 plugin 48249ced076c|11|21|1.97|destring 122/0, egen 78/2, tostring 1/0|201/0/0|37|0|0|0|0|14|PASS|
|dataverse-Y8MIH0|RFS|2025|[10.7910/DVN/Y8MIH0](https://doi.org/10.7910/DVN/Y8MIH0)|Replication Data for: The Real Effect of Sociopolitical Racial/Ethnic Animus: Mutual Fund |V|e124768 plugin 48249ced076c|6|7|1.16|egen 18/0|18/0/0|1|0|0|1|0|0|PASS|
|dataverse-Y9M30R|RFS|2025|[10.7910/DVN/Y9M30R](https://doi.org/10.7910/DVN/Y9M30R)|Replication Data for: Technological Obsolescence|V|e124768 plugin 48249ced076c|23|40|1.77|egen 430/0|430/0/0|15|0|0|0|0|6|PASS|
|dataverse-YMSVMX|RFS|2026|[10.7910/DVN/YMSVMX](https://doi.org/10.7910/DVN/YMSVMX)|Replication Package for: Firm-Level Labor-Shortage Exposure|V|e124768 plugin 48249ced076c|60|69|1.16|destring 11/0, duplicates 8/0, egen 260/5, tostring 2/0|281/0/0|48|0|0|0|0|0|PASS|
|dataverse-YWQZED|RFS|2026|[10.7910/DVN/YWQZED](https://doi.org/10.7910/DVN/YWQZED)|Replication Data for: "Learning by Investing: Entrepreneurial Spillovers from Venture Capi|V|e124768 plugin 48249ced076c|69|69|1.00|destring 13/0, duplicates 12/0, egen 208/31, tostring 11/0|244/0/0|72|0|0|23|0|13|PASS|
|dataverse-ZBJKLF|JPE Micro|2025|[10.7910/DVN/ZBJKLF](https://doi.org/10.7910/DVN/ZBJKLF)|Replication Data for: Comparing Crowdfunding Mechanisms: Introducing the Generalized Mouli|V|e124768 plugin 48249ced076c|74|59|0.80|destring 19/0, egen 37/26|56/0/0|7|0|0|0|0|8|PASS|
|dataverse-ZBOLIK|JPE Micro|2026|[10.7910/DVN/ZBOLIK](https://doi.org/10.7910/DVN/ZBOLIK)|Replication Data for: Minimum Wages Reduce Restaurant Employment (Almost Any Way You Slice|V|e124768 plugin 48249ced076c|84|120|1.44|duplicates 30/0, egen 793/108|823/0/0|41|0|0|0|0|14|PASS|
|dataverse-ZGMEQC|RFS|2026|[10.7910/DVN/ZGMEQC](https://doi.org/10.7910/DVN/ZGMEQC)|Replication Package for: Original Sin Redux: Role of Duration Risk|V|e124768 plugin 48249ced076c|123|153|1.25|egen 402/17|402/0/0|24|0|0|0|0|22|PASS|
|dataverse-ZIXTGH|REStat|2026|[10.7910/DVN/ZIXTGH](https://doi.org/10.7910/DVN/ZIXTGH)|Replication data for: Gender Discrimination in Access to Capital: A Field Experiment in Et|V|e124768 plugin 48249ced076c|189|251|1.33|destring 3/0, egen 29/5|32/0/0|41|0|0|0|0|7|PASS|
|zenodo-10120113|REStud|2023|[10.5281/zenodo.10120113](https://doi.org/10.5281/zenodo.10120113)|Replication package for: "The Impact of Online Competition on Local Newspapers: Evidence f|V|e124768 plugin 48249ced076c|4|5|1.26|destring 13/0, duplicates 2/0, egen 3/0|18/0/0|2|0|0|0|0|0|PASS|
|zenodo-10535890|EJ|2024|[10.5281/zenodo.10535890](https://doi.org/10.5281/zenodo.10535890)|Replication package for: What to blame? Self-serving attribution bias with multi-dimension|V|e124768 plugin 48249ced076c|9|12|1.41|destring 178/60, egen 13/2|191/0/0|65|0|0|0|0|0|PASS|
|zenodo-10557110|EJ|2024|[10.5281/zenodo.10557110](https://doi.org/10.5281/zenodo.10557110)|Replication package for:  "Making policies matter: Voter responses to campaign promises"|V|e124768 plugin 48249ced076c|11|11|1.05|egen 6/0, tostring 1/36|7/0/0|31|0|0|0|0|2|PASS|
|zenodo-10611203|REStud|2024|[10.5281/zenodo.10611203](https://doi.org/10.5281/zenodo.10611203)|Replication package for: "Structural Change, Elite Capitalism, and the Emergence of Labor |V|e124768 plugin 48249ced076c|3|4|1.42|egen 0/1|0/0/0|5|0|0|0|0|5|PASS (not counted)|
|zenodo-10629265|EJ|2024|[10.5281/zenodo.10629265](https://doi.org/10.5281/zenodo.10629265)|Bundling Genetic and Financial Technologies for More Resilient and Productive Small-scale |V|e124768 plugin 48249ced076c|0|1|1.40|destring 1/0, egen 2/0|3/0/0|6|0|0|0|0|0|PASS|
|zenodo-10721159|EJ|2024|[10.5281/zenodo.10721159](https://doi.org/10.5281/zenodo.10721159)|Replication package for: "Immigration and the Short- and Long-Term Impact of Improved Pren|V|e124768 plugin 48249ced076c|2|2|0.88||0/0/0|1|0|0|0|0|8|PASS (not counted)|
|zenodo-10887743|EJ|2024|[10.5281/zenodo.10887743](https://doi.org/10.5281/zenodo.10887743)|Borrowing Constraints and Demand for Remedial Education: Evidence from Tanzania|V|e124768 plugin 48249ced076c|0|0|1.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|zenodo-11160672|EJ|2024|[10.5281/zenodo.11160672](https://doi.org/10.5281/zenodo.11160672)|Incentivizing Textbooks for Self-Study: Experimental Evidence from the Democratic Republic|V|e124768 plugin 48249ced076c|1|2|2.25|egen 16/0|16/0/0|2|0|0|0|0|0|PASS|
|zenodo-11186567|EJ|2024|[10.5281/zenodo.11186567](https://doi.org/10.5281/zenodo.11186567)|Replication Package for: Long-Term Effects of Equal Sharing: Evidence from Inheritance Rul|V|e124768 plugin 48249ced076c|22|54|2.43|egen 422/0|422/0/0|2|0|0|0|0|26|PASS|
|zenodo-11376471|EJ|2024|[10.5281/zenodo.11376471](https://doi.org/10.5281/zenodo.11376471)|Replication package for: "Measuring Social Benefits of Media Coverage: How Coverage of Cli|V|e124768 plugin 48249ced076c|594|950|1.60|destring 432/0, duplicates 7/0, egen 41/0, tostring 123/0|603/0/0|21|0|0|0|0|0|PASS|
|zenodo-11447227|EJ|2024|[10.5281/zenodo.11447227](https://doi.org/10.5281/zenodo.11447227)|Gender Differences in Math Tests: The Role of Time Pressure|V|e124768 plugin 48249ced076c|9|10|1.11|destring 0/1, egen 131/0|131/0/0|24|0|0|0|0|1|PASS|
|zenodo-14171972|REStud|2025|[10.5281/zenodo.14171972](https://doi.org/10.5281/zenodo.14171972)|Replication Package for Global Value Chains and Trade Policy|V|e124768 plugin 48249ced076c|1080|1557|1.44|egen 62/3|62/0/0|6|0|0|0|0|8|PASS|
|zenodo-14503622|EJ|2024|[10.5281/zenodo.14503622](https://doi.org/10.5281/zenodo.14503622)|Replication package for: "To Defer or to Differ: Experimental Evidence on the Role of Cash|V|e124768 plugin 48249ced076c|28|45|1.61|egen 488/0|488/0/0|40|0|0|0|0|0|PASS|
|zenodo-14726871|EJ|2025|[10.5281/zenodo.14726871](https://doi.org/10.5281/zenodo.14726871)|Replication package for Yellow Pages: Information, Connections, and Firm Performance|V|e124768 plugin 48249ced076c|29|48|1.65|destring 1/0, duplicates 2/0, egen 187/0, isid 3/0, tostring 25/287|218/0/0|4|0|0|0|0|0|PASS|
|zenodo-14780637|REStud|2025|[10.5281/zenodo.14780637](https://doi.org/10.5281/zenodo.14780637)|Replication package for: How Important Is Health Inequality for Lifetime Earnings Inequali|V|e124768 plugin 48249ced076c|39|55|1.41|duplicates 1/0, egen 7/0|8/0/0|3|0|0|0|0|0|PASS|
|zenodo-14933575|EJ|2025|[10.5281/zenodo.14933575](https://doi.org/10.5281/zenodo.14933575)|Replication Package for: Managerial Leadership, Truth-Telling, and Efficient Coordination|V|e124768 plugin 48249ced076c|3|5|1.89|egen 110/0|110/0/0|5|0|0|0|0|0|PASS|
|zenodo-14976627|REStud|2025|[10.5281/zenodo.14976627](https://doi.org/10.5281/zenodo.14976627)|Creating Cohesive Communities: A Youth Camp Experiment in India|V|e124768 plugin 48249ced076c|1|4|7.00|destring 20/0, duplicates 1/0, egen 40/1, tostring 18/0|79/0/0|13|0|0|0|0|0|PASS|
|zenodo-15223629|EJ|2025|[10.5281/zenodo.15223629](https://doi.org/10.5281/zenodo.15223629)|Replication package for: "Genetic and Socioeconomic Achievement Gaps in Elementary School"|V|e124768 plugin 48249ced076c|3|8|2.36|duplicates 5/0, egen 53/0, tostring 1/0, xtile 15/0|74/0/0|1|0|0|0|0|0|PASS|
|zenodo-15311300|REStud|2025|[10.5281/zenodo.15311300](https://doi.org/10.5281/zenodo.15311300)|Replication package for: Narratives about the Macroeconomy|V|e124768 plugin 48249ced076c|10|14|1.32|destring 1/17, duplicates 2/0, egen 84/0|87/0/0|24|0|0|1|0|0|PASS|
|zenodo-15612582|EJ|2025|[10.5281/zenodo.15612582](https://doi.org/10.5281/zenodo.15612582)|Replication Package for: "Correlation Neglect on Social Media: Effects on Civil Service Ap|V|e124768 plugin 48249ced076c|18|13|0.70|destring 1/0, egen 0/1|1/0/0|19|0|0|0|0|6|PASS|
|zenodo-15634053|EJ|2025|[10.5281/zenodo.15634053](https://doi.org/10.5281/zenodo.15634053)|Replication package for: "On the post-Enlightenment evolution of moral universalism"|V|e124768 plugin 48249ced076c|24|28|1.16|egen 36/0|36/0/0|3|0|0|0|0|40|PASS|
|zenodo-16599207|EJ|2025|[10.5281/zenodo.16599207](https://doi.org/10.5281/zenodo.16599207)|Replication Package for "Civilian Evacuation During War: Evidence from Ukraine"|V|e124768 plugin 48249ced076c|5|6|1.28|destring 1/0, egen 1/0|2/0/0|2|0|0|0|0|0|PASS|
|zenodo-16755528|REStud|2025|[10.5281/zenodo.16755528](https://doi.org/10.5281/zenodo.16755528)|Replication Package For: De Gustibus and Disputes about Reference Dependence|V|e124768 plugin 48249ced076c|73|81|1.11|destring 13/0, egen 39/1, pctile 1/0|53/0/0|7|0|0|0|0|3|PASS|
|zenodo-17128105|EJ|2025|[10.5281/zenodo.17128105](https://doi.org/10.5281/zenodo.17128105)|Replication package for "To Savor Consumption or To Confront Dread: The Hedonic Opportunit|V|e124768 plugin 48249ced076c|6|8|1.17||0/0/0|8|0|0|0|0|3|PASS (not counted)|
|zenodo-17351754|EJ|2025|[10.5281/zenodo.17351754](https://doi.org/10.5281/zenodo.17351754)|Replication package for: "Income, Democracy, and Growth: Reconciling Evidence and Theory"|V|e124768 plugin 48249ced076c|49|62|1.26|egen 74/5, isid 2/0|76/0/0|26|0|0|0|0|7|PASS|
|zenodo-17468794|EJ|2025|[10.5281/zenodo.17468794](https://doi.org/10.5281/zenodo.17468794)|Replication package for: "Bad Democracy Traps"|V|e124768 plugin 48249ced076c|11|18|1.60|destring 143/5, egen 116/0|259/0/0|22|0|0|0|0|2|PASS|
|zenodo-18600000|EJ|2026|[10.5281/zenodo.18600000](https://doi.org/10.5281/zenodo.18600000)|Replication package for: "Telementoring and homeschooling during school closures: A random|V|e124768 plugin 48249ced076c|10|9|0.91||0/0/0|1|0|0|0|0|2|PASS (not counted)|
|zenodo-18611342|EJ|2026|[10.5281/zenodo.18611342](https://doi.org/10.5281/zenodo.18611342)|Replication package for: "Motivated Risk Assessments"|V|e124768 plugin 48249ced076c|10|11|1.11|egen 59/0|59/0/0|16|0|0|0|0|10|PASS|
|zenodo-18825108|REStud|2026|[10.5281/zenodo.18825108](https://doi.org/10.5281/zenodo.18825108)|Replication Package for: "The Selective Disclosure of Evidence: An Experiment"|V|e124768 plugin 48249ced076c|16|29|1.79|duplicates 2/0, egen 1054/6|1056/0/0|1|0|0|0|0|10|PASS|
|zenodo-19115553|EJ|2026|[10.5281/zenodo.19115553](https://doi.org/10.5281/zenodo.19115553)|Impact or Responsibility? Giving Behaviour in a Televised Natural Experiment|V|e124768 plugin 48249ced076c|342|313|0.92|destring 6/0, egen 217/9|223/0/0|27|0|0|0|0|0|PASS|
|zenodo-19234083|EJ|2026|[10.5281/zenodo.19234083](https://doi.org/10.5281/zenodo.19234083)|Replication package for: "Ruling the roost: the vicious circle and the emergence of peckin|V|e124768 plugin 48249ced076c|30|35|1.18|destring 6/1920, egen 62/2|68/0/0|10|0|0|0|0|0|PASS|
|zenodo-19366496|EJ|2026|[10.5281/zenodo.19366496](https://doi.org/10.5281/zenodo.19366496)|Life Expectancy, Age, and Patience|V|e124768 plugin 48249ced076c|290|428|1.48|destring 426/0, duplicates 1/0, egen 164/0|591/0/0|72|0|0|0|0|0|PASS|
|zenodo-19486751|REStud|2026|[10.5281/zenodo.19486751](https://doi.org/10.5281/zenodo.19486751)|Replication Package for: Paying to Match: Decentralized Markets with Information Frictions|V|e124768 plugin 48249ced076c|1632|1710|1.05|destring 10/0, duplicates 5/0, egen 279/3|294/0/0|52|0|0|0|0|17|PASS|
|zenodo-19562339|EJ|2026|[10.5281/zenodo.19562339](https://doi.org/10.5281/zenodo.19562339)|Replication package for "Publicly targeting group identities impacts take-up of educationa|V|e124768 plugin 48249ced076c|96|76|0.79|egen 13/0|13/0/0|41|0|0|0|0|36|PASS|
|zenodo-19743938|EJ|2026|[10.5281/zenodo.19743938](https://doi.org/10.5281/zenodo.19743938)|Replication for: "Campaigning to a Polarised Electorate: Emotions and Information in Real |V|e124768 plugin 48249ced076c|7|7|0.93|egen 119/0|119/0/0|34|0|0|0|0|0|PASS|
|zenodo-20379084|EJ|2026|[10.5281/zenodo.20379084](https://doi.org/10.5281/zenodo.20379084)|Replication package for "On the Benefits of Robo-Advice in Financial Markets"|V|e124768 plugin 48249ced076c|13|15|1.16|egen 2/0|2/0/0|8|0|0|0|0|0|PASS|
|zenodo-20383941|REStud|2026|[10.5281/zenodo.20383941](https://doi.org/10.5281/zenodo.20383941)|"Replication package for: Why Veil? Religious Headscarves and the Economic Role of Women"|V|e124768 plugin 48249ced076c|53|78|1.47|egen 450/2, isid 4/0, pctile 1/0, tostring 1/0, xtile 0/1|456/0/0|27|0|0|0|0|7|PASS|
|zenodo-20542048|EJ|2026|[10.5281/zenodo.20542048](https://doi.org/10.5281/zenodo.20542048)|Replication package for: "On the doorstep of adulthood: Entrepreneurship and fertility of |V|e124768 plugin 48249ced076c|1944|4800|2.47|duplicates 6/0, egen 33176/66063, tostring 327/227|33509/0/0|44|0|0|0|0|11|PASS|
|zenodo-20702728|EJ|2026|[10.5281/zenodo.20702728](https://doi.org/10.5281/zenodo.20702728)|Replication for Trust and Democracy: Political Stability in Times of Economic Crisis|V|e124768 plugin 48249ced076c|118|124|1.06|destring 16/0, duplicates 14/0, egen 111/9, isid 4/0, tostring 1/0, xtile 1/0|147/0/0|70|0|0|0|0|0|PASS|
|zenodo-21698370|EJ|2026|[10.5281/zenodo.21698370](https://doi.org/10.5281/zenodo.21698370)|Replication package for: "Productivity and Entry Regulation in the Service Sector: Evidenc|V|e124768 plugin 48249ced076c|31|46|1.51|duplicates 1/0, egen 88/65|89/0/0|5|0|0|0|0|10|PASS|
|zenodo-21725672|EJ|2026|[10.5281/zenodo.21725672](https://doi.org/10.5281/zenodo.21725672)|Replication package for: Remote work and effort provision in teams|V|e124768 plugin 48249ced076c|7|9|1.29|destring 6/0, duplicates 1/0, egen 53/2, tostring 2/0|62/0/0|63|0|0|0|0|10|PASS|
|zenodo-21775195|EJ|2026|[10.5281/zenodo.21775195](https://doi.org/10.5281/zenodo.21775195)|Replication package for: "Group Identity and Belief Formation: A Microfoundation of Politi|V|e124768 plugin 48249ced076c|4|5|1.07|egen 0/2|0/0/0|8|0|0|0|0|0|PASS (not counted)|
|zenodo-23223970|EJ|2026|[10.5281/zenodo.23223970](https://doi.org/10.5281/zenodo.23223970)|Immigration and the Slope of the Labour Demand Curve: The Role of Firm Heterogeneity in a |V|e124768 plugin 48249ced076c|91|125|1.38|destring 4/0, duplicates 4/0, egen 72/3, isid 2/0, tostring 1/0|83/0/0|50|0|0|0|0|4|PASS|
|zenodo-23320830|EJ|2026|[10.5281/zenodo.23320830](https://doi.org/10.5281/zenodo.23320830)|Replication package for: Cognitive ability, risk preferences and errors|V|e124768 plugin 48249ced076c|663|1236|1.86|egen 2/0|2/0/0|35|0|0|0|0|0|PASS|
|zenodo-8168773|EJ|2023|[10.5281/zenodo.8168773](https://doi.org/10.5281/zenodo.8168773)|Replication package for: The Null Result Penalty|V|e124768 plugin 48249ced076c|598|951|1.59|egen 106/2|106/0/0|18|0|0|0|0|5|PASS|
|zenodo-8242347|REStud|2023|[10.5281/zenodo.8242347](https://doi.org/10.5281/zenodo.8242347)|Path Dependency in Physician Decisions|V|e124768 plugin 48249ced076c|1962|2818|1.44|duplicates 3/0, egen 1453/0|1456/0/0|32|0|0|0|0|12|PASS|
|zenodo-8290180|EJ|2023|[10.5281/zenodo.8290180](https://doi.org/10.5281/zenodo.8290180)|Replication package for "Deliberate Surrender? The Impact of Interwar Indian Protection"|V|e124768 plugin 48249ced076c|87|115|1.32|destring 3/0, duplicates 2/0, egen 129/2|134/0/0|62|0|0|1|0|6|PASS|
|zenodo-8325645|EJ|2023|[10.5281/zenodo.8325645](https://doi.org/10.5281/zenodo.8325645)|Replication Package for "Unemployment and Development"|V|e124768 plugin 48249ced076c|20|32|1.62|duplicates 11/0, egen 19/0|30/0/0|15|0|0|0|0|26|PASS|
|zenodo-8370126|REStud|2023|[10.5281/zenodo.8370126](https://doi.org/10.5281/zenodo.8370126)|Replication package for: {Monopoly of Taxation Without a Monopoly of Violence: The Weak St|V|e124768 plugin 48249ced076c|0|0|1.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|zenodo-8373069|EJ|2023|[10.5281/zenodo.8373069](https://doi.org/10.5281/zenodo.8373069)|Replication package for: "Strategic Campaign Communication: Evidence from 30,000 Candidate|V|e124768 plugin 48249ced076c|25|40|1.58|destring 52/0, egen 192/0, isid 80/0, tostring 115/0|439/0/0|51|0|0|0|0|0|PASS|

## Verify mismatches

None.

## NEAR, TIE, NONDET and DIFF files

|package|file|verdict|A vs fastata arm|A vs A2 or B|
|---|---|---|---|---|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/logfile.smcl`|NONDET|DIFF line 92360: '{res}   1:    758.72 /        1 =     758.7160' vs '{res}   1:   1402.41 /        1 =    1402.4060'|DIFF numbers differ (max reldif 0.2)|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/table_2.rtf`|NONDET|DIFF numbers differ (max reldif 0.96)|DIFF numbers differ (max reldif 0.88)|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/table_3.rtf`|NONDET|DIFF numbers differ (max reldif 0.96)|DIFF numbers differ (max reldif 0.88)|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/table_4.rtf`|NONDET|DIFF numbers differ (max reldif 0.95)|DIFF numbers differ (max reldif 0.83)|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/table_5.rtf`|NONDET|DIFF numbers differ (max reldif 0.93)|DIFF numbers differ (max reldif 0.79)|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/table_6.rtf`|NONDET|DIFF numbers differ (max reldif 3)|DIFF numbers differ (max reldif 0.79)|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/table_7.rtf`|NONDET|DIFF numbers differ (max reldif 4)|DIFF numbers differ (max reldif 0.75)|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/table_8.rtf`|NONDET|DIFF numbers differ (max reldif 1.5)|DIFF numbers differ (max reldif 0.75)|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/table_9.rtf`|NONDET|DIFF numbers differ (max reldif 0.29)|DIFF numbers differ (max reldif 0.68)|
|dataverse-ERHYH7|`results/2_analysis_tables.rtf`|NONDET|DIFF numbers differ (max reldif 0.47)|DIFF numbers differ (max reldif 0.47)|
|dataverse-JOXAFP|`Output/TablesFigures/results_12pthresha.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55247456' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 55247456'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55247456' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 5524745'|
|dataverse-JOXAFP|`Output/TablesFigures/results_8pthresha.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55247456' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 55247456'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55247456' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 5524745'|
|dataverse-JOXAFP|`Output/TablesFigures/results_Mainobsa.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55247456' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 55247456'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55247456' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 5524745'|
|dataverse-JOXAFP|`Output/TablesFigures/results_UrbanbyAgea.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 27666349' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 27666349'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 27666349' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 2766634'|
|dataverse-JOXAFP|`Output/TablesFigures/results_UrbanbyMSa.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 21379971' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 21379971'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 21379971' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 2137997'|
|dataverse-JOXAFP|`Output/TablesFigures/results_droptopa.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 40193149' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 40193149'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 40193149' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 4019314'|
|dataverse-JOXAFP|`Output/TablesFigures/results_familya.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55233292' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 55233292'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55233292' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 5523329'|
|dataverse-JOXAFP|`Output/TablesFigures/results_fsa.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & . \\\\ Mea' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & . \\\\ Mea'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & . \\\\ Mea' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & . \\\\ Me'|
|dataverse-JOXAFP|`Output/TablesFigures/results_gdispa.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55233292' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 55233292'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55233292' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 5523329'|
|dataverse-JOXAFP|`Output/TablesFigures/results_genda.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55232960' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 55232960'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55232960' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 5523296'|
|dataverse-JOXAFP|`Output/TablesFigures/results_income_nysiisa.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55238422' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 55238422'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55238422' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 5523842'|
|dataverse-JOXAFP|`Output/TablesFigures/results_incomea.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 49644045' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 49644045'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 49644045' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 4964404'|
|dataverse-JOXAFP|`Output/TablesFigures/results_indiva.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55030869' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 55030869'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55030869' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 5503086'|
|dataverse-JOXAFP|`Output/TablesFigures/results_insta.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55232960' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 55232960'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55232960' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 5523296'|
|dataverse-JOXAFP|`Output/TablesFigures/results_lasttreateda.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 31522221' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 31522221'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 31522221' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 3152222'|
|dataverse-JOXAFP|`Output/TablesFigures/results_main_pinta.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55233292' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 55233292'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55233292' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 5523329'|
|dataverse-JOXAFP|`Output/TablesFigures/results_realpropheta.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 24967029' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 24967029'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 24967029' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 2496702'|
|dataverse-JOXAFP|`Output/TablesFigures/results_residencea.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55233292' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 55233292'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55233292' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 5523329'|
|dataverse-JOXAFP|`Output/TablesFigures/results_robust_fbpla.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 27725858' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 27725858'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 27725858' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 2772585'|
|dataverse-JOXAFP|`Output/TablesFigures/results_rtrendsa.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55233292' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 55233292'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 55233292' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 5523329'|
|dataverse-JOXAFP|`Output/TablesFigures/results_statesurnamea.tex`|NONDET|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 41458204' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_V/Code Observations & 41458204'|DIFF line 8: '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A/Code Observations & 41458204' vs '/home/leo/fastata-repl/pkgs/dataverse-JOXAFP/arm\\_A2/Code Observations & 4145820'|
|dataverse-QA1IDU|`2_output/Table3.rtf`|NONDET|DIFF numbers differ (max reldif 0.52)|DIFF numbers differ (max reldif 0.53)|
|dataverse-QA1IDU|`2_output/TableA3.rtf`|NONDET|DIFF numbers differ (max reldif 0.52)|DIFF numbers differ (max reldif 0.53)|
|dataverse-QA1IDU|`2_output/TableA4.rtf`|NONDET|DIFF numbers differ (max reldif 0.52)|DIFF numbers differ (max reldif 0.53)|
|dataverse-Y8MIH0|`RFS - Data Sharing Files/MainResults.rtf`|NONDET|DIFF numbers differ (max reldif 0.52)|DIFF numbers differ (max reldif 0.53)|
|dataverse-YWQZED|`Replication_Package_Finalized/Figure/Fig1_LPinvestment_by_year`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/Figure/Fig2_lp_industry_distribution`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/Figure/Fig5_likelihood`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/Figure/Fig6_compare_venture_hightech_dist`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/Figure/Fig7a_industry_distribution_old`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/Figure/Fig7b_industry_distribution_port`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/Figure/Fig7c_industry_distribution_new`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/Figure/FigOA2_1_def_entre_avg`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/Figure/FigOA2_1_def_entre_total`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/Figure/FigOA2_2_def_distress_avg`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/Figure/FigOA2_2_def_distress_total`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/Figure/FigOA2_5_Boom_and_Distressed_Ind`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/Figure/Fig_OA2_3_likelihood_positive`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/avg10.ster`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/avg20.ster`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/avg33.ster`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/avg5.ster`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/avg50.ster`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/total10.ster`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/total20.ster`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/total33.ster`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/total5.ster`|NONDET|DIFF bytes differ|DIFF bytes differ|
|dataverse-YWQZED|`Replication_Package_Finalized/total50.ster`|NONDET|DIFF bytes differ|DIFF bytes differ|
|zenodo-15311300|`<wrapper log>`|NONDET|DIFF numbers differ (max reldif 0.14)|DIFF line 752: '<RUN>/ReplicationDirectory/pr' vs '<RUN>/ReplicationDirectory/p'|
|zenodo-8290180|`3 replication package/Table 7.csv`|NONDET|DIFF line 1: 'PK\x03\x04\x14\x00\x00\x00\x08\x00ѝP]N�Ȗ\x0e\x01\x00\x00' vs 'PK\x03\x04\x14\x00\x00\x00\x08\x00'|DIFF line 1: 'PK\x03\x04\x14\x00\x00\x00\x08\x00ѝP]N�Ȗ\x0e\x01\x00\x00' vs 'PK\x03\x04\x14\x00\x00\x00\x08\x00C�P]N�Ȗ\x0e\x01\x00\x00'|

## Packages that dropped out

|stage: reason|packages|
|---|---:|
|scan: dominated by other languages|504|
|scan: no replaced-command call|337|
|scan: no master found|247|
|fetch: no Stata do-file|241|
|scan: no do-files|229|
|run_A: file <path> not found r(601);|131|
|run_A: > <path> not found r(601);|65|
|run_A: found r(601);|22|
|run_A: <path> not found r(601);|20|
|run_A: 3)  is not a Stata download site (has no stata.toc file). r(631);|19|
|run_A: invalid syntax r(198);|17|
|run_A: not found r(601);|14|
|run_A: timeout after 60 min|12|
|run_A: failed to export to the specified format. r(198);|10|
|run_A: unable to change to <path> r(170);|9|
|run_A: scheme modern not found r(111);|7|
|run_A: file <path> could not be opened r(603);|6|
|run_A: > <path> <path> not found r(601);|6|
|run_A: no FX_REPL_DONE in the log|6|
|fetch: 3-replication-package.zip: unpacks to more than 12 GB|6|
|fetch: ProxyError: HTTPSConnectionPool(host='zenodo.org', port=443): Max retr|5|
|run_A: command br is unrecognized r(199);|4|
|run_A: > dta not found r(601);|3|
|run_A: could not create directory <path> r(693);|3|
|run_A: host not found r(631);|3|
|run_A: file "rddensity_fun.do" not found r(601);|3|
|run_A: command window is unrecognized r(199);|3|
|run_A: command ivreghdfe is unrecognized r(199);|2|
|run_A: no log file open r(606);|2|
|run_A: .     exit 601 r(601);|2|
|run_A: file could not be opened r(603);|2|
|fetch: replication.zip: unpacks to more than 12 GB|2|
|run_A: <path> did not respond or is not a valid update site r(631);|2|
|run_A: insufficient observations r(2001);|2|
|run_A: --Break-- r(1);|2|
|run_A: option absorb() not allowed r(198);|2|
|run_A: file <path> <path> not found r(601);|2|
|run_A: assertion is false r(9);|2|
|run_A: unable to save PDF file r(691);|2|
|run_A: file 2560_BILANZ-SwissRichListDataset_1989-2020_Data_v1.0.dta not foun|2|
|run_A: file <path> 2.do not found r(601);|2|
|run_A: Adolescence <path> not found r(601);|1|
|run_A: > <path> A.1 - List of AODs.xlsx could not be saved r(603);|1|
|run_A: file temp_baseline_panel_for_matlab.dta not found r(601);|1|
|run_A: file File2.dta not found r(601);|1|
|run_A: Controls is not a memory graph r(198);|1|
|run_A: variable logemployees not found r(111);|1|
|run_A: To install, from within Stata type ssc install moremata r(601);|1|
|run_A: file analysis_final.dta not found r(601);|1|
|run_A: variable expo not found r(111);|1|
|run_A: > w_Comprehensive_October_21_2021.dta not found r(601);|1|
|run_A: > a.dta not found r(601);|1|
|run_A: > <path> could not be saved r(603);|1|
|run_A: > 8_corrected.dta not found r(601);|1|
|fetch: replication_package-Nov2024.zip: unpacks to more than 12 GB|1|
|run_A: command eventdd is unrecognized r(199);|1|
|run_A: > re.dta not found r(601);|1|
|run_A: > found r(601);|1|
|run_A: file data_cleaned.dta not found r(601);|1|
|run_A: The dataset of projects was not found. r(601);|1|
|run_A: file Sautmann-Brown-Dean_Mali-Timing-of-Care_ReStat.dta not found r(60|1|
|run_A: > onsensus.do not found r(601);|1|
|run_A: (error occurred while loading ivreg2.ado) r(3000);|1|
|run_A: • is not a valid command name r(199);|1|
|run_A: > ups_BrunoPellegrino.dta not found r(601);|1|
|run_A: file mainregression_data_pseudo.dta not found r(601);|1|
|run_A: file merged_dataset.dta not found r(601);|1|
|run_A: coefficient 1.select#1.open not found r(111);|1|
|run_A: > FTR.dta not found r(601);|1|
|run_A: file base_file_added.dta not found r(601);|1|
|run_A: file bargaining_data_one_by_one.csv not found r(601);|1|
|run_A: .     exit 198 r(198);|1|
|run_A: <istmt>:  3499  fastile() not found r(3499);|1|
|run_A: (error in option by()) r(111);|1|
|run_A: command distplot is unrecognized r(199);|1|
|run_A: > Metrics.dta not found r(601);|1|
|run_A: file merge_UC_Serrano_firm_characteristics.dta not found r(601);|1|
|run_A: file Fund_Month_Regression.dta not found r(601);|1|
|run_A: 05252011.xls not found r(601);|1|
|run_A: > spot_N_statexT.xlsx not found r(601);|1|
|run_A: file 01. Annual data construction not found r(601);|1|
|run_A: > I084_CB_A_YFRM_2014_JUN21_COMB_V01.dta not found r(601);|1|
|run_A: file task.dta not found r(601);|1|
|run_A: file Part0A_SetupCode_Suprises.do not found r(601);|1|
|run_A: file YTS.dta not found r(601);|1|
|run_A: file oregonhie_patterns_vars.dta not found r(601);|1|
|run_A: file Info Adopters.dta not found r(601);|1|
|run_A: ------------------------------------------------------- end run_projec|1|
|run_A: command grubbs is unrecognized r(199);|1|
|run_A: command manyiv is unrecognized r(199);|1|
|run_A: file 1982simple.dta not found r(601);|1|
|run_A: command ivreg2 is unrecognized r(199);|1|
|run_A: file figure2.do not found r(601);|1|
|run_A: > erences.do not found r(601);|1|
|run_A: (error occurred while loading _gtools_internal.ado) r(3000);|1|
|run_A: > <path> Use Data.csv not found r(601);|1|
|run_A: > nt_courts_naf_rev_2.csv is not a valid command name r(199);|1|
|run_A: <istmt>:     -  function returned error r(3498);|1|
|run_A: command sgmediation is unrecognized r(199);|1|
|run_A: > ta.dta not found r(601);|1|
|run_A: file **** YOUR PATH HERE **** <path> not found r(601);|1|
|run_A: file bv_mm_mig_data.dta not found r(601);|1|
|run_A: file create_hcris_vars.do not found r(601);|1|
|run_A: facility_start_date not found r(111);|1|
|run_A: -moremata- is required|1|
|run_A: type ssc install moremata r(499);|1|
|run_A: command brow is unrecognized r(199);|1|
|run_A: maximum using set maxvar|1|
|run_A: see help memory. r(900);|1|
|run_A: file data_working.dta not found r(601);|1|
|run_A: file dta <path> not found r(601);|1|
|run_A: command make_index_gr is unrecognized r(199);|1|
|run_A: file ENIA_F1.dta not found r(601);|1|
|run_A: file usa_00300.do not found r(601);|1|
|run_A: > nies.do not found r(601);|1|
|run_A: net price tool _3Q19_dataonly.xlsx not found r(601);|1|
|run_A: clearglobs not found r(111);|1|
|run_A: > raphs.do not found r(601);|1|
|run_A: unable to change to do r(170);|1|
|run_A: > isits_and_spend_merge.csv not found r(601);|1|
|run_A: 0.5 is not a valid command name r(199);|1|
|run_A: > to201511_selecteditems_n.dta not found r(601);|1|
|run_A: file YOUR ROOT <path> not found r(601);|1|
|run_A: file psychighfreq_AllAges_finalfull.dta not found r(601);|1|
|run_A: 1103_de_2009_a_2016.dta not found r(601);|1|
|run_A: file raven_risklink.txt not found r(601);|1|
|run_A: not Stata format r(610);|1|
|run_A: file data2025.dta not found r(601);|1|
|run_A: file regression_data.dta not found r(601);|1|
|run_A: > ensionfunddata_main.dta not found r(601);|1|
|run_A: STATA FILE e.g. XXX.dta not found r(601);|1|
|run_A: file database_individual_level.dta not found r(601);|1|
|run_A: > _COMBINESURVEY_final.do not found r(601);|1|
|run_A: file Author-paper-referee level data.dta not found r(601);|1|
|run_A: Wanted Abortion.do not found r(601);|1|
|run_A: unable to change to <path> <path> Spreadsheets r(170);|1|
|run_A: file FX_Bloomberg_daily.xlsx not found r(601);|1|
|run_A: > s_data.do not found r(601);|1|
|run_A: command DCdensity is unrecognized r(199);|1|
|run_A: option contents() not allowed since Stata 17|1|
|run_A: see help table for updated syntax r(198);|1|
|run_A: translator Graph2tif not found r(111);|1|
|run_A: command eststo is unrecognized r(199);|1|
|run_A: file USER SPECIFY <path> not found r(601);|1|
|run_A: file clean_ifls.do not found r(601);|1|
|run_A: > ects. r(111);|1|
|run_V: (type -clear mata- to clear Mata) r(4);|1|
|run_A: could not find Graph window r(693);|1|
|run_A: =1997 invalid name r(198);|1|
|run_A: file temp8.dta not found r(601);|1|
|run_A: file 00.Parameters.do not found r(601);|1|
|run_A: > epare-baseline.do not found r(601);|1|
|run_A: file tables.do not found r(601);|1|
|run_A: > <path> could not be opened r(603);|1|
|run_A: directorywhereyou'vesavedreplicationfilestructure invalid name r(198);|1|
|run_A: <path> MS_20180234_AppendixTableA1.do not found r(601);|1|
|run_A: estsample not found r(111);|1|
|run_A: file firm_sample.dta not found r(601);|1|
|run_A: file Rickne_Lev_Arbmiljo_1991.dta not found r(601);|1|
|run_A: variable permitarea not found r(111);|1|
|run_A: file LePennecPons2023.dta not found r(601);|1|
|run_A: file IND2017ER.do not found r(601);|1|
|run_A: > inal.dta not found r(601);|1|
|run_A: command standardize_env is unrecognized r(199);|1|
|run_A: > Directories.do not found r(601);|1|
|run_A: variable rfs_id not found r(111);|1|
|run_A: file LCR_format_December2021__HeSongRFS.dta not found r(601);|1|
|run_A: require: 8 packages are failing requirements r(601);|1|
|run_A: > ck_DN_volatility.dta already exists r(602);|1|
|run_A: file scc_hp_part_dh_06212021_crosswalk.csv not found r(601);|1|
|run_A: command rddisttestk is unrecognized r(199);|1|
|run_A: > <path> 3 Part 1_Household Characteristics.dta not found r(601);|1|
|run_A: invalid 'Claims' r(198);|1|
|run_A: command frameappend is unrecognized r(199);|1|
|run_A: command sas is unrecognized r(199);|1|
|run_A: file uber_usage_dataset.dta not found r(601);|1|
|run_A: studyname is a string variable r(109);|1|
|run_A: > hecks.do not found r(601);|1|
|run_A: file 1_clean_nsc.do not found r(601);|1|
|run_A: could not create directory tables r(693);|1|
|run_A: variable inf_prior not found r(111);|1|
|run_A: file Baseline CEO firm year sample.dta not found r(601);|1|
|run_A: invalid syntax r(111);|1|
|run_A: scheme cblind1 not found r(111);|1|
|run_A: dirname not allowed r(101);|1|
|run_A: > _performance.do not found r(601);|1|
|run_A: varlist, if exp, or in range required r(100);|1|
|run_A: > baseline.do not found r(601);|1|
|run_A: option effects_equal incorrectly specified r(198);|1|
|run_A: > <path> replace) invalid r(498);|1|
|run_A: scheme opp_insights_fb not found r(111);|1|
|run_A: > s.dta not found r(601);|1|
|run_A: file mor_div_fig_main_9193_95.do not found r(601);|1|
|run_A: <path> is not a valid command name r(199);|1|
|run_A: > omplete_20230606.dta not found r(601);|1|
|run_A: file hf_performance_portfolio_sat.csv not found r(601);|1|
|run_A: > ams.do not found r(601);|1|
|run_A: > ist8.dbf not found r(601);|1|
|run_A: file 01_European_analysis.do not found r(601);|1|
|run_A: file postg_analysis.dta not found r(601);|1|
|run_A: file f_kurs_1974-2018.dta not found r(601);|1|
|run_A: > ata.do not found r(601);|1|
|run_A: file creating_sleep_analysis_deid.do not found r(601);|1|
|run_A: > irmsize_total.csv not found r(601);|1|
|run_A: variable aage not found r(111);|1|
|run_A: scheme PS_Custom not found r(111);|1|
|fetch: restricted files|1|
|run_A: > s.sas7bdat not found r(601);|1|
|run_A: > 2013.dta not found r(601);|1|
|run_A: could not be opened r(603);|1|
|run_A: type mismatch r(109);|1|
|run_A: > tallpackages.do not found r(601);|1|
|run_A: > 2.dta not found r(601);|1|
|run_A: > radminvars.dta not found r(601);|1|
|fetch: public_sector.zip: unpacks to more than 12 GB|1|
|run_A: could not read from Graph window r(692);|1|
|run_A: file temp_supply_agg.dta not found r(601);|1|
|fetch: MS240038_Replication_Package.zip: unpacks to more than 12 GB|1|
|run_A: > ta_setup.do not found r(601);|1|
|run_A: > ork_directory not found r(601);|1|
|run_A: file clean_nobel.do not found r(601);|1|
|run_A: .     exit 111 r(111);|1|
|run_A: an error occurred when bootstrap executed Ey_boot r(199);|1|
|run_A: file ecf_interleave_sein_t13_extract.dta not found r(601);|1|
|run_A: scheme burd4 not found r(111);|1|
|run_A: no observations r(2000);|1|
|run_A: > _all_largestT_1865.dta not found r(601);|1|
|run_A: empirical <path> not found r(601);|1|
|run_A: command bartik_weight is unrecognized r(199);|1|
|run_A: Confidential <path> not found r(601);|1|
|run_A: file n280556_taxrebate_may08_wv1.fnldat not found r(601);|1|
|run_A: <path> invalid name r(198);|1|
|run_A: min.csv not found r(601);|1|
|run_A: file format_wiod.do not found r(601);|1|
|run_A: file benknow_prep.do not found r(601);|1|
|run_A: and run acreg again r(498);|1|
|run_A: > nbaum.do not found r(601);|1|
|run_A: file org_sorted_data.dta not found r(601);|1|
|run_A: file <path> Data cleaning.do not found r(601);|1|
|run_A: end of do-file r(601);|1|
|run_A: <istmt>:  3499  parallel_break() not found r(3499);|1|
|run_A: file prowess_returns.dta not found r(601);|1|
|fetch: 3-replication.zip: unpacks to more than 12 GB|1|
|run_A: file paths added at the <path> not found r(601);|1|
|run_A: > l.dta not found r(601);|1|
|run_A: > rogramme <path> not found r(601);|1|
|run_A: <path> <path> not found r(601);|1|
|run_A: option nlocalmin() not allowed r(198);|1|
|run_A: command legend is unrecognized r(199);|1|
|run_A: file Tr_vivienda15.dta not found r(601);|1|
|run_A: file <path> - Folders and files.do not found r(601);|1|
|run_A: > vars_202108_EN_1.0p.dta not found r(601);|1|
|run_A: file cgmwildboot.ado not found r(601);|1|
|run_A: > <path> r(693);|1|
|run_A: > am_bestcontrol.dta not found r(601);|1|
|run_A: To see a list of installed geographies run: maptile_geolist r(198);|1|
|run_A: not be opened r(603);|1|
|run_A: file <path> <path> <path> not found r(601);|1|
|run_A: file mktsummary.dta not found r(601);|1|
|run_A: option gen() required r(198);|1|
|run_A: file create_main_file_1.do not found r(601);|1|
|run_A: scheme lean2 not found r(111);|1|
|run_A: unknown egen function xtile() r(133);|1|
|run_A: file ejdependencies.zip not found r(601);|1|
|run_A: 2016.csv not found r(601);|1|
|run_A: file nhgis0004_ds13_1860_state.dat not found r(601);|1|
|run_A: > a.xlsx could not be saved r(603);|1|
|run_A: > <path> 4.xlsx could not be saved r(603);|1|
|run_A: > 20151113.dta not found r(601);|1|
|run_A: file SLMSround1.dta not found r(601);|1|
|run_A: file SWIFT Institute Volume MT103 Jan 2003 - Dec 2003.xlsx not found r|1|
|fetch: ChunkedEncodingError: ('Connection broken: IncompleteRead(1798760 byte|1|
|run_A: - install from GitHub r(9);|1|
|run_A: 2)  is not a Stata download directory (has no stata.toc file). r(601);|1|
|fetch: ChunkedEncodingError: ('Connection broken: IncompleteRead(49083148 byt|1|
|run_A: file BVW25_Analysis_Study 1.do not found r(601);|1|
|run_A: file full_data_clean.csv not found r(601);|1|
|run_A: > o <path> not found r(601);|1|
|run_A: command Graph is unrecognized r(199);|1|
|run_A: file <path> could not be saved r(603);|1|
|run_A: command orth_out is unrecognized r(199);|1|
|run_A: > v not found r(601);|1|
|run_A: > i1990.dta not found r(601);|1|
|run_A: home not found r(111);|1|
|fetch: ChunkedEncodingError: ('Connection broken: IncompleteRead(20718760 byt|1|
|run_A: command reghdfe is unrecognized r(199);|1|
|run_A: <istmt>:     -  function returned error r(3499);|1|
|run_A: file Data_complete_raw.csv already exists r(602);|1|
|run_A: file nyckel-sni2002-sni2007.xlsx not found r(601);|1|
|run_A: (error occurred while loading ivreghdfe.ado) r(3000);|1|
|run_A: (error occurred while loading robreg.ado) r(499);|1|
|run_A: variable longitude not found r(111);|1|
|run_A: > <path> specified in suboption data() not found r(601);|1|
|run_A: variable pre_switch_up not found r(111);|1|
|run_A: file Master.do not found r(601);|1|
|run_A: > Life10_spine.dta not found r(601);|1|
|run_A: file marital_cohabit_91_15.dta not found r(601);|1|
|run_A: <istmt>:     -  function returned error r(3200);|1|
|run_A: > on +string() r(133);|1|
|run_A: > ic345789_hes_apc_201299.dta not found r(601);|1|
|run_A: > <path> r(170);|1|
|run_A: command coefplot is unrecognized r(199);|1|
|run_A: .     exit 499 r(499);|1|
|run_A: command iabinstall is unrecognized r(199);|1|
|run_A: file synthetic_mt17-19_exp.dta not found r(601);|1|
|run_A: > g_job.csv not found r(601);|1|
|run_A: file cutoffs.dta not found r(601);|1|
|run_A: Acknowledgements.do not found r(601);|1|
|run_A: invalid 'replication' r(198);|1|
|run_A: file fulldata.dta not found r(601);|1|
|run_A: for Replication.dta not found r(601);|1|
|run_A: :  :  :  :  :  :  :  :  :  :  :  : command binscatter is unrecognized |1|
|run_A: <path> 4 7 8 9.do not found r(601);|1|
|run_A: 2016V1.dta not found r(601);|1|
|run_A: file data_mortality_1.dta not found r(601);|1|
|run_A: Config_stata.do is not a valid command name r(199);|1|
|run_A: file 0_Datageneration_2021_08_22.do not found r(601);|1|
|fetch: Replication package.zip: unpacks to more than 12 GB|1|
|run_A: file RCT_survey_data_noPII_PUBLIC.dta not found r(601);|1|
|run_A: option width() required r(198);|1|
