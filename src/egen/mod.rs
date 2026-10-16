//! `egen`: the compute phase of fastata's egen (two-phase protocol, see `crate::cache`). The
//! protocol with `stata/_fx_egen.ado` is in [`spec`]; the arithmetic of each function is in
//! [`reduce`] (expression functions, per group), [`rows`] (row functions) and [`groups`]
//! (grouping, and `group()` numbering).

mod groups;
mod reduce;
mod rows;
pub mod spec;

use crate::args::Args;
use crate::cache::{self, Output, read_cols};
use crate::error::{Error, Res, vec_filled};
use crate::io::{self, Io, Rows};
use crate::par::{StoreMode, for_blocks};

use groups::{Groups, Scatter, for_groups, group_numbers, hashed_groups, key_info, one_group, read_touse, sorted_groups};
use spec::{Fcn, Spec};

/// What one compute phase produced.
pub struct Computed {
    /// The result column, one raw value per observation (`.` = `missval`).
    pub out: Vec<f64>,
    /// Missing values in `out`.
    pub nmiss: usize,
    /// `median`, `pctile`, `iqr` without by-groups: nonmissing sample values.
    pub n: Option<usize>,
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
    crate::nan::check_vars(io, &s.keys, s.threads)?;
    let touse = read_touse(io, s.touse, s.threads)?;
    let mut nn = None;
    let out = if s.fcn.is_keyed() {
        keyed(io, s, touse.as_deref())?
    } else if s.fcn.is_row() {
        row_fn(io, s, touse.as_deref())?
    } else {
        let (o, k) = expr_fn(io, s, touse.as_deref())?;
        nn = k;
        o
    };
    let nmiss = out.iter().filter(|&&v| v >= miss).count();
    Ok(Computed { out, nmiss, n: nn })
}

/// `group()` and `tag()`: groups of the sample by the varlist; without `missing`, groups with a
/// missing key are left out (`.` for group, 0 for tag).
fn keyed<I: Io>(io: &I, s: &Spec, touse: Option<&[bool]>) -> Res<Vec<f64>> {
    let miss = io.missval();
    let n = io.nobs();
    let g = hashed_groups(io, &s.keys, s.touse, touse, s.threads)?;
    let (info, tuples) = key_info(io, &s.keys, &g)?;
    let keep: Vec<bool> = info.has_missing.iter().map(|&m| s.missing || !m).collect();
    let tag = s.fcn == Fcn::Tag;
    let mut out = vec_filled(n, if tag { 0.0 } else { miss })?;
    let ids = if tag { Vec::new() } else { group_numbers(&tuples, &keep) };
    let sc = Scatter::new(&mut out);
    for_groups(io, &g, s.threads, |gi, members, _| {
        if !keep[gi] {
            return Ok(());
        }
        if tag {
            // SAFETY: groups are disjoint; each group is handled by one worker.
            unsafe { sc.set(members[0], 1.0) };
        } else {
            let v = s.ty.cast(ids[gi].map_or(miss, |k| k as f64), miss)?;
            for &o in members {
                // SAFETY: as above.
                unsafe { sc.set(o, v) };
            }
        }
        Ok(())
    })?;
    Ok(out)
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

/// The expression functions, per group of the sample.
fn expr_fn<I: Io>(io: &I, s: &Spec, touse: Option<&[bool]>) -> Res<(Vec<f64>, Option<usize>)> {
    let miss = io.missval();
    let n = io.nobs();
    let x = expr_values(io, s, touse)?;
    let by = !s.keys.is_empty();
    let g: Groups = if !by {
        one_group(n, touse)?
    } else if s.sorted && s.keys.iter().all(|&k| !io.is_str(k)) {
        sorted_groups(io, &s.keys, touse, s.threads)?
    } else {
        hashed_groups(io, &s.keys, s.touse, touse, s.threads)?
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
    let sc = Scatter::new(&mut out);
    let ty = s.ty;
    for_groups(io, &g, s.threads, |_gi, members, scratch| {
        scratch.clear();
        scratch.extend(members.iter().map(|&o| x[o as usize]));
        let put_all = |v: f64| -> Res<()> {
            let v = ty.cast(v, miss)?;
            for &o in members {
                // SAFETY: groups are disjoint; each group is handled by one worker.
                unsafe { sc.set(o, v) };
            }
            Ok(())
        };
        match s.fcn {
            Fcn::Total => put_all(reduce::total(scratch, miss, by, s.missing)),
            Fcn::Mean => put_all(reduce::mean(scratch, miss, by)),
            Fcn::Count => put_all(reduce::count(scratch, miss)),
            Fcn::Max | Fcn::Min => put_all(reduce::extreme(scratch, miss, s.fcn == Fcn::Max, s.missing, by)),
            Fcn::Sd => put_all(reduce::mean_sd(scratch, miss, by).1),
            Fcn::Std => {
                let (m, sd) = reduce::mean_sd(scratch, miss, by);
                for (k, &o) in members.iter().enumerate() {
                    let v = ty.cast(reduce::std_value(scratch[k], m, sd, s.sd, s.mean, miss), miss)?;
                    // SAFETY: as above.
                    unsafe { sc.set(o, v) };
                }
                Ok(())
            }
            Fcn::Median | Fcn::Pctile | Fcn::Iqr => {
                reduce::sort_nonmiss(scratch, miss);
                let sorted = &scratch[..];
                let v = match (s.fcn, by) {
                    (Fcn::Median, true) => reduce::median_by(sorted, miss),
                    (Fcn::Median, false) => reduce::pctile_nob(sorted, 50.0, miss),
                    (Fcn::Pctile, true) => reduce::pctile_by(sorted, s.p, miss),
                    (Fcn::Pctile, false) => reduce::pctile_nob(sorted, s.p, miss),
                    _ => reduce::iqr(sorted, by, miss),
                };
                put_all(v)
            }
            Fcn::Rank => {
                let mut idx = Vec::new();
                reduce::rank(scratch, s.rank, miss, &mut idx, |k, r| {
                    let v = match r {
                        None => miss,
                        Some((lo, ties)) => {
                            let lo = ty.cast(lo, miss)?;
                            if s.rank == spec::RankMode::Default {
                                ty.cast(lo + (ties - 1) as f64 / 2.0, miss)?
                            } else {
                                lo
                            }
                        }
                    };
                    // SAFETY: as above.
                    unsafe { sc.set(members[k], v) };
                    Ok(())
                })
            }
            _ => unreachable!("not an expression function"),
        }
    })?;
    Ok((out, nonmiss_total))
}

/// The row functions, in parallel blocks of observations.
fn row_fn<I: Io>(io: &I, s: &Spec, touse: Option<&[bool]>) -> Res<Vec<f64>> {
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
    let blocks = for_blocks(io, n.div_ceil(ROW_BLOCK), s.threads, StoreMode::Parallel, |b, _emit| {
        let first = b * ROW_BLOCK;
        let m = ROW_BLOCK.min(n - first);
        let mut raw = vec_filled(m * nn, 0.0)?;
        if nn > 0 {
            io.read_block(&numv, Rows::Range { first, n: m }, &mut raw)?;
            crate::nan::check(&raw)?;
        }
        let mut res = vec_filled(m, miss)?;
        let mut v = vec![0.0; k];
        for r in 0..m {
            let o = first + r;
            if touse.is_some_and(|t| !t[o]) {
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
            res[r] = rows::row(s.fcn, &v, s.ty, s.missing, miss)?;
        }
        Ok(res)
    })?;
    let mut out = Vec::new();
    out.try_reserve_exact(n).map_err(|_| Error::oom())?;
    for b in blocks {
        out.extend(b);
    }
    Ok(out)
}

#[cfg(test)]
mod tests;
