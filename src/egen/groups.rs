//! Sample groups for egen: the sample observations grouped by the keys (or one group without
//! keys), observations ascending within each group; the parallel driver over groups; and the
//! `tag()` and `group()` columns (group numbers in Stata's sort order of the keys).

use crate::error::{Res, vec_with_capacity, vec_zeroed};
use crate::group::{KEY_CHUNK, Keyed, Need, ReadOpts, RepKeys, par_for, par_map, par_sort_by, read_flags, sample_from_bools, sorted_starts};
use crate::io::Io;
use crate::par::{Shared, StoreMode, for_blocks, threads_for_rows};

/// Sample observations of each group: group `g` is `ord[starts[g]..starts[g + 1]]`, ascending.
/// Groups without sample observations do not appear.
pub struct Groups {
    pub ord: Vec<u32>,
    pub starts: Vec<usize>,
}

impl Groups {
    pub fn len(&self) -> usize {
        self.starts.len() - 1
    }

    pub fn members(&self, g: usize) -> &[u32] {
        &self.ord[self.starts[g]..self.starts[g + 1]]
    }
}

/// Sample marker per observation (`touse` != 0), or `None` without a marker.
pub fn read_touse<I: Io>(io: &I, touse: Option<i32>, threads: usize) -> Res<Option<Vec<bool>>> {
    touse.map(|t| read_flags(io, t, threads)).transpose()
}

/// The sample observations, ascending.
fn sample_list(n: usize, touse: Option<&[bool]>) -> Res<Vec<u32>> {
    match touse {
        None => {
            let mut o = vec_with_capacity(n)?;
            o.extend(0..n as u32);
            Ok(o)
        }
        Some(t) => {
            let mut o = vec_with_capacity(t.iter().filter(|&&b| b).count())?;
            o.extend((0..n as u32).filter(|&i| t[i as usize]));
            Ok(o)
        }
    }
}

/// Every sample observation as one group (none when the sample is empty).
pub fn one_group(n: usize, touse: Option<&[bool]>) -> Res<Groups> {
    let ord = sample_list(n, touse)?;
    let starts = if ord.is_empty() { vec![0] } else { vec![0, ord.len()] };
    Ok(Groups { ord, starts })
}

/// Groups of data sorted by numeric `keys` (the by prefix): runs of equal keys (`by`'s rule:
/// −0 equals +0, `.` differs from `.a`), restricted to the sample.
pub fn sorted_groups<I: Io>(io: &I, keys: &[i32], touse: Option<&[bool]>, threads: usize) -> Res<Groups> {
    let n = io.nobs();
    let runs = sorted_starts(io, keys, n, threads)?;
    let ord = sample_list(n, touse)?;
    let Some(t) = touse else {
        let starts = if n == 0 { vec![0] } else { runs };
        return Ok(Groups { ord, starts });
    };
    let mut starts = vec_with_capacity(runs.len())?;
    starts.push(0);
    let mut acc = 0;
    for w in runs.windows(2) {
        let k = t[w[0]..w[1]].iter().filter(|&&b| b).count();
        if k > 0 {
            acc += k;
            starts.push(acc);
        }
    }
    Ok(Groups { ord, starts })
}

/// The keys of the sample (missing flags when `miss`).
fn keyed_sample<I: Io>(io: &I, keys: &[i32], touse: Option<&[bool]>, threads: usize, miss: bool) -> Res<Keyed> {
    let samp = touse.map(|t| sample_from_bools(io, t, threads)).transpose()?;
    Keyed::read(io, keys, samp, threads, ReadOpts { miss, blanks: false })
}

/// Groups of unsorted data by `keys` (numeric, str# or strL), restricted to the sample.
pub fn hashed_groups<I: Io>(io: &I, keys: &[i32], touse: Option<&[bool]>, threads: usize) -> Res<Groups> {
    let kd = keyed_sample(io, keys, touse, threads, false)?;
    let g = kd.group(io, threads, Need { ord: true, ..Need::default() })?;
    Ok(Groups { ord: g.ord, starts: g.starts })
}

/// `tag()`: 1 on the lowest sample observation of each group of `keys` (without `missing`, of
/// each group whose keys are all nonmissing), 0 elsewhere.
pub fn tag_column<I: Io>(io: &I, keys: &[i32], touse: Option<&[bool]>, missing: bool, threads: usize) -> Res<Vec<f64>> {
    let kd = keyed_sample(io, keys, touse, threads, !missing)?;
    let g = kd.group(io, threads, Need { reps: true, ..Need::default() })?;
    let mut out = vec_zeroed(io.nobs())?;
    let sh = Shared::new(&mut out);
    par_for(io, g.ngroups, threads, |gi| {
        let r = g.reps[gi] as usize;
        if missing || !kd.missing(r) {
            // SAFETY: each group has its own lowest observation.
            unsafe { sh.set(kd.obs(r), 1.0) };
        }
        Ok(())
    })?;
    Ok(out)
}

/// `group()`: group numbers 1..K in Stata's sort order of the key tuples (numbers ascending with
/// −0 = +0 and missing codes after every number, `.` < `.a` < ... < `.z`; strings bytewise with a
/// prefix first; lexicographic in varlist order), over the sample observations (without
/// `missing`, those whose keys are all nonmissing); `.` elsewhere. Each number is stored as
/// `cast(number)`. Also returns, without `missing`, whether each key is numeric and integer at
/// every observation numbered (empty with `missing`).
pub fn group_column<I, C>(io: &I, keys: &[i32], touse: Option<&[bool]>, missing: bool, threads: usize, cast: C) -> Res<(Vec<f64>, Vec<bool>)>
where
    I: Io,
    C: Fn(f64) -> Res<f64> + Sync,
{
    let kd = keyed_sample(io, keys, touse, threads, !missing)?;
    let g = kd.group(io, threads, Need { gid: true, reps: true, ..Need::default() })?;
    let kept = |gi: usize| missing || !kd.missing(g.reps[gi] as usize);
    let mut keep = vec_with_capacity((0..g.ngroups).filter(|&gi| kept(gi)).count())?;
    keep.extend((0..g.ngroups as u32).filter(|&gi| kept(gi as usize)));
    let rk = kd.rep_keys(io, &g.reps, threads)?;
    let numbers = group_numbers(io, &rk, &keep, g.ngroups, threads)?;
    let mut keyint = Vec::new();
    if !missing {
        for k in 0..keys.len() {
            let ints = for_blocks(io, keep.len().div_ceil(KEY_CHUNK), threads_for_rows(threads, keep.len()), StoreMode::Parallel, |c, _emit| {
                let lo = c * KEY_CHUNK;
                let hi = (lo + KEY_CHUNK).min(keep.len());
                Ok(keep[lo..hi].iter().all(|&gi| rk.view().is_int(k, rk.pos(gi as usize))))
            })?;
            keyint.push(ints.iter().all(|&b| b));
        }
    }
    let miss = io.missval();
    let mut out = par_map(io, io.nobs(), threads, |_| Ok(miss))?;
    let sh = Shared::new(&mut out);
    par_for(io, kd.len(), threads, |p| {
        let k = numbers[g.gid[p] as usize];
        if k > 0 {
            // SAFETY: each sample position is its own observation.
            unsafe { sh.set(kd.obs(p), cast(f64::from(k))?) };
        }
        Ok(())
    })?;
    Ok((out, keyint))
}

/// Number (1..) of each group of `keep` in Stata's sort order of its keys; 0 for the other
/// groups of `0..ngroups`. Keys are distinct between groups, so the order is total and the
/// numbers do not depend on the thread count.
fn group_numbers<I: Io>(io: &I, rk: &RepKeys<'_>, keep: &[u32], ngroups: usize, threads: usize) -> Res<Vec<u32>> {
    let view = rk.view();
    let k = keep.len();
    let order: Vec<u32> = if view.nkeys() == 1 && view.nnum() == 1 {
        // one numeric key: sort (order key, group) pairs
        let mut pairs = par_map(io, k, threads, |i| Ok((view.num_okey(rk.pos(keep[i] as usize), 0), keep[i])))?;
        par_sort_by(io, &mut pairs, threads, |a, b| a.cmp(b))?;
        par_map(io, k, threads, |i| Ok(pairs[i].1))?
    } else {
        // (key prefix, group) records, compared in place; equal prefixes compare whole tuples
        let mut recs = par_map(io, k, threads, |i| Ok((view.prefix(rk.pos(keep[i] as usize)), keep[i])))?;
        par_sort_by(io, &mut recs, threads, |a, b| a.0.cmp(&b.0).then_with(|| view.cmp(rk.pos(a.1 as usize), rk.pos(b.1 as usize))))?;
        par_map(io, k, threads, |i| Ok(recs[i].1))?
    };
    let mut numbers = vec_zeroed(ngroups)?;
    let sh = Shared::new(&mut numbers);
    par_for(io, k, threads, |r| {
        // SAFETY: each group appears once in `order`.
        unsafe { sh.set(order[r] as usize, r as u32 + 1) };
        Ok(())
    })?;
    Ok(numbers)
}

/// Observations per work item of [`for_groups`] (at least one whole group per item).
const ITEM_OBS: usize = 16_384;

/// Runs `f(g, members, scratch)` for every group, in parallel over items of whole groups; each
/// item has its own scratch vector, with room for its largest group. Deterministic: groups are
/// independent.
pub fn for_groups<I, F>(io: &I, g: &Groups, threads: usize, f: F) -> Res<()>
where
    I: Io,
    F: Fn(usize, &[u32], &mut Vec<f64>) -> Res<()> + Sync,
{
    let cut = |acc: usize| acc >= ITEM_OBS;
    let mut nitems = 0;
    let mut acc = 0;
    for gi in 0..g.len() {
        acc += g.starts[gi + 1] - g.starts[gi];
        if cut(acc) || gi + 1 == g.len() {
            nitems += 1;
            acc = 0;
        }
    }
    let mut items = vec_with_capacity(nitems + 1)?;
    items.push(0usize);
    acc = 0;
    for gi in 0..g.len() {
        acc += g.starts[gi + 1] - g.starts[gi];
        if cut(acc) || gi + 1 == g.len() {
            items.push(gi + 1);
            acc = 0;
        }
    }
    for_blocks(io, nitems, threads, StoreMode::Parallel, |it, _emit| {
        let largest = (items[it]..items[it + 1]).map(|gi| g.starts[gi + 1] - g.starts[gi]).max().unwrap_or(0);
        let mut scratch = vec_with_capacity(largest)?;
        for gi in items[it]..items[it + 1] {
            f(gi, g.members(gi), &mut scratch)?;
        }
        Ok(())
    })?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::*;
    use crate::group::okey;
    use crate::io::{MISS, MemIo};
    use crate::testutil::{Rng, miss_a};

    #[derive(Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Debug)]
    enum K {
        N(u64),
        S(Vec<u8>),
    }

    /// `group()` and `tag()` columns against a naive reference (Stata's order of the key tuples,
    /// first observation of each tuple), for 1 and 8 threads, over more than 65,536 groups (the
    /// parallel sort), keys of every shape (one or two numbers, strings sharing long prefixes,
    /// mixed, more than 4 keys), with and without a sample and `missing`; and keyint.
    #[test]
    fn group_and_tag_columns_match_naive_for_any_thread_count() {
        let n = 150_000;
        let mut rng = Rng::new(17);
        let special = [0.0, -0.0, MISS, miss_a(), 1.5, -2.0];
        let a: Vec<f64> = (0..n)
            .map(|_| {
                let r = rng.next_u64();
                if r % 10 == 0 { special[(r / 10 % 6) as usize] } else { (r % 200_000) as f64 }
            })
            .collect();
        let b: Vec<f64> = (0..n).map(|_| (rng.next_u64() % 3) as f64).collect();
        let s: Vec<Vec<u8>> = (0..n)
            .map(|_| {
                let r = rng.next_u64() % 120_000;
                if r < 300 { Vec::new() } else { format!("a common prefix of 24 b{r}").into_bytes() }
            })
            .collect();
        let t: Vec<f64> = (0..n).map(|_| f64::from(u8::from(rng.unif() < 0.8))).collect();
        let mut io = MemIo::new(n);
        let (ca, cb, cs, ct) = (io.add_num(&a), io.add_num(&b), io.add_str(s.clone()), io.add_num(&t));
        let (pa, pb, ps, pt) = (io.push_var(ca), io.push_var(cb), io.push_var(cs), io.push_var(ct));
        let touse: Vec<bool> = t.iter().map(|&x| x != 0.0).collect();
        let canon = |v: f64| if v == 0.0 { 0 } else { v.to_bits() };
        let key = |p: i32, o: usize| -> K {
            if p == ps { K::S(s[o].clone()) } else { K::N(okey(canon(if p == pa { a[o] } else { b[o] }))) }
        };
        let miss_of = |p: i32, o: usize| if p == ps { s[o].is_empty() } else { (if p == pa { a[o] } else { b[o] }) >= MISS };
        for keys in [vec![pa], vec![pa, pb], vec![ps], vec![pb, ps], vec![ps, pa], vec![pa, pb, ps, pb, pa]] {
            for samp in [false, true] {
                let tu = samp.then_some(&touse[..]);
                for missing in [false, true] {
                    let incl = |o: usize| (!samp || touse[o]) && (missing || !keys.iter().any(|&p| miss_of(p, o)));
                    let mut m: BTreeMap<Vec<K>, f64> = BTreeMap::new();
                    for o in (0..n).filter(|&o| incl(o)) {
                        m.insert(keys.iter().map(|&p| key(p, o)).collect(), 0.0);
                    }
                    for (r, v) in m.values_mut().enumerate() {
                        *v = (r + 1) as f64;
                    }
                    let mut first = std::collections::HashSet::new();
                    let mut tag_want = vec![0.0; n];
                    let mut grp_want = vec![MISS; n];
                    for o in (0..n).filter(|&o| incl(o)) {
                        let k: Vec<K> = keys.iter().map(|&p| key(p, o)).collect();
                        grp_want[o] = m[&k];
                        if first.insert(k) {
                            tag_want[o] = 1.0;
                        }
                    }
                    let int_want: Vec<bool> = if missing {
                        Vec::new()
                    } else {
                        keys.iter().map(|&p| p != ps && (0..n).filter(|&o| incl(o)).all(|o| { let v = if p == pa { a[o] } else { b[o] }; v == v.trunc() })).collect()
                    };
                    for threads in [1, 8] {
                        let what = format!("keys {keys:?} samp={samp} missing={missing} threads={threads}");
                        let (got, keyint) = group_column(&io, &keys, tu, missing, threads, Ok).unwrap();
                        assert!(got.iter().zip(&grp_want).all(|(x, y)| x.to_bits() == y.to_bits()), "group {what}");
                        assert_eq!(keyint, int_want, "keyint {what}");
                        let tag = tag_column(&io, &keys, tu, missing, threads).unwrap();
                        assert!(tag == tag_want, "tag {what}");
                    }
                }
            }
        }
        let _ = pt;
    }
}
