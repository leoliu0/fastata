//! Sample groups for egen: the sample observations grouped by the keys (or one group without
//! keys), observations ascending within each group; the parallel driver over groups; and group
//! numbering in Stata's sort order for `group()`.

use std::cmp::Ordering;

use crate::cache::read_cols;
use crate::error::{Error, Res, vec_filled, vec_with_capacity};
use crate::group::{default_hash, hash_groups, sorted_starts};
use crate::io::{Io, Rows};
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

fn check_n(n: usize) -> Res<()> {
    if n > u32::MAX as usize {
        return Err(Error::fallback("over 4294967295 observations"));
    }
    Ok(())
}

/// Sample marker per observation (`touse` != 0), or `None` without a marker.
pub fn read_touse<I: Io>(io: &I, touse: Option<i32>, threads: usize) -> Res<Option<Vec<bool>>> {
    let Some(t) = touse else { return Ok(None) };
    let col = read_cols(io, &[t], threads)?.pop().unwrap_or_default();
    Ok(Some(col.iter().map(|&v| v != 0.0).collect()))
}

/// Every sample observation as one group (none when the sample is empty).
pub fn one_group(n: usize, touse: Option<&[bool]>) -> Res<Groups> {
    check_n(n)?;
    let ord: Vec<u32> = match touse {
        None => {
            let mut o = vec_with_capacity(n)?;
            o.extend(0..n as u32);
            o
        }
        Some(t) => (0..n as u32).filter(|&i| t[i as usize]).collect(),
    };
    let starts = if ord.is_empty() { vec![0] } else { vec![0, ord.len()] };
    Ok(Groups { ord, starts })
}

/// Groups of data sorted by numeric `keys` (the by prefix): runs of equal keys (`by`'s rule:
/// −0 equals +0, `.` differs from `.a`), restricted to the sample.
pub fn sorted_groups<I: Io>(io: &I, keys: &[i32], touse: Option<&[bool]>, threads: usize) -> Res<Groups> {
    let n = io.nobs();
    check_n(n)?;
    let runs = sorted_starts(io, keys, n, threads)?;
    let Some(t) = touse else {
        let mut ord = vec_with_capacity(n)?;
        ord.extend(0..n as u32);
        let starts = if n == 0 { vec![0] } else { runs };
        return Ok(Groups { ord, starts });
    };
    let mut ord = vec_with_capacity(t.iter().filter(|&&b| b).count())?;
    let mut starts = vec![0];
    for w in runs.windows(2) {
        let before = ord.len();
        ord.extend((w[0]..w[1]).filter(|&i| t[i]).map(|i| i as u32));
        if ord.len() > before {
            starts.push(ord.len());
        }
    }
    Ok(Groups { ord, starts })
}

/// Groups of unsorted data by `keys` (numeric, str# or strL), restricted to the sample.
pub fn hashed_groups<I: Io>(io: &I, keys: &[i32], touse_var: Option<i32>, touse: Option<&[bool]>, threads: usize) -> Res<Groups> {
    let n = io.nobs();
    check_n(n)?;
    let ns = touse.map_or(n, |t| t.iter().filter(|&&b| b).count());
    let g = hash_groups(io, keys, touse_var, threads, default_hash)?;
    // Sample groups come first; the non-sample observations form one final range.
    let mut starts = g.starts;
    while starts.last().is_some_and(|&s| s > ns) {
        starts.pop();
    }
    let mut ord = g.ord;
    ord.truncate(ns);
    if starts.last() != Some(&ns) {
        return Err(Error::new(9999, "fastata: internal error (egen grouping); please report it"));
    }
    Ok(Groups { ord, starts })
}

/// Output column shared by the workers of [`for_groups`]: each observation is written by the one
/// worker that owns its group.
pub struct Scatter {
    ptr: *mut f64,
    len: usize,
}

unsafe impl Sync for Scatter {}

impl Scatter {
    pub fn new(out: &mut [f64]) -> Scatter {
        Scatter { ptr: out.as_mut_ptr(), len: out.len() }
    }

    /// Writes observation `i`.
    ///
    /// # Safety
    /// No other thread reads or writes observation `i` while the [`Scatter`] is in use, and the
    /// output slice outlives it.
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
/// item has its own scratch vector. Deterministic: groups are independent.
pub fn for_groups<I, F>(io: &I, g: &Groups, threads: usize, f: F) -> Res<()>
where
    I: Io,
    F: Fn(usize, &[u32], &mut Vec<f64>) -> Res<()> + Sync,
{
    let mut items = vec![0usize];
    let mut acc = 0;
    for gi in 0..g.len() {
        acc += g.starts[gi + 1] - g.starts[gi];
        if acc >= ITEM_OBS {
            items.push(gi + 1);
            acc = 0;
        }
    }
    if *items.last().unwrap_or(&0) != g.len() {
        items.push(g.len());
    }
    for_blocks(io, items.len() - 1, threads, StoreMode::Parallel, |it, _emit| {
        let mut scratch = Vec::new();
        for gi in items[it]..items[it + 1] {
            f(gi, g.members(gi), &mut scratch)?;
        }
        Ok(())
    })?;
    Ok(())
}

/// A key value of one group (its first observation).
#[derive(Clone, PartialEq, Debug)]
pub enum KeyVal {
    Num(f64),
    Str(Vec<u8>),
}

/// For each group of `g` (grouped by `keys`): whether any key is missing (numeric `.`-`.z`,
/// string ""), and its rank (0-based) in Stata's sort order of the key tuples among the groups
/// with `keep[g]`: numbers ascending (−0 = +0, missing codes after every number in the order
/// `.` < `.a` < ... < `.z`), strings bytewise with a prefix first, tuples lexicographic.
pub struct KeyInfo {
    pub has_missing: Vec<bool>,
}

pub fn key_info<I: Io>(io: &I, keys: &[i32], g: &Groups) -> Res<(KeyInfo, Vec<Vec<KeyVal>>)> {
    let miss = io.missval();
    let reps: Vec<u32> = (0..g.len()).map(|i| g.ord[g.starts[i]]).collect();
    let k = g.len();
    let numv: Vec<i32> = keys.iter().copied().filter(|&v| !io.is_str(v)).collect();
    let mut nums = vec_filled(k * numv.len(), 0.0)?;
    if !numv.is_empty() && k > 0 {
        io.read_block(&numv, Rows::List(&reps), &mut nums)?;
    }
    let mut tuples: Vec<Vec<KeyVal>> = vec_with_capacity(k)?;
    let mut has_missing = vec_filled(k, false)?;
    for (gi, &o) in reps.iter().enumerate() {
        let mut t = Vec::with_capacity(keys.len());
        let mut j = 0;
        for &v in keys {
            if io.is_str(v) {
                let mut s = Vec::new();
                io.read_str(v, o as usize, &mut s)?;
                has_missing[gi] |= s.is_empty();
                t.push(KeyVal::Str(s));
            } else {
                let x = nums[gi * numv.len() + j];
                j += 1;
                has_missing[gi] |= x >= miss;
                t.push(KeyVal::Num(if x == 0.0 { 0.0 } else { x }));
            }
        }
        tuples.push(t);
    }
    Ok((KeyInfo { has_missing }, tuples))
}

fn cmp_tuple(a: &[KeyVal], b: &[KeyVal]) -> Ordering {
    for (x, y) in a.iter().zip(b) {
        let o = match (x, y) {
            (KeyVal::Num(p), KeyVal::Num(q)) => p.partial_cmp(q).unwrap_or(Ordering::Equal),
            (KeyVal::Str(p), KeyVal::Str(q)) => p.cmp(q),
            _ => Ordering::Equal,
        };
        if o != Ordering::Equal {
            return o;
        }
    }
    Ordering::Equal
}

/// Group numbers 1..K in Stata's sort order of the key tuples of the groups with `keep`, `None`
/// for the others.
pub fn group_numbers(tuples: &[Vec<KeyVal>], keep: &[bool]) -> Vec<Option<u64>> {
    let mut idx: Vec<usize> = (0..tuples.len()).filter(|&i| keep[i]).collect();
    idx.sort_unstable_by(|&a, &b| cmp_tuple(&tuples[a], &tuples[b]));
    let mut out = vec![None; tuples.len()];
    for (r, &i) in idx.iter().enumerate() {
        out[i] = Some(r as u64 + 1);
    }
    out
}
