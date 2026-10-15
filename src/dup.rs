//! `isid` and `dup`: compute phases of fastata's isid and duplicates (slice B). Not implemented
//! yet: every call falls back.

use crate::args::Args;
use crate::error::{Error, Res};
use crate::io::Io;

pub fn run_isid<I: Io>(_io: &I, _a: &Args) -> Res<()> {
    Err(Error::fallback("not implemented"))
}

pub fn run_dup<I: Io>(_io: &I, _a: &Args) -> Res<()> {
    Err(Error::fallback("not implemented"))
}
