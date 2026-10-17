//! The plugin side of the two-phase protocol. A compute phase (`<cmd> "phase=compute" ...`)
//! reads its inputs, computes every output value and leaves them here with [`put`], returning a
//! token in local `fx_token`; it never writes data. The ado then creates the output variables
//! (nofill) and runs `store`, which writes the outputs and empties the cache. One result is held
//! at a time: [`put`] replaces an earlier one, and a compute phase that falls back or fails
//! empties the cache ([`clear`]).
//!
//! `store`: varlist = the numeric outputs, then the string outputs, in the order of
//! [`Output::nums`] and [`Output::strs`]. Keys `token` (from the compute phase) and `threads`.
//! Writes every observation of every output variable: numeric columns in parallel blocks, string
//! columns on the calling thread. A token that does not match the cached result gives r(9999).
//!
//! `cachetest` (tests of the protocol): varlist = numeric variables, then string variables; key
//! `nnum` (how many are numeric) and `threads`. A compute phase that caches the negated numbers
//! (missing codes unchanged) and the strings with "!" appended, and sets local `fx_token`.

use std::ffi::CStr;
use std::sync::Mutex;
use std::sync::PoisonError;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::args::Args;
use crate::error::{Error, Res, vec_filled, vec_with_capacity, vec_zeroed};
use crate::io::{self, Io, Rows};
use crate::par::{StoreMode, WriteJob, for_blocks, for_chunks, threads_for_rows};

const BLOCK: usize = 8192;

/// Values per work item of [`read_cols`]: a block of rows by every variable (Stata stores the
/// data row by row, so whole rows are read in memory order).
const READ_VALUES: usize = 1 << 18;

/// Output values of one compute phase, one entry per observation of the dataset.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct Output {
    /// Numeric outputs, one column per output variable. Values are raw Stata values: numbers,
    /// missing codes as Stata stores them (`.a` is a finite double above `.`), or NaN for `.`.
    /// The variable's storage type rounds them (float) or must hold them exactly (byte, int,
    /// long): the compute phase checks that before the ado chooses the type.
    pub nums: Vec<Vec<f64>>,
    /// String outputs, one column per output variable.
    pub strs: Vec<StrCol>,
}

/// A string column: its values in observation order, each followed by a NUL byte, in a few
/// large chunks (no allocation per value; `store` hands each value to Stata in place).
#[derive(Debug, Default, Clone)]
pub struct StrCol {
    chunks: Vec<Vec<u8>>,
    len: usize,
}

impl StrCol {
    /// The column made of `chunks`, each a run of NUL-terminated values, `len` values in all.
    pub fn from_chunks(chunks: Vec<Vec<u8>>, len: usize) -> StrCol {
        debug_assert_eq!(chunks.iter().map(|c| c.iter().filter(|&&b| b == 0).count()).sum::<usize>(), len);
        debug_assert!(chunks.iter().all(|c| c.last().is_none_or(|&b| b == 0)));
        StrCol { chunks, len }
    }

    /// Appends `s` (no NUL byte), growing the last chunk fallibly (r(909)).
    pub fn push(&mut self, s: &[u8]) -> Res<()> {
        if s.contains(&0) {
            return Err(Error::syntax("fastata plugin: string value with a NUL byte"));
        }
        if self.chunks.is_empty() {
            self.chunks.try_reserve(1).map_err(|_| Error::oom())?;
            self.chunks.push(Vec::new());
        }
        let c = self.chunks.last_mut().expect("a chunk");
        c.try_reserve(s.len() + 1).map_err(|_| Error::oom())?;
        c.extend_from_slice(s);
        c.push(0);
        self.len += 1;
        Ok(())
    }

    /// Number of values.
    pub fn len(&self) -> usize {
        self.len
    }

    /// The values in observation order.
    pub fn iter(&self) -> impl Iterator<Item = &CStr> {
        self.chunks.iter().flat_map(|c| {
            let mut rest = &c[..];
            std::iter::from_fn(move || {
                let s = CStr::from_bytes_until_nul(rest).ok()?;
                rest = &rest[s.to_bytes_with_nul().len()..];
                Some(s)
            })
        })
    }
}

impl PartialEq for StrCol {
    fn eq(&self, o: &StrCol) -> bool {
        self.len == o.len && self.iter().eq(o.iter())
    }
}

struct Entry {
    token: u64,
    out: Output,
}

static CACHE: Mutex<Option<Entry>> = Mutex::new(None);
static SEQ: AtomicU64 = AtomicU64::new(0);

/// Leaves `out` in the cache (replacing any earlier result) and returns its token.
pub fn put(out: Output) -> u64 {
    let t = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_nanos() as u64);
    let token = (t ^ SEQ.fetch_add(1, Ordering::Relaxed).wrapping_mul(0x9e37_79b9_7f4a_7c15)) | 1;
    *CACHE.lock().unwrap_or_else(PoisonError::into_inner) = Some(Entry { token, out });
    token
}

/// Empties the cache.
pub fn clear() {
    *CACHE.lock().unwrap_or_else(PoisonError::into_inner) = None;
}

/// Removes and returns the cached result if its token is `token`. Any other state is a stale
/// cache, r(9999); the cache is emptied either way.
pub fn take(token: u64) -> Res<Output> {
    match CACHE.lock().unwrap_or_else(PoisonError::into_inner).take() {
        Some(e) if e.token == token => Ok(e.out),
        _ => Err(Error::new(9999, "fastata: internal error (stale cache); please report it")),
    }
}

/// The `store` command (see the module documentation).
pub fn store<I: Io>(io: &I, a: &Args) -> Res<()> {
    a.only(&["token", "threads"])?;
    let token: u64 = a.str_req("token")?.parse().map_err(|_| Error::syntax("fastata plugin: bad token"))?;
    let threads = a.usize_or("threads", 0)?;
    let out = take(token)?;
    write(io, &out, threads)
}

/// The `cachetest` command (see the module documentation).
pub fn cachetest<I: Io>(io: &I, a: &Args) -> Res<()> {
    a.only(&["nnum", "threads"])?;
    let k = a.usize_req("nnum")?;
    let threads = a.usize_or("threads", 0)?;
    if k > io.nvars() {
        return Err(Error::syntax("fastata plugin: cachetest nnum exceeds the varlist"));
    }
    let miss = io.missval();
    let mut nums = read_cols(io, &(1..=k as i32).collect::<Vec<_>>(), threads)?;
    for v in nums.iter_mut().flatten() {
        if *v < miss {
            *v = -*v;
        }
    }
    let mut strs = vec_with_capacity(io.nvars() - k)?;
    let mut s = Vec::new();
    for v in k as i32 + 1..=io.nvars() as i32 {
        let mut col = StrCol::default();
        for obs in 0..io.nobs() {
            s.clear();
            io.read_str(v, obs, &mut s)?;
            s.try_reserve(1).map_err(|_| Error::oom())?;
            s.push(b'!');
            col.push(&s)?;
        }
        strs.push(col);
    }
    let token = put(Output { nums, strs });
    io::local_save("fx_token", &token.to_string())
}

/// Writes `out` into varlist positions 1.. (numeric columns first, then string columns).
pub fn write<I: Io>(io: &I, out: &Output, threads: usize) -> Res<()> {
    let n = io.nobs();
    let k = out.nums.len();
    if io.nvars() != k + out.strs.len() {
        return Err(Error::syntax("fastata plugin: store varlist does not match the cached outputs"));
    }
    if out.nums.iter().any(|c| c.len() != n) || out.strs.iter().any(|c| c.len() != n) {
        return Err(Error::new(9999, "fastata: internal error (cached outputs of the wrong length); please report it"));
    }
    for v in 1..=k as i32 {
        if io.is_str(v) {
            return Err(Error::syntax("fastata plugin: store expects a numeric variable"));
        }
    }
    for v in k as i32 + 1..=(k + out.strs.len()) as i32 {
        if !io.is_str(v) {
            return Err(Error::syntax("fastata plugin: store expects a string variable"));
        }
    }
    if k > 0 && n > 0 {
        let vars: Vec<i32> = (1..=k as i32).collect();
        let mode = StoreMode::from_serial(None);
        for_blocks(io, n.div_ceil(BLOCK), threads_for_rows(threads, n * k), mode, |b, emit| {
            let first = b * BLOCK;
            let m = BLOCK.min(n - first);
            let rows = Rows::Range { first, n: m };
            if k == 1 && mode == StoreMode::Parallel {
                return io.write_block(&vars, rows, &out.nums[0][first..first + m], None);
            }
            let mut vals = vec_filled(m * k, 0.0)?;
            for (j, col) in out.nums.iter().enumerate() {
                for (r, v) in col[first..first + m].iter().enumerate() {
                    vals[r * k + j] = *v;
                }
            }
            if mode == StoreMode::Parallel {
                return io.write_block(&vars, rows, &vals, None);
            }
            emit(WriteJob { vars: vars.clone(), rows: first..first + m, vals, skip: None })
        })?;
    }
    for (j, col) in out.strs.iter().enumerate() {
        let v = (k + j + 1) as i32;
        for (obs, s) in col.iter().enumerate() {
            io.write_str(v, obs, s)?;
        }
    }
    Ok(())
}

/// Reads numeric varlist positions `vars` for every observation, column-major: one vector per
/// variable. Missing values keep their raw codes. Runs in parallel blocks that read straight
/// into the columns (one variable) or through a small row-major buffer per block, so the peak
/// is the columns themselves.
pub fn read_cols<I: Io>(io: &I, vars: &[i32], threads: usize) -> Res<Vec<Vec<f64>>> {
    let n = io.nobs();
    let k = vars.len();
    let mut cols: Vec<Vec<f64>> = vec_with_capacity(k)?;
    for _ in 0..k {
        cols.push(vec_zeroed(n)?);
    }
    if k == 0 || n == 0 {
        return Ok(cols);
    }
    // depends on k only, as every item size must
    let rows = (READ_VALUES / k).clamp(256, BLOCK);
    let mut views: Vec<&mut [f64]> = cols.iter_mut().map(Vec::as_mut_slice).collect();
    for_chunks(io, &mut views, rows, threads_for_rows(threads, n.saturating_mul(k)), |b, ch| {
        let first = b * rows;
        let m = ch[0].len();
        let range = Rows::Range { first, n: m };
        if k == 1 {
            return io.read_block(vars, range, ch[0]);
        }
        let mut buf = vec_zeroed(m * k)?;
        io.read_block(vars, range, &mut buf)?;
        for (j, col) in ch.iter_mut().enumerate() {
            for (r, x) in col.iter_mut().enumerate() {
                *x = buf[r * k + j];
            }
        }
        Ok(())
    })?;
    Ok(cols)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::{MISS, MemIo};
    use crate::testutil::miss_a;

    /// The cache is global; tests that use it run one at a time.
    static LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    fn data(n: usize) -> (MemIo, Output) {
        let mut io = MemIo::new(n);
        let a = io.add_num(&vec![0.0; n]);
        let b = io.add_num(&vec![0.0; n]);
        let s = io.add_str(vec![b"?".to_vec(); n]);
        io.push_var(a);
        io.push_var(b);
        io.push_var(s);
        let nums = vec![
            (0..n).map(|i| if i % 7 == 0 { f64::NAN } else { i as f64 * 0.5 }).collect(),
            (0..n).map(|i| if i % 5 == 0 { miss_a() } else { -(i as f64) }).collect(),
        ];
        let mut col = StrCol::default();
        for i in 0..n {
            col.push(format!("v{i}").as_bytes()).unwrap();
        }
        (io, Output { nums, strs: vec![col] })
    }

    #[test]
    fn store_writes_every_observation_and_missing_codes() {
        let _g = LOCK.lock().unwrap_or_else(PoisonError::into_inner);
        let n = 2 * BLOCK + 11;
        for threads in [1, 3] {
            let (io, out) = data(n);
            let t = put(out.clone());
            write(&io, &take(t).unwrap(), threads).unwrap();
            let got_a = io.col(0);
            for i in 0..n {
                let want = if i % 7 == 0 { MISS } else { i as f64 * 0.5 };
                assert_eq!(got_a[i].to_bits(), want.to_bits(), "obs {i}");
            }
            let got_b = io.col(1);
            assert_eq!(got_b[5].to_bits(), miss_a().to_bits());
            assert_eq!(got_b[6], -6.0);
            assert_eq!(io.str_col(2)[n - 1], format!("v{}", n - 1).into_bytes());
        }
    }

    #[test]
    fn a_stale_token_or_an_empty_cache_is_an_internal_error() {
        let _g = LOCK.lock().unwrap_or_else(PoisonError::into_inner);
        let (_, out) = data(10);
        let t = put(out.clone());
        let _newer = put(out);
        assert_eq!(take(t).unwrap_err().rc, 9999);
        assert_eq!(take(t).unwrap_err().rc, 9999);
    }

    #[test]
    fn read_cols_is_column_major_with_raw_missing_codes() {
        let n = BLOCK + 3;
        let mut io = MemIo::new(n);
        let x: Vec<f64> = (0..n).map(|i| if i == 2 { miss_a() } else { i as f64 }).collect();
        let y: Vec<f64> = (0..n).map(|i| -(i as f64)).collect();
        let cx = io.add_num(&x);
        let cy = io.add_num(&y);
        io.push_var(cx);
        io.push_var(cy);
        for threads in [1, 4] {
            let c = read_cols(&io, &[2, 1], threads).unwrap();
            assert_eq!(c[0], y);
            assert_eq!(c[1][2].to_bits(), miss_a().to_bits());
            assert_eq!(c[1][n - 1], (n - 1) as f64);
            let c = read_cols(&io, &[1], threads).unwrap();
            assert_eq!(c[0][2].to_bits(), miss_a().to_bits());
            assert_eq!(c[0][..2], x[..2]);
            assert_eq!(c[0][3..], x[3..]);
        }
    }

    #[test]
    fn read_cols_covers_every_row_of_wide_varlists() {
        // 1100 variables: blocks of 256 rows; n not a multiple of it
        let n = 3 * 256 + 5;
        let mut io = MemIo::new(n);
        let vars: Vec<i32> = (0..1100)
            .map(|j| {
                let c = io.add_num(&(0..n).map(|i| (i * 1100 + j) as f64).collect::<Vec<_>>());
                io.push_var(c)
            })
            .collect();
        for threads in [1, 3] {
            let c = read_cols(&io, &vars, threads).unwrap();
            for (j, col) in c.iter().enumerate() {
                assert!(col.iter().enumerate().all(|(i, &v)| v == (i * 1100 + j) as f64), "variable {j}");
            }
        }
        assert!(read_cols(&io, &[], 2).unwrap().is_empty());
    }

    #[test]
    fn string_columns_keep_values_in_order() {
        let mut a = StrCol::default();
        for s in ["", "x", "", "longer value", ""] {
            a.push(s.as_bytes()).unwrap();
        }
        let got: Vec<&[u8]> = a.iter().map(CStr::to_bytes).collect();
        assert_eq!(got, [&b""[..], b"x", b"", b"longer value", b""]);
        assert_eq!(a.len(), 5);
        let b = StrCol::from_chunks(vec![b"\0x\0".to_vec(), Vec::new(), b"\0longer value\0\0".to_vec()], 5);
        assert_eq!(a, b);
        assert!(a.push(b"a\0b").is_err());
        assert_eq!(StrCol::default().iter().count(), 0);
    }
}
