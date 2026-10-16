//! Test support shared by the kernel tests: a deterministic RNG and Stata missing codes.

use crate::io::MISS;

/// Extended missing value `.a` (Stata stores it just above `.`).
pub fn miss_a() -> f64 {
    MISS * (1.0 + 2f64.powi(-12))
}

/// A NaN as a plugin or Mata's `st_store()` can leave in a Stata variable (dataverse-A9ZFFF held
/// this one: sign bit set, a payload).
pub fn stata_nan() -> f64 {
    f64::from_bits(0xfffe_53f8_0000_0000)
}

pub struct Rng(u64);

impl Rng {
    pub fn new(seed: u64) -> Rng {
        Rng(seed)
    }

    pub fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        z ^ (z >> 31)
    }

    /// Uniform on [0, 1).
    pub fn unif(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 / (1u64 << 53) as f64
    }
}
