//! Data access. [`Io`] abstracts Stata's dataset: [`SpiIo`] reaches it through `c/glue.c`, and
//! `MemIo` (unit tests) is an in-memory dataset. Variables are 1-based varlist positions (the
//! Stata convention); observations are 0-based.
//!
//! `read_block` and `write_block` may run concurrently on disjoint observations; every other
//! method runs on the calling (Stata) thread only. String reads stay there because parallel
//! ones are unsafe: `tests/stata/stress_strread.do` crashed StataNow 19.5 MP (Linux) with
//! "double free or corruption" on its first 32-thread `strprobe` call over 2e7 str20/strL
//! values. Both implementations check it: [`SpiIo`] in debug builds, `MemIo` (unit tests)
//! always.

use std::ffi::{CStr, CString, c_char, c_int, c_uint, c_void};
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::{Mutex, PoisonError};
use std::thread::ThreadId;

use crate::error::{Error, Res, vec_with_capacity};

/// Observations of one block: a contiguous range or an explicit (0-based) list.
#[derive(Clone, Copy)]
pub enum Rows<'a> {
    Range { first: usize, n: usize },
    List(&'a [u32]),
}

impl Rows<'_> {
    pub fn len(&self) -> usize {
        match self {
            Rows::Range { n, .. } => *n,
            Rows::List(l) => l.len(),
        }
    }

    /// The 0-based observation of row `r`.
    #[cfg(test)]
    pub fn obs(&self, r: usize) -> usize {
        match self {
            Rows::Range { first, .. } => first + r,
            Rows::List(l) => l[r] as usize,
        }
    }
}

/// Stata missing value test on a raw value: `.` and `.a`-`.z` are all `>= missval`.
#[inline]
pub fn is_miss(v: f64, miss: f64) -> bool {
    v >= miss
}

pub trait Io: Sync {
    /// Observations in the dataset.
    fn nobs(&self) -> usize;
    /// Variables in the `plugin call` varlist.
    fn nvars(&self) -> usize;
    /// Stata's system missing value; every missing value (`.`, `.a`-`.z`) is `>=` it.
    fn missval(&self) -> f64;
    /// Raw values, row-major: `out[r * vars.len() + j]` = `vars[j]` at row `r`.
    fn read_block(&self, vars: &[i32], rows: Rows<'_>, out: &mut [f64]) -> Res<()>;
    /// Writes `vals` (row-major as in `read_block`); non-finite values become missing (`.`);
    /// `skip[r * vars.len() + j] != 0` leaves that cell untouched.
    fn write_block(&self, vars: &[i32], rows: Rows<'_>, vals: &[f64], skip: Option<&[u8]>) -> Res<()>;
    /// Calling (Stata) thread only.
    fn is_str(&self, var: i32) -> bool;
    /// Appends the bytes of string variable `var` at `obs` to `out`, growing it fallibly
    /// (r(909)). A binary strL value is a fallback (`binary strL`). Calling (Stata) thread only.
    fn read_str(&self, var: i32, obs: usize, out: &mut Vec<u8>) -> Res<()>;
    /// Stores `s` into string variable `var` at `obs`. Calling (Stata) thread only.
    fn write_str(&self, var: i32, obs: usize, s: &CStr) -> Res<()>;
}

unsafe extern "C" {
    fn fx_set_plugin(p: *mut c_void);
    fn fx_nobs() -> c_int;
    fn fx_nvars() -> c_int;
    fn fx_missval() -> f64;
    fn fx_read_block(vars: *const c_int, nv: c_int, obs: *const c_uint, first: c_int, n: c_int, out: *mut f64) -> c_int;
    fn fx_write_block(
        vars: *const c_int,
        nv: c_int,
        obs: *const c_uint,
        first: c_int,
        n: c_int,
        vals: *const f64,
        skip: *const u8,
    ) -> c_int;
    fn fx_is_str(var: c_int) -> c_int;
    fn fx_is_strl(var: c_int) -> c_int;
    fn fx_read_str(var: c_int, obs: c_int, buf: *mut c_char) -> c_int;
    fn fx_strl_len(var: c_int, obs: c_int) -> c_int;
    fn fx_read_strl(var: c_int, obs: c_int, buf: *mut c_char, cap: c_int) -> c_int;
    fn fx_write_str(var: c_int, obs: c_int, s: *const c_char) -> c_int;
    fn fx_macro_save(name: *const c_char, value: *const c_char) -> c_int;
    fn fx_error(s: *const c_char);
}

/// Buffer size for `str#` values (str2045 + terminator).
const STR_BUF: usize = 2046;

fn cstr(s: &str) -> CString {
    CString::new(s.replace('\0', " ")).expect("no interior NUL")
}

/// Stores the plugin table handed to `pginit`.
///
/// # Safety
/// `p` must be the `ST_plugin*` Stata passes to `pginit`.
pub unsafe fn set_plugin(p: *mut c_void) {
    unsafe { fx_set_plugin(p) }
}

/// Names of the locals set during the current `plugin call` (see [`saved_locals`]).
static SAVED: Mutex<Vec<String>> = Mutex::new(Vec::new());

/// Sets local macro `name` in the program that ran `plugin call`.
pub fn local_save(name: &str, value: &str) -> Res<()> {
    let n = cstr(&format!("_{name}"));
    let v = cstr(value);
    let rc = unsafe { fx_macro_save(n.as_ptr(), v.as_ptr()) };
    if rc != 0 {
        return Err(Error::spi(rc, &format!("saving local {name}")));
    }
    let mut s = SAVED.lock().unwrap_or_else(PoisonError::into_inner);
    if !s.iter().any(|x| x == name) {
        s.push(name.to_string());
    }
    Ok(())
}

/// Takes the names of the locals [`local_save`] set since the last call, so that `stata_call`
/// can list them in local `fx_locals` (`_fx_call.ado` copies exactly those to its caller).
pub fn saved_locals() -> Vec<String> {
    std::mem::take(&mut *SAVED.lock().unwrap_or_else(PoisonError::into_inner))
}

/// Prints an error message (red) in the Results window.
pub fn error(s: &str) {
    let c = cstr(s);
    unsafe { fx_error(c.as_ptr()) };
}

/// Fallback reason for a dataset larger than the SPI's `int` observation count.
pub const TOO_MANY_OBS: &str = "over 2147483647 observations";

/// Storage kinds cached per variable by [`SpiIo`]; 0 = not looked up yet.
const KIND_NUM: u8 = 1;
const KIND_STR: u8 = 2;
const KIND_STRL: u8 = 3;

/// Stata's dataset, through the SPI.
pub struct SpiIo {
    nobs: usize,
    nvars: usize,
    missval: f64,
    /// The storage kind of each varlist position, looked up on first use.
    kinds: Vec<AtomicU8>,
    /// Stata's thread (the one that created this handle), for the string-call checks.
    owner: ThreadId,
}

impl SpiIo {
    /// The dataset of the current `plugin call`. SPI 3.0 counts observations in a C `int`, so a
    /// negative count means more than 2^31-1 observations: the fallback [`TOO_MANY_OBS`]. (Counts
    /// of 2^32 and more wrap to small positive numbers; `_fx_call.ado` falls back before the
    /// plugin is called for those.)
    pub fn new() -> Res<SpiIo> {
        let (nobs, nvars, missval) = unsafe { (fx_nobs(), fx_nvars(), fx_missval()) };
        if nobs < 0 {
            return Err(Error::fallback(TOO_MANY_OBS));
        }
        let nvars = nvars.max(0) as usize;
        let mut kinds = vec_with_capacity(nvars)?;
        kinds.extend((0..nvars).map(|_| AtomicU8::new(0)));
        Ok(SpiIo { nobs: nobs as usize, nvars, missval, kinds, owner: std::thread::current().id() })
    }

    fn check_thread(&self) {
        debug_assert_eq!(std::thread::current().id(), self.owner, "fastata: a string SPI call off Stata's thread");
    }

    fn kind(&self, var: i32) -> u8 {
        let lookup = || unsafe {
            if fx_is_str(var) == 0 {
                KIND_NUM
            } else if fx_is_strl(var) != 0 {
                KIND_STRL
            } else {
                KIND_STR
            }
        };
        let Some(slot) = usize::try_from(var - 1).ok().and_then(|i| self.kinds.get(i)) else { return lookup() };
        match slot.load(Ordering::Relaxed) {
            0 => {
                let k = lookup();
                slot.store(k, Ordering::Relaxed);
                k
            }
            k => k,
        }
    }
}

fn split_rows(rows: Rows<'_>) -> (*const c_uint, c_int, c_int) {
    match rows {
        Rows::Range { first, n } => (std::ptr::null(), first as c_int, n as c_int),
        Rows::List(l) => (l.as_ptr(), 0, l.len() as c_int),
    }
}

impl Io for SpiIo {
    fn nobs(&self) -> usize {
        self.nobs
    }

    fn nvars(&self) -> usize {
        self.nvars
    }

    fn missval(&self) -> f64 {
        self.missval
    }

    fn read_block(&self, vars: &[i32], rows: Rows<'_>, out: &mut [f64]) -> Res<()> {
        assert_eq!(out.len(), rows.len() * vars.len());
        let (obs, first, n) = split_rows(rows);
        let rc = unsafe { fx_read_block(vars.as_ptr(), vars.len() as c_int, obs, first, n, out.as_mut_ptr()) };
        if rc != 0 { Err(Error::spi(rc, "reading variables")) } else { Ok(()) }
    }

    fn write_block(&self, vars: &[i32], rows: Rows<'_>, vals: &[f64], skip: Option<&[u8]>) -> Res<()> {
        assert_eq!(vals.len(), rows.len() * vars.len());
        if let Some(s) = skip {
            assert_eq!(s.len(), vals.len());
        }
        let (obs, first, n) = split_rows(rows);
        let skip = skip.map_or(std::ptr::null(), <[u8]>::as_ptr);
        let rc = unsafe { fx_write_block(vars.as_ptr(), vars.len() as c_int, obs, first, n, vals.as_ptr(), skip) };
        if rc != 0 { Err(Error::spi(rc, "storing variables")) } else { Ok(()) }
    }

    fn is_str(&self, var: i32) -> bool {
        self.check_thread();
        self.kind(var) != KIND_NUM
    }

    fn read_str(&self, var: i32, obs: usize, out: &mut Vec<u8>) -> Res<()> {
        self.check_thread();
        let o = obs as c_int + 1;
        let start = out.len();
        if self.kind(var) == KIND_STRL {
            let len = unsafe { fx_strl_len(var, o) };
            if len < 0 {
                return Err(Error::fallback("binary strL"));
            }
            let len = len as usize;
            out.try_reserve(len + 1).map_err(|_| Error::oom())?;
            out.resize(start + len + 1, 0);
            let rc = unsafe { fx_read_strl(var, o, out[start..].as_mut_ptr().cast(), (len + 1) as c_int) };
            if rc < 0 {
                out.truncate(start);
                return Err(Error::spi(-rc, "reading a strL variable"));
            }
            let end = out[start..start + len].iter().position(|&b| b == 0).unwrap_or(len);
            out.truncate(start + end);
        } else {
            // straight into the spare capacity: nothing is zeroed or copied
            out.try_reserve(STR_BUF).map_err(|_| Error::oom())?;
            let len = unsafe { fx_read_str(var, o, out.as_mut_ptr().add(start).cast()) };
            if len < 0 {
                return Err(Error::spi(-len, "reading a string variable"));
            }
            let len = len as usize;
            if len >= STR_BUF {
                return Err(Error::new(9999, "fastata: internal error (str# value too long); please report it"));
            }
            // SAFETY: fx_read_str wrote len bytes (plus a NUL) into the reserved capacity
            unsafe { out.set_len(start + len) };
        }
        Ok(())
    }

    fn write_str(&self, var: i32, obs: usize, s: &CStr) -> Res<()> {
        self.check_thread();
        let rc = unsafe { fx_write_str(var, obs as c_int + 1, s.as_ptr()) };
        if rc != 0 { Err(Error::spi(rc, "storing a string variable")) } else { Ok(()) }
    }
}

#[cfg(test)]
pub use mem::MemIo;

#[cfg(test)]
mod mem {
    use std::ffi::CStr;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::thread::ThreadId;

    use parking_lot::RwLock;

    use super::{Io, Rows};
    use crate::error::{Error, Res};

    /// Stata's system missing value (2^1023).
    pub const MISS: f64 = 8.98846567431158e307;

    pub enum Col {
        Num(Vec<AtomicU64>),
        Str(RwLock<Vec<Vec<u8>>>),
    }

    /// An in-memory dataset: columns plus a varlist mapping positions (1-based) to columns, so
    /// one column may appear at several positions (aliasing, as in Stata).
    /// String calls must come from the thread that created it (Stata's thread), unless
    /// `any_thread` is set (the parallel-read probe).
    pub struct MemIo {
        pub cols: Vec<Col>,
        pub varlist: Vec<usize>,
        pub n: usize,
        pub any_thread: bool,
        owner: ThreadId,
    }

    impl MemIo {
        pub fn new(n: usize) -> MemIo {
            MemIo { cols: Vec::new(), varlist: Vec::new(), n, any_thread: false, owner: std::thread::current().id() }
        }

        fn check_thread(&self) {
            assert!(self.any_thread || std::thread::current().id() == self.owner, "a string call off the creating thread");
        }

        /// Adds a numeric column; returns its column index.
        pub fn add_num(&mut self, v: &[f64]) -> usize {
            assert_eq!(v.len(), self.n);
            self.cols.push(Col::Num(v.iter().map(|x| AtomicU64::new(x.to_bits())).collect()));
            self.cols.len() - 1
        }

        pub fn add_str(&mut self, v: Vec<Vec<u8>>) -> usize {
            assert_eq!(v.len(), self.n);
            self.cols.push(Col::Str(RwLock::new(v)));
            self.cols.len() - 1
        }

        /// Appends column `c` to the varlist; returns its 1-based position.
        pub fn push_var(&mut self, c: usize) -> i32 {
            self.varlist.push(c);
            self.varlist.len() as i32
        }

        pub fn col(&self, c: usize) -> Vec<f64> {
            match &self.cols[c] {
                Col::Num(v) => v.iter().map(|x| f64::from_bits(x.load(Ordering::Relaxed))).collect(),
                Col::Str(_) => panic!("string column"),
            }
        }

        pub fn str_col(&self, c: usize) -> Vec<Vec<u8>> {
            match &self.cols[c] {
                Col::Str(v) => v.read().clone(),
                Col::Num(_) => panic!("numeric column"),
            }
        }

        fn num(&self, var: i32) -> &[AtomicU64] {
            match &self.cols[self.varlist[var as usize - 1]] {
                Col::Num(v) => v,
                Col::Str(_) => panic!("string column read as numeric"),
            }
        }

        fn strs(&self, var: i32) -> &RwLock<Vec<Vec<u8>>> {
            match &self.cols[self.varlist[var as usize - 1]] {
                Col::Str(v) => v,
                Col::Num(_) => panic!("numeric column used as string"),
            }
        }
    }

    impl Io for MemIo {
        fn nobs(&self) -> usize {
            self.n
        }

        fn nvars(&self) -> usize {
            self.varlist.len()
        }

        fn missval(&self) -> f64 {
            MISS
        }

        fn read_block(&self, vars: &[i32], rows: Rows<'_>, out: &mut [f64]) -> Res<()> {
            let nv = vars.len();
            for r in 0..rows.len() {
                let o = rows.obs(r);
                for (j, &v) in vars.iter().enumerate() {
                    out[r * nv + j] = f64::from_bits(self.num(v)[o].load(Ordering::Relaxed));
                }
            }
            Ok(())
        }

        fn write_block(&self, vars: &[i32], rows: Rows<'_>, vals: &[f64], skip: Option<&[u8]>) -> Res<()> {
            let nv = vars.len();
            for r in 0..rows.len() {
                let o = rows.obs(r);
                for (j, &v) in vars.iter().enumerate() {
                    if skip.is_some_and(|s| s[r * nv + j] != 0) {
                        continue;
                    }
                    let z = vals[r * nv + j];
                    let z = if z.is_finite() { z } else { MISS };
                    self.num(v)[o].store(z.to_bits(), Ordering::Relaxed);
                }
            }
            Ok(())
        }

        fn is_str(&self, var: i32) -> bool {
            self.check_thread();
            matches!(self.cols[self.varlist[var as usize - 1]], Col::Str(_))
        }

        fn read_str(&self, var: i32, obs: usize, out: &mut Vec<u8>) -> Res<()> {
            self.check_thread();
            let v = &self.strs(var).read()[obs];
            out.try_reserve(v.len()).map_err(|_| Error::oom())?;
            out.extend_from_slice(v);
            Ok(())
        }

        fn write_str(&self, var: i32, obs: usize, s: &CStr) -> Res<()> {
            self.check_thread();
            self.strs(var).write()[obs] = s.to_bytes().to_vec();
            Ok(())
        }
    }
}

#[cfg(test)]
pub use mem::MISS;

#[cfg(test)]
mod tests {
    use super::*;

    fn strs() -> MemIo {
        let mut io = MemIo::new(3);
        let c = io.add_str(vec![b"a".to_vec(), Vec::new(), b"ccc".to_vec()]);
        io.push_var(c);
        io
    }

    #[test]
    fn string_reads_append() {
        let io = strs();
        let mut out = b"x".to_vec();
        for obs in 0..3 {
            io.read_str(1, obs, &mut out).unwrap();
        }
        assert_eq!(out, b"xaccc");
    }

    #[test]
    #[should_panic(expected = "a string call off the creating thread")]
    fn string_calls_off_the_creating_thread_are_caught() {
        let io = strs();
        std::thread::scope(|s| {
            let r = s.spawn(|| io.read_str(1, 0, &mut Vec::new())).join();
            r.unwrap_or_else(|p| std::panic::resume_unwind(p)).unwrap();
        });
    }
}
