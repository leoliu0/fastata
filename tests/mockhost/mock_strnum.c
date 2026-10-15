/* mock_strnum.c -- mock-host cases for destring and tostring (slice D). Included by mockhost.c after its helpers
   (call, two_phase, same, pass, fail, want, the dataset), so it is not compiled on its own. */

/* Expected destring value of a V_SNUM string after removing the characters in drop: the C library's (correctly
   rounded) strtod for "%.2f" numbers, Stata's . for everything else. */
static double snum_value(const char *s, const char *drop) {
    char t[STRW];
    int n = 0;
    for (const char *p = s; *p; p++)
        if (!strchr(drop, *p)) t[n++] = *p;
    t[n] = 0;
    if (n == 0) return MISSVAL;
    char *end;
    double v = strtod(t, &end);
    if (*end || strspn(t, "+-0123456789.") != (size_t)n) return MISSVAL;
    return v;
}

static int local_is(const char *what, const char *name, const char *value) {
    const char *v = macro_get(name);
    if (!v || strcmp(v, value)) {
        char why[200];
        snprintf(why, sizeof why, "local %s is \"%s\", want \"%s\"", name, v ? v : "(unset)", value);
        fail(what, why);
        return 0;
    }
    return 1;
}

static void test_destring_force(void) {
    for (int t = 0; t < 2; t++) {
        const char *what = t ? "destring force (4 threads)" : "destring force (1 thread)";
        reset_outputs();
        const char *args[] = {"destring", "phase=compute", t ? "threads=4" : "threads=1", "force=1", "float=0",
                              "percent=0", "dpcomma=0", "ign=", NULL};
        int vars[] = {V_SNUM, -1};
        int outs[] = {V_O1, -1};
        char fb[256];
        int rc = two_phase(vars, args, outs, t ? "4" : "1", fb, sizeof fb);
        if (rc || *fb) { fail(what, *fb ? fb : last_err); continue; }
        int nmiss = 0;
        for (int i = 0; i < NOBS; i++) {
            want[i] = snum_value(str[V_SNUM][i], "");
            nmiss += want[i] >= MISSVAL;
        }
        char nm[32];
        snprintf(nm, sizeof nm, "%d", nmiss);
        /* rerun the compute phase for its locals (two_phase's store call cleared them) */
        call(vars, args);
        if (same(what, V_O1, want) && local_is(what, "_fx_newmiss_1", nm) && local_is(what, "_fx_flag_1", "1") &&
            local_is(what, "_fx_conv_1", "1") && local_is(what, "_fx_type_1", "double"))
            pass(what);
    }
}

static void test_destring_noforce(void) {
    const char *what = "destring without force keeps a variable with junk";
    const char *args[] = {"destring", "phase=compute", "threads=4", "force=0", "ign=", NULL};
    int vars[] = {V_SNUM, -1};
    int rc = call(vars, args);
    if (rc) { fail(what, last_err); return; }
    if (macro_get("_fx_token")) { fail(what, "a token was set"); return; }
    if (local_is(what, "_fx_conv_1", "0") && local_is(what, "_fx_flag_1", "1")) pass(what);
}

static void test_destring_ignore(void) {
    const char *what = "destring ignore(-) force";
    reset_outputs();
    /* 45 is '-', 78 'N' */
    const char *args[] = {"destring", "phase=compute", "threads=3", "force=1", "ign=45 78", NULL};
    int vars[] = {V_SNUM, -1};
    int outs[] = {V_O2, -1};
    char fb[256];
    int rc = two_phase(vars, args, outs, "3", fb, sizeof fb);
    if (rc || *fb) { fail(what, *fb ? fb : last_err); return; }
    for (int i = 0; i < NOBS; i++) want[i] = snum_value(str[V_SNUM][i], "-N");
    call(vars, args);
    if (same(what, V_O2, want) && local_is(what, "_fx_found_1", "1 1")) pass(what);
}

static void test_tostring(void) {
    for (int t = 0; t < 2; t++) {
        const char *what = t ? "tostring %12.0g (4 threads)" : "tostring %12.0g (1 thread)";
        reset_outputs();
        const char *args[] = {"tostring", "phase=compute", t ? "threads=4" : "threads=1", "fmt=g", "width=12", NULL};
        int vars[] = {V_G, -1};
        int outs[] = {V_SOUT, -1};
        char fb[256];
        int rc = two_phase(vars, args, outs, t ? "4" : "1", fb, sizeof fb);
        if (rc || *fb) { fail(what, *fb ? fb : last_err); continue; }
        int ok = 1;
        for (int i = 0; i < NOBS && ok; i++) {
            char w[STRW];
            if (num[V_G][i] >= MISSVAL) strcpy(w, ".");
            else snprintf(w, sizeof w, "%d", (int)num[V_G][i]);
            if (strcmp(str[V_SOUT][i], w)) {
                char why[200];
                snprintf(why, sizeof why, "obs %d: got \"%s\", want \"%s\"", i + 1, str[V_SOUT][i], w);
                fail(what, why);
                ok = 0;
            }
        }
        call(vars, args);
        if (ok && local_is(what, "_fx_len_1", "2")) pass(what);
    }
}

static void test_tostring_noninteger(void) {
    const char *what = "tostring of non-integers falls back";
    const char *args[] = {"tostring", "phase=compute", "threads=2", "fmt=g", "width=12", NULL};
    int vars[] = {V_G, V_X1, -1};
    int rc = call(vars, args);
    const char *fb = macro_get("_fx_fallback");
    if (rc || !fb || strcmp(fb, "non-integer") || macro_get("_fx_token")) {
        char why[300];
        snprintf(why, sizeof why, "rc %d, fallback \"%s\"", rc, fb ? fb : "(unset)");
        fail(what, why);
        return;
    }
    pass(what);
}

static void tests_strnum(void) {
    test_destring_force();
    test_destring_noforce();
    test_destring_ignore();
    test_tostring();
    test_tostring_noninteger();
}
