//! Protocol of the `egen` command between `stata/_fx_egen.ado` and the plugin. Change both sides
//! together.
//!
//! `_fx_call <varlist>, egen "phase=compute" "key=value" ...`
//!
//! The varlist holds, in this order:
//! 1. keys (`nkeys` of them): the varlist of `group()`/`tag()`, or the by variables;
//! 2. values (`nvals`): the expression's variable (one), the varlist of a row function, or none
//!    (`group`, `tag`);
//! 3. the sample marker (if `touse=1`): 0 outside the sample (`if`/`in`), nonzero inside.
//!
//! | key | values |
//! |---|---|
//! | `fcn` | `group tag total sum mean max min count median pctile iqr sd std rank rowtotal rowmean rowmax rowmin rowsd rowmiss rownonmiss` |
//! | `type` | result storage type: `byte int long float double` (`tag`: `byte`) |
//! | `nkeys` | number of keys (0: no by-groups) |
//! | `sorted` | `1`: the data are sorted by the keys (by prefix), groups are runs of numeric keys (string keys are hashed either way); `0`: hash grouping |
//! | `nvals` | number of value variables |
//! | `touse` | `0` or `1` |
//! | `missing` | `0` or `1`: the function's `missing` option |
//! | `cntflag` | `count` only: `1` when the value is a byte flag `!missing(exp)` (0 = missing) |
//! | `p` | `pctile`: the percentile as Stata's `%21x` text |
//! | `mean`, `sd` | `std`: the `mean()` and `sd()` options as `%21x` text |
//! | `rank` | `rank`: `default`, `field` or `track` |
//! | `threads` | 0 = every logical CPU |
//!
//! Result locals: `fx_token` (see `cache`), `fx_nmiss` (missing results, for egen's
//! "(N missing values generated)"), and for `median`, `pctile`, `iqr` without by-groups `fx_n`
//! (nonmissing sample values; 0 makes `_pctile` print "no observations").
//!
//! The arithmetic follows the original `_g<fcn>.ado` files (gated versions); the kernels document
//! each rule. Input the fast path does not cover is a fallback: a string where a number is needed,
//! a result that does not fit the storage type exactly, more than 2^32-1 observations, a binary
//! strL key.

use crate::args::Args;
use crate::error::{Error, Res};

/// An egen function (`sum` is `total`: `_gsum` calls `_gtotal`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Fcn {
    Group,
    Tag,
    Total,
    Mean,
    Max,
    Min,
    Count,
    Median,
    Pctile,
    Iqr,
    Sd,
    Std,
    Rank,
    RowTotal,
    RowMean,
    RowMax,
    RowMin,
    RowSd,
    RowMiss,
    RowNonmiss,
}

impl Fcn {
    fn parse(s: &str) -> Res<Fcn> {
        Ok(match s {
            "group" => Fcn::Group,
            "tag" => Fcn::Tag,
            "total" | "sum" => Fcn::Total,
            "mean" => Fcn::Mean,
            "max" => Fcn::Max,
            "min" => Fcn::Min,
            "count" => Fcn::Count,
            "median" => Fcn::Median,
            "pctile" => Fcn::Pctile,
            "iqr" => Fcn::Iqr,
            "sd" => Fcn::Sd,
            "std" => Fcn::Std,
            "rank" => Fcn::Rank,
            "rowtotal" => Fcn::RowTotal,
            "rowmean" => Fcn::RowMean,
            "rowmax" => Fcn::RowMax,
            "rowmin" => Fcn::RowMin,
            "rowsd" => Fcn::RowSd,
            "rowmiss" => Fcn::RowMiss,
            "rownonmiss" => Fcn::RowNonmiss,
            _ => return Err(Error::syntax(format!("fastata plugin: egen function `{s}` unknown"))),
        })
    }

    pub fn is_row(self) -> bool {
        matches!(
            self,
            Fcn::RowTotal | Fcn::RowMean | Fcn::RowMax | Fcn::RowMin | Fcn::RowSd | Fcn::RowMiss | Fcn::RowNonmiss
        )
    }

    pub fn is_keyed(self) -> bool {
        matches!(self, Fcn::Group | Fcn::Tag)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RankMode {
    Default,
    Field,
    Track,
}

/// Result storage type.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Ty {
    Byte,
    Int,
    Long,
    Float,
    Double,
}

/// 2^127: Stata's float `.`; every nonmissing float is below it in absolute value.
const FLOAT_LIMIT: f64 = 1.7014118346046923e38;

impl Ty {
    fn parse(s: &str) -> Res<Ty> {
        Ok(match s {
            "byte" => Ty::Byte,
            "int" => Ty::Int,
            "long" => Ty::Long,
            "float" => Ty::Float,
            "double" => Ty::Double,
            _ => return Err(Error::syntax(format!("fastata plugin: egen type `{s}` unknown"))),
        })
    }

    /// The value stored by `gen <type> v = x` / `replace v = x` for raw value `x`: missing codes
    /// unchanged, float rounding to nearest. Integer types must hold `x` exactly and floats must
    /// stay in range; anything else (Stata would truncate or make it missing) is a fallback.
    #[inline]
    pub fn cast(self, x: f64, miss: f64) -> Res<f64> {
        if x >= miss {
            return Ok(x);
        }
        let (lo, hi) = match self {
            Ty::Double => return Ok(x),
            Ty::Float => {
                let f = f64::from(x as f32);
                return if f.abs() < FLOAT_LIMIT { Ok(f) } else { Err(Error::fallback("type fit")) };
            }
            Ty::Byte => (-127.0, 100.0),
            Ty::Int => (-32767.0, 32740.0),
            Ty::Long => (-2147483647.0, 2147483620.0),
        };
        if x.fract() == 0.0 && (lo..=hi).contains(&x) { Ok(x) } else { Err(Error::fallback("type fit")) }
    }
}

/// An arithmetic result as Stata keeps it: NaN, infinities and magnitudes at or above `.` are `.`.
#[inline]
pub fn arith(x: f64, miss: f64) -> f64 {
    if x.abs() < miss { x } else { miss }
}

/// Parses Stata's `%21x` text, e.g. `+1.8000000000000X+001` (= 3) or `+0.0000000000000X-3ff`
/// (= 0): exact, unlike decimal text.
pub fn parse_hex(s: &str) -> Option<f64> {
    let s = s.trim();
    let (neg, rest) = match s.as_bytes().first()? {
        b'+' => (false, &s[1..]),
        b'-' => (true, &s[1..]),
        _ => (false, s),
    };
    let (mant, exp) = rest.split_once(['X', 'x'])?;
    let (lead, frac) = mant.split_once('.')?;
    if frac.len() != 13 {
        return None;
    }
    let frac = u64::from_str_radix(frac, 16).ok()?;
    let (eneg, edig) = match exp.as_bytes().first()? {
        b'+' => (false, &exp[1..]),
        b'-' => (true, &exp[1..]),
        _ => return None,
    };
    let e = i64::from_str_radix(edig, 16).ok()?;
    let e = if eneg { -e } else { e };
    let bits = match lead {
        "1" => {
            let be = e + 1023;
            if !(1..=2046).contains(&be) {
                return None;
            }
            ((be as u64) << 52) | frac
        }
        "0" if e == -1023 => frac,
        _ => return None,
    };
    let v = f64::from_bits(bits);
    Some(if neg { -v } else { v })
}

/// The parsed `egen` arguments.
#[derive(Clone, Debug)]
pub struct Spec {
    pub fcn: Fcn,
    pub ty: Ty,
    pub keys: Vec<i32>,
    pub sorted: bool,
    pub vals: Vec<i32>,
    pub touse: Option<i32>,
    pub missing: bool,
    pub cntflag: bool,
    pub p: f64,
    pub mean: f64,
    pub sd: f64,
    pub rank: RankMode,
    pub threads: usize,
}

const KEYS: &[&str] =
    &["phase", "threads", "fcn", "type", "nkeys", "sorted", "nvals", "touse", "missing", "cntflag", "p", "mean", "sd", "rank"];

fn hex_or(a: &Args, key: &str, default: f64) -> Res<f64> {
    match a.str_opt(key) {
        None => Ok(default),
        Some(s) => parse_hex(s).ok_or_else(|| Error::syntax(format!("fastata plugin: bad argument `{key}={s}`"))),
    }
}

impl Spec {
    /// Parses and checks the arguments against a varlist of `nvars` variables.
    pub fn parse(a: &Args, nvars: usize) -> Res<Spec> {
        a.only(KEYS)?;
        if a.str_req("phase")? != "compute" {
            return Err(Error::syntax("fastata plugin: egen supports phase=compute only"));
        }
        let fcn = Fcn::parse(a.str_req("fcn")?)?;
        let ty = Ty::parse(a.str_req("type")?)?;
        let nkeys = a.usize_or("nkeys", 0)?;
        let nvals = a.usize_or("nvals", 0)?;
        let touse = a.flag_or("touse", false)?;
        if nkeys + nvals + usize::from(touse) != nvars {
            return Err(Error::syntax("fastata plugin: egen varlist does not match nkeys, nvals and touse"));
        }
        let ok = if fcn.is_keyed() {
            nkeys >= 1 && nvals == 0
        } else if fcn.is_row() {
            nkeys == 0 && nvals >= 1
        } else {
            nvals == 1
        };
        if !ok || (fcn == Fcn::RowSd && nvals < 2) {
            return Err(Error::syntax("fastata plugin: egen variables do not fit the function"));
        }
        let rank = match a.str_opt("rank").unwrap_or("default") {
            "default" => RankMode::Default,
            "field" => RankMode::Field,
            "track" => RankMode::Track,
            s => return Err(Error::syntax(format!("fastata plugin: bad argument `rank={s}`"))),
        };
        let p = hex_or(a, "p", 50.0)?;
        if !(p > 0.0 && p < 100.0) {
            return Err(Error::syntax("fastata plugin: egen p() must be between 0 and 100"));
        }
        let pos = |k: usize| (k + 1) as i32;
        Ok(Spec {
            fcn,
            ty: if fcn == Fcn::Tag { Ty::Byte } else { ty },
            keys: (0..nkeys).map(pos).collect(),
            sorted: a.flag_or("sorted", false)?,
            vals: (nkeys..nkeys + nvals).map(pos).collect(),
            touse: touse.then(|| pos(nkeys + nvals)),
            missing: a.flag_or("missing", false)?,
            cntflag: a.flag_or("cntflag", false)?,
            p,
            mean: hex_or(a, "mean", 0.0)?,
            sd: hex_or(a, "sd", 1.0)?,
            rank,
            threads: a.usize_or("threads", 0)?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::MISS;

    #[test]
    fn hex_text_round_trips() {
        assert_eq!(parse_hex("+1.0000000000000X+000"), Some(1.0));
        assert_eq!(parse_hex("+1.8000000000000X+001"), Some(3.0));
        assert_eq!(parse_hex("-1.999999999999aX-004"), Some(-0.1));
        assert_eq!(parse_hex("+1.0aaaaaaaaaaabX+005"), Some(33.333333333333336));
        assert_eq!(parse_hex("+0.0000000000000X-3ff"), Some(0.0));
        assert_eq!(parse_hex("+0.0000000000001X-3ff"), Some(f64::from_bits(1)));
        assert_eq!(parse_hex("1.5"), None);
        assert_eq!(parse_hex("+1.00X+000"), None);
    }

    #[test]
    fn casts_follow_storage_types() {
        let m = MISS;
        assert_eq!(Ty::Float.cast(0.1, m).unwrap(), f64::from(0.1f32));
        assert_eq!(Ty::Float.cast(m * 1.5, m).unwrap(), m * 1.5);
        assert!(Ty::Float.cast(2e38, m).unwrap_err().is_fallback());
        assert_eq!(Ty::Byte.cast(100.0, m).unwrap(), 100.0);
        assert!(Ty::Byte.cast(101.0, m).is_err());
        assert!(Ty::Byte.cast(-128.0, m).is_err());
        assert!(Ty::Int.cast(2.5, m).is_err());
        assert_eq!(Ty::Long.cast(-2147483647.0, m).unwrap(), -2147483647.0);
        assert!(Ty::Long.cast(2147483621.0, m).is_err());
        assert_eq!(arith(f64::INFINITY, m), m);
        assert_eq!(arith(f64::NAN, m), m);
        assert_eq!(arith(-1e308, m), m);
        assert_eq!(arith(-2.0, m), -2.0);
    }
}
