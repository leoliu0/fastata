/* mock_dup.c -- mock-host cases for isid and dup (slice B). Included by mockhost.c after its helpers
   (call, two_phase, same, pass, fail, want, the dataset), so it is not compiled on its own. */

static int dup_cmp_double(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}

/* Naive group of (V_G, V_SKEY): V_G is . or 1..50, V_SKEY is k00..k36. */
static int dup_key(int i) {
    int g = num[V_G][i] >= MISSVAL ? 0 : (int)num[V_G][i];
    return g * 37 + atoi(str[V_SKEY][i] + 1);
}

static long dup_local(const char *name) {
    const char *v = macro_get(name);
    return v ? atol(v) : -1;
}

static void dup_check_local(const char *what, const char *name, long expect, int *ok) {
    long got = dup_local(name);
    if (*ok && got != expect) {
        char why[200];
        snprintf(why, sizeof why, "%s = %ld, want %ld", name, got, expect);
        fail(what, why);
        *ok = 0;
    }
}

static void test_isid(void) {
    static double sorted[NOBS];
    for (int t = 0; t < 2; t++) {
        const char *th = t ? "threads=4" : "threads=1";
        char what[80];
        /* V_GS: runs, no missing; not unique */
        snprintf(what, sizeof what, "isid sorted key (%s)", th);
        int ok = 1;
        {
            const char *args[] = {"isid", "missok=0", th, NULL};
            int vars[] = {V_GS, -1};
            int rc = call(vars, args);
            long runs = 1;
            for (int i = 1; i < NOBS; i++) runs += num[V_GS][i] != num[V_GS][i - 1];
            if (rc) { fail(what, last_err); ok = 0; }
            dup_check_local(what, "_fx_nmiss", 0, &ok);
            dup_check_local(what, "_fx_nuniq", runs, &ok);
            if (ok) pass(what);
        }
        /* V_X1 with . and .a: missok=0 skips the uniqueness count, missok=1 gives it */
        snprintf(what, sizeof what, "isid key with missing codes (%s)", th);
        ok = 1;
        {
            long nmiss = 0, nuniq = 0;
            for (int i = 0; i < NOBS; i++) { sorted[i] = num[V_X1][i]; nmiss += sorted[i] >= MISSVAL; }
            qsort(sorted, NOBS, sizeof(double), dup_cmp_double);
            for (int i = 0; i < NOBS; i++) nuniq += i == 0 || sorted[i] != sorted[i - 1];
            const char *a0[] = {"isid", "missok=0", th, NULL};
            const char *a1[] = {"isid", "missok=1", th, NULL};
            int vars[] = {V_X1, -1};
            int rc = call(vars, a0);
            if (rc) { fail(what, last_err); ok = 0; }
            dup_check_local(what, "_fx_nmiss", nmiss, &ok);
            if (ok && macro_get("_fx_nuniq")) { fail(what, "fx_nuniq set with missok=0"); ok = 0; }
            rc = call(vars, a1);
            if (ok && rc) { fail(what, last_err); ok = 0; }
            dup_check_local(what, "_fx_nuniq", nuniq, &ok);
            if (ok) pass(what);
        }
    }
}

/* tag, drop and report over (V_G, V_SKEY) with touse = V_O4 (0 on every third observation). */
static void test_dup_kinds(void) {
    static long cnt[51 * 37];
    static int seen[51 * 37];
    for (int t = 0; t < 2; t++) {
        const char *th = t ? "4" : "1";
        char tharg[32], what[80];
        snprintf(tharg, sizeof tharg, "threads=%s", th);
        reset_outputs();
        for (int i = 0; i < NOBS; i++) num[V_O4][i] = i % 3 != 0;
        memset(cnt, 0, sizeof cnt);
        memset(seen, 0, sizeof seen);
        long ns = 0, ng = 0;
        for (int i = 0; i < NOBS; i++) {
            if (!num[V_O4][i]) continue;
            ns++;
            if (cnt[dup_key(i)]++ == 0) ng++;
        }
        int vars[] = {V_G, V_SKEY, V_O4, -1};

        snprintf(what, sizeof what, "dup tag (%s threads)", th);
        const char *ta[] = {"dup", "phase=compute", "sub=tag", "touse=1", tharg, NULL};
        int out1[] = {V_O1, -1};
        char fb[128];
        int rc = two_phase(vars, ta, out1, th, fb, sizeof fb);
        if (rc || *fb) fail(what, rc ? last_err : fb);
        else {
            for (int i = 0; i < NOBS; i++) want[i] = num[V_O4][i] ? (double)(cnt[dup_key(i)] - 1) : MISSVAL;
            if (same(what, V_O1, want)) pass(what);
        }

        snprintf(what, sizeof what, "dup drop (%s threads)", th);
        const char *da[] = {"dup", "phase=compute", "sub=drop", "touse=1", tharg, NULL};
        int out2[] = {V_O2, -1};
        rc = call(vars, da);
        int ok = !rc;
        if (rc) fail(what, last_err);
        dup_check_local(what, "_fx_n", ns, &ok);
        dup_check_local(what, "_fx_ndrop", ns - ng, &ok);
        if (ok) {
            char token[64], tha[64];
            snprintf(token, sizeof token, "token=%s", macro_get("_fx_token"));
            snprintf(tha, sizeof tha, "threads=%s", th);
            const char *sa[] = {"store", token, tha, NULL};
            rc = call(out2, sa);
            if (rc) { fail(what, last_err); ok = 0; }
        }
        if (ok) {
            for (int i = 0; i < NOBS; i++) {
                int k = dup_key(i);
                want[i] = num[V_O4][i] && seen[k]++ ? 1.0 : 0.0;
            }
            if (same(what, V_O2, want)) pass(what);
        }

        snprintf(what, sizeof what, "dup report (%s threads)", th);
        const char *ra[] = {"dup", "phase=compute", "sub=report", "touse=1", tharg, NULL};
        rc = call(vars, ra);
        ok = !rc;
        if (rc) fail(what, last_err);
        dup_check_local(what, "_fx_nuniq", ng, &ok);
        if (ok) {
            /* freq by group size, ascending */
            static long freq[NOBS + 1];
            memset(freq, 0, sizeof freq);
            for (int k = 0; k < 51 * 37; k++) if (cnt[k]) freq[cnt[k]] += cnt[k];
            char expect[1024] = "", item[64];
            for (int c = 1; c <= NOBS; c++) {
                if (!freq[c]) continue;
                snprintf(item, sizeof item, "%s%d %ld %ld", *expect ? " " : "", c, freq[c], freq[c] - freq[c] / c);
                strncat(expect, item, sizeof expect - strlen(expect) - 1);
            }
            const char *got = macro_get("_fx_table");
            if (!got || strcmp(got, expect)) {
                char why[1100];
                snprintf(why, sizeof why, "fx_table \"%s\", want \"%s\"", got ? got : "(none)", expect);
                fail(what, why);
            }
            else pass(what);
        }

        snprintf(what, sizeof what, "dup examples and list (%s threads)", th);
        long ndup = 0, nlist = 0;
        for (int k = 0; k < 51 * 37; k++) if (cnt[k] > 1) { ndup++; nlist += cnt[k]; }
        const char *ea[] = {"dup", "phase=compute", "sub=examples", "touse=1", tharg, NULL};
        const char *la[] = {"dup", "phase=compute", "sub=list", "touse=1", tharg, NULL};
        rc = call(vars, ea);
        ok = !rc;
        if (rc) fail(what, last_err);
        dup_check_local(what, "_fx_ndup", ndup, &ok);
        dup_check_local(what, "_fx_nlist", ndup, &ok);
        rc = call(vars, la);
        if (ok && rc) { fail(what, last_err); ok = 0; }
        dup_check_local(what, "_fx_nlist", nlist, &ok);
        if (ok) pass(what);
    }
}

/* An empty sample reports fx_n = 0 and caches nothing. */
static void test_dup_empty(void) {
    for (int i = 0; i < NOBS; i++) num[V_O4][i] = 0.0;
    const char *args[] = {"dup", "phase=compute", "sub=tag", "touse=1", NULL};
    int vars[] = {V_GS, V_O4, -1};
    int rc = call(vars, args);
    int ok = !rc;
    if (rc) fail("dup empty sample", last_err);
    dup_check_local("dup empty sample", "_fx_n", 0, &ok);
    if (ok && macro_get("_fx_token")) { fail("dup empty sample", "token set"); ok = 0; }
    if (ok) pass("dup empty sample");
    reset_outputs();
}

/* More key variables than the plugin keeps (V_G and V_SKEY repeated: the same groups as the pair),
   so rows are hashed and groups of equal hashes are re-read through the SPI (observation lists):
   report and drop counts match the naive groups of (V_G, V_SKEY) over the sample V_O4. */
static void test_dup_wide(void) {
    static long cnt[51 * 37];
    for (int i = 0; i < NOBS; i++) num[V_O4][i] = i % 3 != 0;
    memset(cnt, 0, sizeof cnt);
    long ns = 0, ng = 0;
    for (int i = 0; i < NOBS; i++) {
        if (!num[V_O4][i]) continue;
        ns++;
        if (cnt[dup_key(i)]++ == 0) ng++;
    }
    int vars[] = {V_G, V_SKEY, V_G, V_SKEY, V_G, V_O4, -1};
    for (int t = 0; t < 2; t++) {
        const char *th = t ? "threads=4" : "threads=1";
        char what[80];
        snprintf(what, sizeof what, "dup wide keys (%s)", th);
        const char *ra[] = {"dup", "phase=compute", "sub=report", "touse=1", th, NULL};
        int rc = call(vars, ra);
        int ok = !rc;
        if (rc) fail(what, last_err);
        dup_check_local(what, "_fx_n", ns, &ok);
        dup_check_local(what, "_fx_nuniq", ng, &ok);
        const char *da[] = {"dup", "phase=compute", "sub=drop", "touse=1", th, NULL};
        rc = call(vars, da);
        if (ok && rc) { fail(what, last_err); ok = 0; }
        dup_check_local(what, "_fx_ndrop", ns - ng, &ok);
        if (ok) pass(what);
    }
    reset_outputs();
}

static void tests_dup(void) {
    test_isid();
    test_dup_kinds();
    test_dup_empty();
    test_dup_wide();
}
