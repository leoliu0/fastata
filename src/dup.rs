//! `isid` and `dup`: compute phases of fastata's isid and duplicates (slice B).
//!
//! Both group observations by the key tuple of their varlist (numeric, str# or strL keys) the
//! way Stata's `by` groups data sorted by those keys: two observations are in one group when
//! every numeric key has the same value (−0 equals +0; each missing code is a value of its own)
//! and every string key has the same bytes. Data whose sample observations are already in key
//! order is grouped by runs; other data by hashing (fixed partitions, so group ids never depend
//! on the thread count). Group order is Stata's sort order where it matters (`examples`,
//! `list`): numbers by raw value (`.` < `.a` < ... < `.z` after every number), strings bytewise
//! with a prefix first, tuples lexicographically in varlist order.
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

use std::cmp::Ordering;
use std::collections::BTreeMap;

use crate::args::Args;
use crate::cache::{self, Output};
use crate::error::{Error, Res, vec_filled, vec_with_capacity};
use crate::io::{self, Io};
use crate::par::{StoreMode, for_blocks};

/// Sample positions per work item.
const CHUNK: usize = 65_536;
/// Hash partitions (top 8 hash bits); fixed, so group ids do not depend on the thread count.
const PARTS: usize = 256;
/// Group id of a non-sample observation.
const NONE: u32 = u32::MAX;

#[derive(Clone, Copy)]
enum Kind {
    Num(usize),
    Str(usize),
}

/// One string key: the bytes of observation `obs` are `bytes[off[obs]..off[obs + 1]]`.
struct StrCol {
    off: Vec<usize>,
    bytes: Vec<u8>,
}

impl StrCol {
    fn get(&self, obs: usize) -> &[u8] {
        &self.bytes[self.off[obs]..self.off[obs + 1]]
    }
}

/// Key values by observation. Numeric keys hold every observation with −0 stored as +0;
/// string keys hold the sample observations (others are empty).
struct Keys {
    kinds: Vec<Kind>,
    num: Vec<Vec<f64>>,
    strs: Vec<StrCol>,
}

fn mix(mut z: u64) -> u64 {
    // splitmix64 finalizer
    z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    z ^ (z >> 31)
}

fn fnv1a(bytes: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for &b in bytes {
        h ^= u64::from(b);
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    h
}

impl Keys {
    /// Reads varlist positions `vars` (numeric columns in parallel, strings serially, only at
    /// the sample positions `samp`, every observation when `None`).
    fn read<I: Io>(io: &I, vars: &[i32], samp: Option<&[u32]>, threads: usize) -> Res<Keys> {
        let n = io.nobs();
        let mut kinds = Vec::with_capacity(vars.len());
        let mut numv = Vec::new();
        let mut strv = Vec::new();
        for &v in vars {
            if io.is_str(v) {
                kinds.push(Kind::Str(strv.len()));
                strv.push(v);
            } else {
                kinds.push(Kind::Num(numv.len()));
                numv.push(v);
            }
        }
        let mut num = cache::read_cols(io, &numv, threads)?;
        for x in num.iter_mut().flatten() {
            if *x == 0.0 {
                *x = 0.0;
            }
        }
        let mut strs = Vec::with_capacity(strv.len());
        for &v in &strv {
            let mut off = vec_filled(n + 1, 0usize)?;
            let mut bytes = Vec::new();
            match samp {
                None => {
                    for obs in 0..n {
                        io.read_str(v, obs, &mut bytes)?;
                        off[obs + 1] = bytes.len();
                    }
                }
                Some(s) => {
                    // off stays flat (empty values) between sample observations
                    let mut next = 0;
                    for &o in s {
                        let o = o as usize;
                        for x in &mut off[next + 1..=o] {
                            *x = bytes.len();
                        }
                        io.read_str(v, o, &mut bytes)?;
                        off[o + 1] = bytes.len();
                        next = o + 1;
                    }
                    for x in &mut off[next + 1..] {
                        *x = bytes.len();
                    }
                }
            }
            strs.push(StrCol { off, bytes });
        }
        Ok(Keys { kinds, num, strs })
    }

    /// Stata's sort order of the key tuples of observations `a` and `b`.
    fn cmp(&self, a: usize, b: usize) -> Ordering {
        for kind in &self.kinds {
            let o = match *kind {
                Kind::Num(c) => self.num[c][a].total_cmp(&self.num[c][b]),
                Kind::Str(c) => self.strs[c].get(a).cmp(self.strs[c].get(b)),
            };
            if o != Ordering::Equal {
                return o;
            }
        }
        Ordering::Equal
    }

    fn eq(&self, a: usize, b: usize) -> bool {
        self.num.iter().all(|c| c[a].to_bits() == c[b].to_bits()) && self.strs.iter().all(|s| s.get(a) == s.get(b))
    }

    fn hash(&self, i: usize) -> u64 {
        let mut h: u64 = 0x9e37_79b9_7f4a_7c15;
        for kind in &self.kinds {
            let kh = match *kind {
                Kind::Num(c) => mix(self.num[c][i].to_bits()),
                Kind::Str(c) => fnv1a(self.strs[c].get(i)),
            };
            h = mix(h ^ kh);
        }
        h
    }

    /// Observations (of `0..n`) with any missing key: a numeric missing code or "".
    fn count_missing<I: Io>(&self, io: &I, n: usize, threads: usize) -> Res<usize> {
        let miss = io.missval();
        let parts = for_blocks(io, n.div_ceil(CHUNK), threads, StoreMode::Parallel, |c, _emit| {
            let lo = c * CHUNK;
            let hi = (lo + CHUNK).min(n);
            Ok((lo..hi)
                .filter(|&i| {
                    self.num.iter().any(|col| io::is_miss(col[i], miss)) || self.strs.iter().any(|s| s.get(i).is_empty())
                })
                .count())
        })?;
        Ok(parts.iter().sum())
    }

    /// [string blanks] when a string value starts or ends with a byte outside 0x21..=0x7e.
    fn check_blanks(&self) -> Res<()> {
        let bad = |b: u8| b <= 0x20 || b >= 0x7f;
        for s in &self.strs {
            for obs in 0..s.off.len() - 1 {
                let v = s.get(obs);
                if let (Some(&f), Some(&l)) = (v.first(), v.last())
                    && (bad(f) || bad(l))
                {
                    return Err(Error::fallback("string blanks"));
                }
            }
        }
        Ok(())
    }
}

/// Groups of the sample observations: `size[g]` observations, the lowest being `first[g]`;
/// `gid[obs]` (when requested) is the group of each observation, [`NONE`] outside the sample.
struct Groups {
    gid: Vec<u32>,
    size: Vec<u32>,
    first: Vec<u32>,
}

/// Groups the sample observations `samp` (ascending) of `0..n` by key tuple.
fn group<I: Io>(io: &I, k: &Keys, samp: &[u32], n: usize, need_gid: bool, threads: usize) -> Res<Groups> {
    let ns = samp.len();
    let mut gid = if need_gid { vec_filled(n, NONE)? } else { Vec::new() };
    if ns == 0 {
        return Ok(Groups { gid, size: Vec::new(), first: Vec::new() });
    }

    // Already in key order? Then groups are the runs of equal tuples.
    let runs = for_blocks(io, ns.div_ceil(CHUNK), threads, StoreMode::Parallel, |c, _emit| {
        let lo = c * CHUNK;
        let hi = (lo + CHUNK).min(ns);
        let mut starts = Vec::new();
        for p in lo.max(1)..hi {
            match k.cmp(samp[p - 1] as usize, samp[p] as usize) {
                Ordering::Less => starts.push(p),
                Ordering::Equal => {}
                Ordering::Greater => return Ok(None),
            }
        }
        Ok(Some(starts))
    })?;
    if runs.iter().all(Option::is_some) {
        let ng = 1 + runs.iter().map(|r| r.as_ref().map_or(0, Vec::len)).sum::<usize>();
        let mut size = vec_with_capacity(ng)?;
        let mut first = vec_with_capacity(ng)?;
        let mut prev = 0;
        for s in runs.into_iter().flatten().flatten().chain(std::iter::once(ns)) {
            let g = size.len() as u32;
            size.push((s - prev) as u32);
            first.push(samp[prev]);
            if need_gid {
                for &o in &samp[prev..s] {
                    gid[o as usize] = g;
                }
            }
            prev = s;
        }
        return Ok(Groups { gid, size, first });
    }

    // Hashes, then a stable bucketing of the sample positions by partition.
    let chunks = for_blocks(io, ns.div_ceil(CHUNK), threads, StoreMode::Parallel, |c, _emit| {
        let lo = c * CHUNK;
        let hi = (lo + CHUNK).min(ns);
        Ok((lo..hi).map(|p| k.hash(samp[p] as usize)).collect::<Vec<u64>>())
    })?;
    let mut h = vec_with_capacity(ns)?;
    for c in chunks {
        h.extend(c);
    }
    let part_of = |p: usize| (h[p] >> 56) as usize;
    let mut pstart = [0usize; PARTS + 1];
    for p in 0..ns {
        pstart[part_of(p) + 1] += 1;
    }
    for p in 0..PARTS {
        pstart[p + 1] += pstart[p];
    }
    let mut fill = pstart;
    let mut pidx = vec_filled(ns, 0u32)?;
    for p in 0..ns {
        let q = part_of(p);
        pidx[fill[q]] = p as u32;
        fill[q] += 1;
    }

    // Per partition: open addressing, ids in order of first appearance.
    const EMPTY: u32 = u32::MAX;
    let per_part = for_blocks(io, PARTS, threads, StoreMode::Parallel, |q, _emit| {
        let members = &pidx[pstart[q]..pstart[q + 1]];
        let cap = (2 * members.len()).next_power_of_two().max(16);
        let mask = cap - 1;
        let mut table: Vec<(u64, u32, u32)> = vec_filled(cap, (0, EMPTY, 0))?;
        let mut lid = if need_gid { vec_filled(members.len(), 0u32)? } else { Vec::new() };
        let mut size: Vec<u32> = Vec::new();
        let mut first: Vec<u32> = Vec::new();
        for (m, &p) in members.iter().enumerate() {
            let hp = h[p as usize];
            let obs = samp[p as usize];
            let mut slot = hp as usize & mask;
            let id = loop {
                let (eh, rep, id) = table[slot];
                if rep == EMPTY {
                    let id = size.len() as u32;
                    table[slot] = (hp, obs, id);
                    size.push(1);
                    first.push(obs);
                    break id;
                }
                if eh == hp && k.eq(rep as usize, obs as usize) {
                    size[id as usize] += 1;
                    break id;
                }
                slot = (slot + 1) & mask;
            };
            if need_gid {
                lid[m] = id;
            }
        }
        Ok((lid, size, first))
    })?;

    let ng: usize = per_part.iter().map(|p| p.1.len()).sum();
    let mut size = vec_with_capacity(ng)?;
    let mut first = vec_with_capacity(ng)?;
    for (q, (lid, s, f)) in per_part.into_iter().enumerate() {
        let base = size.len() as u32;
        if need_gid {
            for (m, &p) in pidx[pstart[q]..pstart[q + 1]].iter().enumerate() {
                gid[samp[p as usize] as usize] = base + lid[m];
            }
        }
        size.extend(s);
        first.extend(f);
    }
    Ok(Groups { gid, size, first })
}

fn check_nobs(n: usize) -> Res<()> {
    if n >= u32::MAX as usize {
        return Err(Error::fallback("over 4294967294 observations"));
    }
    Ok(())
}

/// What `isid` reports: (observations with a missing key, distinct tuples when computed).
fn isid_counts<I: Io>(io: &I, missok: bool, threads: usize) -> Res<(usize, Option<usize>)> {
    let n = io.nobs();
    check_nobs(n)?;
    let vars: Vec<i32> = (1..=io.nvars() as i32).collect();
    if vars.is_empty() {
        return Err(Error::syntax("fastata plugin: isid needs key variables"));
    }
    let k = Keys::read(io, &vars, None, threads)?;
    k.check_blanks()?;
    let nmiss = k.count_missing(io, n, threads)?;
    if !missok && nmiss > 0 {
        return Ok((nmiss, None));
    }
    let samp: Vec<u32> = (0..n as u32).collect();
    let g = group(io, &k, &samp, n, false, threads)?;
    Ok((nmiss, Some(g.size.len())))
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
    check_nobs(n)?;
    let nv = io.nvars();
    let nk = nv.checked_sub(usize::from(touse)).filter(|&k| k > 0);
    let Some(nk) = nk else {
        return Err(Error::syntax("fastata plugin: dup needs key variables"));
    };
    let vars: Vec<i32> = (1..=nk as i32).collect();
    let samp: Vec<u32> = if touse {
        let t = cache::read_cols(io, &[nv as i32], threads)?.pop().unwrap_or_default();
        let ns = t.iter().filter(|&&x| x != 0.0).count();
        let mut s = vec_with_capacity(ns)?;
        s.extend(t.iter().enumerate().filter(|(_, x)| **x != 0.0).map(|(i, _)| i as u32));
        s
    } else {
        (0..n as u32).collect()
    };
    let ns = samp.len();
    let mut r = DupResult { n: ns, ..DupResult::default() };
    if ns == 0 {
        return Ok(r);
    }
    let k = Keys::read(io, &vars, touse.then_some(&samp[..]), threads)?;
    let g = group(io, &k, &samp, n, sub != Sub::Report, threads)?;
    let ng = g.size.len();
    r.nuniq = ng;
    match sub {
        Sub::Report => {
            let mut by_size: BTreeMap<u64, u64> = BTreeMap::new();
            for &s in &g.size {
                *by_size.entry(u64::from(s)).or_default() += u64::from(s);
            }
            r.table = by_size.into_iter().map(|(c, f)| (c, f, f as f64 - f as f64 / c as f64)).collect();
        }
        Sub::Tag => {
            let mut col = vec_filled(n, f64::NAN)?;
            for &o in &samp {
                col[o as usize] = f64::from(g.size[g.gid[o as usize] as usize] - 1);
            }
            r.max = g.size.iter().map(|&s| f64::from(s - 1)).fold(0.0, f64::max);
            r.out = Some(Output { nums: vec![col], strs: Vec::new() });
        }
        Sub::Drop => {
            r.ndrop = ns - ng;
            if r.ndrop > 0 {
                let mut col = vec_filled(n, 0.0)?;
                for &o in &samp {
                    if g.first[g.gid[o as usize] as usize] != o {
                        col[o as usize] = 1.0;
                    }
                }
                r.out = Some(Output { nums: vec![col], strs: Vec::new() });
            }
        }
        Sub::Examples | Sub::List => {
            let mut dups: Vec<u32> = (0..ng as u32).filter(|&q| g.size[q as usize] > 1).collect();
            dups.sort_unstable_by(|&a, &b| k.cmp(g.first[a as usize] as usize, g.first[b as usize] as usize));
            r.ndup = dups.len();
            if r.ndup > 0 {
                let nums = if sub == Sub::Examples {
                    r.nlist = r.ndup;
                    let order = dups.iter().map(|&q| f64::from(g.first[q as usize]) + 1.0).collect();
                    let dgroup = (1..=r.ndup).map(|i| i as f64).collect();
                    let ngroup = dups.iter().map(|&q| f64::from(g.size[q as usize])).collect();
                    vec![order, dgroup, ngroup]
                } else {
                    // offsets of each duplicated group (by Group) in the listing
                    let mut rank = vec_filled(ng, 0u32)?;
                    let mut off = vec_filled(r.ndup + 1, 0usize)?;
                    for (i, &q) in dups.iter().enumerate() {
                        rank[q as usize] = i as u32 + 1;
                        off[i + 1] = off[i] + g.size[q as usize] as usize;
                    }
                    r.nlist = off[r.ndup];
                    let mut order = vec_filled(r.nlist, 0.0)?;
                    let mut dgroup = vec_filled(r.nlist, 0.0)?;
                    for &o in &samp {
                        let rk = rank[g.gid[o as usize] as usize] as usize;
                        if rk > 0 {
                            order[off[rk - 1]] = f64::from(o) + 1.0;
                            dgroup[off[rk - 1]] = rk as f64;
                            off[rk - 1] += 1;
                        }
                    }
                    vec![order, dgroup]
                };
                r.out = Some(Output { nums, strs: Vec::new() });
            }
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
}
