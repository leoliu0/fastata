//! `egen`: the compute phase of fastata's egen (two-phase protocol, see `crate::cache`). The
//! protocol with `stata/_fx_egen.ado` is in [`spec`]; the arithmetic of each function is in
//! [`reduce`] (expression functions, per group), [`rank`] (rank of a large group), [`rows`] (row
//! functions) and [`groups`] (grouping, and `group()` numbering).

mod groups;
mod rank;
mod reduce;
mod rows;
pub mod spec;

use std::cmp::Ordering as CmpOrdering;
use std::sync::atomic::{AtomicUsize, Ordering};

use crate::args::Args;
use crate::cache::{self, Output, read_cols};
use crate::error::{Error, Res, vec_filled};
use crate::io::{self, Io, Rows};
use crate::par::{Shared, for_chunks};

use groups::{Groups, for_groups, group_column, hashed_groups, one_group, read_touse, sorted_groups, tag_column};
use spec::{Fcn, RankMode, Spec, Ty, miss_count};

/// What one compute phase produced.
pub struct Computed {
    /// The result column, one raw value per observation (`.` = `missval`).
    pub out: Vec<f64>,
    /// Missing values in `out`.
    pub nmiss: usize,
    /// `median`, `pctile`, `iqr` without by-groups: nonmissing sample values.
    pub n: Option<usize>,
    /// `group` without `missing`: per key, numeric and integer-valued in every sample
    /// observation whose keys are all nonmissing (empty otherwise).
    pub keyint: Vec<bool>,
}

pub fn run<I: Io>(io: &I, a: &Args) -> Res<()> {
    let spec = Spec::parse(a, io.nvars())?;
    let c = compute(io, &spec)?;
    let token = cache::put(Output { nums: vec![c.out], strs: Vec::new() });
    io::local_save("fx_token", &token.to_string())?;
    io::local_save("fx_nmiss", &c.nmiss.to_string())?;
    if let Some(n) = c.n {
        io::local_save("fx_n", &n.to_string())?;
    }
    if !c.keyint.is_empty() {
        let k: Vec<&str> = c.keyint.iter().map(|&b| if b { "1" } else { "0" }).collect();
        io::local_save("fx_keyint", &k.join(" "))?;
    }
    Ok(())
}

/// Observations per block of the row functions.
const ROW_BLOCK: usize = 8192;

pub fn compute<I: Io>(io: &I, s: &Spec) -> Res<Computed> {
    let n = io.nobs();
    if n == 0 {
        return Err(Error::fallback("no observations"));
    }
    let miss = io.missval();
    let touse = read_touse(io, s.touse, s.threads)?;
    if s.fcn.is_keyed() {
        let (out, keyint) = keyed(io, s, touse.as_deref())?;
        let nmiss = out.iter().filter(|&&v| v >= miss).count();
        Ok(Computed { out, nmiss, n: None, keyint })
    } else if s.fcn.is_row() {
        let (out, nmiss) = row_fn(io, s, touse.as_deref())?;
        Ok(Computed { out, nmiss, n: None, keyint: Vec::new() })
    } else {
        let (out, nmiss, nn) = expr_fn(io, s, touse.as_deref())?;
        Ok(Computed { out, nmiss, n: nn, keyint: Vec::new() })
    }
}

/// `group()` and `tag()`: groups of the sample by the varlist; without `missing`, groups with a
/// missing key are left out (`.` for group, 0 for tag). Also returns, for `group()` without
/// `missing`, whether each key is numeric and integer at every observation numbered (one entry
/// per key; empty otherwise).
fn keyed<I: Io>(io: &I, s: &Spec, touse: Option<&[bool]>) -> Res<(Vec<f64>, Vec<bool>)> {
    if s.fcn == Fcn::Tag {
        return Ok((tag_column(io, &s.keys, touse, s.missing, s.threads)?, Vec::new()));
    }
    let miss = io.missval();
    let ty = s.ty;
    group_column(io, &s.keys, touse, s.missing, s.threads, |k| ty.cast(k, miss))
}

/// Raw values of the expression: the variable, or for `count` with `cntflag` the flag
/// `!missing(exp)` turned into 0 (nonmissing) / `.` (missing). A string variable (count only)
/// reads as 0 / `.` ("").
fn expr_values<I: Io>(io: &I, s: &Spec, touse: Option<&[bool]>) -> Res<Vec<f64>> {
    let miss = io.missval();
    let v = s.vals[0];
    if io.is_str(v) {
        if s.fcn != Fcn::Count {
            return Err(Error::fallback("string expression"));
        }
        let n = io.nobs();
        let mut x = vec_filled(n, miss)?;
        let mut buf = Vec::new();
        for (o, xo) in x.iter_mut().enumerate() {
            if touse.is_none_or(|t| t[o]) {
                buf.clear();
                io.read_str(v, o, &mut buf)?;
                *xo = if buf.is_empty() { miss } else { 0.0 };
            }
        }
        return Ok(x);
    }
    let mut x = read_cols(io, &[v], s.threads)?.pop().unwrap_or_default();
    crate::nan::check(&x)?;
    if s.cntflag {
        for xo in &mut x {
            *xo = if *xo != 0.0 && *xo < miss { 0.0 } else { miss };
        }
    }
    Ok(x)
}

/// `_grank`'s value for the lowest rank `lo` of `ties` tied values: `lo` (it is `_n`) stored in
/// the type, and for the default mode that plus (ties − 1)/2, stored again.
fn rank_value(lo: usize, ties: usize, mode: RankMode, ty: Ty, miss: f64) -> Res<f64> {
    let lo = ty.cast(lo as f64, miss)?;
    if mode == RankMode::Default { ty.cast(lo + (ties - 1) as f64 / 2.0, miss) } else { Ok(lo) }
}

/// The expression functions, per group of the sample: the result column, its missing values, and
/// for median/pctile/iqr without by-groups the nonmissing sample values.
fn expr_fn<I: Io>(io: &I, s: &Spec, touse: Option<&[bool]>) -> Res<(Vec<f64>, usize, Option<usize>)> {
    let miss = io.missval();
    let n = io.nobs();
    let x = expr_values(io, s, touse)?;
    let by = !s.keys.is_empty();
    let g: Groups = if !by {
        one_group(n, touse)?
    } else if s.sorted && s.keys.iter().all(|&k| !io.is_str(k)) {
        sorted_groups(io, &s.keys, touse, s.threads)?
    } else {
        hashed_groups(io, &s.keys, touse, s.threads)?
    };
    let mut out = vec_filled(n, miss)?;
    let quantile = matches!(s.fcn, Fcn::Median | Fcn::Pctile | Fcn::Iqr);
    let nonmiss_total = if quantile && !by {
        // `_pctile` orders -0 and +0 as ties, in an order of its own
        let zero = |neg: bool| g.ord.iter().any(|&o| x[o as usize] == 0.0 && x[o as usize].is_sign_negative() == neg);
        if zero(true) && zero(false) {
            return Err(Error::fallback("signed zero"));
        }
        Some(g.ord.iter().filter(|&&o| x[o as usize] < miss).count())
    } else {
        None
    };
    let ty = s.ty;
    let field = s.rank == RankMode::Field;
    let big_rank = |members: &[u32]| s.fcn == Fcn::Rank && members.len() >= rank::BIG;
    // Missing results among the sample observations (the others are `.`).
    let nm = AtomicUsize::new(0);
    let sc = Shared::new(&mut out);
    for_groups(io, &g, s.threads, |_gi, members, scratch| {
        if big_rank(members) {
            return Ok(());
        }
        let m = members.len();
        scratch.clear();
        scratch.try_reserve(if s.fcn == Fcn::Rank { 2 * m } else { m }).map_err(|_| Error::oom())?;
        scratch.extend(members.iter().map(|&o| x[o as usize]));
        let put_all = |v: f64| -> Res<()> {
            let v = ty.cast(v, miss)?;
            if miss_count(v, miss)? == 1 {
                nm.fetch_add(m, Ordering::Relaxed);
            }
            for &o in members {
                // SAFETY: groups are disjoint; each group is handled by one worker.
                unsafe { sc.set(o as usize, v) };
            }
            Ok(())
        };
        match s.fcn {
            Fcn::Total => put_all(reduce::total(scratch, miss, by, s.missing)?),
            Fcn::Mean => put_all(reduce::mean(scratch, miss, by)?),
            Fcn::Count => put_all(reduce::count(scratch, miss)),
            Fcn::Max | Fcn::Min => put_all(reduce::extreme(scratch, miss, s.fcn == Fcn::Max, s.missing, by)),
            Fcn::Sd => put_all(reduce::mean_sd(scratch, miss, by)?.1),
            Fcn::Std => {
                let (mu, sd) = reduce::mean_sd(scratch, miss, by)?;
                let mut k = 0;
                for (j, &o) in members.iter().enumerate() {
                    let v = ty.cast(reduce::std_value(scratch[j], mu, sd, s.sd, s.mean, miss)?, miss)?;
                    k += miss_count(v, miss)?;
                    // SAFETY: as above.
                    unsafe { sc.set(o as usize, v) };
                }
                nm.fetch_add(k, Ordering::Relaxed);
                Ok(())
            }
            Fcn::Median | Fcn::Pctile | Fcn::Iqr => {
                reduce::sort_nonmiss(scratch, miss);
                let sorted = &scratch[..];
                let v = match (s.fcn, by) {
                    (Fcn::Median, true) => reduce::median_by(sorted, miss)?,
                    (Fcn::Median, false) => reduce::pctile_nob(sorted, 50.0, miss),
                    (Fcn::Pctile, true) => reduce::pctile_by(sorted, s.p, miss)?,
                    (Fcn::Pctile, false) => reduce::pctile_nob(sorted, s.p, miss),
                    _ => reduce::iqr(sorted, by, miss)?,
                };
                put_all(v)
            }
            Fcn::Rank => {
                // scratch: the members' values, then their nonmissing values sorted
                for j in 0..m {
                    let v = scratch[j];
                    rank::check_input(v, field, miss)?;
                    if v < miss {
                        scratch.push(v);
                    }
                }
                let (vals, sorted) = scratch.split_at_mut(m);
                sorted.sort_unstable_by(|a, b| a.partial_cmp(b).unwrap_or(CmpOrdering::Equal));
                let mut k = 0;
                for (j, &o) in members.iter().enumerate() {
                    let v = vals[j];
                    let r = if v < miss {
                        let (lo, ties) = reduce::rank_of(sorted, v, field);
                        rank_value(lo, ties, s.rank, ty, miss)?
                    } else {
                        k += 1;
                        miss
                    };
                    // SAFETY: as above.
                    unsafe { sc.set(o as usize, r) };
                }
                nm.fetch_add(k, Ordering::Relaxed);
                Ok(())
            }
            _ => unreachable!("not an expression function"),
        }
    })?;
    let mut nmiss = (n - g.ord.len()) + nm.into_inner();
    if s.fcn == Fcn::Rank {
        for gi in 0..g.len() {
            let members = g.members(gi);
            if big_rank(members) {
                nmiss += rank::rank_big(io, &x, members, field, miss, s.threads, |o, lo, ties| {
                    let v = rank_value(lo, ties, s.rank, ty, miss)?;
                    // SAFETY: each observation of the group gets one call; no other writer.
                    unsafe { sc.set(o as usize, v) };
                    Ok(())
                })?;
            }
        }
    }
    Ok((out, nmiss, nonmiss_total))
}

/// The row functions, in parallel blocks of observations, written in place: the result column
/// and its missing values.
fn row_fn<I: Io>(io: &I, s: &Spec, touse: Option<&[bool]>) -> Res<(Vec<f64>, usize)> {
    let miss = io.missval();
    let n = io.nobs();
    let k = s.vals.len();
    let strs: Vec<bool> = s.vals.iter().map(|&v| io.is_str(v)).collect();
    if strs.iter().any(|&b| b) && !matches!(s.fcn, Fcn::RowMiss | Fcn::RowNonmiss) {
        return Err(Error::fallback("string variable"));
    }
    // String variables: missing (`""`) or not, read on this thread.
    let mut smiss: Vec<Vec<bool>> = Vec::new();
    let mut buf = Vec::new();
    for (j, &v) in s.vals.iter().enumerate() {
        if !strs[j] {
            continue;
        }
        let mut col = vec_filled(n, false)?;
        for (o, c) in col.iter_mut().enumerate() {
            if touse.is_none_or(|t| t[o]) {
                buf.clear();
                io.read_str(v, o, &mut buf)?;
                *c = buf.is_empty();
            }
        }
        smiss.push(col);
    }
    let numv: Vec<i32> = s.vals.iter().zip(&strs).filter(|(_, s)| !**s).map(|(v, _)| *v).collect();
    let nn = numv.len();
    let mut out = vec_filled(n, miss)?;
    let counts = for_chunks(io, &mut [&mut out[..]], ROW_BLOCK, s.threads, |b, ch| {
        let res = &mut *ch[0];
        let first = b * ROW_BLOCK;
        let m = res.len();
        let mut raw = vec_filled(m * nn, 0.0)?;
        if nn > 0 {
            io.read_block(&numv, Rows::Range { first, n: m }, &mut raw)?;
            crate::nan::check(&raw)?;
        }
        let mut v = vec![0.0; k];
        let mut nmiss = 0;
        for r in 0..m {
            let o = first + r;
            if touse.is_some_and(|t| !t[o]) {
                nmiss += 1;
                continue;
            }
            let (mut jn, mut js) = (0, 0);
            for j in 0..k {
                if strs[j] {
                    v[j] = if smiss[js][o] { miss } else { 0.0 };
                    js += 1;
                } else {
                    v[j] = raw[r * nn + jn];
                    jn += 1;
                }
            }
            let y = rows::row(s.fcn, &v, s.ty, s.missing, miss)?;
            nmiss += miss_count(y, miss)?;
            res[r] = y;
        }
        Ok(nmiss)
    })?;
    Ok((out, counts.into_iter().sum()))
}

#[cfg(test)]
mod tests;
