//! NaN values in numeric inputs. Stata never makes a NaN, but a plugin or Mata's `st_store()` can
//! store one in a variable. Stata then treats it as a missing value in expressions, `marksample`
//! and summaries (in an expression it becomes `.`), its `sort` never returns on a NaN key, and
//! `string()` shows it as `-`. The kernels follow Stata's missing-value rule `v >= missval`, under
//! which a NaN is a number. So every fast path falls back with reason [`REASON`] when a numeric
//! variable it reads holds a NaN, and the original then does what it does. A NaN in a variable
//! the call does not read changes nothing. Each read checks what it reads (key variables are
//! checked over every observation by the grouping reads in `crate::group`).

use crate::error::{Error, Res};

/// The fallback reason.
pub const REASON: &str = "NaN value";

/// The fallback for a NaN input.
pub fn fallback() -> Error {
    Error::fallback(REASON)
}

/// Falls back when `vals` holds a NaN.
pub fn check(vals: &[f64]) -> Res<()> {
    if vals.iter().any(|v| v.is_nan()) { Err(fallback()) } else { Ok(()) }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::stata_nan;

    #[test]
    fn finds_a_nan_and_nothing_else() {
        assert!(check(&[1.0, stata_nan(), 2.0]).unwrap_err().is_fallback());
        assert!(check(&[f64::NAN]).is_err());
        check(&[1.0, f64::INFINITY, 8.98846567431158e307]).unwrap();
    }
}
