//! NaN values in numeric inputs. Stata never makes a NaN, but a plugin or Mata's `st_store()` can
//! store one in a variable. Stata then treats it as a missing value in expressions, `marksample`
//! and summaries (in an expression it becomes `.`), its `sort` never returns on a NaN key, and
//! `string()` shows it as `-`. The kernels follow Stata's missing-value rule `v >= missval`, under
//! which a NaN is a number. So every fast path falls back with reason [`REASON`] when a numeric
//! variable it reads holds a NaN, and the original then does what it does. A NaN in a variable
//! the call does not read changes nothing.

use crate::error::{Error, Res, vec_filled};
use crate::io::{Io, Rows};
use crate::par::{StoreMode, for_blocks};

/// The fallback reason.
pub const REASON: &str = "NaN value";

/// Observations per work item of [`check_vars`].
const BLOCK: usize = 8192;

/// The fallback for a NaN input.
pub fn fallback() -> Error {
    Error::fallback(REASON)
}

/// Falls back when `vals` holds a NaN.
pub fn check(vals: &[f64]) -> Res<()> {
    if vals.iter().any(|v| v.is_nan()) { Err(fallback()) } else { Ok(()) }
}

/// Falls back when a numeric variable of `vars` (string variables are skipped) holds a NaN in any
/// observation. Reads in parallel blocks; for inputs a caller does not read in full anyway.
pub fn check_vars<I: Io>(io: &I, vars: &[i32], threads: usize) -> Res<()> {
    let num: Vec<i32> = vars.iter().copied().filter(|&v| !io.is_str(v)).collect();
    let n = io.nobs();
    if num.is_empty() || n == 0 {
        return Ok(());
    }
    let k = num.len();
    let bad = for_blocks(io, n.div_ceil(BLOCK), threads, StoreMode::Parallel, |b, _emit| {
        let first = b * BLOCK;
        let m = BLOCK.min(n - first);
        let mut raw = vec_filled(m * k, 0.0)?;
        io.read_block(&num, Rows::Range { first, n: m }, &mut raw)?;
        Ok(raw.iter().any(|v| v.is_nan()))
    })?;
    if bad.into_iter().any(|b| b) { Err(fallback()) } else { Ok(()) }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::MemIo;
    use crate::testutil::stata_nan;

    #[test]
    fn finds_a_nan_in_any_block_and_skips_strings() {
        let n = 3 * BLOCK + 5;
        for at in [0, BLOCK - 1, BLOCK, n - 1] {
            let mut io = MemIo::new(n);
            let mut x = vec![1.0; n];
            x[at] = stata_nan();
            let cx = io.add_num(&x);
            let cy = io.add_num(&vec![2.0; n]);
            let cs = io.add_str(vec![b"a".to_vec(); n]);
            let (px, py, ps) = (io.push_var(cx), io.push_var(cy), io.push_var(cs));
            for threads in [1, 4] {
                let e = check_vars(&io, &[ps, px], threads).unwrap_err();
                assert!(e.is_fallback() && e.msg == REASON);
                check_vars(&io, &[py, ps], threads).unwrap();
            }
            assert!(check(&x).is_err());
        }
        check(&[1.0, f64::INFINITY, 8.98846567431158e307]).unwrap();
    }
}
