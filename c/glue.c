/*
    glue.c -- the only code in fastata that touches the Stata plugin interface (SPI 3.0).

    Compiled by build.rs with -DSYSTEM=OPUNIX|STWIN32 -DSD_FASTMODE and hidden visibility:
    nothing here is exported from the plugin (only the Rust `pginit` / `stata_call` are).
    Observation and variable indices are 1-based, as in Stata.

    fx_read_block and fx_write_block may run concurrently on disjoint observations (reads are
    verified safe by fereg's stress_io.do, writes by center2's tests/stata/stress_store.do); every
    other function must run on Stata's thread.
*/

#include <math.h>
#include <string.h>
#include "stplugin.h"

#if defined(__GNUC__) || defined(__clang__)
#define FX_HIDDEN __attribute__((visibility("hidden")))
#else
#define FX_HIDDEN
#endif

FX_HIDDEN ST_plugin *_stata_ = 0;

FX_HIDDEN void fx_set_plugin(void *p) { _stata_ = (ST_plugin *)p; }

FX_HIDDEN int fx_nobs(void) { return SF_nobs(); }
FX_HIDDEN int fx_nvars(void) { return SF_nvars(); }
FX_HIDDEN double fx_missval(void) { return SV_missval; }

/* Reads n rows x nv variables into out, row-major: out[r*nv + j] = vars[j] at the r-th row.
   The rows are the 0-based observations obs[0..n-1] when obs != NULL, else first..first+n-1.
   Values are raw: Stata missing values (. and .a-.z) stay >= SV_missval. Returns 0 or the SPI
   return code. */
FX_HIDDEN int fx_read_block(const int *vars, int nv, const unsigned int *obs, int first, int n, double *out) {
    for (int r = 0; r < n; r++) {
        int o = (obs ? (int)obs[r] : first + r) + 1;
        double *row = out + (size_t)r * (size_t)nv;
        for (int j = 0; j < nv; j++) {
            ST_double z;
            ST_retcode rc = SF_vdata(vars[j], o, &z);
            if (rc) return rc;
            row[j] = z;
        }
    }
    return 0;
}

/* Writes vals (row-major, rows as in fx_read_block) into the variables; non-finite values are
   stored as missing (.). skip may be NULL; skip[r*nv + j] != 0 leaves that cell untouched. Uses
   the checked safestore even under SD_FASTMODE: the unchecked store indexes variables by dataset
   position, not by varlist position (verified for fereg in Stata 19.5). */
FX_HIDDEN int fx_write_block(const int *vars, int nv, const unsigned int *obs, int first, int n, const double *vals,
                             const unsigned char *skip) {
    ST_double mv = SV_missval;
    for (int r = 0; r < n; r++) {
        int o = (obs ? (int)obs[r] : first + r) + 1;
        size_t base = (size_t)r * (size_t)nv;
        for (int j = 0; j < nv; j++) {
            if (skip && skip[base + j]) continue;
            double z = vals[base + j];
            ST_retcode rc = _stata_->safestore(vars[j], o, isfinite(z) ? z : mv);
            if (rc) return rc;
        }
    }
    return 0;
}

FX_HIDDEN int fx_is_str(int var) { return SF_var_is_string(var) ? 1 : 0; }
FX_HIDDEN int fx_is_strl(int var) { return SF_var_is_strl(var) ? 1 : 0; }

/* str# value into buf (at least 2046 bytes). Returns the length, or -rc on error. */
FX_HIDDEN int fx_read_str(int var, int obs, char *buf) {
    buf[0] = 0;
    ST_retcode rc = SF_sdata(var, obs, buf);
    if (rc) return -rc;
    return (int)strlen(buf);
}

/* strL: byte length of the value (excluding any terminator), or -198 for a binary strL. */
FX_HIDDEN int fx_strl_len(int var, int obs) {
    if (SF_var_is_binary(var, obs)) return -198;
    return SF_sdatalen(var, obs);
}

/* strL value into buf of capacity cap (len + 1). Returns the rc of SF_strldata (bytes copied or <0). */
FX_HIDDEN int fx_read_strl(int var, int obs, char *buf, int cap) { return SF_strldata(var, obs, buf, cap); }

/* Stores the NUL-terminated string s into string variable var at obs. Returns 0 or the SPI rc. */
FX_HIDDEN int fx_write_str(int var, int obs, const char *s) { return SF_sstore(var, obs, (char *)s); }

/* name "_x" sets local x of the calling program. */
FX_HIDDEN int fx_macro_save(const char *name, const char *value) { return SF_macro_save((char *)name, (char *)value); }

FX_HIDDEN void fx_error(const char *s) { SF_error((char *)s); }
