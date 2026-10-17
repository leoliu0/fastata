//! egen compute phase against naive references through `MemIo`, for 1 and 4 threads (results
//! must be bitwise identical), over block-crossing group sizes, missing codes, string keys and
//! samples.

use std::collections::BTreeMap;

use super::spec::{Fcn, RankMode, Spec, Ty};
use super::*;
use crate::io::{MISS, MemIo};
use crate::testutil::{Rng, miss_a};

const N: usize = 40_000;

struct Data {
    io: MemIo,
    /// Varlist positions: g (numeric key, unsorted), gs (sorted key, runs crossing blocks),
    /// s (string key), x (values with . and .a), y (integers), t (sample marker).
    g: i32,
    gs: i32,
    s: i32,
    x: i32,
    y: i32,
    t: i32,
    gv: Vec<f64>,
    gsv: Vec<f64>,
    sv: Vec<Vec<u8>>,
    xv: Vec<f64>,
    yv: Vec<f64>,
    tv: Vec<bool>,
}

fn data() -> Data {
    let mut rng = Rng::new(11);
    let mut gv = Vec::with_capacity(N);
    let mut gsv = Vec::with_capacity(N);
    let mut sv = Vec::with_capacity(N);
    let mut xv = Vec::with_capacity(N);
    let mut yv = Vec::with_capacity(N);
    let mut tv = Vec::with_capacity(N);
    let runs = [1usize, 2, 8191, 8192, 8193, 3, 17000];
    let (mut run, mut left, mut key) = (0, runs[0], 1.0);
    for i in 0..N {
        let u = rng.unif();
        gv.push(if u < 0.02 { MISS } else if u < 0.03 { miss_a() } else if u < 0.04 { -0.0 } else { (rng.next_u64() % 60) as f64 });
        if left == 0 {
            run = (run + 1) % runs.len();
            left = runs[run];
            key += 1.0;
        }
        left -= 1;
        gsv.push(key);
        let k = rng.next_u64() % 30;
        sv.push(if k == 0 { Vec::new() } else { format!("s{k}").into_bytes() });
        let u = rng.unif();
        xv.push(if u < 0.05 { MISS } else if u < 0.07 { miss_a() } else if u < 0.2 { ((rng.next_u64() % 9) as f64) - 4.0 } else { (rng.unif() - 0.3) * 1e3 });
        yv.push(if rng.unif() < 0.05 { MISS } else { (rng.next_u64() % 50) as f64 });
        tv.push(i % 7 != 3 && i != 5);
        let _ = i;
    }
    let mut io = MemIo::new(N);
    let cg = io.add_num(&gv);
    let cgs = io.add_num(&gsv);
    let cs = io.add_str(sv.clone());
    let cx = io.add_num(&xv);
    let cy = io.add_num(&yv);
    let ct = io.add_num(&tv.iter().map(|&b| f64::from(u8::from(b))).collect::<Vec<_>>());
    let g = io.push_var(cg);
    let gs = io.push_var(cgs);
    let s = io.push_var(cs);
    let x = io.push_var(cx);
    let y = io.push_var(cy);
    let t = io.push_var(ct);
    Data { io, g, gs, s, x, y, t, gv, gsv, sv, xv, yv, tv }
}

fn spec(fcn: Fcn, ty: Ty, keys: Vec<i32>, vals: Vec<i32>, touse: Option<i32>) -> Spec {
    Spec {
        fcn,
        ty,
        keys,
        sorted: false,
        vals,
        touse,
        missing: false,
        cntflag: false,
        p: 50.0,
        mean: 0.0,
        sd: 1.0,
        rank: RankMode::Default,
        threads: 1,
    }
}

/// Runs `s` with 1 and 4 threads; the results must be bitwise identical.
fn run2(d: &Data, s: &Spec) -> Res<Vec<f64>> {
    let a = compute(&d.io, &Spec { threads: 1, ..s.clone() })?;
    let b = compute(&d.io, &Spec { threads: 4, ..s.clone() })?;
    let ba: Vec<u64> = a.out.iter().map(|v| v.to_bits()).collect();
    let bb: Vec<u64> = b.out.iter().map(|v| v.to_bits()).collect();
    assert!(ba == bb, "{:?}: 1 vs 4 threads differ", s.fcn);
    assert_eq!(a.nmiss, a.out.iter().filter(|&&v| v >= MISS).count());
    Ok(a.out)
}

fn assert_bits(got: &[f64], want: &[f64], what: &str) {
    for i in 0..got.len() {
        assert!(got[i].to_bits() == want[i].to_bits(), "{what}: obs {i}: got {} want {}", got[i], want[i]);
    }
}

fn canon(v: f64) -> u64 {
    if v == 0.0 { 0 } else { v.to_bits() }
}

/// Sample observations per group key (numeric key `k`, or none), ascending.
fn naive_groups(keys: Option<&[f64]>, touse: Option<&[bool]>) -> BTreeMap<u64, Vec<usize>> {
    let mut m: BTreeMap<u64, Vec<usize>> = BTreeMap::new();
    for i in 0..N {
        if touse.is_some_and(|t| !t[i]) {
            continue;
        }
        m.entry(keys.map_or(0, |k| canon(k[i]))).or_default().push(i);
    }
    m
}

fn f32r(v: f64) -> f64 {
    if v >= MISS { v } else { f64::from(v as f32) }
}

/// Naive group value of the simple reductions (by-group arithmetic: sequential sums).
fn naive_value(fcn: Fcn, xs: &[f64]) -> f64 {
    let nm: Vec<f64> = xs.iter().copied().filter(|&v| v < MISS).collect();
    let n = nm.len() as f64;
    let mut s = 0.0;
    for v in &nm {
        s += v;
    }
    match fcn {
        Fcn::Total => s,
        Fcn::Mean => {
            if nm.is_empty() {
                MISS
            } else {
                s / n
            }
        }
        Fcn::Count => n,
        Fcn::Max => nm.iter().copied().fold(MISS, |a, v| if a >= MISS || v > a { v } else { a }),
        Fcn::Min => nm.iter().copied().fold(MISS, |a, v| if v < a { v } else { a }),
        Fcn::Sd => {
            if nm.len() < 2 {
                return MISS;
            }
            let m = s / n;
            let mut q = 0.0;
            for v in &nm {
                q += (v - m) * (v - m);
            }
            (q / (n - 1.0)).sqrt()
        }
        Fcn::Median => {
            let mut v = nm.clone();
            v.sort_by(|a, b| a.partial_cmp(b).unwrap());
            if v.is_empty() {
                MISS
            } else if v.len() % 2 == 1 {
                v[v.len() / 2]
            } else {
                (v[v.len() / 2 - 1] + v[v.len() / 2]) / 2.0
            }
        }
        _ => unreachable!(),
    }
}

#[test]
fn by_group_reductions_match_naive_for_hash_and_sorted_groups() {
    let d = data();
    for fcn in [Fcn::Total, Fcn::Mean, Fcn::Count, Fcn::Max, Fcn::Min, Fcn::Sd, Fcn::Median] {
        for (key, kv, sorted) in [(d.g, &d.gv, false), (d.gs, &d.gsv, true), (d.gs, &d.gsv, false)] {
            for touse in [None, Some(d.t)] {
                let tv = touse.map(|_| &d.tv[..]);
                let mut sp = spec(fcn, Ty::Double, vec![key], vec![d.x], touse);
                sp.sorted = sorted;
                let got = run2(&d, &sp).unwrap();
                let mut want = vec![MISS; N];
                for (_, members) in naive_groups(Some(kv), tv) {
                    let xs: Vec<f64> = members.iter().map(|&o| d.xv[o]).collect();
                    let v = naive_value(fcn, &xs);
                    for &o in &members {
                        want[o] = v;
                    }
                }
                assert_bits(&got, &want, &format!("{fcn:?} sorted={sorted} touse={touse:?}"));
            }
        }
    }
}

#[test]
fn string_keys_group_like_numeric_ones() {
    let d = data();
    let got = run2(&d, &spec(Fcn::Count, Ty::Double, vec![d.s], vec![d.x], Some(d.t))).unwrap();
    let mut m: BTreeMap<Vec<u8>, f64> = BTreeMap::new();
    for i in 0..N {
        if d.tv[i] && d.xv[i] < MISS {
            *m.entry(d.sv[i].clone()).or_default() += 1.0;
        }
    }
    for i in 0..N {
        let want = if d.tv[i] { m.get(&d.sv[i]).copied().unwrap_or(0.0) } else { MISS };
        assert_eq!(got[i], want, "obs {i}");
    }
}

#[test]
fn no_by_uses_summarize_arithmetic_and_float_rounding() {
    let d = data();
    let got = run2(&d, &spec(Fcn::Total, Ty::Float, vec![], vec![d.x], Some(d.t))).unwrap();
    let want = f32r(reduce::neumaier((0..N).filter(|&i| d.tv[i] && d.xv[i] < MISS).map(|i| d.xv[i])));
    for i in 0..N {
        assert_eq!(got[i], if d.tv[i] { want } else { MISS });
    }
    let mut sp = spec(Fcn::Pctile, Ty::Double, vec![], vec![d.x], None);
    sp.p = 33.3;
    let c = compute(&d.io, &sp).unwrap();
    let mut v: Vec<f64> = d.xv.iter().copied().filter(|&x| x < MISS).collect();
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    assert_eq!(c.out[0], crate::quant::pctile(&v, 33.3));
    assert_eq!(c.n, Some(v.len()));
}

#[test]
fn ranks_match_counting_reference() {
    let d = data();
    for mode in [RankMode::Default, RankMode::Field, RankMode::Track] {
        let mut sp = spec(Fcn::Rank, Ty::Float, vec![d.g], vec![d.y], Some(d.t));
        sp.rank = mode;
        let got = run2(&d, &sp).unwrap();
        let groups = naive_groups(Some(&d.gv), Some(&d.tv));
        let mut want = vec![MISS; N];
        for members in groups.values() {
            for &o in members {
                let v = d.yv[o];
                if v >= MISS {
                    continue;
                }
                let vals = members.iter().map(|&j| d.yv[j]).filter(|&w| w < MISS);
                let less = vals.clone().filter(|&w| if mode == RankMode::Field { w > v } else { w < v }).count();
                let ties = vals.filter(|&w| w == v).count();
                let lo = f32r(less as f64 + 1.0);
                want[o] = if mode == RankMode::Default { f32r(lo + (ties as f64 - 1.0) / 2.0) } else { lo };
            }
        }
        assert_bits(&got, &want, &format!("rank {mode:?}"));
    }
}

#[test]
fn group_and_tag_follow_stata_sort_order() {
    let d = data();
    for missing in [false, true] {
        let mut sp = spec(Fcn::Group, Ty::Double, vec![d.g, d.s], vec![], Some(d.t));
        sp.missing = missing;
        let got = run2(&d, &sp).unwrap();
        // Stata order: numeric ascending (missing codes last), then strings bytewise.
        let mut keys: BTreeMap<(u64, Vec<u8>), usize> = BTreeMap::new();
        let ord = |v: f64| -> u64 {
            // order-preserving map of nonnegative-and-negative doubles to u64
            let b = (if v == 0.0 { 0.0 } else { v }).to_bits();
            if b >> 63 == 1 { !b } else { b | (1 << 63) }
        };
        let incl = |i: usize| d.tv[i] && (missing || (d.gv[i] < MISS && !d.sv[i].is_empty()));
        for i in 0..N {
            if incl(i) {
                keys.insert((ord(d.gv[i]), d.sv[i].clone()), 0);
            }
        }
        for (k, (_, v)) in keys.iter_mut().enumerate() {
            *v = k + 1;
        }
        let mut first = std::collections::HashSet::new();
        let mut tagw = vec![0.0; N];
        for i in 0..N {
            let want = if incl(i) { keys[&(ord(d.gv[i]), d.sv[i].clone())] as f64 } else { MISS };
            assert_eq!(got[i], want, "group missing={missing} obs {i}");
            if incl(i) && first.insert((ord(d.gv[i]), d.sv[i].clone())) {
                tagw[i] = 1.0;
            }
        }
        let mut sp = spec(Fcn::Tag, Ty::Float, vec![d.g, d.s], vec![], Some(d.t));
        sp.missing = missing;
        let got = run2(&d, &sp).unwrap();
        assert_bits(&got, &tagw, "tag");
    }
}

#[test]
fn integer_types_must_fit() {
    let d = data();
    let r = compute(&d.io, &spec(Fcn::Mean, Ty::Int, vec![d.g], vec![d.x], None));
    assert!(r.err().is_some_and(|e| e.is_fallback() && e.msg == "type fit"));
    let ok = run2(&d, &spec(Fcn::Count, Ty::Byte, vec![d.gs], vec![d.y], None));
    assert!(ok.err().is_some_and(|e| e.msg == "type fit"), "runs of 8192 exceed byte");
    run2(&d, &spec(Fcn::Max, Ty::Byte, vec![d.g], vec![d.y], None)).unwrap();
}

#[test]
fn row_functions_match_naive() {
    let d = data();
    for fcn in [Fcn::RowTotal, Fcn::RowMean, Fcn::RowMax, Fcn::RowMin, Fcn::RowSd, Fcn::RowMiss, Fcn::RowNonmiss] {
        let vals = if matches!(fcn, Fcn::RowMiss | Fcn::RowNonmiss) { vec![d.x, d.s, d.y] } else { vec![d.x, d.y, d.x] };
        let got = run2(&d, &spec(fcn, Ty::Double, vec![], vals, Some(d.t))).unwrap();
        for i in 0..N {
            let want = if !d.tv[i] {
                MISS
            } else {
                let (x, y) = (d.xv[i], d.yv[i]);
                let nm: Vec<f64> = [x, y, x].into_iter().filter(|&v| v < MISS).collect();
                match fcn {
                    Fcn::RowTotal => nm.iter().fold(0.0, |a, v| a + v),
                    Fcn::RowMean => {
                        if nm.is_empty() {
                            MISS
                        } else {
                            nm.iter().fold(0.0, |a, v| a + v) / nm.len() as f64
                        }
                    }
                    Fcn::RowMax => {
                        if nm.is_empty() {
                            x
                        } else {
                            nm.iter().copied().fold(f64::MIN, f64::max)
                        }
                    }
                    Fcn::RowMin => nm.iter().copied().fold(MISS, f64::min),
                    Fcn::RowSd => {
                        if nm.len() < 2 {
                            MISS
                        } else {
                            let m = nm.iter().fold(0.0, |a, v| a + v) / nm.len() as f64;
                            let q = [x, y, x].iter().fold(0.0, |a, &v| a + if v < MISS { (v - m) * (v - m) } else { 0.0 });
                            (q / (nm.len() - 1) as f64).sqrt()
                        }
                    }
                    Fcn::RowMiss => [x >= MISS, d.sv[i].is_empty(), y >= MISS].iter().filter(|&&b| b).count() as f64,
                    _ => [x < MISS, !d.sv[i].is_empty(), y < MISS].iter().filter(|&&b| b).count() as f64,
                }
            };
            assert_eq!(got[i].to_bits(), want.to_bits(), "{fcn:?} obs {i}: got {} want {}", got[i], want);
        }
    }
}

#[test]
fn std_and_extremes_with_missing_option() {
    let d = data();
    let mut sp = spec(Fcn::Std, Ty::Double, vec![d.g], vec![d.x], None);
    sp.mean = 1.5;
    sp.sd = 2.0;
    let got = run2(&d, &sp).unwrap();
    for members in naive_groups(Some(&d.gv), None).values() {
        let xs: Vec<f64> = members.iter().map(|&o| d.xv[o]).collect();
        let (m, s) = reduce::mean_sd(&xs, MISS, true).unwrap();
        for &o in members {
            let x = d.xv[o];
            let want = if x >= MISS || s >= MISS { MISS } else { spec::arith(2.0 * ((x - m) / s) + 1.5, MISS) };
            assert_eq!(got[o].to_bits(), want.to_bits());
        }
    }
    let mut sp = spec(Fcn::Max, Ty::Float, vec![d.g], vec![d.x], None);
    sp.missing = true;
    let got = run2(&d, &sp).unwrap();
    for members in naive_groups(Some(&d.gv), None).values() {
        let w = members.iter().map(|&o| d.xv[o]).fold(f64::MIN, f64::max);
        for &o in members {
            assert_eq!(got[o].to_bits(), f32r(w).to_bits());
        }
    }
}

#[test]
fn a_nan_in_a_key_or_a_value_falls_back() {
    let nan = crate::testutil::stata_nan();
    let mut io = MemIo::new(N);
    let mut g: Vec<f64> = (0..N).map(|i| (i % 5) as f64).collect();
    let mut x: Vec<f64> = (0..N).map(|i| i as f64).collect();
    x[N - 3] = nan;
    let cg = io.add_num(&g);
    let cx = io.add_num(&x);
    g[17] = nan;
    let cg2 = io.add_num(&g);
    let (pg, px, pg2) = (io.push_var(cg), io.push_var(cx), io.push_var(cg2));
    let is_nan_fb = |r: Res<Computed>| r.err().is_some_and(|e| e.is_fallback() && e.msg == "NaN value");
    assert!(is_nan_fb(compute(&io, &spec(Fcn::Mean, Ty::Double, vec![pg], vec![px], None))));
    assert!(is_nan_fb(compute(&io, &spec(Fcn::RowTotal, Ty::Double, vec![], vec![pg, px], None))));
    assert!(is_nan_fb(compute(&io, &spec(Fcn::Group, Ty::Double, vec![pg2], vec![], None))));
    let mut sp = spec(Fcn::Count, Ty::Double, vec![pg2], vec![pg], None);
    sp.sorted = true;
    assert!(is_nan_fb(compute(&io, &sp)));
    // A NaN in a variable the call does not use changes nothing.
    compute(&io, &spec(Fcn::Tag, Ty::Byte, vec![pg], vec![], None)).unwrap();
}

#[test]
fn signed_zeros() {
    // x: +0 then -0 in each of the two groups of key k (sorted)
    let (p, m) = (0.0_f64, -0.0_f64);
    let xv = vec![p, m, 3.0, p, m, MISS];
    let kv = vec![1.0, 1.0, 1.0, 2.0, 2.0, 2.0];
    let mut io = MemIo::new(xv.len());
    let (cx, ck) = (io.add_num(&xv), io.add_num(&kv));
    let (x, k) = (io.push_var(cx), io.push_var(ck));
    // median, pctile and iqr without by-groups fall back; with by-groups they run
    for fcn in [Fcn::Median, Fcn::Pctile, Fcn::Iqr] {
        let r = compute(&io, &spec(fcn, Ty::Double, vec![], vec![x], None));
        assert!(r.err().is_some_and(|e| e.is_fallback() && e.msg == "signed zero"), "{fcn:?}");
        compute(&io, &spec(fcn, Ty::Double, vec![k], vec![x], None)).unwrap();
    }
    // min: summarize keeps the first of -0 and +0 (no by-groups), _gmin the last (by-groups,
    // missing)
    let neg = |v: f64| v.is_sign_negative();
    let nob = compute(&io, &spec(Fcn::Min, Ty::Double, vec![], vec![x], None)).unwrap().out;
    assert!(!neg(nob[0]));
    let by = compute(&io, &Spec { sorted: true, ..spec(Fcn::Min, Ty::Double, vec![k], vec![x], None) }).unwrap().out;
    assert!(neg(by[0]) && neg(by[3]));
    let mis = compute(&io, &Spec { missing: true, ..spec(Fcn::Min, Ty::Double, vec![], vec![x], None) }).unwrap().out;
    assert!(neg(mis[0]));
}

/// Lowest rank and ties of each value among the nonmissing ones: runs of equal values in a
/// sorted index.
fn naive_ranks(xs: &[f64], mode: RankMode, ty: Ty) -> Vec<f64> {
    let mut idx: Vec<usize> = (0..xs.len()).filter(|&i| xs[i] < MISS).collect();
    idx.sort_by(|&a, &b| {
        let o = xs[a].partial_cmp(&xs[b]).unwrap();
        if mode == RankMode::Field { o.reverse() } else { o }
    });
    let mut out = vec![MISS; xs.len()];
    let mut i = 0;
    while i < idx.len() {
        let mut j = i + 1;
        while j < idx.len() && xs[idx[j]] == xs[idx[i]] {
            j += 1;
        }
        let lo = ty.cast((i + 1) as f64, MISS).unwrap();
        let r = if mode == RankMode::Default { ty.cast(lo + ((j - i) as f64 - 1.0) / 2.0, MISS).unwrap() } else { lo };
        for &k in &idx[i..j] {
            out[k] = r;
        }
        i = j;
    }
    out
}

/// rank() of groups of at least `rank::BIG` observations (the parallel sample sort): without
/// by-groups, and a large by-group next to small ones; ties, -0/+0, missing codes, a sample.
#[test]
fn large_group_ranks_match_counting_reference() {
    let n = rank::BIG + 70_001;
    let mut rng = Rng::new(5);
    let xv: Vec<f64> = (0..n)
        .map(|i| {
            let u = rng.unif();
            if u < 0.03 {
                MISS
            } else if u < 0.04 {
                miss_a()
            } else if u < 0.06 {
                if i % 2 == 0 { -0.0 } else { 0.0 }
            } else if u < 0.5 {
                ((rng.next_u64() % 2000) as f64) - 1000.0
            } else {
                (rng.unif() - 0.5) * 1e6
            }
        })
        .collect();
    // key: group 1 holds 3 of every 4 observations; the others form small groups
    let gv: Vec<f64> = (0..n).map(|i| if i % 4 != 0 { 1.0 } else { 2.0 + (i % 400) as f64 }).collect();
    let tv: Vec<bool> = (0..n).map(|i| i % 11 != 0).collect();
    let mut io = MemIo::new(n);
    let (cx, cg) = (io.add_num(&xv), io.add_num(&gv));
    let ct = io.add_num(&tv.iter().map(|&b| f64::from(u8::from(b))).collect::<Vec<_>>());
    let (g, x, t) = (io.push_var(cg), io.push_var(cx), io.push_var(ct));
    for mode in [RankMode::Default, RankMode::Field, RankMode::Track] {
        for (keys, touse) in [(vec![], None), (vec![], Some(t)), (vec![g], Some(t))] {
            let mut want = vec![MISS; n];
            let mut grp: BTreeMap<u64, Vec<usize>> = BTreeMap::new();
            for i in (0..n).filter(|&i| touse.is_none() || tv[i]) {
                grp.entry(if keys.is_empty() { 0 } else { gv[i].to_bits() }).or_default().push(i);
            }
            for members in grp.values() {
                let xs: Vec<f64> = members.iter().map(|&o| xv[o]).collect();
                for (&o, r) in members.iter().zip(naive_ranks(&xs, mode, Ty::Double)) {
                    want[o] = r;
                }
            }
            let sp = Spec { rank: mode, threads: 1, ..spec(Fcn::Rank, Ty::Double, keys.clone(), vec![x], touse) };
            let a = compute(&io, &sp).unwrap();
            let b = compute(&io, &Spec { threads: 7, ..sp.clone() }).unwrap();
            assert_bits(&a.out, &want, &format!("rank {mode:?} keys {keys:?} touse {touse:?}"));
            assert_bits(&b.out, &want, &format!("rank {mode:?} keys {keys:?} touse {touse:?}, 7 threads"));
            assert_eq!(a.nmiss, want.iter().filter(|&&v| v >= MISS).count());
            assert_eq!(b.nmiss, a.nmiss);
        }
    }
    // a byte rank does not fit
    let r = compute(&io, &spec(Fcn::Rank, Ty::Byte, vec![], vec![x], None));
    assert!(r.err().is_some_and(|e| e.msg == "type fit"));
}

/// rust_kernels F1 through the compute phase: by-group sums past `.`, row sums past -`.`, a raw
/// value beyond `.` in a result, and field ranks of values the original's `-(exp)` moves across
/// `.` fall back [overflow]; values in range do not.
#[test]
fn results_beyond_dot_fall_back() {
    let raw = f64::from_bits(MISS.to_bits() + 1);
    let gv = vec![1.0, 1.0, 2.0, 2.0, 2.0, 3.0, 3.0, 3.0];
    let xv = vec![8e307, 8e307, -8e307, -8e307, -8e307, 1e160, -1e160, 0.0];
    let yv = vec![1.0, raw, 2.0, -1e308, MISS, 3.0, miss_a(), 1.0];
    let mut io = MemIo::new(gv.len());
    let (cg, cx, cy) = (io.add_num(&gv), io.add_num(&xv), io.add_num(&yv));
    let (g, x, y) = (io.push_var(cg), io.push_var(cx), io.push_var(cy));
    let over = |sp: Spec| compute(&io, &sp).err().is_some_and(|e| e.is_fallback() && e.msg == spec::OVERFLOW);
    for fcn in [Fcn::Total, Fcn::Mean, Fcn::Sd, Fcn::Std, Fcn::Median] {
        for sorted in [false, true] {
            assert!(over(Spec { sorted, ..spec(fcn, Ty::Double, vec![g], vec![x], None) }), "{fcn:?}");
        }
    }
    assert!(over(spec(Fcn::RowTotal, Ty::Double, vec![], vec![x, x], None)));
    assert!(over(spec(Fcn::RowMean, Ty::Double, vec![], vec![x, x, y], None)));
    assert!(over(spec(Fcn::RowMax, Ty::Double, vec![], vec![y, y], None)));
    assert!(over(Spec { rank: RankMode::Field, ..spec(Fcn::Rank, Ty::Double, vec![], vec![y], None) }));
    // max with missing keeps the raw value of group 1 (1, raw): Stata's message would not count it
    assert!(over(Spec { missing: true, ..spec(Fcn::Max, Ty::Double, vec![g], vec![y], None) }));
    // in range
    let c = compute(&io, &spec(Fcn::Rank, Ty::Double, vec![g], vec![y], None)).unwrap();
    assert_eq!(c.out[3], 1.0);
    assert_eq!(c.nmiss, 3);
    let c = compute(&io, &spec(Fcn::Max, Ty::Double, vec![g], vec![y], None)).unwrap();
    assert_eq!((c.out[0], c.out[2], c.nmiss), (1.0, 2.0, 0));
    compute(&io, &spec(Fcn::RowMin, Ty::Double, vec![], vec![x, y], None)).unwrap();
}

#[test]
fn keyint_of_group_keys() {
    let a = vec![1.0, 2.0, MISS, 2.0];
    let b = vec![0.5, 1.0, 7.5, 1.0];
    let mut io = MemIo::new(a.len());
    let (ca, cb) = (io.add_num(&a), io.add_num(&b));
    let cs = io.add_str(vec![b"x".to_vec(); 4]);
    let (pa, pb, ps) = (io.push_var(ca), io.push_var(cb), io.push_var(cs));
    let c = compute(&io, &spec(Fcn::Group, Ty::Double, vec![pa, pb, ps], vec![], None)).unwrap();
    assert_eq!(c.keyint, vec![true, false, false]);
    // observation 3 (a missing) is left out: b is integer in the others
    let t = io.add_num(&[0.0, 1.0, 1.0, 1.0]);
    let pt = io.push_var(t);
    let c = compute(&io, &spec(Fcn::Group, Ty::Double, vec![pa, pb], vec![], Some(pt))).unwrap();
    assert_eq!(c.keyint, vec![true, true]);
    let c = compute(&io, &Spec { missing: true, ..spec(Fcn::Group, Ty::Double, vec![pa, pb], vec![], None) }).unwrap();
    assert!(c.keyint.is_empty());
}
