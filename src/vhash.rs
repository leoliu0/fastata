//! `vhash`: one 64-bit hash per variable, for verify mode (`_fx verify` in `_fx.ado`). Verify
//! hashes every variable of the fast path's frame and of the frame the original ran in; a
//! variable with equal hashes is bitwise equal (up to a 2^-64 chance), every other one goes to
//! the detailed comparison in Mata.
//!
//! A numeric variable hashes the raw bits of its values as `SF_vdata` gives them (missing codes,
//! the sign of zero and NaN payloads included), in parallel blocks combined in block order, so
//! the hash is the same for every thread count. Each step of [`mix`] is a bijection of the
//! state, so two variables that differ in a single value always get different hashes. String
//! variables are not hashed: the plugin reads strings one value at a time on Stata's thread
//! (parallel string reads are unsafe, see [`crate::io`]), slower than Mata's `st_sdata()`, so
//! the caller compares them itself.
//!
//! Varlist: the variables to hash (verify passes `_all`). Key `threads` (0 = every logical CPU).
//! Local `fx_vh`: one token per variable, in varlist order: 16 hex digits for a numeric variable,
//! followed by `n` when the variable holds a NaN (Stata expressions read a NaN as `.`, so the
//! caller then compares in Mata), and `-` for a string variable.

use crate::args::Args;
use crate::error::{Res, vec_filled, vec_with_capacity};
use crate::io::{self, Io, Rows};
use crate::par::{StoreMode, for_blocks, threads_for_rows};

/// Values read per work item: a block of observations by every numeric variable. Stata stores
/// the data observation by observation, so reading whole rows walks memory in order; a block of
/// one variable would stride across every row.
const ITEM_VALUES: usize = 1 << 18;
const K: u64 = 0x9e37_79b9_7f4a_7c15;
const SEED: u64 = 0x2545_f491_4f6c_dd1d;

/// One step: for a fixed `x` a bijection of `h`, for a fixed `h` a bijection of `x`.
fn mix(h: u64, x: u64) -> u64 {
    (h.rotate_left(5) ^ x).wrapping_mul(K)
}

/// The hash of a variable and whether it holds a NaN.
pub type Hash = (u64, bool);

/// Observations per block for `k` numeric variables (depends on `k` only, so the hashes do not
/// depend on the thread count).
fn block_rows(k: usize) -> usize {
    (ITEM_VALUES / k.max(1)).clamp(256, 1 << 15)
}

/// Per variable of `vars`, the hash of observations `first..first + n` and whether they hold a
/// NaN.
fn num_block<I: Io>(io: &I, vars: &[i32], first: usize, n: usize) -> Res<Vec<Hash>> {
    let k = vars.len();
    let mut buf = vec_filled(n * k, 0.0)?;
    io.read_block(vars, Rows::Range { first, n }, &mut buf)?;
    let mut out = vec_filled(k, (SEED, false))?;
    for row in buf.chunks_exact(k) {
        for (o, v) in out.iter_mut().zip(row) {
            o.0 = mix(o.0, v.to_bits());
            o.1 |= v.is_nan();
        }
    }
    Ok(out)
}

/// The hash of every variable `1..=nvars` (`None` for a string variable).
pub fn hashes<I: Io>(io: &I, threads: usize) -> Res<Vec<Option<Hash>>> {
    let k = io.nvars();
    let n = io.nobs();
    let num: Vec<i32> = (1..=k as i32).filter(|&v| !io.is_str(v)).collect();
    let rows = block_rows(num.len());
    let nb = if num.is_empty() { 0 } else { n.div_ceil(rows).max(1) };
    let blocks = for_blocks(io, nb, threads_for_rows(threads, n.saturating_mul(num.len())), StoreMode::Parallel, |b, _emit| {
        let first = b * rows;
        num_block(io, &num, first, rows.min(n - first.min(n)))
    })?;
    let mut out = vec_with_capacity(k)?;
    let mut j = 0;
    for v in 1..=k as i32 {
        if io.is_str(v) {
            out.push(None);
        } else {
            let h = blocks.iter().fold((SEED, false), |h, b| (mix(h.0, b[j].0), h.1 | b[j].1));
            out.push(Some(h));
            j += 1;
        }
    }
    Ok(out)
}

pub fn run<I: Io>(io: &I, a: &Args) -> Res<()> {
    a.only(&["threads"])?;
    let threads = a.usize_or("threads", 0)?;
    let hs = hashes(io, threads)?;
    let toks: Vec<String> = hs
        .iter()
        .map(|h| h.map_or_else(|| "-".to_string(), |(h, nan)| format!("{h:016x}{}", if nan { "n" } else { "" })))
        .collect();
    io::local_save("fx_vh", &toks.join(" "))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::MemIo;
    use crate::testutil::{Rng, stata_nan};

    fn frame(x: &[Vec<f64>], s: &[Vec<Vec<u8>>]) -> MemIo {
        let n = x.first().map_or_else(|| s[0].len(), Vec::len);
        let mut io = MemIo::new(n);
        for c in x {
            let i = io.add_num(c);
            io.push_var(i);
        }
        for c in s {
            let i = io.add_str(c.clone());
            io.push_var(i);
        }
        io
    }

    fn data(n: usize) -> (Vec<Vec<f64>>, Vec<Vec<Vec<u8>>>) {
        let mut rng = Rng::new(3);
        let x = (0..3).map(|_| (0..n).map(|_| rng.unif() * 100.0).collect()).collect();
        let s = vec![(0..n).map(|i| format!("v{}", i % 17).into_bytes()).collect()];
        (x, s)
    }

    #[test]
    fn same_for_every_thread_count() {
        for n in [0, 1, 255, 256, 257, 3 * 8192 + 5, (1 << 15) + 1] {
            let (x, s) = data(n);
            let io = frame(&x, &s);
            let one = hashes(&io, 1).unwrap();
            assert_eq!(one.len(), 4);
            for t in [2, 5] {
                assert_eq!(hashes(&io, t).unwrap(), one, "n={n} threads={t}");
            }
        }
    }

    #[test]
    fn a_single_changed_value_changes_only_its_variable() {
        let n = 2 * (1 << 15) + 3;
        let blk = block_rows(3);
        let (x, s) = data(n);
        let base = hashes(&frame(&x, &s), 4).unwrap();
        let other = f64::from_bits(stata_nan().to_bits() ^ 1);
        for at in [0, blk - 1, blk, n - 1] {
            for v in [-0.0, 0.0, stata_nan(), other, 8.98846567431158e307, x[1][at] + 1e-12] {
                let mut y = x.clone();
                if y[1][at].to_bits() == v.to_bits() {
                    continue;
                }
                y[1][at] = v;
                let h = hashes(&frame(&y, &s), 4).unwrap();
                assert_eq!(h[0], base[0]);
                assert_ne!(h[1], base[1], "at={at} v={v:?}");
                assert_eq!(h[2], base[2]);
                assert_eq!(h[3], base[3]);
            }
        }
        // -0 against +0 and two NaN payloads
        let mut a = x.clone();
        let mut b = x.clone();
        a[0][5] = 0.0;
        b[0][5] = -0.0;
        assert_ne!(hashes(&frame(&a, &s), 2).unwrap()[0], hashes(&frame(&b, &s), 2).unwrap()[0]);
        a[0][5] = stata_nan();
        b[0][5] = other;
        let (ha, hb) = (hashes(&frame(&a, &s), 2).unwrap()[0].unwrap(), hashes(&frame(&b, &s), 2).unwrap()[0].unwrap());
        assert_ne!(ha.0, hb.0);
        assert!(ha.1 && hb.1, "NaN flags");
    }

    #[test]
    fn wide_frames_hash_by_row_blocks() {
        // 1200 numeric variables: blocks of 256 observations
        let n = 3 * 256 + 7;
        let mut rng = Rng::new(5);
        let x: Vec<Vec<f64>> = (0..1200).map(|_| (0..n).map(|_| rng.unif()).collect()).collect();
        let s = vec![(0..n).map(|i| format!("s{i}").into_bytes()).collect()];
        let base = hashes(&frame(&x, &s), 1).unwrap();
        for t in [3, 8] {
            assert_eq!(hashes(&frame(&x, &s), t).unwrap(), base, "threads={t}");
        }
        let mut y = x.clone();
        y[700][300] += 1.0;
        let h = hashes(&frame(&y, &s), 4).unwrap();
        for (j, (a, b)) in h.iter().zip(&base).enumerate() {
            assert_eq!(a == b, j != 700, "variable {j}");
        }
    }

    #[test]
    fn string_variables_are_left_to_the_caller() {
        let (x, s) = data(10);
        let h = hashes(&frame(&x, &s), 3).unwrap();
        assert!(h[..3].iter().all(|x| x.is_some_and(|(_, nan)| !nan)));
        assert_eq!(h[3], None);
    }
}
