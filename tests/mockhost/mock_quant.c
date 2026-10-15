/* mock_quant.c -- mock-host cases for quant: xtile and pctile (slice C). Included by mockhost.c after its helpers
   (call, two_phase, same, pass, fail, want, the dataset), so it is not compiled on its own.

   References: _pctile's definitions as calibrated (src/quant.rs): unweighted P = n*k/nq exactly, altdef
   (1-h)*x(i) + h*x(i+1) with P = ((n+1)*k)/nq, weighted W(i) within 1e-7*W of P = W*k/nq averages. V_O3 serves
   as the 0/1 sample marker. */

static double q_xs[NOBS], q_ws[NOBS], q_qs[1024];

static int q_cmp(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}

/* (x, w) pairs sorted by x */
static int q_cmp2(const void *a, const void *b) { return q_cmp(a, b); }

/* Sample of x (weights w or -1, marker t or -1); returns n, fills q_xs (sorted) and q_ws. */
static int q_sample(int x, int w, int t) {
    static double pairs[NOBS][2];
    int n = 0;
    for (int i = 0; i < NOBS; i++) {
        if (t >= 0 && num[t][i] == 0.0) continue;
        if (w >= 0 && !(num[w][i] < MISSVAL && num[w][i] > 0.0)) continue;
        if (num[x][i] >= MISSVAL) continue;
        pairs[n][0] = num[x][i];
        pairs[n][1] = w >= 0 ? num[w][i] : 1.0;
        n++;
    }
    qsort(pairs, (size_t)n, sizeof pairs[0], q_cmp2);
    for (int k = 0; k < n; k++) { q_xs[k] = pairs[k][0]; q_ws[k] = pairs[k][1]; }
    return n;
}

static double q_at(int n, long r) { return q_xs[(r < 1 ? 1 : r > n ? n : r) - 1]; }

/* k-th percentile of n(nq): 0 default, 1 altdef, 2 weighted */
static double q_pct(int n, int k, int nq, int def) {
    if (def == 0) {
        long long nk = (long long)n * k;
        long i = (long)(nk / nq);
        if (nk % nq == 0) return (q_at(n, i) + q_at(n, i + 1)) / 2.0;
        return q_at(n, i + 1);
    }
    if (def == 1) {
        double p = (double)((long long)(n + 1) * k) / (double)nq;
        double i = floor(p), h = p - i;
        if (i < 1) return q_xs[0];
        if (i >= n) return q_xs[n - 1];
        return (1.0 - h) * q_xs[(long)i - 1] + h * q_xs[(long)i];
    }
    double W = 0.0;
    for (int j = 0; j < n; j++) W += q_ws[j];
    double P = W * k / nq, tol = 1e-7 * W, c = 0.0;
    for (int j = 0; j < n; j++) {
        c += q_ws[j];
        if (c > P - tol) {
            if (c <= P + tol && j + 1 < n) return (q_xs[j] + q_xs[j + 1]) / 2.0;
            return q_xs[j];
        }
    }
    return q_xs[n - 1];
}

/* Expected column: xtile categories (kind 0) or pctile values (kind 1, rounded to float if flt). */
static void q_want(int x, int w, int t, int nq, int def, int kind, int flt) {
    int n = q_sample(x, w, t);
    for (int k = 1; k < nq; k++) q_qs[k - 1] = q_pct(n, k, nq, def);
    for (int i = 0; i < NOBS; i++) want[i] = MISSVAL;
    if (kind == 1) {
        for (int k = 1; k < nq; k++) want[k - 1] = flt ? (double)(float)q_qs[k - 1] : q_qs[k - 1];
        return;
    }
    for (int i = 0; i < NOBS; i++) {
        if (t >= 0 && num[t][i] == 0.0) continue;
        if (w >= 0 && !(num[w][i] < MISSVAL && num[w][i] > 0.0)) continue;
        if (num[x][i] >= MISSVAL) continue;
        int k = 1;
        while (k < nq && num[x][i] > q_qs[k - 1]) k++;
        want[i] = k;
    }
}

static void q_case(const char *what, int x, int w, int t, int nq, int def, int kind, int flt) {
    char nqs[32], wts[32];
    snprintf(nqs, sizeof nqs, "nq=%d", nq);
    snprintf(wts, sizeof wts, "wtype=%s", w < 0 ? "none" : w == V_FW ? "fw" : "aw");
    int vars[4], nv = 0;
    vars[nv++] = x;
    if (w >= 0) vars[nv++] = w;
    if (t >= 0) vars[nv++] = t;
    vars[nv] = -1;
    int outs[] = {V_O1, -1};
    for (int th = 0; th < 2; th++) {
        reset_outputs();
        if (t >= 0) for (int i = 0; i < NOBS; i++) num[t][i] = unif(i, 9) < 0.6 ? 1.0 : 0.0;
        const char *args[] = {"quant", "phase=compute", th ? "threads=8" : "threads=1", kind ? "kind=pctile" : "kind=xtile",
                              nqs, wts, def == 1 ? "altdef=1" : "altdef=0", t >= 0 ? "touse=1" : "touse=0",
                              flt ? "float=1" : "float=0", NULL};
        char fb[256], name[160];
        snprintf(name, sizeof name, "%s (%s)", what, th ? "8 threads" : "1 thread");
        int rc = two_phase(vars, args, outs, th ? "8" : "1", fb, sizeof fb);
        if (rc) { fail(name, last_err); continue; }
        if (fb[0]) { fail(name, fb); continue; }
        q_want(x, w, t, nq, def, kind, flt);
        for (int i = 0; i < NOBS; i++) if (want[i] >= MISSVAL) want[i] = MISSVAL;
        if (same(name, V_O1, want)) pass(name);
    }
}

static void tests_quant(void) {
    q_case("quant xtile nq=10", V_X1, -1, -1, 10, 0, 0, 0);
    q_case("quant xtile nq=7 if", V_X2, -1, V_O3, 7, 0, 0, 0);
    q_case("quant xtile nq=4 altdef", V_X1, -1, -1, 4, 1, 0, 0);
    q_case("quant xtile nq=5 [aw]", V_X1, V_W, -1, 5, 2, 0, 0);
    q_case("quant xtile nq=3 [fw] if", V_X2, V_FW, V_O3, 3, 2, 0, 0);
    q_case("quant xtile nq=50 ties", V_G, -1, -1, 50, 0, 0, 0);
    q_case("quant pctile nq=100", V_X1, -1, -1, 100, 0, 1, 0);
    q_case("quant pctile nq=9 float altdef", V_X2, -1, V_O3, 9, 1, 1, 1);
    q_case("quant pctile nq=20 [fw]", V_G, V_FW, -1, 20, 2, 1, 0);

    /* An empty sample falls back; a noninteger frequency weight falls back. */
    reset_outputs();
    for (int i = 0; i < NOBS; i++) num[V_O3][i] = 0.0;
    {
        const char *args[] = {"quant", "phase=compute", "kind=xtile", "nq=4", "touse=1", NULL};
        int vars[] = {V_X1, V_O3, -1};
        int rc = call(vars, args);
        const char *fb = macro_get("_fx_fallback");
        if (rc || !fb || strcmp(fb, "error")) fail("quant empty sample falls back", fb ? fb : "no fallback");
        else pass("quant empty sample falls back");
    }
    {
        const char *args[] = {"quant", "phase=compute", "kind=pctile", "nq=4", "wtype=fw", NULL};
        int vars[] = {V_X1, V_W, -1};
        int rc = call(vars, args);
        const char *fb = macro_get("_fx_fallback");
        if (rc || !fb || strcmp(fb, "weights")) fail("quant noninteger fweight falls back", fb ? fb : "no fallback");
        else pass("quant noninteger fweight falls back");
    }
    reset_outputs();
}
