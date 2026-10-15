/* mock_egen.c -- mock-host cases for egen (slice A). Included by mockhost.c after its helpers
   (call, two_phase, same, pass, fail, want, the dataset), so it is not compiled on its own.
   Each case runs the compute phase and the store with 1 and 4 threads against a naive reference
   in this file. */

static int cmp_dbl(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}

/* Runs egen (vars, args with threads=<t>) and stores into V_O1 for t = 1 and 4; checks V_O1
   against want. */
static void egen_case(const char *what, const int *vars, const char **args) {
    for (int t = 0; t < 2; t++) {
        const char *a[32];
        int k = 0;
        while (args[k]) { a[k] = args[k]; k++; }
        a[k++] = t ? "threads=4" : "threads=1";
        a[k] = NULL;
        reset_outputs();
        char fb[256];
        int outs[] = {V_O1, -1};
        int rc = two_phase(vars, a, outs, t ? "4" : "1", fb, sizeof fb);
        char w[200];
        snprintf(w, sizeof w, "%s (%d thread%s)", what, t ? 4 : 1, t ? "s" : "");
        if (rc || fb[0]) {
            char why[1400];
            snprintf(why, sizeof why, "rc %d, fallback \"%s\", %s", rc, fb, last_err);
            fail(w, why);
            continue;
        }
        if (same(w, V_O1, want)) pass(w);
    }
}

/* Mean of V_X1 by V_G (hash groups), double: sequential sum / count of nonmissing values. */
static void egen_mean_by(void) {
    static double sum[64], cnt[64], sumdot, cntdot;
    memset(sum, 0, sizeof sum);
    memset(cnt, 0, sizeof cnt);
    sumdot = cntdot = 0;
    for (int i = 0; i < NOBS; i++) {
        double x = num[V_X1][i], g = num[V_G][i];
        if (x >= MISSVAL) continue;
        if (g >= MISSVAL) { sumdot += x; cntdot++; }
        else { sum[(int)g] += x; cnt[(int)g]++; }
    }
    for (int i = 0; i < NOBS; i++) {
        double g = num[V_G][i];
        double s = g >= MISSVAL ? sumdot : sum[(int)g], c = g >= MISSVAL ? cntdot : cnt[(int)g];
        want[i] = c > 0 ? s / c : MISSVAL;
    }
    int vars[] = {V_G, V_X1, -1};
    const char *args[] = {"egen", "phase=compute", "fcn=mean", "type=double", "nkeys=1", "nvals=1", NULL};
    egen_case("egen mean(x1), by(g)", vars, args);
}

/* Total of V_X2 by sorted V_GS (by prefix), float: runs of 1, 7, 300 and 9000 observations. */
static void egen_total_sorted(void) {
    int start = 0;
    for (int i = 1; i <= NOBS; i++) {
        if (i == NOBS || num[V_GS][i] != num[V_GS][start]) {
            double s = 0;
            for (int j = start; j < i; j++) if (num[V_X2][j] < MISSVAL) s += num[V_X2][j];
            for (int j = start; j < i; j++) want[j] = (double)(float)s;
            start = i;
        }
    }
    int vars[] = {V_GS, V_X2, -1};
    const char *args[] = {"egen", "phase=compute", "fcn=total", "type=float", "nkeys=1", "sorted=1", "nvals=1", NULL};
    egen_case("by gs: egen total(x2)", vars, args);
}

/* group(g): 1..K in ascending order of g, . last (it sorts after every number); missing
   option, so . is a group. */
static void egen_group(void) {
    static int seen[64], dot;
    memset(seen, 0, sizeof seen);
    dot = 0;
    for (int i = 0; i < NOBS; i++) {
        if (num[V_G][i] >= MISSVAL) dot = 1;
        else seen[(int)num[V_G][i]] = 1;
    }
    static double id[64];
    double k = 0;
    for (int v = 0; v < 64; v++) if (seen[v]) id[v] = ++k;
    for (int i = 0; i < NOBS; i++) want[i] = num[V_G][i] >= MISSVAL ? k + dot : id[(int)num[V_G][i]];
    int vars[] = {V_G, -1};
    const char *args[] = {"egen", "phase=compute", "fcn=group", "type=double", "nkeys=1", "missing=1", NULL};
    egen_case("egen group(g), missing", vars, args);
}

/* tag(skey): 1 on the first observation of each string. */
static void egen_tag(void) {
    for (int i = 0; i < NOBS; i++) {
        want[i] = 1;
        for (int j = 0; j < i; j++) {
            if (!strcmp(str[V_SKEY][j], str[V_SKEY][i])) { want[i] = 0; break; }
        }
    }
    int vars[] = {V_SKEY, -1};
    const char *args[] = {"egen", "phase=compute", "fcn=tag", "type=float", "nkeys=1", NULL};
    egen_case("egen tag(skey)", vars, args);
}

/* rowtotal(x1 x2), double: missing counts as 0. */
static void egen_rowtotal(void) {
    for (int i = 0; i < NOBS; i++) {
        double a = num[V_X1][i] >= MISSVAL ? 0 : num[V_X1][i];
        double b = num[V_X2][i] >= MISSVAL ? 0 : num[V_X2][i];
        want[i] = a + b;
    }
    int vars[] = {V_X1, V_X2, -1};
    const char *args[] = {"egen", "phase=compute", "fcn=rowtotal", "type=double", "nvals=2", NULL};
    egen_case("egen rowtotal(x1 x2)", vars, args);
}

/* median(x2) by g with a sample (V_W > 1 as touse): middle value or the mean of the two. */
static void egen_median_by(void) {
    static double vals[NOBS];
    for (int i = 0; i < NOBS; i++) want[i] = MISSVAL;
    for (int gv = -1; gv < 64; gv++) {
        int n = 0;
        for (int i = 0; i < NOBS; i++) {
            int gi = num[V_G][i] >= MISSVAL ? -1 : (int)num[V_G][i];
            if (gi == gv && num[V_W][i] != 0 && num[V_X2][i] < MISSVAL) vals[n++] = num[V_X2][i];
        }
        qsort(vals, n, sizeof(double), cmp_dbl);
        double m = n == 0 ? MISSVAL : n % 2 ? vals[n / 2] : (vals[n / 2 - 1] + vals[n / 2]) / 2;
        for (int i = 0; i < NOBS; i++) {
            int gi = num[V_G][i] >= MISSVAL ? -1 : (int)num[V_G][i];
            if (gi == gv && num[V_W][i] != 0) want[i] = m;
        }
    }
    int vars[] = {V_G, V_X2, V_W, -1};
    const char *args[] = {"egen", "phase=compute", "fcn=median", "type=double", "nkeys=1", "nvals=1", "touse=1", NULL};
    egen_case("egen median(x2), by(g) with touse", vars, args);
}

/* A result that does not fit the type falls back; nothing is cached. */
static void egen_type_fit(void) {
    int vars[] = {V_G, V_X1, -1};
    const char *args[] = {"egen", "phase=compute", "fcn=mean", "type=byte", "nkeys=1", "nvals=1", NULL};
    int rc = call(vars, args);
    const char *fb = macro_get("_fx_fallback");
    if (rc || !fb || strcmp(fb, "type fit") || macro_get("_fx_token")) {
        char why[300];
        snprintf(why, sizeof why, "rc %d, fallback \"%s\"", rc, fb ? fb : "(none)");
        fail("egen byte mean(): fallback type fit", why);
        return;
    }
    pass("egen byte mean(): fallback type fit");
}

static void tests_egen(void) {
    egen_mean_by();
    egen_total_sorted();
    egen_group();
    egen_tag();
    egen_rowtotal();
    egen_median_by();
    egen_type_fit();
}
