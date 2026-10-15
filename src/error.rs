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
