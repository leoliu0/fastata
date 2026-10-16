//! Stata plugin (SPI 3.0) behind fastata, fast drop-in versions of official Stata data commands.
//!
//! Only `pginit` and `stata_call` are exported. Every Stata API call goes through `c/glue.c`
//! (wrapped by [`io`]); worker threads live only inside a call ([`par`]). The commands follow
//! the two-phase protocol of [`cache`]; each documents its ado/plugin protocol in its module.

use std::ffi::{CStr, c_char, c_int, c_void};
use std::panic::{self, AssertUnwindSafe};
use std::sync::{Mutex, Once, PoisonError};

mod args;
mod cache;
mod dup;
mod egen;
mod error;
mod group;
mod io;
mod nan;
mod par;
mod quant;
mod selftest;
mod strnum;
mod strprobe;
#[cfg(test)]
mod testutil;
mod xtile;

use args::Args;
use error::{Error, Res};

/// `SD_PLUGINVER` = SF_MAKELONG(3, 0).
const SD_PLUGINVER: c_int = 3;

/// Message of the last panic (filled by the panic hook, consumed by `stata_call`).
static PANIC_MSG: Mutex<Option<String>> = Mutex::new(None);
static INIT: Once = Once::new();

/// Called by Stata when the plugin is loaded.
///
/// # Safety
/// `p` is the `ST_plugin*` table provided by Stata.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn pginit(p: *mut c_void) -> c_int {
    unsafe { io::set_plugin(p) };
    INIT.call_once(|| {
        panic::set_hook(Box::new(|info| {
            let msg = match info.payload().downcast_ref::<&str>() {
                Some(s) => (*s).to_string(),
                None => info.payload().downcast_ref::<String>().cloned().unwrap_or_else(|| "unknown panic".into()),
            };
            let loc = info.location().map(|l| format!(" at {}:{}", l.file(), l.line())).unwrap_or_default();
            *PANIC_MSG.lock().unwrap_or_else(PoisonError::into_inner) = Some(format!("{msg}{loc}"));
        }));
    });
    SD_PLUGINVER
}

/// Entry point of `plugin call`; `argv[0]` is the command.
///
/// A fallback ([`Error::fallback`]) sets local `fx_fallback` to the reason and returns 0. Any
/// other error is printed, stored in local `fx_errmsg` (the ado calls the plugin under `capture`,
/// which hides the printed message) and returned as the return code. Both empty the cache of the
/// two-phase protocol. Last, local `fx_locals` lists every local the call set.
///
/// # Safety
/// `argv` holds `argc` NUL-terminated strings (Stata guarantees this).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn stata_call(argc: c_int, argv: *mut *mut c_char) -> c_int {
    let argv: Vec<String> = (0..argc.max(0) as usize)
        .map(|i| unsafe { CStr::from_ptr(*argv.add(i)) }.to_string_lossy().into_owned())
        .collect();
    io::saved_locals();
    let rc = match panic::catch_unwind(AssertUnwindSafe(|| run(&argv))) {
        Ok(Ok(())) => 0,
        Ok(Err(e)) if e.is_fallback() => {
            cache::clear();
            match io::local_save("fx_fallback", &e.msg) {
                Ok(()) => 0,
                Err(e) => report(e),
            }
        }
        Ok(Err(e)) => {
            cache::clear();
            report(e)
        }
        Err(payload) => {
            cache::clear();
            let msg = PANIC_MSG.lock().unwrap_or_else(PoisonError::into_inner).take().unwrap_or_else(|| {
                payload
                    .downcast_ref::<&str>()
                    .map(|s| s.to_string())
                    .or_else(|| payload.downcast_ref::<String>().cloned())
                    .unwrap_or_else(|| "unknown panic".into())
            });
            report(Error::new(9999, format!("fastata: internal error (panic: {msg}); please report it")))
        }
    };
    // Best effort: without fx_locals, _fx_call copies no results, which the ado treats as a
    // failed call.
    let names = io::saved_locals();
    let _ = io::local_save("fx_locals", &names.join(" "));
    io::saved_locals();
    rc
}

/// Prints `err`, saves its message in local `fx_errmsg` and returns its return code.
fn report(err: Error) -> c_int {
    io::error(&format!("{err}\n"));
    // Best effort: the return code already reports the failure.
    let _ = io::local_save("fx_errmsg", &err.msg);
    err.rc
}

fn run(argv: &[String]) -> Res<()> {
    let a = Args::parse(argv)?;
    let spi = io::SpiIo::new();
    match a.cmd.as_str() {
        "version" => {
            a.only(&[])?;
            io::local_save("fx_plugver", env!("CARGO_PKG_VERSION"))
        }
        "selftest" => selftest::run(&spi, &a),
        "strprobe" => strprobe::run(&spi, &a),
        "cachetest" => cache::cachetest(&spi, &a),
        "store" => cache::store(&spi, &a),
        "egen" => egen::run(&spi, &a),
        "isid" => dup::run_isid(&spi, &a),
        "dup" => dup::run_dup(&spi, &a),
        "quant" => xtile::run(&spi, &a),
        "destring" => strnum::run_destring(&spi, &a),
        "tostring" => strnum::run_tostring(&spi, &a),
        c => Err(Error::syntax(format!("fastata plugin: unknown command `{c}`"))),
    }
}
