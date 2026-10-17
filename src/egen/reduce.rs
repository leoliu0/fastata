//! Group kernels of the expression functions. Each takes the group's raw values in ascending
//! observation order (sample observations only) and follows the original `_g<fcn>.ado`:
//!
//! - with by-groups, the running `sum()`s of `_gtotal`/`_gmean`/`_gsd`/`_gstd` (a sequential
//!   double sum from +0, missing values skipped) and the sorted-subscript formulas of
//!   `_gmedian`/`_gpctile`/`_giqr`;
//! - without by-groups, `summarize` (calibration C2: a Neumaier-compensated sum in observation
//!   order; mean = sum/N; variance = compensated sum of (x − mean)² over N − 1; sd = its sqrt)
//!   and `_pctile` (`crate::quant::pctile`).
//!
//! Intermediate results of Stata arithmetic that Stata keeps differently from f64 (beyond `.`,
//! infinite, NaN) are a fallback [overflow] (`spec::checked`).

use std::cmp::Ordering;

use super::spec::{arith, checked};
use crate::error::Res;
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

/// `(sum, count)` of the nonmissing values: by-group running sum (`sum()`, every partial sum
/// checked), or summarize's sum.
pub fn sum_count(xs: &[f64], miss: f64, by: bool) -> Res<(f64, usize)> {
    if by {
        let (mut s, mut n) = (0.0, 0usize);
        for v in nonmiss(xs, miss) {
            s = checked(s + v, miss)?;
            n += 1;
        }
        Ok((s, n))
    } else {
        Ok((neumaier(nonmiss(xs, miss)), nonmiss(xs, miss).count()))
    }
}

/// `total()`: the sum (0 when every value is missing, `.` then with `missing`).
pub fn total(xs: &[f64], miss: f64, by: bool, missing: bool) -> Res<f64> {
    let (s, n) = sum_count(xs, miss, by)?;
    Ok(if missing && n == 0 { miss } else { arith(s, miss) })
}

/// `mean()`: sum/n, `.` when n = 0.
pub fn mean(xs: &[f64], miss: f64, by: bool) -> Res<f64> {
    let (s, n) = sum_count(xs, miss, by)?;
    Ok(arith(s / n as f64, miss))
}

/// `(mean, sd)` as `_gsd` (by-groups: `m = sum/n`, `sqrt(sum((x − m)²)/(n − 1))`, sequential,
/// every difference, square and partial sum checked) or `summarize` (`r(mean)`, `r(sd)`).
/// n = 0 gives (`.`, `.`); n = 1 gives sd `.`.
pub fn mean_sd(xs: &[f64], miss: f64, by: bool) -> Res<(f64, f64)> {
    let (s, n) = sum_count(xs, miss, by)?;
    if n == 0 {
        return Ok((miss, miss));
    }
    let m = s / n as f64;
    let ss = if by {
        let mut a = 0.0;
        for v in nonmiss(xs, miss) {
            let d = checked(v - m, miss)?;
            a = checked(a + checked(d * d, miss)?, miss)?;
        }
        a
    } else {
        neumaier(nonmiss(xs, miss).map(|v| (v - m) * (v - m)))
    };
    Ok((arith(m, miss), arith((ss / (n - 1) as f64).sqrt(), miss)))
}

/// `std()` of value `x`: `sd_opt*(x − m)/s + mean_opt`, `.` when any part is missing or s is 0
/// (Stata's division by zero), every step checked. Stata's expression parser binds `/` tighter
/// than `*`: `a*b/c` is `a*(b/c)`.
#[inline]
pub fn std_value(x: f64, m: f64, s: f64, sd_opt: f64, mean_opt: f64, miss: f64) -> Res<f64> {
    if x >= miss || m >= miss || s >= miss || s == 0.0 {
        return Ok(miss);
    }
    let q = checked(checked(x - m, miss)? / s, miss)?;
    checked(checked(sd_opt * q, miss)? + mean_opt, miss)
}

/// `max()`/`min()`: the extreme nonmissing value (`.` if none). With `missing`, missing values
/// count as larger than every number and keep their codes (`.` < `.a` < ... < `.z`). Of equal
/// values (only -0 and +0 differ in their bits), `summarize`'s `r(max)`/`r(min)` (no by-groups,
/// no `missing`) is the first; `_gmax`'s and `_gmin`'s running comparison over the group in
/// observation order (by-groups or `missing`) keeps the last.
pub fn extreme(xs: &[f64], miss: f64, max: bool, missing: bool, by: bool) -> f64 {
    let last = by || missing;
    let mut it = xs.iter().copied().filter(|&v| missing || v < miss);
    let Some(first) = it.next() else { return miss };
    it.fold(first, |a, v| if (max && v > a) || (!max && v < a) || (last && v == a) { v } else { a })
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

/// `(a + b)/2`, the sum checked.
fn half_sum(a: f64, b: f64, miss: f64) -> Res<f64> {
    if a >= miss || b >= miss { Ok(miss) } else { Ok(checked(a + b, miss)? / 2.0) }
}

/// `_gmedian` by-group: `cond(mod(n,2), x[(n+1)/2], (x[n/2] + x[n/2+1])/2)` over the sorted
/// nonmissing values `s` (n = 0 gives `.`).
pub fn median_by(s: &[f64], miss: f64) -> Res<f64> {
    let n = s.len() as f64;
    if s.len() % 2 == 1 { Ok(at(s, (n + 1.0) / 2.0, miss)) } else { half_sum(at(s, n / 2.0, miss), at(s, n / 2.0 + 1.0, miss), miss) }
}

/// Stata's `round(x, 1)`.
#[inline]
fn round1(x: f64) -> f64 {
    (x + 0.5).floor()
}

/// `_gpctile` by-group: `np = round(n*p/100, 1)`; `cond(100*np == n*p, (x[np] + x[np+1])/2,
/// x[floor(n*p/100) + 1])`, with `n*p/100` = `n*(p/100)` (see [`std_value`]).
pub fn pctile_by(s: &[f64], p: f64, miss: f64) -> Res<f64> {
    let n = s.len() as f64;
    let np = round1(n * (p / 100.0));
    if 100.0 * np == n * p {
        half_sum(at(s, np, miss), at(s, np + 1.0, miss), miss)
    } else {
        Ok(at(s, (n * (p / 100.0)).floor() + 1.0, miss))
    }
}

/// `_pctile` of the sorted nonmissing values (`.` when there are none).
pub fn pctile_nob(s: &[f64], p: f64, miss: f64) -> f64 {
    if s.is_empty() { miss } else { quant::pctile(s, p) }
}

/// `a - b`, checked (Stata keeps a raw `r(r2) - r(r1)` beyond `.`).
fn diff(a: f64, b: f64, miss: f64) -> Res<f64> {
    if a >= miss || b >= miss { Ok(miss) } else { checked(a - b, miss) }
}

/// `iqr()`: p75 − p25 (by-group formulas, or `_pctile`'s `r(r2) - r(r1)`).
pub fn iqr(s: &[f64], by: bool, miss: f64) -> Res<f64> {
    if by {
        diff(pctile_by(s, 75.0, miss)?, pctile_by(s, 25.0, miss)?, miss)
    } else {
        diff(pctile_nob(s, 75.0, miss), pctile_nob(s, 25.0, miss), miss)
    }
}

/// `_grank` of nonmissing value `v` among the group's nonmissing values `sorted` (ascending):
/// `(lowest rank, ties)`. Default and `track`: ascending; `field`: descending. -0 and +0 tie.
#[inline]
pub fn rank_of(sorted: &[f64], v: f64, field: bool) -> (usize, usize) {
    let lo = sorted.partition_point(|&y| y < v);
    let hi = sorted.partition_point(|&y| y <= v);
    (if field { sorted.len() - hi } else { lo } + 1, hi - lo)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::MISS;
    use crate::testutil::miss_a;

    fn is_overflow(r: Res<impl std::fmt::Debug>) -> bool {
        r.err().is_some_and(|e| e.is_fallback() && e.msg == super::super::spec::OVERFLOW)
    }

    #[test]
    fn neumaier_recovers_cancelled_terms() {
        assert_eq!(neumaier([1e16, 1.0, -1e16].into_iter()), 1.0);
        assert_eq!(neumaier([2f64.powi(200), 1.0, -(2f64.powi(200))].into_iter()), 1.0);
        assert_eq!(neumaier(std::iter::empty()), 0.0);
        // Sequential double addition loses the 1.
        assert_eq!(sum_count(&[1e16, 1.0, -1e16], MISS, true).unwrap().0, 0.0);
    }

    #[test]
    fn by_group_quantile_formulas() {
        let s = [1.0, 2.0, 3.0, 4.0];
        assert_eq!(median_by(&s, MISS).unwrap(), 2.5);
        assert_eq!(median_by(&s[..3], MISS).unwrap(), 2.0);
        assert_eq!(median_by(&[], MISS).unwrap(), MISS);
        assert_eq!(pctile_by(&s, 50.0, MISS).unwrap(), 2.5);
        assert_eq!(pctile_by(&s, 30.0, MISS).unwrap(), 2.0);
        assert_eq!(pctile_by(&s, 10.0, MISS).unwrap(), 1.0);
        assert_eq!(pctile_by(&[], 10.0, MISS).unwrap(), MISS);
        assert_eq!(pctile_by(&[7.0], 99.0, MISS).unwrap(), 7.0);
        assert_eq!(iqr(&s, true, MISS).unwrap(), 2.0);
    }

    /// The review's cases (rust_kernels F1): where Stata keeps a raw result beyond `.`, skips an
    /// overflowed square in `sum()` or turns a raw operand into `.`, the kernels fall back.
    #[test]
    fn overflow_falls_back() {
        let big = 8e307;
        // by-group sum, mean, sd of (8e307, 8e307): the running sum passes `.`
        assert!(is_overflow(total(&[big, big], MISS, true, false)));
        assert!(is_overflow(mean(&[big, big], MISS, true)));
        // (-8e307 x3): the sum passes -`.`
        assert!(is_overflow(total(&[-big, -big, -big], MISS, true, false)));
        // (1e160, -1e160, 0) and (±6e307 x2): the squares overflow (Stata's sum() skips them)
        assert!(is_overflow(mean_sd(&[1e160, -1e160, 0.0], MISS, true)));
        assert!(is_overflow(mean_sd(&[6e307, -6e307, 6e307, -6e307], MISS, true)));
        // median of (8e307, 8e307): x[1] + x[2] passes `.`
        assert!(is_overflow(median_by(&[big, big], MISS)));
        assert!(is_overflow(pctile_by(&[big, big], 50.0, MISS)));
        // iqr without by-groups: r(r2) - r(r1) beyond `.`
        assert!(is_overflow(iqr(&[-big, -big, -big, 1.0, 2.0, big, big, big], false, MISS)));
        // std: (x - m)/s beyond `.`
        assert!(is_overflow(std_value(big, -big, 0.5, 1.0, 0.0, MISS)));
        // In range: unchanged; summarize's sums without by-groups keep their rule.
        assert_eq!(total(&[1e160, -1e160, 0.0], MISS, true, false).unwrap(), 0.0);
        assert_eq!(total(&[big, big], MISS, false, false).unwrap(), MISS);
        assert_eq!(mean_sd(&[6e307, -6e307], MISS, false).unwrap().0, 0.0);
        // std of a constant group: s = 0, Stata's division by zero is `.`
        assert_eq!(std_value(3.0, 3.0, 0.0, 1.0, 0.0, MISS).unwrap(), MISS);
    }

    #[test]
    fn extremes_of_signed_zeros() {
        let (p, m) = (0.0_f64, -0.0_f64);
        let sign = |v: f64| v.is_sign_negative();
        for max in [true, false] {
            // summarize: the first; _gmax/_gmin (by-groups or missing): the last
            assert!(!sign(extreme(&[p, m], MISS, max, false, false)));
            assert!(sign(extreme(&[m, p], MISS, max, false, false)));
            for (missing, by) in [(true, false), (false, true), (true, true)] {
                assert!(sign(extreme(&[p, m], MISS, max, missing, by)));
                assert!(!sign(extreme(&[m, p, MISS], MISS, max, missing, by)));
            }
        }
    }

    #[test]
    fn extremes_and_missing_codes() {
        let xs = [3.0, MISS, miss_a(), -1.0];
        assert_eq!(extreme(&xs, MISS, true, false, false), 3.0);
        assert_eq!(extreme(&xs, MISS, false, false, false), -1.0);
        assert_eq!(extreme(&xs, MISS, true, true, false), miss_a());
        assert_eq!(extreme(&xs, MISS, false, true, false), -1.0);
        assert_eq!(extreme(&[miss_a()], MISS, true, false, false), MISS);
        assert_eq!(extreme(&[miss_a(), MISS], MISS, false, true, false), MISS);
    }

    #[test]
    fn ranks_ties_and_fields() {
        let mut s = vec![5.0, 1.0, 5.0, MISS, -0.0, 0.0];
        sort_nonmiss(&mut s, MISS);
        assert_eq!(rank_of(&s, 5.0, false), (4, 2));
        assert_eq!(rank_of(&s, 1.0, false), (3, 1));
        assert_eq!(rank_of(&s, -0.0, false), (1, 2));
        assert_eq!(rank_of(&s, 0.0, false), (1, 2));
        assert_eq!(rank_of(&s, 5.0, true), (1, 2));
        assert_eq!(rank_of(&s, 1.0, true), (3, 1));
        assert_eq!(rank_of(&s, 0.0, true), (4, 2));
    }

    #[test]
    fn sd_of_one_value_is_missing() {
        assert_eq!(mean_sd(&[3.0], MISS, true).unwrap(), (3.0, MISS));
        assert_eq!(mean_sd(&[3.0], MISS, false).unwrap(), (3.0, MISS));
        assert_eq!(mean_sd(&[MISS], MISS, true).unwrap(), (MISS, MISS));
        let (m, s) = mean_sd(&[1.0, 2.0, 3.0, 4.0], MISS, false).unwrap();
        assert_eq!(m, 2.5);
        assert_eq!(s, (5.0f64 / 3.0).sqrt());
    }
}
