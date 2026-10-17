//! Errors handed back to Stata: a return code plus a one-line message.
//!
//! [`Error::fallback`] is not an error for the user: a compute phase uses it when the input needs
//! the original command. `stata_call` turns it into the local `fx_fallback` (the reason) and
//! return code 0, and the ado runs the original. Compute phases never write data, so a fallback
//! can be raised anywhere in them.

use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Error {
    pub rc: i32,
    pub msg: String,
}

pub type Res<T> = Result<T, Error>;

/// Return code of [`Error::fallback`]; never handed to Stata.
pub const FALLBACK_RC: i32 = -1;

impl Error {
    pub fn new(rc: i32, msg: impl Into<String>) -> Self {
        Self { rc, msg: msg.into() }
    }

    /// r(198): a malformed plugin call (an ado/plugin mismatch, never user input) or bad data.
    pub fn syntax(msg: impl Into<String>) -> Self {
        Self::new(198, msg)
    }

    pub fn oom() -> Self {
        Self::new(909, "fastata: out of memory")
    }

    pub fn spi(rc: i32, what: &str) -> Self {
        Self::new(rc, format!("fastata: Stata returned r({rc}) while {what}"))
    }

    /// The input needs the original command; `reason` is recorded by `fastata status`.
    pub fn fallback(reason: impl Into<String>) -> Self {
        Self::new(FALLBACK_RC, reason)
    }

    pub fn is_fallback(&self) -> bool {
        self.rc == FALLBACK_RC
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.msg)
    }
}

/// `len` copies of `v`, or r(909) when the allocation fails.
pub fn vec_filled<T: Clone>(len: usize, v: T) -> Res<Vec<T>> {
    let mut out = Vec::new();
    out.try_reserve_exact(len).map_err(|_| Error::oom())?;
    out.resize(len, v);
    Ok(out)
}

/// An empty vector with room for `cap` elements, or r(909).
pub fn vec_with_capacity<T>(cap: usize) -> Res<Vec<T>> {
    let mut out = Vec::new();
    out.try_reserve_exact(cap).map_err(|_| Error::oom())?;
    Ok(out)
}

/// Element types whose all-zero bit pattern is a valid value (`0`, `0.0`, `false`).
///
/// # Safety
/// Implement only for types where every zero byte pattern is a valid value.
pub unsafe trait Zeroable: Copy {}
unsafe impl Zeroable for f64 {}
unsafe impl Zeroable for u8 {}
unsafe impl Zeroable for u32 {}
unsafe impl Zeroable for u64 {}
unsafe impl Zeroable for usize {}
unsafe impl Zeroable for bool {}
// SAFETY: a tuple of zeroable fields is all zero bytes (padding included) when its fields are.
unsafe impl<A: Zeroable, B: Zeroable> Zeroable for (A, B) {}

/// `len` zeros, or r(909). Unlike [`vec_filled`] nothing is written here: the allocator hands
/// out zeroed memory (fresh pages for large sizes), so a column is first touched by the worker
/// threads that fill it, in parallel.
pub fn vec_zeroed<T: Zeroable>(len: usize) -> Res<Vec<T>> {
    if len == 0 || size_of::<T>() == 0 {
        return Ok(Vec::new());
    }
    let layout = std::alloc::Layout::array::<T>(len).map_err(|_| Error::oom())?;
    // SAFETY: the layout has a nonzero size; all-zero bytes are a valid T (Zeroable), and the
    // allocation has exactly the layout of a Vec<T> with capacity len.
    unsafe {
        let p = std::alloc::alloc_zeroed(layout).cast::<T>();
        if p.is_null() {
            return Err(Error::oom());
        }
        Ok(Vec::from_raw_parts(p, len, len))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zeroed_vectors_are_zero_and_huge_ones_are_out_of_memory() {
        let v: Vec<f64> = vec_zeroed(100_000).unwrap();
        assert!(v.len() == 100_000 && v.iter().all(|x| x.to_bits() == 0));
        assert!(vec_zeroed::<u32>(0).unwrap().is_empty());
        assert_eq!(vec_zeroed::<f64>(usize::MAX / 4).unwrap_err().rc, 909);
        assert_eq!(vec_with_capacity::<u64>(usize::MAX / 4).unwrap_err().rc, 909);
    }
}
