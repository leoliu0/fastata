//! Group kernels of the expression functions. Each takes the group's raw values in ascending
//! observation order (sample observations only) and follows the original `_g<fcn>.ado`:
//!
//! - with by-groups, the running `sum()`s of `_gtotal`/`_gmean`/`_gsd`/`_gstd` (a sequential
//!   double sum from +0, missing values skipped) and the sorted-subscript formulas of
//!   `_gmedian`/`_gpctile`/`_giqr`;
//! - without by-groups, `summarize` (calibration C2: a Neumaier-compensated sum in observation
//!   order; mean = sum/N; variance = compensated sum of (x − mean)² over N − 1; sd = its sqrt)
//!   and `_pctile` (`crate::quant::pctile`).

use std::cmp::Ordering;

use super::spec::{RankMode, arith};
use crate::quant;

/// `summarize`'s sum (calibration C2): Neumaier's compensated sum in the given order.
pub fn neumaier(xs: impl Iterator<Item = f64>) -> f64 {
    let (mut s, mut c) = (0.0f64, 0.0f64);
    for x in xs {
        let t = s + x;
        if s.abs() >= x.abs() {
            c += (s - t) + x;
        } else {
            c += (x - t) + s;
        }
        s = t;
    }
    s + c
}

fn nonmiss(xs: &[f64], miss: f64) -> impl Iterator<Item = f64> + '_ {
    xs.iter().copied().filter(move |&v| v < miss)
}

/// `(sum, count)` of the nonmissing values: by-group running sum, or summarize's sum.
pub fn sum_count(xs: &[f64], miss: f64, by: bool) -> (f64, usize) {
    let n = nonmiss(xs, miss).count();
    let s = if by {
        let mut s = 0.0;
        for v in nonmiss(xs, miss) {
            s += v;
        }
        s
    } else {
        neumaier(nonmiss(xs, miss))
    };
    (s, n)
}

/// `total()`: the sum (0 when every value is missing, `.` then with `missing`).
pub fn total(xs: &[f64], miss: f64, by: bool, missing: bool) -> f64 {
    let (s, n) = sum_count(xs, miss, by);
    if missing && n == 0 { miss } else { arith(s, miss) }
}

/// `mean()`: sum/n, `.` when n = 0.
pub fn mean(xs: &[f64], miss: f64, by: bool) -> f64 {
    let (s, n) = sum_count(xs, miss, by);
    arith(s / n as f64, miss)
}

/// `(mean, sd)` as `_gsd` (by-groups: `m = sum/n`, `sqrt(sum((x − m)²)/(n − 1))`, sequential)
/// or `summarize` (`r(mean)`, `r(sd)`). n = 0 gives (`.`, `.`); n = 1 gives sd `.`.
pub fn mean_sd(xs: &[f64], miss: f64, by: bool) -> (f64, f64) {
    let (s, n) = sum_count(xs, miss, by);
    if n == 0 {
        return (miss, miss);
    }
    let m = s / n as f64;
    let sq = nonmiss(xs, miss).map(|v| (v - m) * (v - m));
    let ss = if by {
        let mut a = 0.0;
        for q in sq {
            a += q;
        }
        a
    } else {
        neumaier(sq)
    };
    (arith(m, miss), arith((ss / (n - 1) as f64).sqrt(), miss))
}

/// `std()` of value `x`: `sd_opt*(x − m)/s + mean_opt`, `.` when any part is missing.
#[inline]
pub fn std_value(x: f64, m: f64, s: f64, sd_opt: f64, mean_opt: f64, miss: f64) -> f64 {
    if x >= miss || m >= miss || s >= miss {
        return miss;
    }
    arith(sd_opt * (x - m) / s + mean_opt, miss)
}

/// `max()`/`min()`: the extreme nonmissing value (`.` if none). With `missing`, missing values
/// count as larger than every number and keep their codes (`.` < `.a` < ... < `.z`).
pub fn extreme(xs: &[f64], miss: f64, max: bool, missing: bool) -> f64 {
    let mut it = xs.iter().copied().filter(|&v| missing || v < miss);
    let Some(first) = it.next() else { return miss };
    it.fold(first, |a, v| if (max && v > a) || (!max && v < a) { v } else { a })
}

pub fn count(xs: &[f64], miss: f64) -> f64 {
    nonmiss(xs, miss).count() as f64
}

/// Keeps the nonmissing values of `xs`, sorted ascending.
pub fn sort_nonmiss(xs: &mut Vec<f64>, miss: f64) {
    xs.retain(|&v| v < miss);
    xs.sort_unstable_by(|a, b| a.partial_cmp(b).unwrap_or(Ordering::Equal));
}

/// `x[k]` of the sorted nonmissing values, 1-based; outside 1..n it is `.` (Stata's subscript
/// beyond the group, or the missing values sorted last are never reached by the formulas).
#[inline]
fn at(s: &[f64], k: f64, miss: f64) -> f64 {
    if k >= 1.0 && k <= s.len() as f64 { s[k as usize - 1] } else { miss }
}

fn half_sum(a: f64, b: f64, miss: f64) -> f64 {
    if a >= miss || b >= miss { miss } else { arith((a + b) / 2.0, miss) }
}

/// `_gmedian` by-group: `cond(mod(n,2), x[(n+1)/2], (x[n/2] + x[n/2+1])/2)` over the sorted
/// nonmissing values `s` (n = 0 gives `.`).
pub fn median_by(s: &[f64], miss: f64) -> f64 {
    let n = s.len() as f64;
    if s.len() % 2 == 1 { at(s, (n + 1.0) / 2.0, miss) } else { half_sum(at(s, n / 2.0, miss), at(s, n / 2.0 + 1.0, miss), miss) }
}

/// Stata's `round(x, 1)`.
#[inline]
fn round1(x: f64) -> f64 {
    (x + 0.5).floor()
}

/// `_gpctile` by-group: `np = round(n*p/100, 1)`; `cond(100*np == n*p, (x[np] + x[np+1])/2,
/// x[floor(n*p/100) + 1])`.
pub fn pctile_by(s: &[f64], p: f64, miss: f64) -> f64 {
    let n = s.len() as f64;
    let np = round1(n * p / 100.0);
    if 100.0 * np == n * p { half_sum(at(s, np, miss), at(s, np + 1.0, miss), miss) } else { at(s, (n * p / 100.0).floor() + 1.0, miss) }
}

/// `_pctile` of the sorted nonmissing values (`.` when there are none).
pub fn pctile_nob(s: &[f64], p: f64, miss: f64) -> f64 {
    if s.is_empty() { miss } else { quant::pctile(s, p) }
}

fn diff(a: f64, b: f64, miss: f64) -> f64 {
    if a >= miss || b >= miss { miss } else { arith(a - b, miss) }
}

/// `iqr()`: p75 − p25 (by-group formulas or `_pctile`).
pub fn iqr(s: &[f64], by: bool, miss: f64) -> f64 {
    if by { diff(pctile_by(s, 75.0, miss), pctile_by(s, 25.0, miss), miss) } else { diff(pctile_nob(s, 75.0, miss), pctile_nob(s, 25.0, miss), miss) }
}

/// `_grank`: per member (same order as `xs`), the rank among the group's nonmissing values, `.`
/// for missing ones. Default and `track`: ascending; `field`: descending. Ties get the lowest
/// rank, `cast`-ed to the storage type; the default then adds (ties − 1)/2 and casts again.
pub fn rank<F>(xs: &[f64], mode: RankMode, miss: f64, idx: &mut Vec<u32>, mut out: F) -> crate::error::Res<()>
where
    F: FnMut(usize, Option<(f64, usize)>) -> crate::error::Res<()>,
{
    idx.clear();
    idx.extend((0..xs.len() as u32).filter(|&i| xs[i as usize] < miss));
    let key = |i: &u32| xs[*i as usize];
    match mode {
        RankMode::Field => idx.sort_unstable_by(|a, b| key(b).partial_cmp(&key(a)).unwrap_or(Ordering::Equal)),
        _ => idx.sort_unstable_by(|a, b| key(a).partial_cmp(&key(b)).unwrap_or(Ordering::Equal)),
    }
    let mut i = 0;
    while i < idx.len() {
        let v = key(&idx[i]);
        let mut j = i + 1;
        while j < idx.len() && key(&idx[j]) == v {
            j += 1;
        }
        for &m in &idx[i..j] {
            out(m as usize, Some(((i + 1) as f64, j - i)))?;
        }
        i = j;
    }
    for (m, &v) in xs.iter().enumerate() {
        if v >= miss {
            out(m, None)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::MISS;
    use crate::testutil::miss_a;

    #[test]
    fn neumaier_recovers_cancelled_terms() {
        assert_eq!(neumaier([1e16, 1.0, -1e16].into_iter()), 1.0);
        assert_eq!(neumaier([2f64.powi(200), 1.0, -(2f64.powi(200))].into_iter()), 1.0);
        assert_eq!(neumaier(std::iter::empty()), 0.0);
        // Sequential double addition loses the 1.
        assert_eq!(sum_count(&[1e16, 1.0, -1e16], MISS, true).0, 0.0);
    }

    #[test]
    fn by_group_quantile_formulas() {
        let s = [1.0, 2.0, 3.0, 4.0];
        assert_eq!(median_by(&s, MISS), 2.5);
        assert_eq!(median_by(&s[..3], MISS), 2.0);
        assert_eq!(median_by(&[], MISS), MISS);
        assert_eq!(pctile_by(&s, 50.0, MISS), 2.5);
        assert_eq!(pctile_by(&s, 30.0, MISS), 2.0);
        assert_eq!(pctile_by(&s, 10.0, MISS), 1.0);
        assert_eq!(pctile_by(&[], 10.0, MISS), MISS);
        assert_eq!(pctile_by(&[7.0], 99.0, MISS), 7.0);
        assert_eq!(iqr(&s, true, MISS), 2.0);
    }

    #[test]
    fn extremes_and_missing_codes() {
        let xs = [3.0, MISS, miss_a(), -1.0];
        assert_eq!(extreme(&xs, MISS, true, false), 3.0);
        assert_eq!(extreme(&xs, MISS, false, false), -1.0);
        assert_eq!(extreme(&xs, MISS, true, true), miss_a());
        assert_eq!(extreme(&xs, MISS, false, true), -1.0);
        assert_eq!(extreme(&[miss_a()], MISS, true, false), MISS);
        assert_eq!(extreme(&[miss_a(), MISS], MISS, false, true), MISS);
    }

    #[test]
    fn ranks_ties_and_fields() {
        let xs = [5.0, 1.0, 5.0, MISS, -0.0, 0.0];
        let mut idx = Vec::new();
        let mut got = vec![None; xs.len()];
        rank(&xs, RankMode::Default, MISS, &mut idx, |m, r| {
            got[m] = r;
            Ok(())
        })
        .unwrap();
        assert_eq!(got, vec![Some((4.0, 2)), Some((3.0, 1)), Some((4.0, 2)), None, Some((1.0, 2)), Some((1.0, 2))]);
        rank(&xs, RankMode::Field, MISS, &mut idx, |m, r| {
            got[m] = r;
            Ok(())
        })
        .unwrap();
        assert_eq!(got[0], Some((1.0, 2)));
        assert_eq!(got[1], Some((3.0, 1)));
        assert_eq!(got[4], Some((4.0, 2)));
    }

    #[test]
    fn sd_of_one_value_is_missing() {
        assert_eq!(mean_sd(&[3.0], MISS, true), (3.0, MISS));
        assert_eq!(mean_sd(&[3.0], MISS, false), (3.0, MISS));
        assert_eq!(mean_sd(&[MISS], MISS, true), (MISS, MISS));
        let (m, s) = mean_sd(&[1.0, 2.0, 3.0, 4.0], MISS, false);
        assert_eq!(m, 2.5);
        assert_eq!(s, (5.0f64 / 3.0).sqrt());
    }
}
