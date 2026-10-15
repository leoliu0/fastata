//! Row functions, one observation at a time, exactly as the `_grow<fcn>.ado` statements run:
//! a `gen <type>` followed by one `replace` per further variable, each storing (so rounding to
//! the storage type, [`Ty::cast`]) its result. Values are raw; for string variables (rowmiss,
//! rownonmiss) only missingness matters, so the caller passes `.` for "" and 0 otherwise.

use super::spec::{Fcn, Ty, arith};
use crate::error::Res;

#[inline]
fn zero_if_miss(v: f64, miss: f64) -> f64 {
    if v >= miss { 0.0 } else { v }
}

/// Stata's `a + b`: missing if either is missing.
#[inline]
fn add(a: f64, b: f64, miss: f64) -> f64 {
    if a >= miss || b >= miss { miss } else { arith(a + b, miss) }
}

/// The function's value for one sample observation with values `v` (varlist order).
pub fn row(fcn: Fcn, v: &[f64], ty: Ty, missing: bool, miss: f64) -> Res<f64> {
    let c = |x: f64| ty.cast(x, miss);
    let flag = |b: bool| if b { 1.0 } else { 0.0 };
    match fcn {
        Fcn::RowTotal if !missing => {
            // gen g = cond(v1>=.,0,v1); replace g = g + cond(vk>=.,0,vk)
            let mut g = c(zero_if_miss(v[0], miss))?;
            for &x in &v[1..] {
                g = c(add(g, zero_if_miss(x, miss), miss))?;
            }
            Ok(g)
        }
        Fcn::RowTotal => {
            // gen g = cond(v1>=.,.,v1)
            // replace g = cond(g==., cond(vk>=.,.,vk), cond(vk>=., g, g + vk))
            let mut g = c(if v[0] >= miss { miss } else { v[0] })?;
            for &x in &v[1..] {
                let y = if g == miss {
                    if x >= miss { miss } else { x }
                } else if x >= miss {
                    g
                } else {
                    add(g, x, miss)
                };
                g = c(y)?;
            }
            Ok(g)
        }
        Fcn::RowMean => {
            // double g = sum of cond(v>=.,0,v); long NOBS = sum of (v<.); gen h = g/NOBS
            let mut g = 0.0;
            let mut n = 0u64;
            for &x in v {
                g = add(g, zero_if_miss(x, miss), miss);
                n += u64::from(x < miss);
            }
            c(if g >= miss { miss } else { arith(g / n as f64, miss) })
        }
        Fcn::RowMax => {
            // gen g = v1; replace g = cond(g>=. | (vk>g & vk<.), vk, g)
            let mut g = c(v[0])?;
            for &x in &v[1..] {
                g = c(if g >= miss || (x > g && x < miss) { x } else { g })?;
            }
            Ok(g)
        }
        Fcn::RowMin => {
            // gen g = .; replace g = cond(vk < g, vk, g)
            let mut g = c(miss)?;
            for &x in v {
                g = c(if x < g { x } else { g })?;
            }
            Ok(g)
        }
        Fcn::RowSd => {
            // MU = (sum of cond(v>=.,0,v)) / NOBS; g = sum of cond(v>=.,0,v−MU)^2;
            // cond(NOBS==0, ., sqrt(g/(NOBS−1)))
            let mut mu = 0.0;
            let mut n = 0u64;
            for &x in v {
                mu = add(mu, zero_if_miss(x, miss), miss);
                n += u64::from(x < miss);
            }
            let mu = if mu >= miss { miss } else { arith(mu / n as f64, miss) };
            let mut g = 0.0;
            for &x in v {
                let d = if x >= miss {
                    0.0
                } else if mu >= miss {
                    miss
                } else {
                    arith(x - mu, miss)
                };
                let sq = if d >= miss { miss } else { arith(d * d, miss) };
                g = add(g, sq, miss);
            }
            c(if n == 0 || g >= miss { miss } else { arith((g / (n - 1) as f64).sqrt(), miss) })
        }
        Fcn::RowMiss => {
            let mut g = c(flag(v[0] >= miss))?;
            for &x in &v[1..] {
                g = c(add(g, flag(x >= miss), miss))?;
            }
            Ok(g)
        }
        Fcn::RowNonmiss => {
            let mut g = c(flag(v[0] < miss))?;
            for &x in &v[1..] {
                g = c(add(g, flag(x < miss), miss))?;
            }
            Ok(g)
        }
        _ => unreachable!("not a row function"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::MISS;
    use crate::testutil::miss_a;

    fn r(f: Fcn, v: &[f64], ty: Ty, m: bool) -> f64 {
        row(f, v, ty, m, MISS).unwrap()
    }

    #[test]
    fn rowtotal_rounds_after_every_step() {
        let v = [0.1, 0.2, MISS, 0.3];
        let mut want = f64::from(0.1f32);
        want = f64::from((want + 0.2) as f32);
        want = f64::from((want + 0.0) as f32);
        want = f64::from((want + 0.3) as f32);
        assert_eq!(r(Fcn::RowTotal, &v, Ty::Float, false), want);
        assert_eq!(r(Fcn::RowTotal, &[MISS, miss_a()], Ty::Double, false), 0.0);
        assert_eq!(r(Fcn::RowTotal, &[MISS, miss_a()], Ty::Double, true), MISS);
        assert_eq!(r(Fcn::RowTotal, &[MISS, 2.0, MISS, 3.0], Ty::Double, true), 5.0);
    }

    #[test]
    fn rowmax_keeps_the_last_missing_code_and_rowmin_gives_dot() {
        assert_eq!(r(Fcn::RowMax, &[MISS, miss_a()], Ty::Float, false), miss_a());
        assert_eq!(r(Fcn::RowMax, &[miss_a(), 1.0, MISS], Ty::Double, false), 1.0);
        assert_eq!(r(Fcn::RowMin, &[miss_a(), MISS], Ty::Double, false), MISS);
        assert_eq!(r(Fcn::RowMin, &[miss_a(), 4.0, -2.0], Ty::Double, false), -2.0);
    }

    #[test]
    fn rowmean_rowsd_counts() {
        assert_eq!(r(Fcn::RowMean, &[1.0, MISS, 2.0], Ty::Double, false), 1.5);
        assert_eq!(r(Fcn::RowMean, &[MISS, MISS], Ty::Double, false), MISS);
        assert_eq!(r(Fcn::RowSd, &[1.0, MISS], Ty::Double, false), MISS);
        assert_eq!(r(Fcn::RowSd, &[1.0, 3.0], Ty::Double, false), 2f64.sqrt());
        assert_eq!(r(Fcn::RowMiss, &[1.0, MISS, miss_a()], Ty::Byte, false), 2.0);
        assert_eq!(r(Fcn::RowNonmiss, &[1.0, MISS, miss_a()], Ty::Byte, false), 1.0);
        assert!(row(Fcn::RowTotal, &[200.0], Ty::Byte, false, MISS).unwrap_err().is_fallback());
    }
}
