//! Bitwise emulations of the Stata conversions behind `destring` and `tostring`, each proved
//! against Stata by `tests/stata/calib_strnum.do`:
//! - [`real`]: Stata's `real(s)` as stored by `generate double` (calibration C3);
//! - [`prep`]: what `destring.ado` does to a value before `real()` (`ignore()`, `ustrtrim()`,
//!   the missing-value test, `dpcomma`, leading zeros);
//! - [`to_float`]: `generate float` from a double (C3, float option);
//! - [`compress_type`]: the storage type `compress` chooses (C4);
//! - [`int_string`]: `string(v, "%W.0g")` / `string(v, "%W.0f")` for integers (C5).
//!
//! Inputs outside the proved classes return `Err(reason)`: the command then falls back.

/// Longest decimal number (after trimming) the emulation accepts; longer ones fall back
/// (calibration C3 covers numbers up to about 70 characters).
const MAX_DEC: usize = 64;

/// The raw value of extended missing code `.c` (`c` in `a..=z`): `.` plus `(c - 'a' + 1) << 40`.
#[inline]
pub fn ext_missing(miss: f64, c: u8) -> f64 {
    f64::from_bits(miss.to_bits() + (u64::from(c - b'a' + 1) << 40))
}

fn trim_spaces(s: &[u8]) -> &[u8] {
    let a = s.iter().position(|&b| b != b' ').unwrap_or(s.len());
    let e = s.iter().rposition(|&b| b != b' ').map_or(a, |i| i + 1);
    &s[a..e]
}

fn digits(s: &[u8], i: usize, hex: bool) -> usize {
    s[i..].iter().take_while(|b| if hex { b.is_ascii_hexdigit() } else { b.is_ascii_digit() }).count()
}

fn sign(s: &[u8], i: usize) -> usize {
    usize::from(i < s.len() && (s[i] == b'+' || s[i] == b'-'))
}

/// `[+-]? (D+ (. D*)? | . D+) ([eEdD] [+-]? D+)?`, the whole string.
fn is_decimal(s: &[u8]) -> bool {
    let mut i = sign(s, 0);
    let a = digits(s, i, false);
    i += a;
    let mut f = 0;
    if i < s.len() && s[i] == b'.' {
        i += 1;
        f = digits(s, i, false);
        i += f;
    }
    if a + f == 0 {
        return false;
    }
    if i < s.len() && matches!(s[i], b'e' | b'E' | b'd' | b'D') {
        i += 1;
        i += sign(s, i);
        let e = digits(s, i, false);
        if e == 0 {
            return false;
        }
        i += e;
    }
    i == s.len()
}

/// `[+-]? H* . H* [xX] [+-]? H*` (H a hex digit): every string of this shape falls back. Stata
/// reads some of them as hexadecimal numbers (`1.8x+1` is 3); calibration C3 shows that every
/// other string containing `x` or `X` is missing.
fn is_hex_candidate(s: &[u8]) -> bool {
    let mut i = sign(s, 0);
    i += digits(s, i, true);
    if i >= s.len() || s[i] != b'.' {
        return false;
    }
    i += 1;
    i += digits(s, i, true);
    if i >= s.len() || !matches!(s[i], b'x' | b'X') {
        return false;
    }
    i += 1;
    i += sign(s, i);
    i += digits(s, i, true);
    i == s.len()
}

/// Stata's `real(s)` as `generate double` stores it; `miss` is Stata's `.`. Leading and trailing
/// spaces (only spaces) are ignored; `""`, `"."` and anything that is not a number give `.`;
/// `".a"`..`".z"` their missing codes; decimal numbers (exponent letter `e`, `E`, `d` or `D`)
/// round to nearest, overflow gives `.`, underflow 0 or a subnormal. Falls back for strings
/// that may be hexadecimal numbers, for numbers longer than [`MAX_DEC`] characters and for
/// finite values of magnitude 2^1023 or more (Stata stores those raw, beyond `.`).
pub fn real(s: &[u8], miss: f64) -> Result<f64, &'static str> {
    let t = trim_spaces(s);
    if t.is_empty() || t == b"." {
        return Ok(miss);
    }
    if t.len() == 2 && t[0] == b'.' && t[1].is_ascii_lowercase() {
        return Ok(ext_missing(miss, t[1]));
    }
    if t.iter().any(|&b| b == b'x' || b == b'X') {
        return if is_hex_candidate(t) { Err("hexadecimal number") } else { Ok(miss) };
    }
    if !is_decimal(t) {
        return Ok(miss);
    }
    if t.len() > MAX_DEC {
        return Err("long number");
    }
    let mut buf = [0u8; MAX_DEC];
    for (d, &b) in buf.iter_mut().zip(t) {
        *d = if b == b'd' || b == b'D' { b'e' } else { b };
    }
    // The grammar check above guarantees ASCII that Rust's (correctly rounded) parser accepts.
    let v: f64 = std::str::from_utf8(&buf[..t.len()]).ok().and_then(|x| x.parse().ok()).ok_or("number")?;
    if v.is_infinite() {
        return Ok(miss);
    }
    if v.abs() >= miss {
        return Err("number beyond Stata's range");
    }
    Ok(v)
}

/// `generate float` of double `v`: missing codes are kept, zeros become +0, everything else rounds
/// to nearest float. Falls back outside 1e-37 <= |v| <= 1.7e38 (where Stata flushes to 0 or
/// gives `.`; the exact edges are not calibrated).
pub fn to_float(v: f64, miss: f64) -> Result<f64, &'static str> {
    if v >= miss {
        return Ok(v);
    }
    if v == 0.0 {
        return Ok(0.0);
    }
    let a = v.abs();
    if !(1e-37..=1.7e38).contains(&a) {
        return Err("float range");
    }
    Ok(f64::from(v as f32))
}

/// Whitespace removed by `ustrtrim()` from ASCII text (calibrated: \t \n \v \f \r and space).
fn is_uspace(b: u8) -> bool {
    matches!(b, 9..=13 | 32)
}

/// What `destring.ado` (2.4.4, caller >= 14) does to one value before `real()`. `s` is pure
/// ASCII; `ignore` lists the characters to remove (each its own pass, in order). Writes the
/// string `real()` sees to `out` and returns whether the value counts as missing (`""`, `"."`
/// or `".a"`..`".z"` after removal and trimming).
pub fn prep(s: &[u8], ignore: &[u8], dpcomma: bool, out: &mut Vec<u8>) -> bool {
    out.clear();
    if ignore.is_empty() {
        out.extend_from_slice(s);
    } else {
        out.extend(s.iter().filter(|b| !ignore.contains(b)));
    }
    let a = out.iter().position(|&b| !is_uspace(b)).unwrap_or(out.len());
    let e = out.iter().rposition(|&b| !is_uspace(b)).map_or(a, |i| i + 1);
    out.truncate(e);
    out.drain(..a);
    let t = &out[..];
    let ismissing = t.is_empty() || t == b"." || (t.len() == 2 && t[0] == b'.' && t[1].is_ascii_lowercase());
    if dpcomma {
        if !ismissing {
            for b in out.iter_mut() {
                if *b == b'.' {
                    *b = b'X';
                }
            }
        }
        // subinstr(s, ",", ".", 1) unless ustrregexm(s, "(,[a-z])|(^,$)")
        let t = &out[..];
        let blocked = t == b"," || t.windows(2).any(|w| w[0] == b',' && w[1].is_ascii_lowercase());
        if !blocked {
            if let Some(i) = out.iter().position(|&b| b == b',') {
                out[i] = b'.';
            }
        }
    }
    // ustrregexrf(s, "^0+", "0")
    let z = out.iter().take_while(|&&b| b == b'0').count();
    if z > 1 {
        out.drain(..z - 1);
    }
    ismissing
}

/// Storage types, in `compress` order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Type {
    Byte,
    Int,
    Long,
    Float,
    Double,
}

impl Type {
    pub fn name(self) -> &'static str {
        match self {
            Type::Byte => "byte",
            Type::Int => "int",
            Type::Long => "long",
            Type::Float => "float",
            Type::Double => "double",
        }
    }
}

/// Running summary of a column for [`compress_type`]: whether every nonmissing value is an
/// integer, and their range.
#[derive(Clone, Copy, Debug)]
pub struct Range {
    pub all_int: bool,
    pub lo: f64,
    pub hi: f64,
}

impl Default for Range {
    fn default() -> Self {
        Range { all_int: true, lo: f64::INFINITY, hi: f64::NEG_INFINITY }
    }
}

impl Range {
    #[inline]
    pub fn add(&mut self, v: f64, miss: f64) {
        if v >= miss {
            return;
        }
        if v.trunc() != v {
            self.all_int = false;
        }
        self.lo = self.lo.min(v);
        self.hi = self.hi.max(v);
    }

    pub fn merge(&mut self, o: &Range) {
        self.all_int &= o.all_int;
        self.lo = self.lo.min(o.lo);
        self.hi = self.hi.max(o.hi);
    }
}

/// The type `compress` gives a `from` (double or float) variable with values summarised by `r`
/// (calibration C4): the smallest of byte (-127..100), int (-32767..32740) and, for doubles
/// only, long (-2147483647..2147483620) that holds every nonmissing value as an integer; byte
/// when every value is missing; otherwise `from` (a double never becomes float).
pub fn compress_type(from: Type, r: &Range) -> Type {
    if !r.all_int {
        return from;
    }
    if r.lo > r.hi || (r.lo >= -127.0 && r.hi <= 100.0) {
        return Type::Byte;
    }
    if r.lo >= -32767.0 && r.hi <= 32740.0 {
        return Type::Int;
    }
    if from == Type::Double && r.lo >= -2147483647.0 && r.hi <= 2147483620.0 {
        return Type::Long;
    }
    from
}

/// `%W.0g` or `%W.0f`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Fmt {
    G(usize),
    F(usize),
}

/// The largest number of digits, by sign, for which `string(v, fmt)` of an integer is its plain
/// decimal digits (calibration C5): `%W.0g` W-2 digits for W >= 4 (none below), at most 19;
/// `%W.0f` max(8, W) digits for positive and max(7, W-1) for negative values, at most 19.
pub fn max_digits(fmt: Fmt, negative: bool) -> usize {
    let d = match fmt {
        Fmt::G(w) => w.saturating_sub(2) * usize::from(w >= 4),
        Fmt::F(w) if negative => 7.max(w.saturating_sub(1)),
        Fmt::F(w) => 8.max(w),
    };
    d.min(19)
}

/// Appends `string(v, fmt)` for value `v` to `out`: `"."`, `".a"`..`".z"` for missing codes and
/// the plain decimal digits (with `-` for negatives; -0 gives `"0"`) for integers within
/// [`max_digits`]. Anything else (a non-integer, too many digits, a raw value beyond `.z`) is a
/// fallback.
pub fn int_string(v: f64, miss: f64, fmt: Fmt, out: &mut Vec<u8>) -> Result<(), &'static str> {
    if v >= miss {
        let k = (v.to_bits() - miss.to_bits()) >> 40;
        if v.to_bits() & ((1 << 40) - 1) != 0 || k > 26 {
            return Err("nonstandard missing value");
        }
        out.push(b'.');
        if k > 0 {
            out.push(b'a' + k as u8 - 1);
        }
        return Ok(());
    }
    if v.trunc() != v || v.abs() >= 1e19 {
        return Err("non-integer");
    }
    let neg = v < 0.0;
    let mut m = v.abs() as u64;
    let mut buf = [0u8; 20];
    let mut i = buf.len();
    loop {
        i -= 1;
        buf[i] = b'0' + (m % 10) as u8;
        m /= 10;
        if m == 0 {
            break;
        }
    }
    if buf.len() - i > max_digits(fmt, neg) {
        return Err("format bound");
    }
    if neg {
        out.push(b'-');
    }
    out.extend_from_slice(&buf[i..]);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::MISS;
    use crate::testutil::miss_a;

    fn r(s: &str) -> Result<f64, &'static str> {
        real(s.as_bytes(), MISS)
    }

    #[test]
    fn real_matches_the_calibrated_cases() {
        assert_eq!(r("1").unwrap(), 1.0);
        assert_eq!(r("  1 ").unwrap(), 1.0);
        assert_eq!(r("1d5").unwrap(), 1e5);
        assert_eq!(r("1E+5").unwrap(), 1e5);
        assert_eq!(r("+.5").unwrap(), 0.5);
        assert_eq!(r("5.").unwrap(), 5.0);
        assert_eq!(r("-0").unwrap().to_bits(), (-0.0f64).to_bits());
        assert_eq!(r("9007199254740993").unwrap(), 9007199254740992.0);
        assert_eq!(r("1e-310").unwrap(), 1e-310);
        assert_eq!(r("1e-400").unwrap(), 0.0);
        for m in ["", ".", " ", "..", "1e", "e5", "1e+", "inf", "nan", "1,000", "- 5", "1 000", "\t1", "1\n", "x", "1x+1", "0x10", ".A", "-.a", "+."] {
            assert_eq!(r(m).unwrap().to_bits(), MISS.to_bits(), "{m:?}");
        }
        assert_eq!(r(".a").unwrap().to_bits(), miss_a().to_bits());
        assert_eq!(r(" .a ").unwrap().to_bits(), miss_a().to_bits());
        assert_eq!(r("1e400").unwrap().to_bits(), MISS.to_bits());
        assert!(r("1.0x+1").is_err());
        assert!(r("-1.8X-2").is_err());
        assert!(r("0.x").is_err());
        assert_eq!(r(".x").unwrap().to_bits(), ext_missing(MISS, b'x').to_bits());
        assert!(r("1e308").is_err());
        assert!(r("-1e308").is_err());
        assert!(r(&"1".repeat(70)).is_err());
    }

    #[test]
    fn prep_follows_destring() {
        let mut o = Vec::new();
        assert!(!prep(b" 007 ", b"", false, &mut o));
        assert_eq!(o, b"07");
        assert!(!prep(b"000", b"", false, &mut o));
        assert_eq!(o, b"0");
        assert!(prep(b"\t.b\n", b"", false, &mut o));
        assert_eq!(o, b".b");
        assert!(prep(b"$", b"$", false, &mut o));
        assert!(!prep(b"$1,000", b"$,", false, &mut o));
        assert_eq!(o, b"1000");
        assert!(!prep(b"1.234,5", b"", true, &mut o));
        assert_eq!(o, b"1X234.5");
        assert!(!prep(b"1,5", b"", true, &mut o));
        assert_eq!(o, b"1.5");
        assert!(!prep(b"1,a", b"", true, &mut o));
        assert_eq!(o, b"1,a");
        assert!(prep(b".", b"", true, &mut o));
        assert_eq!(o, b".");
    }

    #[test]
    fn float_and_compress() {
        assert_eq!(to_float(16777217.0, MISS).unwrap(), 16777216.0);
        assert_eq!(to_float(-0.0, MISS).unwrap().to_bits(), 0);
        assert_eq!(to_float(miss_a(), MISS).unwrap().to_bits(), miss_a().to_bits());
        assert!(to_float(1e39, MISS).is_err());
        assert!(to_float(1e-40, MISS).is_err());
        let range = |v: &[f64]| {
            let mut r = Range::default();
            v.iter().for_each(|&x| r.add(x, MISS));
            r
        };
        let d = Type::Double;
        assert_eq!(compress_type(d, &range(&[100.0, -127.0, MISS])), Type::Byte);
        assert_eq!(compress_type(d, &range(&[101.0])), Type::Int);
        assert_eq!(compress_type(d, &range(&[-128.0])), Type::Int);
        assert_eq!(compress_type(d, &range(&[32741.0])), Type::Long);
        assert_eq!(compress_type(d, &range(&[-2147483647.0])), Type::Long);
        assert_eq!(compress_type(d, &range(&[2147483621.0])), Type::Double);
        assert_eq!(compress_type(d, &range(&[0.5])), Type::Double);
        assert_eq!(compress_type(d, &range(&[MISS])), Type::Byte);
        assert_eq!(compress_type(Type::Float, &range(&[32741.0])), Type::Float);
        assert_eq!(compress_type(Type::Float, &range(&[-0.0, 3.0])), Type::Byte);
    }

    #[test]
    fn integer_strings() {
        let s = |v: f64, f: Fmt| {
            let mut o = Vec::new();
            int_string(v, MISS, f, &mut o).map(|_| String::from_utf8(o).unwrap())
        };
        assert_eq!(s(1234567890.0, Fmt::G(12)).unwrap(), "1234567890");
        assert!(s(12345678901.0, Fmt::G(12)).is_err());
        assert_eq!(s(-1234567890.0, Fmt::G(12)).unwrap(), "-1234567890");
        assert_eq!(s(-0.0, Fmt::G(12)).unwrap(), "0");
        assert_eq!(s(12345678.0, Fmt::F(1)).unwrap(), "12345678");
        assert!(s(-12345678.0, Fmt::F(1)).is_err());
        assert!(s(5.0, Fmt::G(3)).is_err());
        assert!(s(0.5, Fmt::G(12)).is_err());
        assert_eq!(s(MISS, Fmt::G(12)).unwrap(), ".");
        assert_eq!(s(miss_a(), Fmt::G(12)).unwrap(), ".a");
        assert_eq!(s(ext_missing(MISS, b'z'), Fmt::G(12)).unwrap(), ".z");
        assert!(s(f64::from_bits(MISS.to_bits() + 1), Fmt::G(12)).is_err());
    }
}
