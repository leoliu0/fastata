//! Percentiles under the definitions of Stata's `_pctile` ([D] pctile, Methods and formulas),
//! shared by xtile and pctile (slice C) and by egen's median, pctile and iqr (slice A). The
//! floating-point details come from calibration C1 (`tests/stata/calib_pctile.do`), which
//! compares them with `_pctile` bitwise:
//!
//! - Unweighted: P = n*p/100 for a percentile p, but P = n*k/nq exactly (integer arithmetic) for
//!   `_pctile, n(nq)`: `_pctile` does not go through 100*k/nq. The comparison `P == floor(P)` is
//!   exact (no tolerance, checked up to n = 1e6 with P off an integer by 1e-7).
//! - `altdef`: P = (n+1)*p/100, or ((n+1)*k)/nq for n(nq); h = P - floor(P); the value is
//!   (1-h)*x(i) + h*x(i+1) (not x(i) + h*(x(i+1)-x(i))).
//! - Weighted (aweight, fweight and pweight alike): P = W*p/100, or (W*k)/nq. `_pctile` treats a
//!   cumulative weight W(i) as equal to P when it is within about 1e-7*W of it (measured: the
//!   switch lies within 1e-7*W*(1 +- 2e-9) for weights scaled from 1e-6 to 1e6), so W(i) slightly
//!   above P also averages x(i) and x(i+1). The exact form of that test is not known, so
//!   [`Weighted::pctile`] answers `None` whenever a cumulative weight lies close enough to the
//!   switch for the answer to depend on it (the caller then runs the original).
//!
//! The unweighted functions take the nonmissing values sorted ascending, nonempty, and a
//! percentile `p` with 0 < p < 100. `x(i)` below is the i-th smallest value (1-based); an index
//! below 1 means x(1) and one above n means x(n).

fn at(xs: &[f64], i: f64) -> f64 {
    let n = xs.len();
    xs[(i.max(1.0) as usize).min(n) - 1]
}

/// Which order statistics (1-based ranks) an unweighted percentile needs and how it combines
/// them.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Need {
    /// x(i).
    One(usize),
    /// (x(i) + x(i+1))/2.
    Avg(usize),
    /// (1-h)*x(i) + h*x(i+1).
    Interp(usize, f64),
}

impl Need {
    /// The ranks this percentile reads.
    pub fn ranks(self) -> (usize, Option<usize>) {
        match self {
            Need::One(i) => (i, None),
            Need::Avg(i) | Need::Interp(i, _) => (i, Some(i + 1)),
        }
    }

    /// The percentile, given the order statistic of every rank in [`Need::ranks`].
    pub fn value(self, x: impl Fn(usize) -> f64) -> f64 {
        match self {
            Need::One(i) => x(i),
            Need::Avg(i) => (x(i) + x(i + 1)) / 2.0,
            Need::Interp(i, h) => (1.0 - h) * x(i) + h * x(i + 1),
        }
    }
}

/// A requested percentile: `P(p)` (as `_pctile, p(p)`) or `Nq(k, nq)` (the k-th of
/// `_pctile, n(nq)`).
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Pos {
    P(f64),
    Nq(usize, usize),
}

/// Default definition over n values: P = n*p/100 (or n*k/nq), i = floor(P); x(i+1) when P > i,
/// (x(i) + x(i+1))/2 when P == i. Ranks are clamped to 1..n.
pub fn need_default(n: usize, pos: Pos) -> Need {
    let (i, exact) = match pos {
        Pos::P(p) => {
            let pp = n as f64 * p / 100.0;
            let i = pp.floor();
            (i as usize, pp == i)
        }
        Pos::Nq(k, nq) => {
            let nk = n as u128 * k as u128;
            ((nk / nq as u128) as usize, nk % nq as u128 == 0)
        }
    };
    let c = |r: usize| r.clamp(1, n);
    if exact {
        let (a, b) = (c(i), c(i + 1));
        if a == b { Need::One(a) } else { Need::Avg(a) }
    } else {
        Need::One(c(i + 1))
    }
}

/// `altdef` over n values: P = (n+1)*p/100 (or ((n+1)*k)/nq), i = floor(P), h = P - i;
/// (1-h)*x(i) + h*x(i+1), with x(i) for i < 1 taken as x(1) and i >= n as x(n).
pub fn need_altdef(n: usize, pos: Pos) -> Need {
    let pp = match pos {
        Pos::P(p) => (n as f64 + 1.0) * p / 100.0,
        Pos::Nq(k, nq) => ((n as u128 + 1) * k as u128) as f64 / nq as f64,
    };
    let i = pp.floor();
    if i < 1.0 {
        Need::One(1)
    } else if i >= n as f64 {
        Need::One(n)
    } else {
        Need::Interp(i as usize, pp - i)
    }
}

/// Default definition: P = n*p/100, i = floor(P). The percentile is x(i+1) when P > i, and
/// (x(i) + x(i+1))/2 when P == i.
pub fn pctile(xs: &[f64], p: f64) -> f64 {
    let pp = xs.len() as f64 * p / 100.0;
    let i = pp.floor();
    if pp > i { at(xs, i + 1.0) } else { (at(xs, i) + at(xs, i + 1.0)) / 2.0 }
}

/// The k-th percentile of `_pctile, n(nq)` under the default definition (P = n*k/nq).
#[cfg(test)]
pub fn pctile_nq(xs: &[f64], k: usize, nq: usize) -> f64 {
    need_default(xs.len(), Pos::Nq(k, nq)).value(|r| xs[r - 1])
}

/// Weighted definition, `ws[k]` the (positive) weight of `xs[k]`, sorted by x: the value of
/// [`Weighted::pctile`], or, where that is undetermined, the value under a tolerance of exactly
/// 1e-7*W (which may differ from `_pctile` there).
pub fn pctile_w(xs: &[f64], ws: &[f64], p: f64) -> f64 {
    debug_assert_eq!(xs.len(), ws.len());
    let t = Weighted::new(xs, ws);
    t.pctile(Pos::P(p)).unwrap_or_else(|| t.pctile_with(Pos::P(p), 0.0).unwrap_or(xs[xs.len() - 1]))
}

/// `altdef`: P = (n+1)*p/100, i = floor(P), h = P - i. The percentile is
/// (1-h)*x(i) + h*x(i+1).
pub fn pctile_altdef(xs: &[f64], p: f64) -> f64 {
    need_altdef(xs.len(), Pos::P(p)).value(|r| xs[r - 1])
}

/// The k-th percentile of `_pctile, n(nq) altdef`.
#[cfg(test)]
pub fn pctile_altdef_nq(xs: &[f64], k: usize, nq: usize) -> f64 {
    need_altdef(xs.len(), Pos::Nq(k, nq)).value(|r| xs[r - 1])
}

/// The percentiles of `nq` quantiles as the manual states them: p_k = 100*k/nq for
/// k = 1..nq-1. (`_pctile, n(nq)` itself uses [`Pos::Nq`].)
pub fn nq_percents(nq: usize) -> Vec<f64> {
    (1..nq).map(|k| 100.0 * k as f64 / nq as f64).collect()
}

/// Relative half-width of the band around `_pctile`'s weighted tolerance in which an answer is
/// undetermined (measured scatter of the switch: 2e-9).
const TOL_BAND: f64 = 1e-6;
/// `_pctile`'s weighted tolerance, relative to the total weight.
const TOL: f64 = 1e-7;

/// One run of equal values in weighted sorted data.
#[derive(Clone, Copy, Debug)]
struct Run {
    x: f64,
    /// Cumulative weight at the end of the run (sequential sum in sorted order).
    cum: f64,
    wmin: f64,
    wmax: f64,
    len: usize,
}

/// Weighted percentiles of data sorted by x, with positive weights.
pub struct Weighted {
    runs: Vec<Run>,
    total: f64,
    /// Bound on how far a cumulative weight (and P) computed by `_pctile`, which may sum in
    /// another order, can be from ours: 0 when every weight is an integer and the sums are exact.
    noise: f64,
}

impl Weighted {
    /// `xs` sorted ascending (equal values adjacent), `ws` their positive weights.
    pub fn new(xs: &[f64], ws: &[f64]) -> Weighted {
        debug_assert_eq!(xs.len(), ws.len());
        let mut runs: Vec<Run> = Vec::new();
        let mut cum = 0.0;
        let mut ints = true;
        for (&x, &w) in xs.iter().zip(ws) {
            cum += w;
            ints &= w.fract() == 0.0;
            match runs.last_mut() {
                Some(r) if r.x == x => {
                    r.cum = cum;
                    r.wmin = r.wmin.min(w);
                    r.wmax = r.wmax.max(w);
                    r.len += 1;
                }
                _ => runs.push(Run { x, cum, wmin: w, wmax: w, len: 1 }),
            }
        }
        let exact = ints && cum <= 9007199254740992.0;
        let noise = if exact { 0.0 } else { (4.0 * xs.len() as f64 + 64.0) * f64::EPSILON * cum };
        Weighted { runs, total: cum, noise }
    }

    #[cfg(test)]
    pub fn total(&self) -> f64 {
        self.total
    }

    /// The weighted percentile, or `None` when it depends on details of `_pctile`'s tolerance
    /// or summation order that are not known.
    pub fn pctile(&self, pos: Pos) -> Option<f64> {
        self.pctile_with(pos, TOL * self.total * TOL_BAND + self.noise)
    }

    /// The first i with W(i) > P - tol decides: (x(i) + x(i+1))/2 if W(i) <= P + tol, else x(i).
    /// Only the cumulative weights at the ends of runs of equal values, and which observation of
    /// a run comes last, can change the value; `None` when one of them is within `delta` of
    /// P - tol or P + tol.
    fn pctile_with(&self, pos: Pos, delta: f64) -> Option<f64> {
        let w = self.total;
        let pp = match pos {
            Pos::P(p) => w * p / 100.0,
            Pos::Nq(k, nq) => w * k as f64 / nq as f64,
        };
        let tol = TOL * w;
        let (lo, hi) = (pp - tol, pp + tol);
        let near = |t: f64| {
            let a = self.runs.partition_point(|r| r.cum < t - delta);
            self.runs.get(a).is_some_and(|r| r.cum <= t + delta)
        };
        if delta > 0.0 && (near(lo) || near(hi)) {
            return None;
        }
        let r = self.runs.partition_point(|r| r.cum <= lo);
        let run = self.runs.get(r)?;
        if run.cum > hi {
            return Some(run.x);
        }
        // W(end of run) is within the tolerance: the run's last observation is the first above
        // P - tol (giving the average with the next value) unless an earlier one already is.
        let last_first = if run.len == 1 {
            true
        } else if run.cum - run.wmin <= lo - delta {
            true
        } else if run.cum - run.wmax > lo + delta {
            false
        } else {
            return None;
        };
        if !last_first {
            return Some(run.x);
        }
        let next = self.runs.get(r + 1)?;
        Some((run.x + next.x) / 2.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_definition_averages_only_on_exact_ranks() {
        assert_eq!(pctile(&[1.0, 2.0, 3.0, 4.0], 50.0), 2.5);
        assert_eq!(pctile(&[1.0, 2.0, 3.0], 50.0), 2.0);
        assert_eq!(pctile(&[1.0, 2.0, 3.0, 4.0], 25.0), 1.5);
        assert_eq!(pctile(&[1.0, 2.0, 3.0, 4.0], 30.0), 2.0);
        assert_eq!(pctile(&[7.0], 1.0), 7.0);
        assert_eq!(pctile(&[7.0], 99.0), 7.0);
        assert_eq!(pctile(&[1.0, 5.0], 99.5), 5.0);
    }

    #[test]
    fn need_default_matches_pctile_for_percent_positions() {
        for n in 1..60usize {
            let xs: Vec<f64> = (1..=n).map(|i| (i * i) as f64 * 0.37).collect();
            for p in [0.5, 1.0, 2.5, 12.5, 25.0, 33.333, 50.0, 66.6667, 87.5, 99.5] {
                let got = need_default(n, Pos::P(p)).value(|r| xs[r - 1]);
                assert_eq!(got.to_bits(), pctile(&xs, p).to_bits(), "n={n} p={p}");
            }
        }
    }

    #[test]
    fn nq_positions_are_exact_rationals_not_100k_over_nq() {
        // n = 11, nq = 11: P = 11*1/11 = 1 exactly, so x(1) and x(2) are averaged, while
        // 11*(100/11)/100 = 1.0000000000000002 would pick x(2).
        let xs: Vec<f64> = (1..=11).map(f64::from).collect();
        assert_eq!(pctile_nq(&xs, 1, 11), 1.5);
        assert_eq!(pctile(&xs, nq_percents(11)[0]), 2.0);
        assert_eq!(need_default(4, Pos::Nq(1, 3)), Need::One(2));
        assert_eq!(need_default(3, Pos::Nq(1, 3)), Need::Avg(1));
        // nq above n + 1 (allowed by _pctile): ranks clamp.
        assert_eq!(need_default(3, Pos::Nq(1, 10)), Need::One(1));
        assert_eq!(need_default(3, Pos::Nq(9, 10)), Need::One(3));
    }

    #[test]
    fn weights_shift_the_percentile_and_equal_weights_match_the_default() {
        let xs = [1.0, 2.0, 3.0, 4.0];
        for p in [10.0, 25.0, 50.0, 75.0, 90.0] {
            assert_eq!(pctile_w(&xs, &[2.0; 4], p), pctile(&xs, p), "p={p}");
        }
        // W = 10, P = 5: W(1) = 1, W(2) = 2, W(3) = 9 > 5.
        assert_eq!(pctile_w(&xs, &[1.0, 1.0, 7.0, 1.0], 50.0), 3.0);
        // W(2) == P exactly: average of x(2) and x(3).
        assert_eq!(pctile_w(&xs, &[1.0, 1.0, 1.0, 1.0], 50.0), 2.5);
    }

    #[test]
    fn weighted_tolerance_averages_near_misses_and_refuses_the_band() {
        let xs = [1.0, 2.0];
        // _pctile x [aw=w], p(50) with w = (1, 1+e): 1.5 up to e = 4e-7 (|W(1) - P| = 1e-7*W),
        // 2 from e = 4.2e-7 on.
        let t = Weighted::new(&xs, &[1.0, 1.0 + 3e-7]);
        assert_eq!(t.pctile(Pos::P(50.0)), Some(1.5));
        let t = Weighted::new(&xs, &[1.0, 1.0 + 4.2e-7]);
        assert_eq!(t.pctile(Pos::P(50.0)), Some(2.0));
        // W(1) slightly above P also averages.
        let t = Weighted::new(&xs, &[1.0 + 3e-7, 1.0]);
        assert_eq!(t.pctile(Pos::P(50.0)), Some(1.5));
        let t = Weighted::new(&xs, &[1.0 + 4.2e-7, 1.0]);
        assert_eq!(t.pctile(Pos::P(50.0)), Some(1.0));
        // At the switch itself the answer is undetermined.
        let t = Weighted::new(&xs, &[1.0, 1.0 + 4.0000008e-7]);
        assert_eq!(t.pctile(Pos::P(50.0)), None);
    }

    #[test]
    fn weighted_runs_of_ties_depend_on_their_last_weight_only_when_it_matters() {
        // Run of 2s with weights 1 and 3 ending exactly at P = 5 (W = 10): whichever comes last,
        // the observation before it has W <= 4 < P - tol, so the average with the next value.
        let t = Weighted::new(&[1.0, 2.0, 2.0, 3.0], &[1.0, 1.0, 3.0, 5.0]);
        assert_eq!(t.pctile(Pos::P(50.0)), Some(2.5));
        // A run of 2s with weights 1e-9 and 1 ending at P: if the 1 comes last, the observation
        // before it is below P - tol (2.5); if the 1e-9 comes last, the one before it is already
        // within the tolerance (2). _pctile's tie order is unknown: refused.
        let xs = [1.0, 1.0, 1.0, 1.0, 2.0, 2.0, 3.0, 3.0, 3.0, 3.0];
        let mut ws = vec![1.0; xs.len()];
        ws[4] = 1e-9;
        let t = Weighted::new(&xs, &ws);
        let p = 100.0 * (5.0 + 1e-9) / t.total();
        assert_eq!(t.pctile(Pos::P(p)), None);
    }

    #[test]
    fn fractional_weights_widen_the_band_with_n() {
        let n = 1000;
        let xs: Vec<f64> = (0..n).map(|i| i as f64).collect();
        let ws: Vec<f64> = (0..n).map(|i| 0.5 + (i % 7) as f64 * 0.1).collect();
        let t = Weighted::new(&xs, &ws);
        assert!(t.noise > 0.0);
        let ti = Weighted::new(&xs, &vec![3.0; n]);
        assert_eq!(ti.noise, 0.0);
        assert_eq!(ti.pctile(Pos::Nq(1, 4)), Some(249.5));
        assert_eq!(ti.pctile(Pos::Nq(1, 3)), Some(333.0));
    }

    #[test]
    fn altdef_interpolates_and_clamps_at_the_ends() {
        let xs: Vec<f64> = (1..=10).map(f64::from).collect();
        assert_eq!(pctile_altdef(&xs, 25.0), 2.75);
        assert_eq!(pctile_altdef(&xs, 50.0), 5.5);
        assert_eq!(pctile_altdef(&xs, 1.0), 1.0);
        assert_eq!(pctile_altdef(&xs, 99.0), 10.0);
        assert_eq!(pctile_altdef_nq(&xs, 1, 4), 2.75);
        // _pctile x, n(3) altdef on (-0.7000000000000001, 0.5, 0.8) gives -0.30000000000000016:
        // (1-h)*x(1) + h*x(2) with h = 4/3 - 1, not x(1) + h*(x(2) - x(1)) = -0.3000000000000001.
        let xs = [-0.7000000000000001, 0.5, 0.8];
        assert_eq!(pctile_altdef_nq(&xs, 1, 3), -0.30000000000000016);
    }

    #[test]
    fn nq_percents_split_evenly() {
        assert_eq!(nq_percents(4), vec![25.0, 50.0, 75.0]);
        assert!(nq_percents(1).is_empty());
    }
}
