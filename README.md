# fastata

Makes official Stata data commands fast, with the same syntax, results and messages: `egen`,
`isid`, `duplicates`, `xtile`, `pctile`, `destring` and `tostring` (Stata 16 or newer). After a
one-time `fastata enable`, Stata runs fastata's versions whenever these commands are called, in your
do-files and inside other ado-files. The work runs in a compiled Rust plugin (Linux, macOS, Windows)
that reads and writes the data in parallel and never sorts. Any input fastata has not been verified
to handle runs the original command.

## Install

```stata
net install fastata, from(https://leoliu0.github.io/fastata)
fastata enable
```

`fastata enable` adds a few lines to your `profile.do`, so fastata is on in every new session.
`fastata disable` removes them; `fastata off` / `fastata on` switch it for the current session;
`fastata status` shows what ran fast in this session. Update with `ado update fastata, update`,
then restart Stata: the session that updated keeps running the version it loaded (from 0.1.0,
`fastata on` in that session stops with `r(111)`). See `help fastata`.

## What is replaced

| command | fast path covers | runs the original for |
|---|---|---|
| `egen` | `count group iqr max mean median min pctile rank rowmax rowmean rowmin rowmiss rownonmiss rowsd rowtotal sd std sum tag total`, with `by`, `if`, `in` | other functions, expressions with `_n`/`_N`/subscripts/random numbers/`regexs()`, results beyond Stata's largest number, string results, a few options |
| `isid` | every form | `using`; string keys with leading or trailing blanks |
| `duplicates` | `report`, `examples`, `list`, `tag`, `drop` | `browse`, error cases, `s()` or `regexs()` in `if` |
| `xtile`, `pctile` | `nquantiles()`, weights, `altdef`, `if`, `in` | `cutpoints()`, `genp()`, `iweight`s, weighted percentiles within rounding distance of a cumulative weight, results beyond Stata's largest number |
| `destring` | `generate()`/`replace`, `force`, `float`, `percent`, `dpcomma`, `ignore()`; callers under `version` 11 or newer | `ignore(…, illegal)`, non-ASCII values, hexadecimal-looking strings, numbers beyond Stata's range, callers under `version` 10 or older |
| `tostring` | integers, with the default or a `%W.0g`/`%W.0f` format | other formats, non-integers |

fastata checks every call and every original ado-file it depends on: if your Stata has other
versions of the originals than those fastata was verified against, the originals run. On small
data (below 100 to 50,000 observations, depending on the command and function; `help fastata`
lists them) the original runs directly, because there it is faster than fastata's fixed cost per
call.

## Same results

On the fast path, the data (values bitwise, missing codes, types, formats, labels, notes,
characteristics, sort marker), the Results-window output (text and SMCL logs, style tags
included), errors and documented stored results are those of the original, with three documented
exceptions (`help fastata`): fastata does not sort, so a later command that depends on the order
of ties in a sort may order them differently; undocumented leftovers in `r()` and `s()` are not
reproduced; and `egen` sums, means and standard deviations within groups of unsorted data agree to
a relative 1e-13 (one unit in the last place for float), because the original's own sums depend
on the random order of ties in its internal sort.

This is checked against the originals by 2,055 specifications across the seven commands, a
randomized test of 3,000 cases, bitwise calibrations of `_pctile`, `summarize`, `real()`,
`compress` and `string()`, and 100 published replication packages (QJE, JPE, REStat, RFS, REStud
and EJ; [repl/RESULTS.md](repl/RESULTS.md)), each run without fastata and with fastata in verify
mode: all 375,039 fast calls in them gave the original's results.

## Speed

10 million observations, 100,000 groups, StataNow 19.5 MP on 64 cores (AMD Threadripper PRO
5995WX; [bench/RESULTS.md](bench/RESULTS.md)):

| command | original s | fastata s | speed-up |
|---|---:|---:|---:|
| `duplicates report g` | 21.64 | 0.037 | 585x |
| `isid id` | 7.07 | 0.016 | 442x |
| `xtile q = x1, nq(10)` | 13.92 | 0.046 | 302x |
| `egen t = tag(g)` | 10.99 | 0.048 | 229x |
| `egen gg = group(g)` | 5.69 | 0.082 | 69x |
| `duplicates tag g year, gen(dt)` | 5.31 | 0.079 | 67x |
| `egen r = rank(x1), by(g)` | 4.92 | 0.094 | 52x |
| `egen double md = median(x1), by(g)` | 4.76 | 0.095 | 50x |
| `egen double m = mean(x1), by(g)` | 4.46 | 0.094 | 47x |
| `egen gg = group(idu)` (10 million groups) | 5.30 | 0.203 | 26x |
| `destring sn, replace force` | 5.98 | 0.443 | 13.5x |
| `tostring z, replace` | 4.80 | 0.583 | 8.2x |

Commands that are already fast in Stata (no internal sort, e.g. `egen` row functions or
`bysort g: egen` on data sorted by `g`) gain less: most of their time is Stata adding the new
variable to the dataset, a cost any implementation pays.

## Build from source

Needs Rust 1.88+ and a C compiler. `scripts/build_plugin.sh` builds `stata/fastata.plugin`.
Tests: `cargo test --release`; the mock host in `tests/mockhost`; and, in `tests/stata`,
`stata-mp -b do run_all.do` (the full random test: `do test_random.do`). Benchmarks, in `bench`:
`stata-mp -b do bench.do` (10 million observations) and `stata-mp -b do small.do` (milliseconds
per call on small data). Replication harness: `repl/` (`uv run repl --help`).

Verify mode (environment variable `FASTATA_MODE=verify`, or `_fx mode verify` for a session) is for
testing on real code: every call that takes a fast path also runs the original command, quietly,
on a copy of the data made before the call, from the same random-number states; the two results
are compared and the original's is kept, so a whole run gives the original's results (sort tie
order included). With `FASTATA_COUNTS=<file>` set, each such call appends `<cmd>,verify_ok,`,
`<cmd>,verify_mismatch,<first difference>` or `<cmd>,verify_skipped,<reason>` to that file.

MIT license.
