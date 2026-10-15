//! `destring` and `tostring`: compute phases of fastata's destring and tostring (slice D),
//! following the two-phase protocol of [`crate::cache`]. The conversions are the calibrated
//! emulations of [`real`]. Strings are read and written on Stata's thread only; the conversion
//! itself runs in parallel blocks.
//!
//! `destring "phase=compute"`: varlist = the string variables of the user's varlist, in order.
//! Keys `threads`, `force`, `float`, `percent`, `dpcomma` (0/1), `ign` (the character codes of
//! `ignore()`, in order, separated by spaces; may be empty) and `raw` (0/1, calibration only).
//! For each variable j (1-based) it runs what `destring.ado` does: remove the ignored characters,
//! `ustrtrim()`, count the missing-looking values, `dpcomma`, collapse leading zeros, `real()`,
//! round to float with `float`; the variable converts unless some value that does not look
//! missing gives missing and `force` is off. A converting variable is divided by 100 when
//! `percent` is on and its first ignored `%` was found, then gets `compress`'s type. Sets locals
//! - `fx_flag_j` 1 if some value of variable j that does not look missing gives missing;
//! - `fx_conv_j` 1 if variable j converts (`fx_flag_j` 0 or `force`), else 0;
//! - `fx_found_j` one 0/1 per `ign` code: whether that pass removed anything;
//! - `fx_newmiss_j` missing values after `real()`;
//! - `fx_type_j` the storage type `compress` leaves (converting variables only);
//! - `fx_token` when any variable converts. The cache holds one numeric column per converting
//!   variable, in varlist order.
//!
//! Falls back (all or nothing) for a non-ASCII value [non-ASCII] and for values outside the
//! calibrated classes of [`real::real`] and [`real::to_float`]. With `raw=1` (calibration C3) it
//! applies only `real()` (and the float rounding with `float=1`) and caches two columns per
//! variable: the value, and 1 where the emulation would fall back (value `.` there).
//!
//! `tostring "phase=compute"`: varlist = the numeric variables to convert. Keys `threads`, `fmt`
//! (`g` or `f`) and `width` (W of `%W.0g` / `%W.0f`). Caches one string column per variable
//! (`string(v, fmt)`, see [`real::int_string`]) and sets `fx_len_j`, the longest value of
//! variable j, and `fx_token`. Falls back unless every nonmissing value is an integer within the
//! calibrated digit bound of the format [non-integer].

pub mod real;

use crate::args::Args;
use crate::cache::{self, Output};
use crate::error::{Error, Res, vec_filled, vec_with_capacity};
use crate::io::{self, Io};
use crate::par::{StoreMode, for_blocks};

use real::{Fmt, Range, Type};

const BLOCK: usize = 8192;

#[derive(Clone, Debug, Default)]
pub struct DestringOpts {
    pub threads: usize,
    pub force: bool,
    pub float: bool,
    pub percent: bool,
    pub dpcomma: bool,
    pub ignore: Vec<u8>,
    pub raw: bool,
}

/// Per-variable result of the destring compute phase.
#[derive(Clone, Debug, PartialEq)]
pub struct VarInfo {
    /// Some value that does not look missing gives missing.
    pub flag: bool,
    pub conv: bool,
    pub found: Vec<bool>,
    pub newmiss: usize,
    pub typ: Type,
}

/// Every value of string variable `var`, concatenated, with `n + 1` offsets.
fn read_strings<I: Io>(io: &I, var: i32) -> Res<(Vec<u8>, Vec<usize>)> {
    let n = io.nobs();
    let mut buf = Vec::new();
    let mut off = vec_with_capacity(n + 1)?;
    off.push(0);
    for obs in 0..n {
        io.read_str(var, obs, &mut buf)?;
        off.push(buf.len());
    }
    Ok((buf, off))
}

fn fb(reason: &'static str) -> Error {
    Error::fallback(reason)
}

/// One block of one variable: values (after `real()` and float rounding) and counts.
struct Part {
    vals: Vec<f64>,
    found: Vec<bool>,
    oldmiss: usize,
    newmiss: usize,
}

/// The destring compute phase without the SPI side effects: the cached output and per-variable
/// results.
pub fn destring_compute<I: Io>(io: &I, o: &DestringOpts) -> Res<(Output, Vec<VarInfo>)> {
    let n = io.nobs();
    let miss = io.missval();
    let nb = n.div_ceil(BLOCK);
    let mut out = Output::default();
    let mut infos = Vec::new();
    // `%` decides the percent division only at its first pass.
    let pct_pass = o.ignore.iter().position(|&c| c == b'%');
    for var in 1..=io.nvars() as i32 {
        if !io.is_str(var) {
            return Err(Error::syntax("fastata plugin: destring expects string variables"));
        }
        let (buf, off) = read_strings(io, var)?;
        if buf.iter().any(|&b| b >= 0x80) {
            return Err(fb("non-ASCII"));
        }
        let parts = for_blocks(io, nb, o.threads, StoreMode::Serial, |b, _emit| {
            let first = b * BLOCK;
            let m = BLOCK.min(n - first);
            let mut p = Part { vals: vec_filled(m, miss)?, found: vec![false; o.ignore.len()], oldmiss: 0, newmiss: 0 };
            let mut t = Vec::new();
            for r in 0..m {
                let s = &buf[off[first + r]..off[first + r + 1]];
                if o.raw {
                    let v = real::real(s, miss).and_then(|v| if o.float { real::to_float(v, miss) } else { Ok(v) });
                    // NaN marks a value the emulation would fall back for
                    p.vals[r] = v.unwrap_or(f64::NAN);
                    continue;
                }
                for (k, &c) in o.ignore.iter().enumerate() {
                    // a pass finds c unless an earlier pass already removed every c
                    if !p.found[k] && !o.ignore[..k].contains(&c) && s.contains(&c) {
                        p.found[k] = true;
                    }
                }
                let ismissing = real::prep(s, &o.ignore, o.dpcomma, &mut t);
                let mut v = real::real(&t, miss).map_err(fb)?;
                if o.float {
                    v = real::to_float(v, miss).map_err(fb)?;
                }
                p.oldmiss += usize::from(ismissing);
                p.newmiss += usize::from(v >= miss);
                p.vals[r] = v;
            }
            Ok(p)
        })?;
        drop(buf);
        drop(off);
        let mut vals = vec_with_capacity(n)?;
        let mut found = vec![false; o.ignore.len()];
        let (mut oldmiss, mut newmiss) = (0, 0);
        for p in parts {
            vals.extend_from_slice(&p.vals);
            found.iter_mut().zip(&p.found).for_each(|(f, &x)| *f |= x);
            oldmiss += p.oldmiss;
            newmiss += p.newmiss;
        }
        if o.raw {
            let flags: Vec<f64> = vals.iter().map(|v| if v.is_nan() { 1.0 } else { 0.0 }).collect();
            vals.iter_mut().for_each(|v| {
                if v.is_nan() {
                    *v = miss;
                }
            });
            out.nums.push(vals);
            out.nums.push(flags);
            let typ = if o.float { Type::Float } else { Type::Double };
            infos.push(VarInfo { flag: false, conv: true, found, newmiss, typ });
            continue;
        }
        let flag = oldmiss != newmiss;
        let conv = !flag || o.force;
        let mut typ = if o.float { Type::Float } else { Type::Double };
        if conv {
            if o.percent && pct_pass.is_some_and(|k| found[k]) {
                divide_by_100(&mut vals, miss, o.float)?;
            }
            let ranges = for_blocks(io, nb, o.threads, StoreMode::Serial, |b, _emit| {
                let mut rg = Range::default();
                vals[b * BLOCK..n.min((b + 1) * BLOCK)].iter().for_each(|&v| rg.add(v, miss));
                Ok(rg)
            })?;
            let mut rg = Range::default();
            ranges.iter().for_each(|r| rg.merge(r));
            typ = real::compress_type(typ, &rg);
            out.nums.push(vals);
        }
        infos.push(VarInfo { flag, conv, found, newmiss, typ });
    }
    Ok((out, infos))
}

/// `replace v = v/100`: missing codes become `.`.
fn divide_by_100(vals: &mut [f64], miss: f64, float: bool) -> Res<()> {
    for v in vals.iter_mut() {
        if *v >= miss {
            *v = miss;
            continue;
        }
        let q = *v / 100.0;
        if q != 0.0 && q.abs() < f64::MIN_POSITIVE {
            return Err(fb("subnormal result"));
        }
        *v = if float { real::to_float(q, miss).map_err(fb)? } else { q };
    }
    Ok(())
}

fn ignore_codes(s: &str) -> Res<Vec<u8>> {
    s.split_whitespace()
        .map(|t| t.parse::<u8>().ok().filter(|c| (32..127).contains(c)))
        .collect::<Option<Vec<u8>>>()
        .ok_or_else(|| Error::syntax(format!("fastata plugin: bad argument `ign={s}`")))
}

/// The `destring` command (see the module documentation).
pub fn run_destring<I: Io>(io: &I, a: &Args) -> Res<()> {
    a.only(&["phase", "threads", "force", "float", "percent", "dpcomma", "ign", "raw"])?;
    if a.str_req("phase")? != "compute" {
        return Err(Error::syntax("fastata plugin: destring supports phase=compute only"));
    }
    let o = DestringOpts {
        threads: a.usize_or("threads", 0)?,
        force: a.flag_or("force", false)?,
        float: a.flag_or("float", false)?,
        percent: a.flag_or("percent", false)?,
        dpcomma: a.flag_or("dpcomma", false)?,
        ignore: ignore_codes(a.str_opt("ign").unwrap_or(""))?,
        raw: a.flag_or("raw", false)?,
    };
    let (out, infos) = destring_compute(io, &o)?;
    for (j, v) in infos.iter().enumerate() {
        let j = j + 1;
        io::local_save(&format!("fx_flag_{j}"), if v.flag { "1" } else { "0" })?;
        io::local_save(&format!("fx_conv_{j}"), if v.conv { "1" } else { "0" })?;
        let f: Vec<&str> = v.found.iter().map(|&x| if x { "1" } else { "0" }).collect();
        io::local_save(&format!("fx_found_{j}"), &f.join(" "))?;
        io::local_save(&format!("fx_newmiss_{j}"), &v.newmiss.to_string())?;
        if v.conv {
            io::local_save(&format!("fx_type_{j}"), v.typ.name())?;
        }
    }
    if !out.nums.is_empty() {
        io::local_save("fx_token", &cache::put(out).to_string())?;
    }
    Ok(())
}

/// The tostring compute phase without the SPI side effects: the cached strings and the longest
/// value of each variable.
pub fn tostring_compute<I: Io>(io: &I, fmt: Fmt, threads: usize) -> Res<(Output, Vec<usize>)> {
    let n = io.nobs();
    let miss = io.missval();
    let nb = n.div_ceil(BLOCK);
    let mut out = Output::default();
    let mut lens = Vec::new();
    for var in 1..=io.nvars() as i32 {
        if io.is_str(var) {
            return Err(Error::syntax("fastata plugin: tostring expects numeric variables"));
        }
        let col = cache::read_cols(io, &[var], threads)?.pop().unwrap_or_default();
        let parts = for_blocks(io, nb, threads, StoreMode::Serial, |b, _emit| {
            let first = b * BLOCK;
            let m = BLOCK.min(n - first);
            let mut strs: Vec<Vec<u8>> = vec_with_capacity(m)?;
            let mut len = 0;
            for &v in &col[first..first + m] {
                let mut s = Vec::with_capacity(20);
                real::int_string(v, miss, fmt, &mut s).map_err(|_| fb("non-integer"))?;
                len = len.max(s.len());
                strs.push(s);
            }
            Ok((strs, len))
        })?;
        let mut strs = vec_with_capacity(n)?;
        let mut len = 0;
        for (s, l) in parts {
            strs.extend(s);
            len = len.max(l);
        }
        out.strs.push(strs);
        lens.push(len);
    }
    Ok((out, lens))
}

/// The `tostring` command (see the module documentation).
pub fn run_tostring<I: Io>(io: &I, a: &Args) -> Res<()> {
    a.only(&["phase", "threads", "fmt", "width"])?;
    if a.str_req("phase")? != "compute" {
        return Err(Error::syntax("fastata plugin: tostring supports phase=compute only"));
    }
    let w = a.usize_req("width")?;
    let fmt = match a.str_req("fmt")? {
        "g" => Fmt::G(w),
        "f" => Fmt::F(w),
        f => return Err(Error::syntax(format!("fastata plugin: bad argument `fmt={f}`"))),
    };
    let (out, lens) = tostring_compute(io, fmt, a.usize_or("threads", 0)?)?;
    for (j, l) in lens.iter().enumerate() {
        io::local_save(&format!("fx_len_{}", j + 1), &l.to_string())?;
    }
    if !out.strs.is_empty() {
        io::local_save("fx_token", &cache::put(out).to_string())?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::{MISS, MemIo};
    use crate::testutil::{Rng, miss_a};

    fn strvar_io(cols: &[Vec<&str>]) -> MemIo {
        let n = cols[0].len();
        let mut io = MemIo::new(n);
        for c in cols {
            let k = io.add_str(c.iter().map(|s| s.as_bytes().to_vec()).collect());
            io.push_var(k);
        }
        io
    }

    /// Naive reference for one variable: (values, oldmiss, newmiss, found).
    fn naive(col: &[Vec<u8>], o: &DestringOpts) -> (Vec<f64>, usize, usize, Vec<bool>) {
        let mut found = vec![false; o.ignore.len()];
        let mut vals = Vec::new();
        let (mut om, mut nm) = (0, 0);
        for s in col {
            let mut cur = s.clone();
            for (k, c) in o.ignore.iter().enumerate() {
                if cur.contains(c) {
                    found[k] = true;
                }
                cur.retain(|b| b != c);
            }
            let mut t = Vec::new();
            om += usize::from(real::prep(&cur, &[], o.dpcomma, &mut t));
            let mut v = real::real(&t, MISS).unwrap();
            if o.float {
                v = real::to_float(v, MISS).unwrap();
            }
            nm += usize::from(v >= MISS);
            vals.push(v);
        }
        (vals, om, nm, found)
    }

    fn random_strings(n: usize, seed: u64) -> Vec<String> {
        let mut rng = Rng::new(seed);
        let junk = ["NA", "-", "", ".", ".a", " .z ", "$1,234", "12%", "1,5", "007", "1e3", "x", "  42  "];
        (0..n)
            .map(|_| {
                let u = rng.unif();
                if u < 0.1 {
                    junk[(rng.unif() * junk.len() as f64) as usize].to_string()
                } else if u < 0.5 {
                    format!("{}", ((rng.unif() - 0.5) * 2e5).round())
                } else {
                    format!("{:.3}", (rng.unif() - 0.5) * 1e4)
                }
            })
            .collect()
    }

    #[test]
    fn destring_matches_naive_reference_for_any_thread_count() {
        let n = 3 * BLOCK + 17;
        let a = random_strings(n, 1);
        let b: Vec<String> = (0..n).map(|i| format!("{}", i as i64 - 100)).collect();
        let cols = vec![a.iter().map(String::as_str).collect::<Vec<_>>(), b.iter().map(String::as_str).collect()];
        let io = strvar_io(&cols);
        for (force, float, ign, dp) in [(true, false, "", false), (false, false, "", false), (true, true, "$,%", false), (true, false, "", true)] {
            let o1 = DestringOpts { threads: 1, force, float, ignore: ign.as_bytes().to_vec(), dpcomma: dp, ..Default::default() };
            let (out1, inf1) = destring_compute(&io, &o1).unwrap();
            let o8 = DestringOpts { threads: 8, ..o1.clone() };
            let (out8, inf8) = destring_compute(&io, &o8).unwrap();
            assert_eq!(inf1, inf8);
            assert_eq!(out1.nums.len(), out8.nums.len());
            for (x, y) in out1.nums.iter().zip(&out8.nums) {
                assert!(x.iter().zip(y).all(|(p, q)| p.to_bits() == q.to_bits()));
            }
            let mut k = 0;
            for (j, c) in cols.iter().enumerate() {
                let col: Vec<Vec<u8>> = c.iter().map(|s| s.as_bytes().to_vec()).collect();
                let (vals, om, nm, found) = naive(&col, &o1);
                assert_eq!(inf1[j].newmiss, nm);
                assert_eq!(inf1[j].found, found);
                assert_eq!(inf1[j].flag, om != nm);
                assert_eq!(inf1[j].conv, force || om == nm);
                if inf1[j].conv {
                    assert!(out1.nums[k].iter().zip(&vals).all(|(p, q)| p.to_bits() == q.to_bits()));
                    k += 1;
                }
            }
        }
    }

    #[test]
    fn destring_types_percent_and_skips() {
        let io = strvar_io(&[
            vec!["1", "2", "", "NA"],
            vec!["1", "2", "", ".b"],
            vec!["50%", "1.5", "", ".a"],
            vec!["70000", "1", "-3", "."],
        ]);
        let o = DestringOpts { threads: 2, ..Default::default() };
        let (out, inf) = destring_compute(&io, &o).unwrap();
        assert!(!inf[0].conv);
        assert_eq!(inf[0].newmiss, 2);
        assert!(inf[1].conv && inf[1].typ == Type::Byte);
        assert_eq!(out.nums[0][3].to_bits(), real::ext_missing(MISS, b'b').to_bits());
        assert!(!inf[2].conv);
        assert!(inf[3].conv && inf[3].typ == Type::Long);
        let o = DestringOpts { threads: 2, percent: true, ignore: b"%".to_vec(), ..Default::default() };
        let (out, inf) = destring_compute(&io, &o).unwrap();
        assert!(inf[2].conv && inf[2].found == vec![true] && inf[2].typ == Type::Double);
        assert_eq!(out.nums[1], vec![0.5, 0.015, MISS, MISS]);
        assert_eq!(inf[1].found, vec![false]);
        assert_eq!(out.nums[0][3].to_bits(), real::ext_missing(MISS, b'b').to_bits());
        let io = strvar_io(&[vec!["1", "é"]]);
        assert!(destring_compute(&io, &o).unwrap_err().is_fallback());
        let io = strvar_io(&[vec!["1", "1.0x+1"]]);
        assert!(destring_compute(&io, &o).unwrap_err().is_fallback());
    }

    #[test]
    fn destring_raw_marks_fallback_values() {
        let io = strvar_io(&[vec!["1", "1.0x+1", "1e308", ".c"]]);
        let o = DestringOpts { raw: true, ..Default::default() };
        let (out, _) = destring_compute(&io, &o).unwrap();
        assert_eq!(out.nums[1], vec![0.0, 1.0, 1.0, 0.0]);
        assert_eq!(out.nums[0][0], 1.0);
        assert_eq!(out.nums[0][1].to_bits(), MISS.to_bits());
    }

    #[test]
    fn tostring_matches_reference_for_any_thread_count() {
        let n = 2 * BLOCK + 5;
        let mut io = MemIo::new(n);
        let x: Vec<f64> = (0..n).map(|i| if i % 11 == 0 { miss_a() } else if i % 13 == 0 { MISS } else { i as f64 * 37.0 - 9000.0 }).collect();
        let c = io.add_num(&x);
        io.push_var(c);
        let (o1, l1) = tostring_compute(&io, Fmt::G(12), 1).unwrap();
        let (o4, l4) = tostring_compute(&io, Fmt::G(12), 4).unwrap();
        assert_eq!(o1, o4);
        assert_eq!(l1, l4);
        for (i, s) in o1.strs[0].iter().enumerate() {
            let want = if i % 11 == 0 { ".a".to_string() } else if i % 13 == 0 { ".".to_string() } else { format!("{}", i as i64 * 37 - 9000) };
            assert_eq!(s, want.as_bytes());
        }
        assert_eq!(l1[0], format!("{}", (n as i64 - 1) * 37 - 9000).len());
        let mut io = MemIo::new(2);
        let c = io.add_num(&[1.0, 1.5]);
        io.push_var(c);
        assert!(tostring_compute(&io, Fmt::G(12), 2).unwrap_err().is_fallback());
    }
}
