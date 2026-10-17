//! Sample groups for egen: the sample observations grouped by the keys (or one group without
//! keys), observations ascending within each group; the parallel driver over groups; and the
//! `tag()` and `group()` columns (group numbers in Stata's sort order of the keys).

use std::marker::PhantomData;

use crate::error::{Res, vec_filled, vec_with_capacity};
use crate::group::{KEY_CHUNK, Keyed, Need, ReadOpts, RepKeys, Shared, par_for, par_map, par_sort_by, read_flags, sample_from_bools, sorted_starts};
use crate::io::Io;
use crate::par::{StoreMode, for_blocks};

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
    let mut out = vec_filled(io.nobs(), 0.0)?;
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
            let ints = par_map(io, keep.len().div_ceil(KEY_CHUNK), threads, |c| {
                let lo = c * KEY_CHUNK;
                let hi = (lo + KEY_CHUNK).min(keep.len());
                Ok(keep[lo..hi].iter().all(|&gi| rk.view().is_int(k, rk.pos(gi as usize))))
            })?;
            keyint.push(ints.iter().all(|&b| b));
        }
    }
    let mut out = vec_filled(io.nobs(), io.missval())?;
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
    } else if view.nkeys() == view.nnum() {
        // numeric keys: rows of order keys, flat
        let nn = view.nnum();
        let mut rows = vec_filled(k * nn, 0u64)?;
        let sh = Shared::new(&mut rows);
        par_for(io, k, threads, |i| {
            let p = rk.pos(keep[i] as usize);
            for j in 0..nn {
                // SAFETY: row i is written by the chunk that holds i only.
                unsafe { sh.set(i * nn + j, view.num_okey(p, j)) };
            }
            Ok(())
        })?;
        let mut idx = par_map(io, k, threads, |i| Ok(i as u32))?;
        par_sort_by(io, &mut idx, threads, |&a, &b| rows[a as usize * nn..][..nn].cmp(&rows[b as usize * nn..][..nn]))?;
        par_map(io, k, threads, |i| Ok(keep[idx[i] as usize]))?
    } else {
        let mut idx = vec_with_capacity(k)?;
        idx.extend_from_slice(keep);
        par_sort_by(io, &mut idx, threads, |&a, &b| view.cmp(rk.pos(a as usize), rk.pos(b as usize)))?;
        idx
    };
    let mut numbers = vec_filled(ngroups, 0u32)?;
    let sh = Shared::new(&mut numbers);
    par_for(io, k, threads, |r| {
        // SAFETY: each group appears once in `order`.
        unsafe { sh.set(order[r] as usize, r as u32 + 1) };
        Ok(())
    })?;
    Ok(numbers)
}

/// Output column shared by the workers of [`for_groups`]: each observation is written by the one
/// worker that owns its group.
pub struct Scatter<'a> {
    ptr: *mut f64,
    len: usize,
    _out: PhantomData<&'a mut [f64]>,
}

unsafe impl Sync for Scatter<'_> {}

impl<'a> Scatter<'a> {
    pub fn new(out: &'a mut [f64]) -> Scatter<'a> {
        Scatter { ptr: out.as_mut_ptr(), len: out.len(), _out: PhantomData }
    }

    /// Writes observation `i`.
    ///
    /// # Safety
    /// No other thread reads or writes observation `i` while the [`Scatter`] is in use.
    #[inline]
    pub unsafe fn set(&self, i: u32, v: f64) {
        let i = i as usize;
        assert!(i < self.len);
        unsafe { *self.ptr.add(i) = v };
    }
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
