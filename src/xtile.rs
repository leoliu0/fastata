//! `quant`: compute phase of fastata's xtile and pctile (slice C), and `_pctile`-style
//! percentile lists for calibration C1 (`tests/stata/calib_pctile.do`).
//!
//! Varlist: x (numeric), then the weight when `wtype` is not `none`, then the sample marker
//! (0/1, from `mark`) when `touse=1`. Keys:
//! - `phase=compute`, `threads=<n>`;
//! - `kind=xtile|pctile|plist`;
//! - `nq=<n>` (xtile, pctile; 2..), or `p=<p1>,<p2>,...` (plist; each 0 < p < 100);
//! - `wtype=none|aw|fw|pw`, `altdef=0|1`, `touse=0|1`;
//! - `float=0|1` (pctile, plist): round the percentiles to float.
//!
//! The if/in sample is the observations with a nonzero marker (all without one) and, with
//! weights, a positive nonmissing weight (`mark` drops missing and zero weights). The sample is
//! the if/in sample with nonmissing x. Percentiles follow [`crate::quant`]: `n(nq)` positions
//! for xtile and pctile, `p()` positions for plist.
//!
//! Output (one numeric column through [`cache::put`]): xtile, the category of each sample
//! observation (the smallest k with x <= q_k, or nq above every q_k: the rule of xtile.ado's
//! MakeQuan, nonunique percentiles included), missing elsewhere; pctile and plist, the k-th
//! percentile in observation k, missing elsewhere.
//!
//! Locals: `fx_token`; `fx_n0` (if/in sample size), `fx_n` (sample size), `fx_max` (xtile: the
//! largest category assigned).
//!
//! Falls back (the original then gives its error or result): a negative weight, or a noninteger
//! frequency weight, in any observation [weight values]; xtile with nq > fx_n0 + 1, an empty sample,
//! pctile/plist with more percentiles than observations [error]; both -0 and +0 in the sample
//! (`_pctile` orders them as ties) [signed zero]; a weighted percentile within the band where
//! `_pctile`'s tolerance or summation order decides [weighted tolerance].

use crate::args::Args;
use crate::cache::{self, Output, read_cols};
use crate::error::{Error, Res, vec_filled, vec_with_capacity};
use crate::io::{self, Io};
use crate::par::{StoreMode, for_blocks, resolve_threads};
use crate::quant::{Need, Pos, Weighted, need_altdef, need_default};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Xtile,
    Pctile,
    Plist,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Wtype {
    None,
    Aw,
    Fw,
    Pw,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Spec {
    pub kind: Kind,
    pub nq: usize,
    pub plist: Vec<f64>,
    pub wtype: Wtype,
    pub altdef: bool,
    pub touse: bool,
    pub float: bool,
}

impl Spec {
    fn parse(a: &Args) -> Res<Spec> {
        let kind = match a.str_req("kind")? {
            "xtile" => Kind::Xtile,
            "pctile" => Kind::Pctile,
            "plist" => Kind::Plist,
            k => return Err(Error::syntax(format!("fastata plugin: bad kind `{k}`"))),
        };
        let wtype = match a.str_opt("wtype").unwrap_or("none") {
            "none" => Wtype::None,
            "aw" => Wtype::Aw,
            "fw" => Wtype::Fw,
            "pw" => Wtype::Pw,
            w => return Err(Error::syntax(format!("fastata plugin: bad wtype `{w}`"))),
        };
        let (nq, plist) = if kind == Kind::Plist {
            let mut ps = Vec::new();
            for t in a.str_req("p")?.split(',') {
                let p: f64 = t.trim().parse().map_err(|_| Error::syntax(format!("fastata plugin: bad percentile `{t}`")))?;
                if !(p > 0.0 && p < 100.0) {
                    return Err(Error::syntax(format!("fastata plugin: bad percentile `{t}`")));
                }
                ps.push(p);
            }
            (0, ps)
        } else {
            let nq = a.usize_req("nq")?;
            if nq < 2 {
                return Err(Error::syntax("fastata plugin: nq must be at least 2"));
            }
            (nq, Vec::new())
        };
        Ok(Spec {
            kind,
            nq,
            plist,
            wtype,
            altdef: a.flag_or("altdef", false)?,
            touse: a.flag_or("touse", false)?,
            float: a.flag_or("float", false)?,
        })
    }

    fn positions(&self) -> Vec<Pos> {
        match self.kind {
            Kind::Plist => self.plist.iter().map(|&p| Pos::P(p)).collect(),
            _ => (1..self.nq).map(|k| Pos::Nq(k, self.nq)).collect(),
        }
    }
}

/// Result of the compute phase.
#[derive(Debug, PartialEq)]
pub struct Computed {
    pub col: Vec<f64>,
    pub n0: usize,
    pub n: usize,
    /// xtile: the largest category assigned; otherwise 0.
    pub max: usize,
}

pub fn run<I: Io>(io: &I, a: &Args) -> Res<()> {
    a.only(&["phase", "threads", "kind", "nq", "p", "wtype", "altdef", "touse", "float"])?;
    if a.str_req("phase")? != "compute" {
        return Err(Error::syntax("fastata plugin: quant supports phase=compute only"));
    }
    let spec = Spec::parse(a)?;
    let threads = a.usize_or("threads", 0)?;
    let r = compute(io, &spec, threads)?;
    let token = cache::put(Output { nums: vec![r.col], strs: Vec::new() });
    io::local_save("fx_n0", &r.n0.to_string())?;
    io::local_save("fx_n", &r.n.to_string())?;
    io::local_save("fx_max", &r.max.to_string())?;
    io::local_save("fx_token", &token.to_string())
}

/// Order-preserving map of a nonmissing double to u64 (-0 sorts before +0).
#[inline]
fn key(x: f64) -> u64 {
    let b = x.to_bits();
    if b >> 63 == 1 { !b } else { b | 1 << 63 }
}

#[inline]
fn unkey(k: u64) -> f64 {
    if k >> 63 == 1 { f64::from_bits(k & !(1 << 63)) } else { f64::from_bits(!k) }
}

const NEG_ZERO: u64 = !(1u64 << 63); // key(-0.0)
const POS_ZERO: u64 = 1u64 << 63; // key(+0.0)

/// What one chunk of observations contributes.
#[derive(Default)]
struct Chunk {
    n0: usize,
    /// Keys of the sample's x values: sorted (unweighted) or in observation order (weighted).
    keys: Vec<u64>,
    ws: Vec<f64>,
    neg_weight: bool,
    nonint_fw: bool,
    /// The sample has x = -0 / x = +0.
    neg_zero: bool,
    pos_zero: bool,
}

/// Rows per chunk of the gathering and category passes, at least.
const MIN_CHUNK: usize = 1 << 16;

pub fn compute<I: Io>(io: &I, spec: &Spec, threads: usize) -> Res<Computed> {
    let nobs = io.nobs();
    let miss = io.missval();
    let hasw = spec.wtype != Wtype::None;
    let nv = 1 + hasw as usize + spec.touse as usize;
    if io.nvars() != nv || (0..nv as i32).any(|v| io.is_str(v + 1)) {
        return Err(Error::syntax("fastata plugin: quant varlist does not match its options"));
    }
    let vars: Vec<i32> = (1..=nv as i32).collect();
    let cols = read_cols(io, &vars, threads)?;
    let x = &cols[0];
    let w = hasw.then(|| &cols[1]);
    let t = spec.touse.then(|| &cols[nv - 1]);
    let fw = spec.wtype == Wtype::Fw;

    // Observation i is in the if/in sample: Some(its weight) (1 without weights), else None.
    let ifin = |i: usize| -> Option<f64> {
        if t.is_some_and(|t| t[i] == 0.0) {
            return None;
        }
        match w {
            None => Some(1.0),
            Some(w) => (w[i] < miss && w[i] > 0.0).then_some(w[i]),
        }
    };

    let nchunks = resolve_threads(threads, nobs.div_ceil(MIN_CHUNK).max(1));
    let csize = nobs.div_ceil(nchunks).max(1);
    let chunks = for_blocks(io, nchunks, threads, StoreMode::Serial, |c, _emit| {
        let first = (c * csize).min(nobs);
        let last = ((c + 1) * csize).min(nobs);
        let mut ch = Chunk { keys: vec_with_capacity(last - first)?, ..Chunk::default() };
        if hasw {
            ch.ws = vec_with_capacity(last - first)?;
        }
        for i in first..last {
            if let Some(w) = w {
                let wi = w[i];
                if wi < miss {
                    ch.neg_weight |= wi < 0.0;
                    ch.nonint_fw |= fw && wi.fract() != 0.0;
                }
            }
            let Some(wi) = ifin(i) else { continue };
            ch.n0 += 1;
            if x[i] < miss {
                let k = key(x[i]);
                ch.neg_zero |= k == NEG_ZERO;
                ch.pos_zero |= k == POS_ZERO;
                ch.keys.push(k);
                if hasw {
                    ch.ws.push(wi);
                }
            }
        }
        if !hasw {
            ch.keys.sort_unstable();
        }
        Ok(ch)
    })?;

    if chunks.iter().any(|c| c.neg_weight || c.nonint_fw) {
        return Err(Error::fallback("weight values"));
    }
    let n0: usize = chunks.iter().map(|c| c.n0).sum();
    let n: usize = chunks.iter().map(|c| c.keys.len()).sum();
    let positions = spec.positions();
    if n == 0
        || (spec.kind == Kind::Xtile && spec.nq > n0 + 1)
        || (spec.kind != Kind::Xtile && positions.len() > nobs)
    {
        return Err(Error::fallback("error"));
    }
    if chunks.iter().any(|c| c.neg_zero) && chunks.iter().any(|c| c.pos_zero) {
        return Err(Error::fallback("signed zero"));
    }

    let qs = if hasw { weighted_pctiles(&chunks, &positions)? } else { unweighted_pctiles(&chunks, n, spec, &positions) };

    match spec.kind {
        Kind::Xtile => {
            let parts = for_blocks(io, nchunks, threads, StoreMode::Serial, |c, _emit| {
                let first = (c * csize).min(nobs);
                let last = ((c + 1) * csize).min(nobs);
                let mut out = vec_with_capacity(last - first)?;
                let mut max = 0usize;
                for i in first..last {
                    if ifin(i).is_some() && x[i] < miss {
                        let k = qs.partition_point(|&q| q < x[i]) + 1;
                        max = max.max(k);
                        out.push(k as f64);
                    } else {
                        out.push(f64::NAN);
                    }
                }
                Ok((out, max))
            })?;
            let mut col = vec_with_capacity(nobs)?;
            let mut max = 0;
            for (p, m) in parts {
                col.extend_from_slice(&p);
                max = max.max(m);
            }
            Ok(Computed { col, n0, n, max })
        }
        Kind::Pctile | Kind::Plist => {
            let mut col = vec_filled(nobs, f64::NAN)?;
            for (k, q) in qs.iter().enumerate() {
                col[k] = if spec.float { *q as f32 as f64 } else { *q };
            }
            Ok(Computed { col, n0, n, max: 0 })
        }
    }
}

/// The r-th smallest key (1-based) across sorted chunks.
fn kth(chunks: &[Chunk], r: usize) -> u64 {
    let count_le = |v: u64| chunks.iter().map(|c| c.keys.partition_point(|&k| k <= v)).sum::<usize>();
    let (mut lo, mut hi) = (0u64, u64::MAX);
    while lo < hi {
        let mid = lo + (hi - lo) / 2;
        if count_le(mid) >= r { hi = mid } else { lo = mid + 1 }
    }
    lo
}

fn unweighted_pctiles(chunks: &[Chunk], n: usize, spec: &Spec, positions: &[Pos]) -> Vec<f64> {
    let needs: Vec<Need> =
        positions.iter().map(|&p| if spec.altdef { need_altdef(n, p) } else { need_default(n, p) }).collect();
    let mut ranks: Vec<usize> = needs
        .iter()
        .flat_map(|nd| {
            let (a, b) = nd.ranks();
            std::iter::once(a).chain(b)
        })
        .collect();
    ranks.sort_unstable();
    ranks.dedup();
    let vals: Vec<f64> = ranks.iter().map(|&r| unkey(kth(chunks, r))).collect();
    let at = |r: usize| vals[ranks.binary_search(&r).expect("rank was selected")];
    needs.iter().map(|nd| nd.value(at)).collect()
}

fn weighted_pctiles(chunks: &[Chunk], positions: &[Pos]) -> Res<Vec<f64>> {
    let n: usize = chunks.iter().map(|c| c.keys.len()).sum();
    let mut pairs: Vec<(u64, f64)> = vec_with_capacity(n)?;
    for c in chunks {
        pairs.extend(c.keys.iter().copied().zip(c.ws.iter().copied()));
    }
    // Stable: ties stay in observation order.
    pairs.sort_by_key(|p| p.0);
    let mut xs = vec_with_capacity(n)?;
    let mut ws = vec_with_capacity(n)?;
    for (k, w) in pairs {
        xs.push(unkey(k));
        ws.push(w);
    }
    let t = Weighted::new(&xs, &ws);
    positions.iter().map(|&p| t.pctile(p).ok_or_else(|| Error::fallback("weighted tolerance"))).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::{MISS, MemIo};
    use crate::quant::{pctile_altdef, pctile_altdef_nq, pctile_nq};
    use crate::testutil::{Rng, miss_a};

    struct Data {
        x: Vec<f64>,
        w: Option<Vec<f64>>,
        t: Option<Vec<f64>>,
    }

    fn memio(d: &Data) -> MemIo {
        let mut io = MemIo::new(d.x.len());
        let c = io.add_num(&d.x);
        io.push_var(c);
        if let Some(w) = &d.w {
            let c = io.add_num(w);
            io.push_var(c);
        }
        if let Some(t) = &d.t {
            let c = io.add_num(t);
            io.push_var(c);
        }
        io
    }

    fn spec(kind: Kind, nq: usize, wtype: Wtype, altdef: bool, touse: bool) -> Spec {
        Spec { kind, nq, plist: Vec::new(), wtype, altdef, touse, float: false }
    }

    /// Naive reference: the sample sorted by x (stable), then the quant functions; or the
    /// fallback reason compute must give.
    fn reference(d: &Data, s: &Spec) -> Result<(Vec<f64>, usize), &'static str> {
        let n = d.x.len();
        let mut samp: Vec<(f64, f64)> = Vec::new();
        let mut n0 = 0;
        let inn = |i: usize| {
            d.t.as_ref().is_none_or(|t| t[i] != 0.0) && d.w.as_ref().is_none_or(|w| w[i] < MISS && w[i] > 0.0)
        };
        for i in 0..n {
            if inn(i) {
                n0 += 1;
                if d.x[i] < MISS {
                    samp.push((d.x[i], d.w.as_ref().map_or(1.0, |w| w[i])));
                }
            }
        }
        if samp.is_empty() || (s.kind == Kind::Xtile && s.nq > n0 + 1) || (s.kind == Kind::Pctile && s.nq - 1 > n) {
            return Err("error");
        }
        samp.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap());
        let xs: Vec<f64> = samp.iter().map(|p| p.0).collect();
        let ws: Vec<f64> = samp.iter().map(|p| p.1).collect();
        let qs: Vec<f64> = if d.w.is_some() {
            let t = Weighted::new(&xs, &ws);
            (1..s.nq).map(|k| t.pctile(Pos::Nq(k, s.nq))).collect::<Option<Vec<_>>>().ok_or("weighted tolerance")?
        } else if s.altdef {
            (1..s.nq).map(|k| pctile_altdef_nq(&xs, k, s.nq)).collect()
        } else {
            (1..s.nq).map(|k| pctile_nq(&xs, k, s.nq)).collect()
        };
        match s.kind {
            Kind::Xtile => {
                let col = (0..n)
                    .map(|i| {
                        if !inn(i) || d.x[i] >= MISS {
                            return f64::NAN;
                        }
                        (1..s.nq).find(|&k| d.x[i] <= qs[k - 1]).unwrap_or(s.nq) as f64
                    })
                    .collect();
                Ok((col, n0))
            }
            _ => {
                let mut col = vec![f64::NAN; n];
                col[..qs.len()].copy_from_slice(&qs);
                Ok((col, n0))
            }
        }
    }

    fn same(a: &[f64], b: &[f64]) -> bool {
        a.len() == b.len() && a.iter().zip(b).all(|(x, y)| x.to_bits() == y.to_bits() || (x.is_nan() && y.is_nan()))
    }

    fn data(n: usize, seed: u64, ties: bool, weights: Option<Wtype>, touse: bool) -> Data {
        let mut r = Rng::new(seed);
        let x = (0..n)
            .map(|_| {
                let u = r.unif();
                if u < 0.03 {
                    MISS
                } else if u < 0.04 {
                    miss_a()
                } else if ties {
                    (r.unif() * 20.0).floor() - 5.0
                } else {
                    r.unif() * 100.0 - 30.0
                }
            })
            .collect();
        let w = weights.map(|wt| {
            (0..n)
                .map(|_| {
                    let u = r.unif();
                    if u < 0.02 {
                        MISS
                    } else if u < 0.03 {
                        0.0
                    } else if wt == Wtype::Fw {
                        (r.unif() * 5.0).floor() + 1.0
                    } else {
                        r.unif() + 0.1
                    }
                })
                .collect()
        });
        let t = touse.then(|| (0..n).map(|_| if r.unif() < 0.7 { 1.0 } else { 0.0 }).collect());
        Data { x, w, t }
    }

    #[test]
    fn matches_the_reference_for_every_thread_count() {
        let sizes = [1usize, 2, 3, 7, 100, 1000, MIN_CHUNK - 1, MIN_CHUNK + 1, 3 * MIN_CHUNK + 17];
        let mut seed = 1;
        for &n in &sizes {
            for ties in [false, true] {
                for wt in [None, Some(Wtype::Aw), Some(Wtype::Fw)] {
                    for touse in [false, true] {
                        for (kind, nq, altdef) in [
                            (Kind::Xtile, 2, false),
                            (Kind::Xtile, 10, false),
                            (Kind::Xtile, 7, true),
                            (Kind::Pctile, 4, false),
                            (Kind::Pctile, 3, true),
                        ] {
                            if altdef && wt.is_some() {
                                continue;
                            }
                            seed += 1;
                            let d = data(n, seed, ties, wt, touse);
                            let io = memio(&d);
                            let s = spec(kind, nq, wt.unwrap_or(Wtype::None), altdef, touse);
                            let want = reference(&d, &s);
                            let mut first: Option<Res<Computed>> = None;
                            for threads in [1, 4, 7] {
                                let got = compute(&io, &s, threads);
                                match (&want, &got) {
                                    (Ok((col, n0)), Ok(c)) => {
                                        assert!(same(&c.col, col), "n={n} ties={ties} {s:?} threads={threads}");
                                        assert_eq!(c.n0, *n0);
                                    }
                                    (Err(why), Err(e)) => assert!(e.is_fallback() && e.msg == *why, "{e:?} vs {why}"),
                                    _ => panic!("n={n} {s:?}: reference {:?} vs compute {:?}", want.as_ref().err(), got.as_ref().err()),
                                }
                                if let Some(f) = &first {
                                    match (f, &got) {
                                        (Ok(a), Ok(b)) => assert!(same(&a.col, &b.col) && a.max == b.max),
                                        (Err(a), Err(b)) => assert_eq!(a, b),
                                        _ => panic!("thread counts disagree: {s:?}"),
                                    }
                                } else {
                                    first = Some(got);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn xtile_categories_with_known_values() {
        // x = 1..10, nq = 4: q = 3, 5.5, 8 (n*k/nq = 2.5, 5, 7.5).
        let d = Data { x: (1..=10).map(f64::from).collect(), w: None, t: None };
        let c = compute(&memio(&d), &spec(Kind::Xtile, 4, Wtype::None, false, false), 2).unwrap();
        assert_eq!(c.col, vec![1.0, 1.0, 1.0, 2.0, 2.0, 3.0, 3.0, 3.0, 4.0, 4.0]);
        assert_eq!((c.n0, c.n, c.max), (10, 10, 4));
        // Nonunique percentiles: the smallest k with x <= q_k (x = 1,1,1,1,2: q = 1,1,1,1.5).
        let d = Data { x: vec![1.0, 1.0, 2.0, 1.0, 1.0], w: None, t: None };
        let c = compute(&memio(&d), &spec(Kind::Xtile, 5, Wtype::None, false, false), 1).unwrap();
        assert_eq!(c.col, vec![1.0, 1.0, 5.0, 1.0, 1.0]);
        assert_eq!(c.max, 5);
    }

    #[test]
    fn pctile_puts_percentiles_in_the_first_observations_and_rounds_to_float() {
        let d = Data { x: vec![0.1, 0.2, 0.3, 0.4, 0.5, MISS], w: None, t: None };
        let mut s = spec(Kind::Pctile, 4, Wtype::None, false, false);
        let c = compute(&memio(&d), &s, 1).unwrap();
        assert_eq!(&c.col[..3], &[0.2, 0.3, 0.4]);
        assert!(c.col[3..].iter().all(|v| v.is_nan()));
        s.float = true;
        let c = compute(&memio(&d), &s, 1).unwrap();
        assert_eq!(c.col[0], 0.2f32 as f64);
        let xs = [0.1, 0.2, 0.3, 0.4, 0.5];
        let s = Spec { kind: Kind::Plist, plist: vec![10.0, 50.0, 90.0], ..spec(Kind::Plist, 0, Wtype::None, true, false) };
        let c = compute(&memio(&d), &s, 1).unwrap();
        assert_eq!(&c.col[..3], &[pctile_altdef(&xs, 10.0), pctile_altdef(&xs, 50.0), pctile_altdef(&xs, 90.0)]);
    }

    #[test]
    fn fallbacks() {
        let fb = |d: &Data, s: &Spec| compute(&memio(d), s, 2).map(|_| ()).unwrap_err();
        let x: Vec<f64> = (1..=10).map(f64::from).collect();
        // Negative weight anywhere, noninteger frequency weight.
        let mut w = vec![1.0; 10];
        w[9] = -1.0;
        let d = Data { x: x.clone(), w: Some(w.clone()), t: Some(vec![1.0; 10]) };
        assert_eq!(fb(&d, &spec(Kind::Xtile, 2, Wtype::Aw, false, true)).msg, "weight values");
        w[9] = 1.5;
        let d = Data { x: x.clone(), w: Some(w), t: None };
        assert_eq!(fb(&d, &spec(Kind::Xtile, 2, Wtype::Fw, false, false)).msg, "weight values");
        assert!(compute(&memio(&d), &spec(Kind::Xtile, 2, Wtype::Aw, false, false), 1).is_ok());
        // nq > n0 + 1; no nonmissing x.
        let d = Data { x: x.clone(), w: None, t: None };
        assert_eq!(fb(&d, &spec(Kind::Xtile, 12, Wtype::None, false, false)).msg, "error");
        assert!(compute(&memio(&d), &spec(Kind::Xtile, 11, Wtype::None, false, false), 1).is_ok());
        let d = Data { x: vec![MISS; 4], w: None, t: None };
        assert_eq!(fb(&d, &spec(Kind::Pctile, 2, Wtype::None, false, false)).msg, "error");
        // -0 and +0 together.
        let d = Data { x: vec![-0.0, 0.0, 1.0], w: None, t: None };
        assert_eq!(fb(&d, &spec(Kind::Pctile, 2, Wtype::None, false, false)).msg, "signed zero");
        let d = Data { x: vec![-0.0, -0.0, 1.0], w: None, t: None };
        let c = compute(&memio(&d), &spec(Kind::Pctile, 2, Wtype::None, false, false), 1).unwrap();
        assert_eq!(c.col[0].to_bits(), (-0.0f64).to_bits());
    }

    #[test]
    fn keys_preserve_order() {
        let v = [-1e300, -2.5, -1e-300, -0.0, 0.0, 1e-300, 3.0, 1e300];
        for w in v.windows(2) {
            assert!(key(w[0]) < key(w[1]));
        }
        for x in v {
            assert_eq!(unkey(key(x)).to_bits(), x.to_bits());
        }
        assert_eq!(key(-0.0), NEG_ZERO);
        assert_eq!(key(0.0), POS_ZERO);
    }
}
