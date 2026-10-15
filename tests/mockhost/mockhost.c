/*
    mockhost.c -- a fake Stata host for ABI tests of the fastata plugin on every OS.

    Implements the SPI 3.0 ST_plugin table over an in-memory 20,000-observation dataset (numeric
    variables plus string variables that support both reads and stores), loads the plugin with
    dlopen/LoadLibrary and runs its commands. Expected values come from naive references in this
    file.

    Build/run (from the repository root):
        cc -O2 -DSYSTEM=OPUNIX -Ic tests/mockhost/mockhost.c -ldl -lm -o target/mockhost
        target/mockhost stata/fastata.plugin
    Exit status: 0 when nothing FAILed.
*/

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "stplugin.h"

#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

#define NOBS 20000
#define MISSVAL 8.98846567431158e307
/* Stata's .a: just above . */
#define MISS_A (MISSVAL * (1.0 + 1.0 / 4096.0))
#define STRW 64

/* ---------------------------------------------------------------- dataset */

enum {
    V_X1,   /* with . and .a */
    V_X2,   /* with . */
    V_G,    /* numeric key, unsorted: 50 groups, some . */
    V_GS,   /* numeric key, sorted: runs of 1, 7, 300 and 9000 (crossing 8192-row blocks) */
    V_W,    /* weight in (0.5, 1.5) */
    V_FW,   /* integer weight 1..4 */
    V_O1,   /* outputs, prefilled with SENTINEL */
    V_O2,
    V_O3,
    V_O4,
    V_SKEY, /* string, read-only: 37 distinct values */
    V_SNUM, /* string, read-only: numbers as text, every 50th junk ("NA", "-", "1e3x") */
    V_SOUT, /* string, written by the plugin; prefilled with "?" */
    V_SOUT2,
    NVAR
};

#define SENTINEL 12345.0

static double num[NVAR][NOBS];
static char str[NVAR][NOBS][STRW];

static int is_strvar(int v) { return v == V_SKEY || v == V_SNUM || v == V_SOUT || v == V_SOUT2; }

static double unif(uint64_t i, uint64_t k) {
    uint64_t z = i * 0x9e3779b97f4a7c15ULL + k * 0xbf58476d1ce4e5b9ULL;
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
    z ^= z >> 31;
    return (double)(z >> 11) / 9007199254740992.0;
}

static void reset_outputs(void) {
    for (int i = 0; i < NOBS; i++) {
        num[V_O1][i] = SENTINEL;
        num[V_O2][i] = SENTINEL;
        num[V_O3][i] = SENTINEL;
        num[V_O4][i] = SENTINEL;
        strcpy(str[V_SOUT][i], "?");
        strcpy(str[V_SOUT2][i], "?");
    }
}

static void make_data(void) {
    static const int runs[] = {1, 7, 300, 9000};
    int run = 0, left = runs[0], key = 1;
    for (int i = 0; i < NOBS; i++) {
        num[V_X1][i] = i % 23 == 0 ? MISSVAL : i % 29 == 0 ? MISS_A : 20.0 * unif(i, 1) - 5.0;
        num[V_X2][i] = i % 19 == 0 ? MISSVAL : 3.0 * unif(i, 2) + 100.0;
        num[V_G][i] = i % 97 == 0 ? MISSVAL : (double)(int)(50.0 * unif(i, 3) + 1.0);
        if (left == 0) { run = (run + 1) % 4; left = runs[run]; key++; }
        num[V_GS][i] = key;
        left--;
        num[V_W][i] = 0.5 + unif(i, 4);
        num[V_FW][i] = (double)(1 + (int)(4.0 * unif(i, 5)));
        snprintf(str[V_SKEY][i], STRW, "k%02d", (int)((i * 7919u + i / 3u) % 37u));
        if (i % 50 == 7) strcpy(str[V_SNUM][i], i % 150 == 7 ? "NA" : i % 150 == 57 ? "-" : "1e3x");
        else snprintf(str[V_SNUM][i], STRW, "%.2f", 2000.0 * unif(i, 6) - 1000.0);
    }
    reset_outputs();
}

/* Current call: varlist (dataset variable per 1-based position). */
static int varlist[64];
static int nvarlist = 0;
static ST_int stopflag = 0;

static int pos_ok(int i, int j) { return i >= 1 && i <= nvarlist && j >= 1 && j <= NOBS; }

/* ---------------------------------------------------------------- ST_plugin functions */

#define MAXREG 32
static struct { char name[64]; char value[1024]; } macros[MAXREG];
static int nmacros = 0;
static char last_err[1024];

static const char *macro_get(const char *name) {
    for (int k = 0; k < nmacros; k++) if (!strcmp(macros[k].name, name)) return macros[k].value;
    return NULL;
}

static ST_int m_spoutsml(char *s) { fputs(s, stdout); return 0; }
static ST_int m_spouterr(char *s) {
    fputs(s, stdout);
    snprintf(last_err, sizeof last_err, "%s", s);
    return 0;
}
static void m_spoutflush(void) { fflush(stdout); }
static ST_int m_poll(void) { return 0; }
static ST_int m_macresave(char *name, char *value) {
    int k = 0;
    while (k < nmacros && strcmp(macros[k].name, name)) k++;
    if (k == nmacros) { if (nmacros == MAXREG) return 920; nmacros++; }
    snprintf(macros[k].name, sizeof macros[k].name, "%s", name);
    snprintf(macros[k].value, sizeof macros[k].value, "%s", value);
    return 0;
}
static ST_int m_vdata(ST_int i, ST_int j, ST_double *z) {
    if (!pos_ok(i, j) || is_strvar(varlist[i - 1])) return 198;
    *z = num[varlist[i - 1]][j - 1];
    return 0;
}
static ST_int m_store(ST_int i, ST_int j, ST_double v) {
    if (!pos_ok(i, j) || is_strvar(varlist[i - 1])) return 198;
    num[varlist[i - 1]][j - 1] = v;
    return 0;
}
static ST_int m_sdata(ST_int i, ST_int j, char *s) {
    if (!pos_ok(i, j) || !is_strvar(varlist[i - 1])) return 198;
    strcpy(s, str[varlist[i - 1]][j - 1]);
    return 0;
}
static ST_int m_sstore(ST_int i, ST_int j, char *s) {
    if (!pos_ok(i, j) || (varlist[i - 1] != V_SOUT && varlist[i - 1] != V_SOUT2) || strlen(s) >= STRW) return 198;
    strcpy(str[varlist[i - 1]][j - 1], s);
    return 0;
}
static ST_boolean m_isstr(ST_int i) { return i >= 1 && i <= nvarlist && is_strvar(varlist[i - 1]); }
static ST_boolean m_isstrl(ST_int i) { (void)i; return 0; }
static ST_boolean m_isbinary(ST_int i, ST_int j) { (void)i; (void)j; return 0; }
static ST_int m_sdatalen(ST_int i, ST_int j) {
    return pos_ok(i, j) && is_strvar(varlist[i - 1]) ? (ST_int)strlen(str[varlist[i - 1]][j - 1]) : -198;
}
static ST_int m_strldata(ST_int i, ST_int j, char *s, ST_int len) { (void)i; (void)j; (void)s; (void)len; return -198; }
static ST_boolean m_selobs(ST_int j) { return j >= 1 && j <= NOBS; }
static ST_int m_nobs1(void) { return 1; }
static ST_int m_nobs2(void) { return NOBS; }
static ST_int m_nobs(void) { return NOBS; }
static ST_int m_nvar(void) { return NVAR; }
static ST_int m_nvars(void) { return nvarlist; }
static ST_boolean m_ismissing(ST_double z) { return z >= MISSVAL; }

static ST_plugin table;

static void init_table(void) {
    memset(&table, 0, sizeof table);
    table.spoutsml = m_spoutsml;
    table.spoutnosml = m_spoutsml;
    table.spoutflush = m_spoutflush;
    table.pollstd = m_poll;
    table.pollnow = m_poll;
    table.macresave = m_macresave;
    table.vdata = m_vdata;
    table.safevdata = m_vdata;
    table.store = m_store;
    table.safestore = m_store;
    table.sdata = m_sdata;
    table.sstore = m_sstore;
    table.isstr = m_isstr;
    table.isstrl = m_isstrl;
    table.isbinary = m_isbinary;
    table.sdatalen = m_sdatalen;
    table.strldata = m_strldata;
    table.selobs = m_selobs;
    table.nobs1 = m_nobs1;
    table.nobs2 = m_nobs2;
    table.nobs = m_nobs;
    table.nvar = m_nvar;
    table.nvars = m_nvars;
    table.missval = MISSVAL;
    table.ismissing = m_ismissing;
    table.stopflag = &stopflag;
    table.spouterr = m_spouterr;
    table.major = 3;
    table.minor = 0;
}

/* ---------------------------------------------------------------- plugin loading */

typedef ST_retcode (*pginit_fn)(ST_plugin *);
typedef ST_retcode (*call_fn)(int, char **);
static call_fn stata_call_p;

static int load_plugin(const char *path) {
    void *pg, *sc;
#ifdef _WIN32
    HMODULE lib = LoadLibraryA(path);
    if (!lib) { fprintf(stderr, "cannot load %s (error %lu)\n", path, GetLastError()); return 0; }
    pg = (void *)GetProcAddress(lib, "pginit");
    sc = (void *)GetProcAddress(lib, "stata_call");
#else
    void *lib = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!lib) { fprintf(stderr, "cannot load %s: %s\n", path, dlerror()); return 0; }
    pg = dlsym(lib, "pginit");
    sc = dlsym(lib, "stata_call");
#endif
    if (!pg || !sc) { fprintf(stderr, "plugin lacks pginit/stata_call\n"); return 0; }
    ST_retcode ver = ((pginit_fn)pg)(&table);
    if (ver != SD_PLUGINVER) { fprintf(stderr, "pginit returned %d, expected %d\n", ver, SD_PLUGINVER); return 0; }
    stata_call_p = (call_fn)sc;
    return 1;
}

/* Calls the plugin: vars = dataset variables (terminated by -1), args = argv (NULL-terminated).
   Clears the locals first, so each test sees only what its call set. */
static int call(const int *vars, const char **args) {
    nvarlist = 0;
    while (vars[nvarlist] >= 0) { varlist[nvarlist] = vars[nvarlist]; nvarlist++; }
    int argc = 0;
    char *argv[64];
    while (args[argc]) { argv[argc] = (char *)args[argc]; argc++; }
    last_err[0] = 0;
    nmacros = 0;
    return stata_call_p(argc, argv);
}

/* ---------------------------------------------------------------- checks */

static int fails = 0;

static void pass(const char *what) { printf("PASS    %s\n", what); }
static void fail(const char *what, const char *why) { printf("FAIL    %s: %s\n", what, why); fails++; }

/* Bitwise equality of a numeric variable with want. Returns 1 when equal. */
static int same(const char *what, int var, const double *want) {
    for (int i = 0; i < NOBS; i++) {
        if (memcmp(&num[var][i], &want[i], sizeof(double)) != 0) {
            char why[160];
            snprintf(why, sizeof why, "obs %d: got %.17g, want %.17g", i + 1, num[var][i], want[i]);
            fail(what, why);
            return 0;
        }
    }
    return 1;
}

static double want[NOBS];

/* ---------------------------------------------------------------- tests */

static void test_version(void) {
    const char *args[] = {"version", NULL};
    int vars[] = {-1};
    int rc = call(vars, args);
    const char *v = macro_get("_fx_plugver");
    if (rc || !v || !*v) { fail("version", "no _fx_plugver local"); return; }
    printf("        plugin version %s\n", v);
    pass("version");
}

static void test_selftest(void) {
    for (int serial = 0; serial <= 1; serial++) {
        const char *what = serial ? "selftest (serial stores)" : "selftest (parallel stores)";
        reset_outputs();
        const char *args[] = {"selftest", "k=2", "sign=-1", "threads=4", serial ? "serialstore=1" : "serialstore=0", NULL};
        int vars[] = {V_X1, V_X2, V_O1, V_O2, -1};
        int rc = call(vars, args);
        if (rc) { fail(what, last_err); continue; }
        int ok = 1;
        for (int j = 0; j < 2 && ok; j++) {
            int x = j ? V_X2 : V_X1;
            for (int i = 0; i < NOBS; i++) want[i] = num[x][i] >= MISSVAL ? MISSVAL : -num[x][i];
            ok = same(what, j ? V_O2 : V_O1, want);
        }
        if (ok) pass(what);
    }
}

static void test_bad_argument(void) {
    const char *args[] = {"selftest", "k=1", "sign=1", "bogus=1", NULL};
    int vars[] = {V_X1, V_O1, -1};
    int rc = call(vars, args);
    if (rc != 198 || !strstr(last_err, "bogus")) {
        char why[1100];
        snprintf(why, sizeof why, "rc %d, message \"%s\"", rc, last_err);
        fail("bad argument gives r(198)", why);
        return;
    }
    pass("bad argument gives r(198)");
}

static void test_unknown_command(void) {
    const char *args[] = {"nosuchcommand", NULL};
    int vars[] = {-1};
    int rc = call(vars, args);
    if (rc != 198 || !strstr(last_err, "nosuchcommand")) {
        char why[1100];
        snprintf(why, sizeof why, "rc %d, message \"%s\"", rc, last_err);
        fail("unknown command gives r(198)", why);
        return;
    }
    pass("unknown command gives r(198)");
}

/* Two-phase protocol: runs the compute phase (vars, args), then `store` of the cached result into
   outs (terminated by -1) with the given thread count. Returns the first nonzero rc; *fallback
   (if not NULL) receives the fx_fallback reason ("" when the fast path ran). */
static int two_phase(const int *vars, const char **args, const int *outs, const char *threads,
                     char *fallback, size_t fallback_len) {
    int rc = call(vars, args);
    const char *fb = macro_get("_fx_fallback");
    if (fallback) snprintf(fallback, fallback_len, "%s", fb ? fb : "");
    if (rc || fb) return rc;
    const char *tok = macro_get("_fx_token");
    if (!tok) { snprintf(last_err, sizeof last_err, "no _fx_token local"); return -1; }
    char token[64], th[64];
    snprintf(token, sizeof token, "token=%s", tok);
    snprintf(th, sizeof th, "threads=%s", threads);
    const char *sargs[] = {"store", token, th, NULL};
    return call(outs, sargs);
}

static void test_cachetest(void) {
    for (int t = 0; t < 2; t++) {
        const char *what = t ? "cachetest + store (4 threads)" : "cachetest + store (1 thread)";
        reset_outputs();
        const char *args[] = {"cachetest", "nnum=2", t ? "threads=4" : "threads=1", NULL};
        int vars[] = {V_X1, V_X2, V_SKEY, -1};
        int outs[] = {V_O1, V_O2, V_SOUT, -1};
        int rc = two_phase(vars, args, outs, t ? "4" : "1", NULL, 0);
        if (rc) { fail(what, last_err); continue; }
        int ok = 1;
        for (int j = 0; j < 2 && ok; j++) {
            int x = j ? V_X2 : V_X1;
            for (int i = 0; i < NOBS; i++) want[i] = num[x][i] >= MISSVAL ? num[x][i] : -num[x][i];
            ok = same(what, j ? V_O2 : V_O1, want);
        }
        for (int i = 0; i < NOBS && ok; i++) {
            char w[STRW];
            snprintf(w, sizeof w, "%s!", str[V_SKEY][i]);
            if (strcmp(str[V_SOUT][i], w)) {
                char why[200];
                snprintf(why, sizeof why, "obs %d: got \"%s\", want \"%s\"", i + 1, str[V_SOUT][i], w);
                fail(what, why);
                ok = 0;
            }
        }
        if (ok) pass(what);
    }
}

/* A used token, and a token after a fallback emptied the cache, are stale: r(9999). */
static void test_stale_token(void) {
    const char *args[] = {"cachetest", "nnum=1", NULL};
    int vars[] = {V_X1, -1};
    int rc = call(vars, args);
    const char *tok = macro_get("_fx_token");
    if (rc || !tok) { fail("stale token", "cachetest failed"); return; }
    char token[64];
    snprintf(token, sizeof token, "token=%s", tok);
    const char *sargs[] = {"store", token, NULL};
    int outs[] = {V_O1, -1};
    int rc1 = call(outs, sargs);
    int rc2 = call(outs, sargs);
    rc = call(vars, args);
    tok = macro_get("_fx_token");
    if (rc || !tok) { fail("stale token", "second cachetest failed"); return; }
    snprintf(token, sizeof token, "token=%s", tok);
    const char *fargs[] = {"egen", NULL};
    int rc3 = call(vars, fargs);
    int fb = macro_get("_fx_fallback") != NULL;
    int rc4 = call(outs, sargs);
    if (rc1 || rc2 != 9999 || rc3 || !fb || rc4 != 9999) {
        char why[200];
        snprintf(why, sizeof why, "store rc %d, reuse rc %d, fallback rc %d (%s), store after fallback rc %d",
                 rc1, rc2, rc3, fb ? "set" : "not set", rc4);
        fail("stale token gives r(9999)", why);
        return;
    }
    pass("stale token gives r(9999)");
}

/* ---------------------------------------------------------------- per-command cases */

#include "mock_egen.c"
#include "mock_dup.c"
#include "mock_quant.c"
#include "mock_strnum.c"

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: mockhost <fastata plugin>\n");
        return 2;
    }
    make_data();
    init_table();
    if (!load_plugin(argv[1])) return 2;
    test_version();
    test_selftest();
    test_cachetest();
    test_stale_token();
    tests_egen();
    tests_dup();
    tests_quant();
    tests_strnum();
    test_bad_argument();
    test_unknown_command();
    printf("%s: %d failed\n", fails ? "MOCKHOST FAILED" : "MOCKHOST PASSED", fails);
    return fails ? 1 : 0;
}
