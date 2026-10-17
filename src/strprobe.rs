//! `strprobe`: parallel string-read probe (`tests/stata/stress_strread.do`). Reads every value of
//! the string variables of the varlist, in blocks of 8192 observations through [`for_blocks`]
//! with `threads` workers, and returns an FNV-1a checksum of the values in observation order.
//! Correct reads give the same checksum for every thread count.
//!
//! Varlist: string variables (str# or strL). Key `threads` (0 = every logical CPU). Locals:
//! `fx_chk` (the checksum, 16 hex digits) and `fx_n` (values read).
//!
//! Not in the shipped plugin (parallel string reads crashed Stata, see [`crate::io`]): it is built
//! only with the cargo feature `probes`, in release mode (a debug build asserts that string reads
//! stay on Stata's thread).

use crate::args::Args;
use crate::error::{Error, Res};
use crate::io::{self, Io};
use crate::par::{StoreMode, for_blocks};

const BLOCK: usize = 8192;
const FNV_OFFSET: u64 = 0xcbf2_9ce4_8422_2325;
const FNV_PRIME: u64 = 0x0000_0100_0000_01b3;

fn fnv(mut h: u64, bytes: &[u8]) -> u64 {
    for &b in bytes {
        h ^= u64::from(b);
        h = h.wrapping_mul(FNV_PRIME);
    }
    h
}

/// Checksum of the values of string variables `1..=k` over all observations: each block hashes
/// its values (length, then bytes) in observation-then-variable order, and the block hashes are
/// combined in block order.
pub fn checksum<I: Io>(io: &I, k: usize, threads: usize) -> Res<u64> {
    let n = io.nobs();
    let blocks = for_blocks(io, n.div_ceil(BLOCK), threads, StoreMode::Parallel, |b, _emit| {
        let first = b * BLOCK;
        let mut h = FNV_OFFSET;
        let mut buf = Vec::new();
        for obs in first..n.min(first + BLOCK) {
            for v in 1..=k as i32 {
                buf.clear();
                io.read_str(v, obs, &mut buf)?;
                h = fnv(h, &(buf.len() as u64).to_le_bytes());
                h = fnv(h, &buf);
            }
        }
        Ok(h)
    })?;
    Ok(blocks.iter().fold(FNV_OFFSET, |h, b| fnv(h, &b.to_le_bytes())))
}

pub fn run<I: Io>(io: &I, a: &Args) -> Res<()> {
    a.only(&["threads"])?;
    let threads = a.usize_or("threads", 0)?;
    let k = io.nvars();
    if k == 0 || !(1..=k as i32).all(|v| io.is_str(v)) {
        return Err(Error::syntax("fastata plugin: strprobe needs string variables"));
    }
    let h = checksum(io, k, threads)?;
    io::local_save("fx_chk", &format!("{h:016x}"))?;
    io::local_save("fx_n", &(io.nobs() * k).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::MemIo;
    use crate::testutil::Rng;

    #[test]
    fn checksum_is_the_same_for_every_thread_count_and_sees_every_value() {
        let n = 3 * BLOCK + 17;
        let mut rng = Rng::new(7);
        let mut io = MemIo::new(n);
        io.any_thread = true;
        let a: Vec<Vec<u8>> = (0..n).map(|i| format!("s{}", (rng.unif() * 1e6) as u64 + i as u64).into_bytes()).collect();
        let b: Vec<Vec<u8>> = (0..n).map(|i| if i % 5 == 0 { Vec::new() } else { vec![b'x'; i % 40] }).collect();
        let ca = io.add_str(a.clone());
        let cb = io.add_str(b.clone());
        io.push_var(ca);
        io.push_var(cb);
        let one = checksum(&io, 2, 1).unwrap();
        for t in [2, 4, 7] {
            assert_eq!(checksum(&io, 2, t).unwrap(), one, "threads={t}");
        }
        // one changed byte, or two values swapped across variables, change the checksum
        let mut io2 = MemIo::new(n);
        io2.any_thread = true;
        let mut a2 = a.clone();
        a2[n - 1][0] = b't';
        let c2a = io2.add_str(a2);
        let c2b = io2.add_str(b.clone());
        io2.push_var(c2a);
        io2.push_var(c2b);
        assert_ne!(checksum(&io2, 2, 4).unwrap(), one);
        let mut io3 = MemIo::new(n);
        io3.any_thread = true;
        let c3a = io3.add_str(b);
        let c3b = io3.add_str(a);
        io3.push_var(c3a);
        io3.push_var(c3b);
        assert_ne!(checksum(&io3, 2, 4).unwrap(), one);
    }
}
