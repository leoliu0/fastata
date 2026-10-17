# fastata replication results

Generated 2026-10-17 19:17 by `repl report`. Arms: A original commands; V fastata in verify mode (every fast call is checked against the original, which also decides the session state), compared strictly with A; A2 a second A run, for packages that are nondeterministic themselves (NONDET files). Packages compared with arm F (fastata as users run it, with tolerance; B = A with `set sortseed 20261015` for TIE files) are marked F.
A package counts when it was compared and its fastata arm made at least one fast call. A package fails on any DIFF or ERR file or any verify mismatch.

## Totals

- counted packages: **100** (PASS 100, files with DIFF: 0, verify mismatches: 0)
- verified calls (counted packages): ok 375039, mismatch 0, skipped 0
- compared packages: 114; packages tried: 1777
- file verdicts (all compared packages): SAME 3018, NEAR 0, TIE 0, NONDET 65, DIFF 0, SKIP 1174, ERR 0
- fastata the counted packages were verified with: `a67bb45 plugin 1d12c5682306`: 100 (current)

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
|dataverse-0TXDTW|REStat|2026|[10.7910/DVN/0TXDTW](https://doi.org/10.7910/DVN/0TXDTW)|Replication Data for: Globalization, Innovation, and Margins of Sourcing|V|a67bb45 plugin 1d12c5682306|1|0|0.50|destring 1/0|1/0/0|4|0|0|0|0|0|PASS|
|dataverse-2BADW3|JPE|2023|[10.7910/DVN/2BADW3](https://doi.org/10.7910/DVN/2BADW3)|Replication Data for: The Effect of Incentives in Non-Routine Analytical Team Tasks|V|a67bb45 plugin 1d12c5682306|76|96|1.27|destring 8/0, egen 721/0|729/0/0|50|0|0|0|0|22|PASS|
|dataverse-2BVMKX|QJE|2026|[10.7910/DVN/2BVMKX](https://doi.org/10.7910/DVN/2BVMKX)|Replication Data for: 'In Their Shoes: Empathy Through Information'|V|e124768 plugin 48249ced076c|0|0|1.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|dataverse-58OI0B|REStat|2026|[10.7910/DVN/58OI0B](https://doi.org/10.7910/DVN/58OI0B)|Replication Data for: Good News Is Not a Sufficient Condition for Motivated Reasoning|V|a67bb45 plugin 1d12c5682306|11|14|1.33|egen 24/3|24/0/0|6|0|0|0|0|6|PASS|
|dataverse-5GRHLO|RFS|2024|[10.7910/DVN/5GRHLO](https://doi.org/10.7910/DVN/5GRHLO)|Replication Data for "Teams and Bankruptcy"|V|a67bb45 plugin 1d12c5682306|267|304|1.14|duplicates 4/0, egen 3/2|7/0/0|12|0|0|0|0|5|PASS|
|dataverse-5JGHDM|REStat|2026|[10.7910/DVN/5JGHDM](https://doi.org/10.7910/DVN/5JGHDM)|DRV, SOEP, SAVE|V|a67bb45 plugin 1d12c5682306|17|17|0.95|destring 138/8, egen 24/0|162/0/0|160|0|0|0|0|3|PASS|
|dataverse-6KG67M|JPE|2025|[10.7910/DVN/6KG67M](https://doi.org/10.7910/DVN/6KG67M)|Replication Data for: "The Origin of the State: Land Productivity or Appropriability? Comm|V|a67bb45 plugin 1d12c5682306|10|26|2.46|egen 337/0|337/0/0|4|0|0|0|0|1|PASS|
|dataverse-77YTLD|RFS|2026|[10.7910/DVN/77YTLD](https://doi.org/10.7910/DVN/77YTLD)|Replication Package for: Capital Controls, Corporate Debt and Real Effects: Evidence from |V|a67bb45 plugin 1d12c5682306|759|1386|1.83|destring 27/0, duplicates 20/0, egen 292/135, tostring 11/0|350/0/0|62|0|0|9|0|8|PASS|
|dataverse-8MKKPO|RFS|2023|[10.7910/DVN/8MKKPO](https://doi.org/10.7910/DVN/8MKKPO)|Replication Data for: Size Discount and Size Penalty: Trading Costs in Bond Markets|V|a67bb45 plugin 1d12c5682306|47|66|1.40|duplicates 9/0, egen 764/249|773/0/0|40|0|0|0|0|8|PASS|
|dataverse-9KNRFO|JPE|2025|[10.7910/DVN/9KNRFO](https://doi.org/10.7910/DVN/9KNRFO)|Replication Data for: Exchange Rates and Asset Prices in a Global Demand System|V|e124768 plugin 48249ced076c|0|0|1.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|dataverse-A9ZFFF|QJE|2026|[10.7910/DVN/A9ZFFF](https://doi.org/10.7910/DVN/A9ZFFF)|Replication Data for: '(Not) Thinking About the Future: Financial Information and Maternal|V|a67bb45 plugin 1d12c5682306|243|893|3.67|destring 26/11, duplicates 3/0, egen 162739/41, tostring 4/0|162772/0/0|98|0|0|0|0|55|PASS|
|dataverse-AOY4D6|QJE|2026|[10.7910/DVN/AOY4D6](https://doi.org/10.7910/DVN/AOY4D6)|Replication Data for: 'Stories, Statistics, and Memory'|V|a67bb45 plugin 1d12c5682306|18|20|1.12|destring 14/14, duplicates 39/0, egen 55/14, pctile 4/0|112/0/0|80|0|0|0|0|34|PASS|
|dataverse-AQDEXY|REStat|2025|[10.7910/DVN/AQDEXY](https://doi.org/10.7910/DVN/AQDEXY)|Replication Data for: Minimum Wages and Poverty: New Evidence from Dynamic Difference-in-D|V|e124768 plugin 48249ced076c|0|0|1.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|dataverse-AQJWOH|QJE|2026|[10.7910/DVN/AQJWOH](https://doi.org/10.7910/DVN/AQJWOH)|Replication Data for: 'How Does Wage Inequality Affect the Labor Movement?'|V|a67bb45 plugin 1d12c5682306|12|12|1.03|destring 1/0, egen 21/0, tostring 1/0|23/0/0|2|0|0|0|0|31|PASS|
|dataverse-BF4W3E|REStat|2025|[10.7910/DVN/BF4W3E](https://doi.org/10.7910/DVN/BF4W3E)|Replication data for: The Response of Wages to Rejected Offers|V|a67bb45 plugin 1d12c5682306|260|422|1.62|egen 7/6, xtile 1/0|8/0/0|12|0|0|0|0|6|PASS|
|dataverse-BG3V8P|REStat|2024|[10.7910/DVN/BG3V8P](https://doi.org/10.7910/DVN/BG3V8P)|Replication data for: Peer Effects in the Adoption of a Youth Employment Subsidy|V|a67bb45 plugin 1d12c5682306|22|33|1.49|egen 2/0|2/0/0|1|0|0|0|0|5|PASS|
|dataverse-BYAMQ6|RFS|2025|[10.7910/DVN/BYAMQ6](https://doi.org/10.7910/DVN/BYAMQ6)|Replication Data for: Data-driven Investors|V|a67bb45 plugin 1d12c5682306|19|23|1.21|egen 18/0, xtile 7/0|25/0/0|2|0|0|0|0|0|PASS|
|dataverse-CRXOAN|JPE Micro|2024|[10.7910/DVN/CRXOAN](https://doi.org/10.7910/DVN/CRXOAN)|Replication Data for: "Delegation in Hiring: Evidence from a Two-Sided Audit"|V|a67bb45 plugin 1d12c5682306|2446|2338|0.96|destring 108/0, egen 115/3, tostring 20/0, xtile 1/0|244/0/0|126|0|0|0|0|2|PASS|
|dataverse-CYF1X4|JPE|2025|[10.7910/DVN/CYF1X4](https://doi.org/10.7910/DVN/CYF1X4)|Replication Data for: "A Model of Social Duties"|V|a67bb45 plugin 1d12c5682306|20|30|1.48|destring 8/0, egen 0/372|8/0/0|59|0|0|0|0|26|PASS|
|dataverse-DCKKLW|REStat|2026|[10.7910/DVN/DCKKLW](https://doi.org/10.7910/DVN/DCKKLW)|Replication data for: When Transparency Fails: Financial Incentives for Local Banking Agen|V|a67bb45 plugin 1d12c5682306|0|0|2.00|destring 2/0, tostring 1/0|3/0/0|3|0|0|0|0|0|PASS|
|dataverse-DWKN2J|RFS|2026|[10.7910/DVN/DWKN2J](https://doi.org/10.7910/DVN/DWKN2J)|Replication Package for: How Private Equity Fuels Non-Bank Lending|V|a67bb45 plugin 1d12c5682306|10|14|1.38|duplicates 4/0, egen 28/1|32/0/0|31|0|0|0|0|3|PASS|
|dataverse-DZBURR|REStat|2024|[10.7910/DVN/DZBURR](https://doi.org/10.7910/DVN/DZBURR)|Replication data for: The Unintended Consequences of Infrastructure Development|V|e124768 plugin 48249ced076c|0|0|1.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|dataverse-E7HAPA|REStat|2024|[10.7910/DVN/E7HAPA](https://doi.org/10.7910/DVN/E7HAPA)|Replication Data for:Human Capital and Climate Change|V|a67bb45 plugin 1d12c5682306|678|645|0.95|egen 40/12|40/0/0|31|0|0|0|0|2|PASS|
|dataverse-EHXLE4|JPE|2023|[10.7910/DVN/EHXLE4](https://doi.org/10.7910/DVN/EHXLE4)|Replication Data for: Estimation of a Life-Cycle Model with Human Capital, Labor Supply, a|V|a67bb45 plugin 1d12c5682306|161|203|1.26|egen 14/0|14/0/0|40|0|0|0|0|68|PASS|
|dataverse-EP9TGW|RFS|2026|[10.7910/DVN/EP9TGW](https://doi.org/10.7910/DVN/EP9TGW)|Replication Package for: Mutual Fund Flows and the Supply of Capital in Municipal Financin|V|a67bb45 plugin 1d12c5682306|37|43|1.16|duplicates 2/0, egen 23/6, tostring 1/0|26/0/0|55|0|0|0|0|7|PASS|
|dataverse-ERHYH7|RFS|2025|[10.7910/DVN/ERHYH7](https://doi.org/10.7910/DVN/ERHYH7)|Replication Data for: Risk Managers in Banks|V|a67bb45 plugin 1d12c5682306|8|13|1.63|egen 98/0|98/0/0|4|0|0|1|0|0|PASS|
|dataverse-F1MTEN|REStat|2026|[10.7910/DVN/F1MTEN](https://doi.org/10.7910/DVN/F1MTEN)|Replication data for: Firm Responses to Hiring and Investment Subsidies: Regression Discon|V|a67bb45 plugin 1d12c5682306|8|7|0.88|egen 4/0|4/0/0|5|0|0|0|0|3|PASS|
|dataverse-FTVDNH|JPE Macro|2023|[10.7910/DVN/FTVDNH](https://doi.org/10.7910/DVN/FTVDNH)|Replication Data for: "'Golden Ages': A Tale of the Labor Markets in China and the United |V|a67bb45 plugin 1d12c5682306|284|448|1.58|destring 1/0, egen 542/1468|543/0/0|41|0|0|0|0|15|PASS|
|dataverse-GOORY3|REStat|2026|[10.7910/DVN/GOORY3](https://doi.org/10.7910/DVN/GOORY3)|Replication Data for: Contracting structures in public procurement: Evidence from donor-fu|V|a67bb45 plugin 1d12c5682306|120|136|1.13|destring 1/0, duplicates 2/0, egen 14/0, isid 10/0|27/0/0|8|0|0|0|0|26|PASS|
|dataverse-GOXYYT|RFS|2026|[10.7910/DVN/GOXYYT](https://doi.org/10.7910/DVN/GOXYYT)|Replication Package for: United They Fall: Bank Risk After the Financial Crisis|V|a67bb45 plugin 1d12c5682306|23|27|1.20|egen 29/0|29/0/0|14|0|0|0|0|2|PASS|
|dataverse-H5CWEP|REStat|2024|[10.7910/DVN/H5CWEP](https://doi.org/10.7910/DVN/H5CWEP)|Replication data for: The Impact of Children’s Health Shocks on Parents’ Labor Earnings an|V|e124768 plugin 48249ced076c|0|0|1.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|dataverse-HIY143|JPE|2025|[10.7910/DVN/HIY143](https://doi.org/10.7910/DVN/HIY143)|Replication Data for: Black Empowerment and White Mobilization: The Effects of the Voting |V|a67bb45 plugin 1d12c5682306|19|23|1.22|egen 32/0|32/0/0|8|0|0|0|0|22|PASS|
|dataverse-HYJFCL|RFS|2024|[10.7910/DVN/HYJFCL](https://doi.org/10.7910/DVN/HYJFCL)|Replication Data for: "Financial Effects of Remote Product Delivery: Evidence from Hospita|V|a67bb45 plugin 1d12c5682306|13|20|1.54|egen 3/0|3/0/0|2|0|0|0|0|14|PASS|
|dataverse-ICNB18|JPE Micro|2026|[10.7910/DVN/ICNB18](https://doi.org/10.7910/DVN/ICNB18)|Replication Data for: Attention as a First-Order Barrier to Adoption of Evidence-based Pro|V|a67bb45 plugin 1d12c5682306|2|2|1.11|egen 3/0|3/0/0|22|0|0|0|0|0|PASS|
|dataverse-JD0W1S|RFS|2026|[10.7910/DVN/JD0W1S](https://doi.org/10.7910/DVN/JD0W1S)|Replication Package for: Financial Advice and Investor Beliefs: Experimental Evidence on A|V|a67bb45 plugin 1d12c5682306|9|10|1.14|egen 95/1, isid 1/0|96/0/0|27|0|0|0|0|10|PASS|
|dataverse-JFEZXC|RFS|2025|[10.7910/DVN/JFEZXC](https://doi.org/10.7910/DVN/JFEZXC)|Replication Data for: The Impact of Consolidation on Credit Supply and Performance (RFS MS|V|a67bb45 plugin 1d12c5682306|14|21|1.55|destring 6/0, duplicates 20/0, egen 130/0, tostring 2/0, xtile 3/0|161/0/0|35|0|0|4|0|6|PASS|
|dataverse-JOXAFP|QJE|2024|[10.7910/DVN/JOXAFP](https://doi.org/10.7910/DVN/JOXAFP)|Replication Data for: 'Economic Consequences of Kinship: Evidence from U.S. Bans on Cousin|V|a67bb45 plugin 1d12c5682306|741|930|1.25|egen 3/1, isid 5/0, tostring 1/0|9/0/0|27|0|0|21|0|29|PASS|
|dataverse-KIDK6R|RFS|2026|[10.7910/DVN/KIDK6R](https://doi.org/10.7910/DVN/KIDK6R)|Replication Package for: The Coherence Side of Rationality: Theory and Evidence from Firm |V|a67bb45 plugin 1d12c5682306|355|735|2.07|duplicates 2/0, egen 627/0, isid 10/0|639/0/0|51|0|0|0|0|4|PASS|
|dataverse-LSBHQJ|JPE Macro|2026|[10.7910/DVN/LSBHQJ](https://doi.org/10.7910/DVN/LSBHQJ)|Replication Data for: We Think That They Think: Political Affiliation and Higher-Order Bel|V|a67bb45 plugin 1d12c5682306|81|80|0.99|duplicates 5/0, egen 11/8|16/0/0|71|0|0|0|0|88|PASS|
|dataverse-MSQE6U|QJE|2023|[10.7910/DVN/MSQE6U](https://doi.org/10.7910/DVN/MSQE6U)|Replication Data for: "Measuring Welfare and Inequality with Incomplete Price Information"|V|e124768 plugin 48249ced076c|0|0|2.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|dataverse-NYXW03|JPE|2026|[10.7910/DVN/NYXW03](https://doi.org/10.7910/DVN/NYXW03)|Replication Data for: Not Learning from Others|V|a67bb45 plugin 1d12c5682306|26|26|1.00|egen 7/3|7/0/0|21|0|0|0|0|30|PASS|
|dataverse-O4AUDQ|QJE|2026|[10.7910/DVN/O4AUDQ](https://doi.org/10.7910/DVN/O4AUDQ)|Replication Data for: 'The Macroeconomic Impact of Climate Change: Global Versus Local Tem|V|a67bb45 plugin 1d12c5682306|618|7683|12.42|duplicates 1/0, egen 151807/0|151808/0/0|49|0|0|0|0|122|PASS|
|dataverse-OBH3KV|RFS|2024|[10.7910/DVN/OBH3KV](https://doi.org/10.7910/DVN/OBH3KV)|Replication Data for: The Fed and the Secular Decline in Interest Rates|V|a67bb45 plugin 1d12c5682306|21|32|1.50|egen 2/0|2/0/0|8|0|0|0|0|20|PASS|
|dataverse-OQ8UYN|RFS|2023|[10.7910/DVN/OQ8UYN](https://doi.org/10.7910/DVN/OQ8UYN)|Replication code for: Freeze! Financial Sanctions and Bank Responses|V|a67bb45 plugin 1d12c5682306|132|180|1.37|duplicates 1/0, egen 9/0|10/0/0|12|0|0|0|0|4|PASS|
|dataverse-P7AQKG|RFS|2025|[10.7910/DVN/P7AQKG](https://doi.org/10.7910/DVN/P7AQKG)|The Effect of Primary Dealer Constraints on Intermediation in the Treasury Market|V|a67bb45 plugin 1d12c5682306|127|146|1.15|destring 3/0, duplicates 13/0, egen 122/3, isid 1/0, tostring 2/0|141/0/0|22|0|0|0|0|35|PASS|
|dataverse-PDFDKR|QJE|2025|[10.7910/DVN/PDFDKR](https://doi.org/10.7910/DVN/PDFDKR)|Replication Data for: 'Can Pollution Markets Work in Developing Countries? Experimental Ev|V|a67bb45 plugin 1d12c5682306|197|908|4.61|duplicates 9/0, egen 2155/12|2164/0/0|37|0|0|0|0|9|PASS|
|dataverse-PMVKXH|JPE Micro|2024|[10.7910/DVN/PMVKXH](https://doi.org/10.7910/DVN/PMVKXH)|Replication Data for: "The Thrill of Gradual Learning"|V|a67bb45 plugin 1d12c5682306|2|2|1.20|egen 8/1|8/0/0|2|0|0|0|0|1|PASS|
|dataverse-QA1IDU|REStat|2023|[10.7910/DVN/QA1IDU](https://doi.org/10.7910/DVN/QA1IDU)|Replication Data for: Discrimination, narratives and family history: An experiment with Jo|V|a67bb45 plugin 1d12c5682306|20|20|1.02|destring 1/0, duplicates 1/0, egen 4/0|6/0/0|9|0|0|3|0|3|PASS|
|dataverse-R2AM7F|RFS|2024|[10.7910/DVN/R2AM7F](https://doi.org/10.7910/DVN/R2AM7F)|Replication Data for: Finance, Advertising, and Race|V|a67bb45 plugin 1d12c5682306|8|14|1.88|destring 1/0, duplicates 1/0, egen 4/6|6/0/0|1|0|0|0|0|0|PASS|
|dataverse-RXWKTV|QJE|2023|[10.7910/DVN/RXWKTV](https://doi.org/10.7910/DVN/RXWKTV)|Replication Data for: 'Labor Market Dynamics and Development'|V|a67bb45 plugin 1d12c5682306|3|4|1.15|egen 24/0|24/0/0|5|0|0|0|0|0|PASS|
|dataverse-SHXCAH|REStat|2026|[10.7910/DVN/SHXCAH](https://doi.org/10.7910/DVN/SHXCAH)|Replication data for: How Credible are the Findings from Online Experiments?|V|a67bb45 plugin 1d12c5682306|149|181|1.22|destring 66/23, duplicates 33/0, egen 50/29, pctile 7/0, tostring 1/2|157/0/0|52|0|0|0|0|72|PASS|
|dataverse-TZ7OOV|REStat|2026|[10.7910/DVN/TZ7OOV](https://doi.org/10.7910/DVN/TZ7OOV)|Replication data for: The Factor Bias of External Inputs: Implications for Substitution be|V|a67bb45 plugin 1d12c5682306|225|346|1.53|destring 8503/0, duplicates 40/0, egen 281/203|8824/0/0|191|0|0|0|0|6|PASS|
|dataverse-VYPKDJ|RFS|2024|[10.7910/DVN/VYPKDJ](https://doi.org/10.7910/DVN/VYPKDJ)|Replication Data for: "Return Predictability, Expectations, and Investment: Experimental E|V|a67bb45 plugin 1d12c5682306|9|14|1.54|egen 153/0, tostring 0/2|153/0/0|34|0|0|0|0|0|PASS|
|dataverse-VZDBQF|REStat|2024|[10.7910/DVN/VZDBQF](https://doi.org/10.7910/DVN/VZDBQF)|Replication Data for: /Improving Workers' Performance in Small Firms: A Randomized Experim|V|a67bb45 plugin 1d12c5682306|0|2|6.33|egen 8/2|8/0/0|4|0|0|0|0|0|PASS|
|dataverse-XNV6CY|RFS|2025|[10.7910/DVN/XNV6CY](https://doi.org/10.7910/DVN/XNV6CY)|Replication Code and Pseudo-Data for "The Intangibles Song in Takeover Announcements: Good|V|e124768 plugin 48249ced076c|0|0|1.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|dataverse-XUJGCK|QJE|2026|[10.7910/DVN/XUJGCK](https://doi.org/10.7910/DVN/XUJGCK)|Replication Data for: 'Beliefs About the Economy Are Excessively Sensitive to Household-Le|V|a67bb45 plugin 1d12c5682306|11|16|1.52|destring 122/0, egen 78/2, tostring 1/0|201/0/0|37|0|0|0|0|14|PASS|
|dataverse-Y8MIH0|RFS|2025|[10.7910/DVN/Y8MIH0](https://doi.org/10.7910/DVN/Y8MIH0)|Replication Data for: The Real Effect of Sociopolitical Racial/Ethnic Animus: Mutual Fund |V|a67bb45 plugin 1d12c5682306|6|9|1.44|egen 18/0|18/0/0|1|0|0|1|0|0|PASS|
|dataverse-Y9M30R|RFS|2025|[10.7910/DVN/Y9M30R](https://doi.org/10.7910/DVN/Y9M30R)|Replication Data for: Technological Obsolescence|V|a67bb45 plugin 1d12c5682306|23|42|1.86|egen 430/0|430/0/0|15|0|0|0|0|6|PASS|
|dataverse-YMSVMX|RFS|2026|[10.7910/DVN/YMSVMX](https://doi.org/10.7910/DVN/YMSVMX)|Replication Package for: Firm-Level Labor-Shortage Exposure|V|a67bb45 plugin 1d12c5682306|60|77|1.28|destring 11/0, duplicates 8/0, egen 260/5, tostring 2/0|281/0/0|48|0|0|0|0|0|PASS|
|dataverse-YWQZED|RFS|2026|[10.7910/DVN/YWQZED](https://doi.org/10.7910/DVN/YWQZED)|Replication Data for: "Learning by Investing: Entrepreneurial Spillovers from Venture Capi|V|a67bb45 plugin 1d12c5682306|69|85|1.23|destring 13/0, duplicates 12/0, egen 208/31, tostring 11/0|244/0/0|72|0|0|23|0|13|PASS|
|dataverse-ZBJKLF|JPE Micro|2025|[10.7910/DVN/ZBJKLF](https://doi.org/10.7910/DVN/ZBJKLF)|Replication Data for: Comparing Crowdfunding Mechanisms: Introducing the Generalized Mouli|V|a67bb45 plugin 1d12c5682306|74|76|1.03|destring 19/0, egen 37/26|56/0/0|7|0|0|0|0|8|PASS|
|dataverse-ZBOLIK|JPE Micro|2026|[10.7910/DVN/ZBOLIK](https://doi.org/10.7910/DVN/ZBOLIK)|Replication Data for: Minimum Wages Reduce Restaurant Employment (Almost Any Way You Slice|V|a67bb45 plugin 1d12c5682306|84|96|1.15|duplicates 30/0, egen 793/108|823/0/0|41|0|0|0|0|14|PASS|
|dataverse-ZGMEQC|RFS|2026|[10.7910/DVN/ZGMEQC](https://doi.org/10.7910/DVN/ZGMEQC)|Replication Package for: Original Sin Redux: Role of Duration Risk|V|a67bb45 plugin 1d12c5682306|123|192|1.56|egen 402/17|402/0/0|24|0|0|0|0|22|PASS|
|dataverse-ZIXTGH|REStat|2026|[10.7910/DVN/ZIXTGH](https://doi.org/10.7910/DVN/ZIXTGH)|Replication data for: Gender Discrimination in Access to Capital: A Field Experiment in Et|V|a67bb45 plugin 1d12c5682306|189|244|1.30|destring 3/0, egen 29/5|32/0/0|41|0|0|0|0|7|PASS|
|zenodo-10120113|REStud|2023|[10.5281/zenodo.10120113](https://doi.org/10.5281/zenodo.10120113)|Replication package for: "The Impact of Online Competition on Local Newspapers: Evidence f|V|a67bb45 plugin 1d12c5682306|4|4|1.08|destring 13/0, duplicates 2/0, egen 3/0|18/0/0|2|0|0|0|0|0|PASS|
|zenodo-10535890|EJ|2024|[10.5281/zenodo.10535890](https://doi.org/10.5281/zenodo.10535890)|Replication package for: What to blame? Self-serving attribution bias with multi-dimension|V|a67bb45 plugin 1d12c5682306|9|12|1.41|destring 178/60, egen 13/2|191/0/0|65|0|0|0|0|0|PASS|
|zenodo-10557110|EJ|2024|[10.5281/zenodo.10557110](https://doi.org/10.5281/zenodo.10557110)|Replication package for: "Making policies matter: Voter responses to campaign promises"|V|a67bb45 plugin 1d12c5682306|11|11|1.02|egen 6/0, tostring 1/36|7/0/0|31|0|0|0|0|2|PASS|
|zenodo-10611203|REStud|2024|[10.5281/zenodo.10611203](https://doi.org/10.5281/zenodo.10611203)|Replication package for: "Structural Change, Elite Capitalism, and the Emergence of Labor |V|e124768 plugin 48249ced076c|3|4|1.42|egen 0/1|0/0/0|5|0|0|0|0|5|PASS (not counted)|
|zenodo-10629265|EJ|2024|[10.5281/zenodo.10629265](https://doi.org/10.5281/zenodo.10629265)|Bundling Genetic and Financial Technologies for More Resilient and Productive Small-scale |V|a67bb45 plugin 1d12c5682306|0|1|1.40|destring 1/0, egen 2/0|3/0/0|6|0|0|0|0|0|PASS|
|zenodo-10721159|EJ|2024|[10.5281/zenodo.10721159](https://doi.org/10.5281/zenodo.10721159)|Replication package for: "Immigration and the Short- and Long-Term Impact of Improved Pren|V|e124768 plugin 48249ced076c|2|2|0.88||0/0/0|1|0|0|0|0|8|PASS (not counted)|
|zenodo-10887743|EJ|2024|[10.5281/zenodo.10887743](https://doi.org/10.5281/zenodo.10887743)|Borrowing Constraints and Demand for Remedial Education: Evidence from Tanzania|V|e124768 plugin 48249ced076c|0|0|1.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|zenodo-11160672|EJ|2024|[10.5281/zenodo.11160672](https://doi.org/10.5281/zenodo.11160672)|Incentivizing Textbooks for Self-Study: Experimental Evidence from the Democratic Republic|V|a67bb45 plugin 1d12c5682306|1|2|1.88|egen 16/0|16/0/0|2|0|0|0|0|0|PASS|
|zenodo-11186567|EJ|2024|[10.5281/zenodo.11186567](https://doi.org/10.5281/zenodo.11186567)|Replication Package for: Long-Term Effects of Equal Sharing: Evidence from Inheritance Rul|V|a67bb45 plugin 1d12c5682306|22|59|2.67|egen 422/0|422/0/0|2|0|0|0|0|26|PASS|
|zenodo-11376471|EJ|2024|[10.5281/zenodo.11376471](https://doi.org/10.5281/zenodo.11376471)|Replication package for: "Measuring Social Benefits of Media Coverage: How Coverage of Cli|V|a67bb45 plugin 1d12c5682306|594|817|1.38|destring 432/0, duplicates 7/0, egen 41/0, tostring 123/0|603/0/0|21|0|0|0|0|0|PASS|
|zenodo-11447227|EJ|2024|[10.5281/zenodo.11447227](https://doi.org/10.5281/zenodo.11447227)|Gender Differences in Math Tests: The Role of Time Pressure|V|a67bb45 plugin 1d12c5682306|9|12|1.40|destring 0/1, egen 131/0|131/0/0|24|0|0|0|0|1|PASS|
|zenodo-14171972|REStud|2025|[10.5281/zenodo.14171972](https://doi.org/10.5281/zenodo.14171972)|Replication Package for Global Value Chains and Trade Policy|V|a67bb45 plugin 1d12c5682306|1080|1484|1.37|egen 62/3|62/0/0|6|0|0|0|0|8|PASS|
|zenodo-14503622|EJ|2024|[10.5281/zenodo.14503622](https://doi.org/10.5281/zenodo.14503622)|Replication package for: "To Defer or to Differ: Experimental Evidence on the Role of Cash|V|a67bb45 plugin 1d12c5682306|28|54|1.94|egen 488/0|488/0/0|40|0|0|0|0|0|PASS|
|zenodo-14726871|EJ|2025|[10.5281/zenodo.14726871](https://doi.org/10.5281/zenodo.14726871)|Replication package for Yellow Pages: Information, Connections, and Firm Performance|V|a67bb45 plugin 1d12c5682306|29|58|2.02|destring 1/0, duplicates 2/0, egen 187/0, isid 3/0, tostring 25/287|218/0/0|4|0|0|0|0|0|PASS|
|zenodo-14780637|REStud|2025|[10.5281/zenodo.14780637](https://doi.org/10.5281/zenodo.14780637)|Replication package for: How Important Is Health Inequality for Lifetime Earnings Inequali|V|a67bb45 plugin 1d12c5682306|39|66|1.70|duplicates 1/0, egen 7/0|8/0/0|3|0|0|0|0|0|PASS|
|zenodo-14933575|EJ|2025|[10.5281/zenodo.14933575](https://doi.org/10.5281/zenodo.14933575)|Replication Package for: Managerial Leadership, Truth-Telling, and Efficient Coordination|V|a67bb45 plugin 1d12c5682306|3|5|1.89|egen 110/0|110/0/0|5|0|0|0|0|0|PASS|
|zenodo-14976627|REStud|2025|[10.5281/zenodo.14976627](https://doi.org/10.5281/zenodo.14976627)|Creating Cohesive Communities: A Youth Camp Experiment in India|V|a67bb45 plugin 1d12c5682306|1|4|5.83|destring 20/0, duplicates 1/0, egen 40/1, tostring 18/0|79/0/0|13|0|0|0|0|0|PASS|
|zenodo-15223629|EJ|2025|[10.5281/zenodo.15223629](https://doi.org/10.5281/zenodo.15223629)|Replication package for: "Genetic and Socioeconomic Achievement Gaps in Elementary School"|V|a67bb45 plugin 1d12c5682306|3|7|2.12|duplicates 5/0, egen 53/0, tostring 1/0, xtile 15/0|74/0/0|1|0|0|0|0|0|PASS|
|zenodo-15311300|REStud|2025|[10.5281/zenodo.15311300](https://doi.org/10.5281/zenodo.15311300)|Replication package for: Narratives about the Macroeconomy|V|a67bb45 plugin 1d12c5682306|10|19|1.84|destring 1/17, duplicates 2/0, egen 84/0|87/0/0|24|0|0|1|0|0|PASS|
|zenodo-15612582|EJ|2025|[10.5281/zenodo.15612582](https://doi.org/10.5281/zenodo.15612582)|Replication Package for: "Correlation Neglect on Social Media: Effects on Civil Service Ap|V|a67bb45 plugin 1d12c5682306|18|16|0.89|destring 1/0, egen 0/1|1/0/0|19|0|0|0|0|6|PASS|
|zenodo-15634053|EJ|2025|[10.5281/zenodo.15634053](https://doi.org/10.5281/zenodo.15634053)|Replication package for: "On the post-Enlightenment evolution of moral universalism"|V|a67bb45 plugin 1d12c5682306|24|32|1.30|egen 36/0|36/0/0|3|0|0|0|0|40|PASS|
|zenodo-16599207|EJ|2025|[10.5281/zenodo.16599207](https://doi.org/10.5281/zenodo.16599207)|Replication Package for "Civilian Evacuation During War: Evidence from Ukraine"|V|a67bb45 plugin 1d12c5682306|5|10|2.04|destring 1/0, egen 1/0|2/0/0|2|0|0|0|0|0|PASS|
|zenodo-16755528|REStud|2025|[10.5281/zenodo.16755528](https://doi.org/10.5281/zenodo.16755528)|Replication Package For: De Gustibus and Disputes about Reference Dependence|V|a67bb45 plugin 1d12c5682306|73|95|1.31|destring 13/0, egen 39/1, pctile 1/0|53/0/0|7|0|0|0|0|3|PASS|
|zenodo-17128105|EJ|2025|[10.5281/zenodo.17128105](https://doi.org/10.5281/zenodo.17128105)|Replication package for "To Savor Consumption or To Confront Dread: The Hedonic Opportunit|V|e124768 plugin 48249ced076c|6|8|1.17||0/0/0|8|0|0|0|0|3|PASS (not counted)|
|zenodo-17351754|EJ|2025|[10.5281/zenodo.17351754](https://doi.org/10.5281/zenodo.17351754)|Replication package for: "Income, Democracy, and Growth: Reconciling Evidence and Theory"|V|a67bb45 plugin 1d12c5682306|49|74|1.50|egen 74/5, isid 2/0|76/0/0|26|0|0|0|0|7|PASS|
|zenodo-17468794|EJ|2025|[10.5281/zenodo.17468794](https://doi.org/10.5281/zenodo.17468794)|Replication package for: "Bad Democracy Traps"|V|a67bb45 plugin 1d12c5682306|11|18|1.60|destring 143/5, egen 116/0|259/0/0|22|0|0|0|0|2|PASS|
|zenodo-18600000|EJ|2026|[10.5281/zenodo.18600000](https://doi.org/10.5281/zenodo.18600000)|Replication package for: "Telementoring and homeschooling during school closures: A random|V|e124768 plugin 48249ced076c|10|9|0.91||0/0/0|1|0|0|0|0|2|PASS (not counted)|
|zenodo-18611342|EJ|2026|[10.5281/zenodo.18611342](https://doi.org/10.5281/zenodo.18611342)|Replication package for: "Motivated Risk Assessments"|V|a67bb45 plugin 1d12c5682306|10|13|1.31|egen 59/0|59/0/0|16|0|0|0|0|10|PASS|
|zenodo-18825108|REStud|2026|[10.5281/zenodo.18825108](https://doi.org/10.5281/zenodo.18825108)|Replication Package for: "The Selective Disclosure of Evidence: An Experiment"|V|a67bb45 plugin 1d12c5682306|16|39|2.40|duplicates 2/0, egen 1054/6|1056/0/0|1|0|0|0|0|10|PASS|
|zenodo-19115553|EJ|2026|[10.5281/zenodo.19115553](https://doi.org/10.5281/zenodo.19115553)|Impact or Responsibility? Giving Behaviour in a Televised Natural Experiment|V|a67bb45 plugin 1d12c5682306|342|409|1.20|destring 6/0, egen 217/9|223/0/0|27|0|0|0|0|0|PASS|
|zenodo-19234083|EJ|2026|[10.5281/zenodo.19234083](https://doi.org/10.5281/zenodo.19234083)|Replication package for: "Ruling the roost: the vicious circle and the emergence of peckin|V|a67bb45 plugin 1d12c5682306|30|43|1.44|destring 6/1920, egen 62/2|68/0/0|10|0|0|0|0|0|PASS|
|zenodo-19366496|EJ|2026|[10.5281/zenodo.19366496](https://doi.org/10.5281/zenodo.19366496)|Life Expectancy, Age, and Patience|V|a67bb45 plugin 1d12c5682306|290|458|1.58|destring 426/0, duplicates 1/0, egen 164/0|591/0/0|72|0|0|0|0|0|PASS|
|zenodo-19486751|REStud|2026|[10.5281/zenodo.19486751](https://doi.org/10.5281/zenodo.19486751)|Replication Package for: Paying to Match: Decentralized Markets with Information Frictions|V|a67bb45 plugin 1d12c5682306|1632|1755|1.08|destring 10/0, duplicates 5/0, egen 279/3|294/0/0|52|0|0|0|0|17|PASS|
|zenodo-19562339|EJ|2026|[10.5281/zenodo.19562339](https://doi.org/10.5281/zenodo.19562339)|Replication package for "Publicly targeting group identities impacts take-up of educationa|V|a67bb45 plugin 1d12c5682306|96|90|0.94|egen 13/0|13/0/0|41|0|0|0|0|36|PASS|
|zenodo-19743938|EJ|2026|[10.5281/zenodo.19743938](https://doi.org/10.5281/zenodo.19743938)|Replication for: "Campaigning to a Polarised Electorate: Emotions and Information in Real |V|a67bb45 plugin 1d12c5682306|7|8|1.11|egen 119/0|119/0/0|34|0|0|0|0|0|PASS|
|zenodo-20379084|EJ|2026|[10.5281/zenodo.20379084](https://doi.org/10.5281/zenodo.20379084)|Replication package for "On the Benefits of Robo-Advice in Financial Markets"|V|a67bb45 plugin 1d12c5682306|13|16|1.24|egen 2/0|2/0/0|8|0|0|0|0|0|PASS|
|zenodo-20383941|REStud|2026|[10.5281/zenodo.20383941](https://doi.org/10.5281/zenodo.20383941)|"Replication package for: Why Veil? Religious Headscarves and the Economic Role of Women"|V|a67bb45 plugin 1d12c5682306|53|75|1.42|egen 450/2, isid 4/0, pctile 1/0, tostring 1/0, xtile 0/1|456/0/0|27|0|0|0|0|7|PASS|
|zenodo-20542048|EJ|2026|[10.5281/zenodo.20542048](https://doi.org/10.5281/zenodo.20542048)|Replication package for: "On the doorstep of adulthood: Entrepreneurship and fertility of |V|a67bb45 plugin 1d12c5682306|1944|4730|2.43|duplicates 6/0, egen 33176/66063, tostring 327/227|33509/0/0|44|0|0|0|0|11|PASS|
|zenodo-20702728|EJ|2026|[10.5281/zenodo.20702728](https://doi.org/10.5281/zenodo.20702728)|Replication for Trust and Democracy: Political Stability in Times of Economic Crisis|V|a67bb45 plugin 1d12c5682306|118|123|1.05|destring 16/0, duplicates 14/0, egen 111/9, isid 4/0, tostring 1/0, xtile 1/0|147/0/0|70|0|0|0|0|0|PASS|
|zenodo-21698370|EJ|2026|[10.5281/zenodo.21698370](https://doi.org/10.5281/zenodo.21698370)|Replication package for: "Productivity and Entry Regulation in the Service Sector: Evidenc|V|a67bb45 plugin 1d12c5682306|31|36|1.16|duplicates 1/0, egen 88/65|89/0/0|5|0|0|0|0|10|PASS|
|zenodo-21725672|EJ|2026|[10.5281/zenodo.21725672](https://doi.org/10.5281/zenodo.21725672)|Replication package for: Remote work and effort provision in teams|V|a67bb45 plugin 1d12c5682306|7|8|1.16|destring 6/0, duplicates 1/0, egen 53/2, tostring 2/0|62/0/0|63|0|0|0|0|10|PASS|
|zenodo-21775195|EJ|2026|[10.5281/zenodo.21775195](https://doi.org/10.5281/zenodo.21775195)|Replication package for: "Group Identity and Belief Formation: A Microfoundation of Politi|V|e124768 plugin 48249ced076c|4|5|1.07|egen 0/2|0/0/0|8|0|0|0|0|0|PASS (not counted)|
|zenodo-23223970|EJ|2026|[10.5281/zenodo.23223970](https://doi.org/10.5281/zenodo.23223970)|Immigration and the Slope of the Labour Demand Curve: The Role of Firm Heterogeneity in a |V|a67bb45 plugin 1d12c5682306|91|109|1.20|destring 4/0, duplicates 4/0, egen 72/3, isid 2/0, tostring 1/0|83/0/0|50|0|0|0|0|4|PASS|
|zenodo-23320830|EJ|2026|[10.5281/zenodo.23320830](https://doi.org/10.5281/zenodo.23320830)|Replication package for: Cognitive ability, risk preferences and errors|V|a67bb45 plugin 1d12c5682306|663|1171|1.77|egen 2/0|2/0/0|35|0|0|0|0|0|PASS|
|zenodo-8168773|EJ|2023|[10.5281/zenodo.8168773](https://doi.org/10.5281/zenodo.8168773)|Replication package for: The Null Result Penalty|V|a67bb45 plugin 1d12c5682306|598|707|1.18|egen 106/2|106/0/0|18|0|0|0|0|5|PASS|
|zenodo-8242347|REStud|2023|[10.5281/zenodo.8242347](https://doi.org/10.5281/zenodo.8242347)|Path Dependency in Physician Decisions|V|a67bb45 plugin 1d12c5682306|1962|2543|1.30|duplicates 3/0, egen 1453/0|1456/0/0|32|0|0|0|0|12|PASS|
|zenodo-8290180|EJ|2023|[10.5281/zenodo.8290180](https://doi.org/10.5281/zenodo.8290180)|Replication package for "Deliberate Surrender? The Impact of Interwar Indian Protection"|V|a67bb45 plugin 1d12c5682306|87|74|0.85|destring 3/0, duplicates 2/0, egen 129/2|134/0/0|62|0|0|1|0|6|PASS|
|zenodo-8325645|EJ|2023|[10.5281/zenodo.8325645](https://doi.org/10.5281/zenodo.8325645)|Replication Package for "Unemployment and Development"|V|a67bb45 plugin 1d12c5682306|20|24|1.22|duplicates 11/0, egen 19/0|30/0/0|15|0|0|0|0|26|PASS|
|zenodo-8370126|REStud|2023|[10.5281/zenodo.8370126](https://doi.org/10.5281/zenodo.8370126)|Replication package for: {Monopoly of Taxation Without a Monopoly of Violence: The Weak St|V|e124768 plugin 48249ced076c|0|0|1.00||0/0/0|1|0|0|0|0|0|PASS (not counted)|
|zenodo-8373069|EJ|2023|[10.5281/zenodo.8373069](https://doi.org/10.5281/zenodo.8373069)|Replication package for: "Strategic Campaign Communication: Evidence from 30,000 Candidate|V|a67bb45 plugin 1d12c5682306|25|23|0.92|destring 52/0, egen 192/0, isid 80/0, tostring 115/0|439/0/0|50|0|0|1|0|0|PASS|

## Verify mismatches

None.

## NEAR, TIE, NONDET and DIFF files

|package|file|verdict|A vs fastata arm|A vs A2 or B|
|---|---|---|---|---|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/logfile.smcl`|NONDET|DIFF line 92360|DIFF numbers differ (max reldif 0.24)|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/table_2.rtf`|NONDET|DIFF numbers differ (max reldif 0.88)|DIFF numbers differ (max reldif 0.95)|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/table_3.rtf`|NONDET|DIFF numbers differ (max reldif 0.88)|DIFF numbers differ (max reldif 0.95)|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/table_4.rtf`|NONDET|DIFF numbers differ (max reldif 0.84)|DIFF numbers differ (max reldif 0.92)|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/table_5.rtf`|NONDET|DIFF numbers differ (max reldif 0.81)|DIFF numbers differ (max reldif 0.9)|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/table_6.rtf`|NONDET|DIFF numbers differ (max reldif 0.81)|DIFF numbers differ (max reldif 0.9)|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/table_7.rtf`|NONDET|DIFF numbers differ (max reldif 0.77)|DIFF numbers differ (max reldif 0.88)|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/table_8.rtf`|NONDET|DIFF numbers differ (max reldif 0.77)|DIFF numbers differ (max reldif 0.88)|
|dataverse-77YTLD|`RFS_Pseudo_DE/tables/table_9.rtf`|NONDET|DIFF numbers differ (max reldif 0.72)|DIFF numbers differ (max reldif 0.83)|
|dataverse-ERHYH7|`results/2_analysis_tables.rtf`|NONDET|DIFF numbers differ (max reldif 1.8)|DIFF numbers differ (max reldif 1.8)|
|dataverse-JFEZXC|`MPT_Replication_Package/MPT_Replication_Package/Reduced_Form_Model/Tables\\Table_I.tex`|NONDET|DIFF only in arm V|DIFF only in arm A2|
|dataverse-JFEZXC|`MPT_Replication_Package/MPT_Replication_Package/Reduced_Form_Model/Tables\\Table_I.xlsx`|NONDET|DIFF only in arm V|DIFF only in arm A2|
|dataverse-JFEZXC|`MPT_Replication_Package/MPT_Replication_Package/Reduced_Form_Model/Tables\\Table_V.tex`|NONDET|DIFF only in arm V|DIFF only in arm A2|
|dataverse-JFEZXC|`MPT_Replication_Package/MPT_Replication_Package/Reduced_Form_Model/Tables\\Table_V.xlsx`|NONDET|DIFF only in arm V|DIFF only in arm A2|
|dataverse-JOXAFP|`Output/TablesFigures/results_12pthresha.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_8pthresha.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_Mainobsa.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_UrbanbyAgea.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_UrbanbyMSa.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_droptopa.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_familya.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_fsa.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_gdispa.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_genda.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_income_nysiisa.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_incomea.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_indiva.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_insta.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_lasttreateda.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_main_pinta.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_realpropheta.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_residencea.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_robust_fbpla.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_rtrendsa.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-JOXAFP|`Output/TablesFigures/results_statesurnamea.tex`|NONDET|DIFF line 8|DIFF line 8|
|dataverse-QA1IDU|`2_output/Table3.rtf`|NONDET|DIFF numbers differ (max reldif 0.11)|DIFF numbers differ (max reldif 0.11)|
|dataverse-QA1IDU|`2_output/TableA3.rtf`|NONDET|DIFF numbers differ (max reldif 0.11)|DIFF numbers differ (max reldif 0.11)|
|dataverse-QA1IDU|`2_output/TableA4.rtf`|NONDET|DIFF numbers differ (max reldif 0.11)|DIFF numbers differ (max reldif 0.11)|
|dataverse-Y8MIH0|`RFS - Data Sharing Files/MainResults.rtf`|NONDET|DIFF numbers differ (max reldif 1.4)|DIFF numbers differ (max reldif 1.4)|
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
|zenodo-15311300|`/wrapper log/`|NONDET|DIFF numbers differ (max reldif 0.41)|DIFF line 752|
|zenodo-8290180|`3 replication package/Table 7.csv`|NONDET|DIFF line 1|DIFF line 1|
|zenodo-8373069|`/wrapper log/`|NONDET|DIFF line 189875|DIFF line 115|

## Packages that dropped out

|stage: reason|packages|
|---|---:|
|scan: dominated by other languages|504|
|run_A: r(601)|434|
|scan: no replaced-command call|337|
|scan: no master found|247|
|fetch: no Stata do-file|241|
|scan: no do-files|229|
|run_A: r(198)|42|
|run_A: r(199)|37|
|run_A: r(111)|30|
|run_A: r(631)|24|
|run_A: r(603)|16|
|run_A: timeout after 60 min|12|
|run_A: r(170)|12|
|run_A: r(693)|6|
|run_A: no FX_REPL_DONE in the log|6|
|fetch: 3-replication-package.zip: unpacks to more than 12 GB|6|
|fetch: ProxyError: HTTPSConnectionPool(host='zenodo.org', port=443): Max retr|5|
|run_A: r(3000)|3|
|run_A: r(3499)|3|
|run_A: r(499)|3|
|run_A: r(9)|3|
|run_A: r(606)|2|
|fetch: replication.zip: unpacks to more than 12 GB|2|
|run_A: r(2001)|2|
|run_A: r(602)|2|
|run_A: r(1)|2|
|run_A: r(109)|2|
|run_A: r(498)|2|
|run_A: r(691)|2|
|run_A: r(133)|2|
|fetch: replication_package-Nov2024.zip: unpacks to more than 12 GB|1|
|run_A: r(3498)|1|
|run_A: r(900)|1|
|run_A: r(610)|1|
|run_V: r(4)|1|
|run_A: r(101)|1|
|run_A: r(100)|1|
|fetch: restricted files|1|
|fetch: public_sector.zip: unpacks to more than 12 GB|1|
|run_A: r(692)|1|
|fetch: MS240038_Replication_Package.zip: unpacks to more than 12 GB|1|
|run_A: r(2000)|1|
|fetch: 3-replication.zip: unpacks to more than 12 GB|1|
|fetch: ChunkedEncodingError: ('Connection broken: IncompleteRead(1798760 byte|1|
|fetch: ChunkedEncodingError: ('Connection broken: IncompleteRead(49083148 byt|1|
|fetch: ChunkedEncodingError: ('Connection broken: IncompleteRead(20718760 byt|1|
|run_A: r(3200)|1|
|fetch: Replication package.zip: unpacks to more than 12 GB|1|
