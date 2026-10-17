//! `isid` and `dup`: compute phases of fastata's isid and duplicates (slice B).
//!
//! Both group observations by the key tuple of their varlist (numeric, str# or strL keys) the
//! way Stata's `by` groups data sorted by those keys (see `crate::group`: −0 equals +0, each
//! missing code is a value of its own, strings compare bytewise). Where order matters
//! (`examples`, `list`) groups follow Stata's sort order: numbers by raw value (`.` < `.a` < ...
//! < `.z` after every number), strings bytewise with a prefix first, tuples lexicographically in
//! varlist order. A NaN in a key (any observation) falls back.
//!
//! `isid`: varlist = the keys. Keys `missok` (0/1) and `threads`. Locals:
//! - `fx_nmiss`: observations with a missing key (a numeric missing code, or "" in a string);
//! - `fx_nuniq`: distinct key tuples over every observation (not set when missok=0 and
//!   fx_nmiss>0: isid then fails before it checks uniqueness).
//!
//! Falls back [string blanks] when a value of a string key starts or ends with a byte <= 0x20
//! or >= 0x7f: the original may then print a note about leading or trailing blanks.
//!
//! `dup`: varlist = the keys, then the touse variable when `touse=1` (sample = touse != 0;
//! otherwise every observation). Keys `phase=compute`, `sub` (report|tag|drop|examples|list),
//! `touse` (0/1) and `threads`. Local `fx_n` (sample size) always, and per subcommand:
//! - `report`: `fx_nuniq` (distinct tuples in the sample) and `fx_table`, the triples
//!   `c freq surplus` for every group size c in ascending order: freq = sample observations in
//!   groups of c, surplus = freq − freq/c (double, as the original's `_N - _N/Ngroup`).
//! - `tag`: `fx_max` (largest value) and `fx_token`; cached column: c − 1 for each sample
//!   observation (c its group's size), `.` elsewhere.
//! - `drop`: `fx_ndrop`; when it is > 0, `fx_token` and a cached column that is 1 on the sample
//!   observations to drop (every one but the lowest of its group) and 0 elsewhere.
//! - `examples`, `list`: `fx_ndup` (groups of more than one sample observation) and `fx_nlist`
//!   (rows listed); when fx_ndup > 0, `fx_token` and cached columns of `fx_nlist` rows in listing
//!   order (duplicated groups in sort order of their keys, numbered 1.. as `Group`): `examples`
//!   one row per group (its lowest observation, 1-based; Group; group size), `list` one row per
//!   observation of those groups, ascending inside a group (observation, 1-based; Group). The
//!   ado stores them into a frame of `fx_nlist` observations.

use std::collections::BTreeMap;

use crate::args::Args;
use crate::cache::{self, Output};
use crate::error::{Error, Res, vec_filled, vec_with_capacity};
use crate::group::{Keyed, Need, ReadOpts, Shared, par_for, par_sort_by, read_flags, sample_from_bools};
use crate::io::{self, Io};

/// What `isid` reports: (observations with a missing key, distinct tuples when computed).
fn isid_counts<I: Io>(io: &I, missok: bool, threads: usize) -> Res<(usize, Option<usize>)> {
    let vars: Vec<i32> = (1..=io.nvars() as i32).collect();
    if vars.is_empty() {
        return Err(Error::syntax("fastata plugin: isid needs key variables"));
    }
    let k = Keyed::read(io, &vars, None, threads, ReadOpts { miss: true, blanks: true })?;
    let nmiss = k.nmiss();
    if !missok && nmiss > 0 {
        return Ok((nmiss, None));
    }
    let g = k.group(io, threads, Need::default())?;
    Ok((nmiss, Some(g.ngroups)))
}

pub fn run_isid<I: Io>(io: &I, a: &Args) -> Res<()> {
    a.only(&["missok", "threads"])?;
    let missok = a.flag_req("missok")?;
    let threads = a.usize_or("threads", 0)?;
    let (nmiss, nuniq) = isid_counts(io, missok, threads)?;
    io::local_save("fx_nmiss", &nmiss.to_string())?;
    if let Some(u) = nuniq {
        io::local_save("fx_nuniq", &u.to_string())?;
    }
    Ok(())
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Sub {
    Report,
    Tag,
    Drop,
    Examples,
    List,
}

/// Result of a `dup` compute phase (see the module documentation).
#[derive(Debug, Default, PartialEq)]
struct DupResult {
    n: usize,
    nuniq: usize,
    /// (c, freq, surplus) by ascending c.
    table: Vec<(u64, u64, f64)>,
    max: f64,
    ndrop: usize,
    ndup: usize,
    nlist: usize,
    out: Option<Output>,
}

fn dup_compute<I: Io>(io: &I, sub: Sub, touse: bool, threads: usize) -> Res<DupResult> {
    let n = io.nobs();
    let nv = io.nvars();
    let nk = nv.checked_sub(usize::from(touse)).filter(|&k| k > 0);
    let Some(nk) = nk else {
        return Err(Error::syntax("fastata plugin: dup needs key variables"));
    };
    let vars: Vec<i32> = (1..=nk as i32).collect();
    let samp = if touse { Some(sample_from_bools(io, &read_flags(io, nv as i32, threads)?, threads)?) } else { None };
    let ns = samp.as_ref().map_or(n, Vec::len);
    let mut r = DupResult { n: ns, ..DupResult::default() };
    if ns == 0 {
        return Ok(r);
    }
    let k = Keyed::read(io, &vars, samp, threads, ReadOpts::default())?;
    let need = match sub {
        Sub::Report => Need { sizes: true, ..Need::default() },
        Sub::Tag => Need { gid: true, sizes: true, ..Need::default() },
        Sub::Drop => Need { gid: true, reps: true, ..Need::default() },
        Sub::Examples | Sub::List => Need { gid: true, reps: true, sizes: true, ..Need::default() },
    };
    let g = k.group(io, threads, need)?;
    let ng = g.ngroups;
    r.nuniq = ng;
    match sub {
        Sub::Report => {
            let mut by_size: BTreeMap<u64, u64> = BTreeMap::new();
            for &s in &g.sizes {
                *by_size.entry(u64::from(s)).or_default() += u64::from(s);
            }
            r.table = by_size.into_iter().map(|(c, f)| (c, f, f as f64 - f as f64 / c as f64)).collect();
        }
        Sub::Tag => {
            let mut col = vec_filled(n, f64::NAN)?;
            let sh = Shared::new(&mut col);
            par_for(io, ns, threads, |p| {
                // SAFETY: each sample position is its own observation.
                unsafe { sh.set(k.obs(p), f64::from(g.sizes[g.gid[p] as usize] - 1)) };
                Ok(())
            })?;
            r.max = g.sizes.iter().map(|&s| f64::from(s - 1)).fold(0.0, f64::max);
            r.out = Some(Output { nums: vec![col], strs: Vec::new() });
        }
        Sub::Drop => {
            r.ndrop = ns - ng;
            if r.ndrop > 0 {
                let mut col = vec_filled(n, 0.0)?;
                let sh = Shared::new(&mut col);
                par_for(io, ns, threads, |p| {
                    if g.reps[g.gid[p] as usize] as usize != p {
                        // SAFETY: as above.
                        unsafe { sh.set(k.obs(p), 1.0) };
                    }
                    Ok(())
                })?;
                r.out = Some(Output { nums: vec![col], strs: Vec::new() });
            }
        }
        Sub::Examples | Sub::List => {
            // duplicated groups, in sort order of their keys
            let mut dups = vec_with_capacity(g.sizes.iter().filter(|&&s| s > 1).count())?;
            dups.extend((0..ng as u32).filter(|&q| g.sizes[q as usize] > 1));
            r.ndup = dups.len();
            if r.ndup == 0 {
                return Ok(r);
            }
            let mut reps = vec_with_capacity(r.ndup)?;
            reps.extend(dups.iter().map(|&q| g.reps[q as usize]));
            let rk = k.rep_keys(io, &reps, threads)?;
            let mut idx = vec_with_capacity(r.ndup)?;
            idx.extend(0..r.ndup as u32);
            par_sort_by(io, &mut idx, threads, |&a, &b| rk.view().cmp(rk.pos(a as usize), rk.pos(b as usize)))?;
            let first = |i: u32| k.obs(reps[i as usize] as usize) as f64 + 1.0;
            let nums = if sub == Sub::Examples {
                r.nlist = r.ndup;
                let mut order = vec_with_capacity(r.ndup)?;
                order.extend(idx.iter().map(|&i| first(i)));
                let mut dgroup = vec_with_capacity(r.ndup)?;
                dgroup.extend((1..=r.ndup).map(|i| i as f64));
                let mut ngroup = vec_with_capacity(r.ndup)?;
                ngroup.extend(idx.iter().map(|&i| f64::from(g.sizes[dups[i as usize] as usize])));
                vec![order, dgroup, ngroup]
            } else {
                // offsets of each duplicated group (by Group) in the listing
                let mut rank = vec_filled(ng, 0u32)?;
                let mut off = vec_filled(r.ndup + 1, 0usize)?;
                for (j, &i) in idx.iter().enumerate() {
                    let q = dups[i as usize] as usize;
                    rank[q] = j as u32 + 1;
                    off[j + 1] = off[j] + g.sizes[q] as usize;
                }
                r.nlist = off[r.ndup];
                let mut order = vec_filled(r.nlist, 0.0)?;
                let mut dgroup = vec_filled(r.nlist, 0.0)?;
                for p in 0..ns {
                    let rk = rank[g.gid[p] as usize] as usize;
                    if rk > 0 {
                        order[off[rk - 1]] = k.obs(p) as f64 + 1.0;
                        dgroup[off[rk - 1]] = rk as f64;
                        off[rk - 1] += 1;
                    }
                }
                vec![order, dgroup]
            };
            r.out = Some(Output { nums, strs: Vec::new() });
        }
    }
    Ok(r)
}

pub fn run_dup<I: Io>(io: &I, a: &Args) -> Res<()> {
    a.only(&["phase", "sub", "touse", "threads"])?;
    if a.str_req("phase")? != "compute" {
        return Err(Error::syntax("fastata plugin: dup supports phase=compute only"));
    }
    let sub = match a.str_req("sub")? {
        "report" => Sub::Report,
        "tag" => Sub::Tag,
        "drop" => Sub::Drop,
        "examples" => Sub::Examples,
        "list" => Sub::List,
        s => return Err(Error::syntax(format!("fastata plugin: unknown dup subcommand `{s}`"))),
    };
    let touse = a.flag_req("touse")?;
    let threads = a.usize_or("threads", 0)?;
    let r = dup_compute(io, sub, touse, threads)?;
    io::local_save("fx_n", &r.n.to_string())?;
    if r.n == 0 {
        return Ok(());
    }
    match sub {
        Sub::Report => {
            io::local_save("fx_nuniq", &r.nuniq.to_string())?;
            let t: Vec<String> = r.table.iter().map(|(c, f, s)| format!("{c} {f} {s}")).collect();
            io::local_save("fx_table", &t.join(" "))?;
        }
        Sub::Tag => io::local_save("fx_max", &r.max.to_string())?,
        Sub::Drop => io::local_save("fx_ndrop", &r.ndrop.to_string())?,
        Sub::Examples | Sub::List => {
            io::local_save("fx_ndup", &r.ndup.to_string())?;
            io::local_save("fx_nlist", &r.nlist.to_string())?;
        }
    }
    if let Some(out) = r.out {
        io::local_save("fx_token", &cache::put(out).to_string())?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::{MISS, MemIo};
    use crate::testutil::{Rng, miss_a};

    #[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
    enum K {
        N(i64),
        S(Vec<u8>),
    }

    /// Naive sort key of a numeric value: order-preserving map of the canonical double.
    fn nkey(v: f64) -> i64 {
        let v = if v == 0.0 { 0.0 } else { v };
        let b = v.to_bits() as i64;
        if b < 0 { b ^ i64::MAX } else { b }
    }

    struct Data {
        io: MemIo,
        tuples: Vec<Vec<K>>,
        touse: Vec<bool>,
    }

    /// Keys a (numeric with −0, ., .a), b (small integers), s (strings incl. "" and prefixes),
    /// then a touse column; `sorted` sorts the observations by (a, b, s).
    fn data(n: usize, seed: u64, ngroups: u64, sorted: bool, with_touse: bool) -> Data {
        let num = [0.0, -0.0, MISS, miss_a(), 1.5, -2.0, 1e300];
        let strs: [&[u8]; 5] = [b"", b"ab", b"abc", b"B", b"z\xc3\xa9z"];
        let mut rng = Rng::new(seed);
        let mut rows: Vec<(f64, f64, Vec<u8>, f64)> = (0..n)
            .map(|_| {
                let a = num[(rng.next_u64() % num.len() as u64) as usize];
                let b = (rng.next_u64() % ngroups) as f64;
                let s = strs[(rng.next_u64() % strs.len() as u64) as usize].to_vec();
                let t = if rng.unif() < 0.2 { 0.0 } else { 1.0 };
                (a, b, s, t)
            })
            .collect();
        if sorted {
            rows.sort_by(|x, y| (nkey(x.0), nkey(x.1), &x.2).cmp(&(nkey(y.0), nkey(y.1), &y.2)));
        }
        let mut io = MemIo::new(n);
        let ca = io.add_num(&rows.iter().map(|r| r.0).collect::<Vec<_>>());
        let cb = io.add_num(&rows.iter().map(|r| r.1).collect::<Vec<_>>());
        let cs = io.add_str(rows.iter().map(|r| r.2.clone()).collect());
        let ct = io.add_num(&rows.iter().map(|r| r.3).collect::<Vec<_>>());
        for c in [ca, cb, cs] {
            io.push_var(c);
        }
        if with_touse {
            io.push_var(ct);
        }
        let tuples = rows.iter().map(|r| vec![K::N(nkey(r.0)), K::N(nkey(r.1)), K::S(r.2.clone())]).collect();
        let touse = rows.iter().map(|r| r.3 != 0.0).collect();
        Data { io, tuples, touse }
    }

    /// Naive groups: tuple -> sample observations (ascending), in sort order of the tuples.
    fn naive(d: &Data, touse: bool) -> BTreeMap<Vec<K>, Vec<usize>> {
        let mut m: BTreeMap<Vec<K>, Vec<usize>> = BTreeMap::new();
        for (i, t) in d.tuples.iter().enumerate() {
            if !touse || d.touse[i] {
                m.entry(t.clone()).or_default().push(i);
            }
        }
        m
    }

    fn naive_dup(d: &Data, sub: Sub, touse: bool) -> DupResult {
        let n = d.tuples.len();
        let m = naive(d, touse);
        let ns: usize = m.values().map(Vec::len).sum();
        let mut r = DupResult { n: ns, nuniq: m.len(), ..DupResult::default() };
        match sub {
            Sub::Report => {
                let mut t: BTreeMap<u64, u64> = BTreeMap::new();
                for v in m.values() {
                    *t.entry(v.len() as u64).or_default() += v.len() as u64;
                }
                r.table = t.into_iter().map(|(c, f)| (c, f, (f - f / c) as f64)).collect();
            }
            Sub::Tag => {
                let mut col = vec![f64::NAN; n];
                for v in m.values() {
                    for &o in v {
                        col[o] = (v.len() - 1) as f64;
                    }
                    r.max = r.max.max((v.len() - 1) as f64);
                }
                r.out = Some(Output { nums: vec![col], strs: vec![] });
            }
            Sub::Drop => {
                let mut col = vec![0.0; n];
                for v in m.values() {
                    for &o in &v[1..] {
                        col[o] = 1.0;
                        r.ndrop += 1;
                    }
                }
                if r.ndrop > 0 {
                    r.out = Some(Output { nums: vec![col], strs: vec![] });
                }
            }
            Sub::Examples | Sub::List => {
                let (mut order, mut dg, mut ngr) = (vec![], vec![], vec![]);
                for v in m.values().filter(|v| v.len() > 1) {
                    r.ndup += 1;
                    let rows = if sub == Sub::Examples { &v[..1] } else { &v[..] };
                    for &o in rows {
                        order.push(o as f64 + 1.0);
                        dg.push(r.ndup as f64);
                        ngr.push(v.len() as f64);
                    }
                }
                r.nlist = order.len();
                if r.ndup > 0 {
                    let nums = if sub == Sub::Examples { vec![order, dg, ngr] } else { vec![order, dg] };
                    r.out = Some(Output { nums, strs: vec![] });
                }
            }
        }
        r
    }

    /// NaN-aware bitwise equality of results (tag columns hold NaN).
    fn same(a: &DupResult, b: &DupResult) -> bool {
        let bits = |r: &DupResult| {
            r.out.as_ref().map(|o| o.nums.iter().map(|c| c.iter().map(|x| x.to_bits()).collect::<Vec<_>>()).collect::<Vec<_>>())
        };
        (a.n, a.nuniq, a.ndrop, a.ndup, a.nlist, a.max.to_bits()) == (b.n, b.nuniq, b.ndrop, b.ndup, b.nlist, b.max.to_bits())
            && a.table.iter().map(|t| (t.0, t.1, t.2.to_bits())).eq(b.table.iter().map(|t| (t.0, t.1, t.2.to_bits())))
            && bits(a) == bits(b)
    }

    /// The observation counts around the 8192 and 65536 blocks, sorted and unsorted, few and
    /// many groups, with and without touse: every subcommand matches the naive reference for 1
    /// and 5 threads.
    #[test]
    fn dup_matches_naive_reference_for_any_thread_count() {
        let subs = [Sub::Report, Sub::Tag, Sub::Drop, Sub::Examples, Sub::List];
        for &(n, ng) in &[(1, 3), (7, 2), (8191, 3), (8193, 4000), (65_537, 5), (140_000, 60_000)] {
            for sorted in [false, true] {
                for touse in [false, true] {
                    let d = data(n, n as u64 + 11, ng, sorted, touse);
                    let io = &d.io;
                    for &sub in &subs {
                        let want = naive_dup(&d, sub, touse);
                        for threads in [1, 5] {
                            let got = dup_compute(io, sub, touse, threads).unwrap();
                            assert!(same(&got, &want), "n={n} sorted={sorted} touse={touse} {sub:?} threads={threads}\n{got:?}\n{want:?}");
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn isid_counts_missing_and_distinct_tuples() {
        for &(n, ng) in &[(5, 2), (9000, 100_000), (70_000, 1 << 40)] {
            let d = data(n, 3, ng, false, false);
            let io = &d.io;
            let m = naive(&d, false);
            let nmiss = d.tuples.iter().filter(|t| t[0] >= K::N(nkey(MISS)) || t[2] == K::S(vec![])).count();
            assert!(n < 100 || nmiss > 0);
            for threads in [1, 4] {
                assert_eq!(isid_counts(io, true, threads).unwrap(), (nmiss, Some(m.len())));
                let strict = if nmiss > 0 { None } else { Some(m.len()) };
                assert_eq!(isid_counts(io, false, threads).unwrap(), (nmiss, strict));
            }
        }
        // a unique numeric key, sorted and reversed
        let n = 100_000;
        for rev in [false, true] {
            let mut io = MemIo::new(n);
            let v: Vec<f64> = (0..n).map(|i| if rev { (n - i) as f64 } else { i as f64 }).collect();
            let c = io.add_num(&v);
            io.push_var(c);
            assert_eq!(isid_counts(&io, false, 3).unwrap(), (0, Some(n)));
        }
    }

    #[test]
    fn isid_falls_back_on_string_blanks() {
        for bad in [&b" a"[..], b"a ", b"a\t", b"\xc2\xa0a", b"a\x7f"] {
            let mut io = MemIo::new(3);
            let c = io.add_str(vec![b"x".to_vec(), bad.to_vec(), b"a b".to_vec()]);
            io.push_var(c);
            let e = isid_counts(&io, false, 1).unwrap_err();
            assert!(e.is_fallback() && e.msg == "string blanks", "{bad:?}");
        }
        let mut io = MemIo::new(3);
        let c = io.add_str(vec![b"x".to_vec(), b"a b".to_vec(), Vec::new()]);
        io.push_var(c);
        assert_eq!(isid_counts(&io, true, 1).unwrap(), (1, Some(3)));
    }

    /// More keys than `group::STORED_KEYS` (the three keys twice: the same groups): rows are
    /// hashed and groups checked against the data; every subcommand and isid still match the
    /// naive reference for 1 and 5 threads.
    #[test]
    fn wide_keys_match_naive_reference() {
        let subs = [Sub::Report, Sub::Tag, Sub::Drop, Sub::Examples, Sub::List];
        for &(n, ng) in &[(7, 2), (8193, 4000), (70_000, 5), (70_000, 1 << 40)] {
            for touse in [false, true] {
                let mut d = data(n, n as u64 + 5, ng, false, touse);
                let (k, t) = (d.io.varlist[..3].to_vec(), d.io.varlist[3..].to_vec());
                d.io.varlist = [k.clone(), k, t].concat();
                for &sub in &subs {
                    let want = naive_dup(&d, sub, touse);
                    for threads in [1, 5] {
                        let got = dup_compute(&d.io, sub, touse, threads).unwrap();
                        assert!(same(&got, &want), "n={n} touse={touse} {sub:?} threads={threads}");
                    }
                }
                if !touse {
                    let m = naive(&d, false);
                    let nmiss = d.tuples.iter().filter(|t| t[0] >= K::N(nkey(MISS)) || t[2] == K::S(vec![])).count();
                    for threads in [1, 4] {
                        assert_eq!(isid_counts(&d.io, true, threads).unwrap(), (nmiss, Some(m.len())));
                    }
                }
            }
        }
    }

    #[test]
    fn minus_zero_equals_zero_and_missing_codes_differ() {
        let mut io = MemIo::new(6);
        let c = io.add_num(&[0.0, -0.0, MISS, miss_a(), MISS, 1.0]);
        io.push_var(c);
        let r = dup_compute(&io, Sub::Examples, false, 1).unwrap();
        // groups {0, -0} and {., .}; sort order puts 0 before .
        assert_eq!(r.ndup, 2);
        assert_eq!(r.out.unwrap().nums, vec![vec![1.0, 3.0], vec![1.0, 2.0], vec![2.0, 2.0]]);
    }

    #[test]
    fn empty_sample_reports_zero() {
        let mut io = MemIo::new(4);
        let a = io.add_num(&[1.0, 1.0, 2.0, 2.0]);
        let t = io.add_num(&[0.0; 4]);
        io.push_var(a);
        io.push_var(t);
        assert_eq!(dup_compute(&io, Sub::Tag, true, 2).unwrap(), DupResult::default());
    }

    #[test]
    fn a_nan_key_falls_back_and_a_nan_elsewhere_does_not_matter() {
        // Stata's sort never returns on a NaN key (isid and duplicates sort), so these run the
        // original; the key check reads only the keys.
        let nan = crate::testutil::stata_nan();
        let mut io = MemIo::new(9000);
        let mut a: Vec<f64> = (0..9000).map(|i| (i % 7) as f64).collect();
        a[8500] = nan;
        let b: Vec<f64> = (0..9000).map(f64::from).collect();
        let cn = io.add_num(&a);
        let cb = io.add_num(&b);
        io.push_var(cn);
        io.push_var(cb);
        for threads in [1, 4] {
            let e = isid_counts(&io, true, threads).unwrap_err();
            assert!(e.is_fallback() && e.msg == crate::nan::REASON);
            for sub in [Sub::Report, Sub::Tag, Sub::Drop] {
                let e = dup_compute(&io, sub, false, threads).unwrap_err();
                assert!(e.is_fallback() && e.msg == crate::nan::REASON);
            }
        }
        // the same data with only b as the key
        io.varlist = vec![cb];
        assert_eq!(isid_counts(&io, false, 4).unwrap(), (0, Some(9000)));
    }
}
