//! Percentiles under the definitions of Stata's `_pctile` ([D] pctile, Methods and formulas),
//! shared by xtile and pctile (slice C) and by egen's median, pctile and iqr (slice A). These are
//! the plan's starting formulas; calibration C1 compares them with `_pctile` bitwise and fixes
//! the floating-point details here (slice C owns this file).
//!
//! Every function takes the nonmissing values sorted ascending, nonempty, and a percentile
//! `p` with 0 < p < 100. `x(i)` below is the i-th smallest value (1-based); an index below 1
//! means x(1) and one above n means x(n).

fn at(xs: &[f64], i: f64) -> f64 {
    let n = xs.len();
    xs[(i.max(1.0) as usize).min(n) - 1]
}

/// Default definition: P = n*p/100, i = floor(P). The percentile is x(i+1) when P > i, and
/// (x(i) + x(i+1))/2 when P == i.
pub fn pctile(xs: &[f64], p: f64) -> f64 {
    let pp = xs.len() as f64 * p / 100.0;
    let i = pp.floor();
    if pp > i { at(xs, i + 1.0) } else { (at(xs, i) + at(xs, i + 1.0)) / 2.0 }
}

/// Weighted definition, `ws[k]` the (positive) weight of `xs[k]`: P = W*p/100 with W the total
/// weight, W(i) the cumulative weight of x(1)..x(i). The percentile is x(i) for the first i with
/// W(i) > P, or (x(i-1) + x(i))/2 when W(i-1) == P.
pub fn pctile_w(xs: &[f64], ws: &[f64], p: f64) -> f64 {
    debug_assert_eq!(xs.len(), ws.len());
    let total: f64 = ws.iter().sum();
    let pp = total * p / 100.0;
    let mut cum = 0.0;
    for (i, w) in ws.iter().enumerate() {
        let prev = cum;
        cum += w;
        if cum > pp {
            return if i > 0 && prev == pp { (xs[i - 1] + xs[i]) / 2.0 } else { xs[i] };
        }
    }
    xs[xs.len() - 1]
}

/// `altdef`: P = (n+1)*p/100, i = floor(P), h = P - i. The percentile is
/// x(i) + h*(x(i+1) - x(i)).
pub fn pctile_altdef(xs: &[f64], p: f64) -> f64 {
    let pp = (xs.len() as f64 + 1.0) * p / 100.0;
    let i = pp.floor();
    let h = pp - i;
    let lo = at(xs, i);
    lo + h * (at(xs, i + 1.0) - lo)
}

/// The percentiles of `nq` quantiles: p_k = 100*k/nq for k = 1..nq-1.
pub fn nq_percents(nq: usize) -> Vec<f64> {
    (1..nq).map(|k| 100.0 * k as f64 / nq as f64).collect()
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
    fn altdef_interpolates_and_clamps_at_the_ends() {
        let xs: Vec<f64> = (1..=10).map(f64::from).collect();
        assert_eq!(pctile_altdef(&xs, 25.0), 2.75);
        assert_eq!(pctile_altdef(&xs, 50.0), 5.5);
        assert_eq!(pctile_altdef(&xs, 1.0), 1.0);
        assert_eq!(pctile_altdef(&xs, 99.0), 10.0);
    }

    #[test]
    fn nq_percents_split_evenly() {
        assert_eq!(nq_percents(4), vec![25.0, 50.0, 75.0]);
        assert!(nq_percents(1).is_empty());
    }
}
