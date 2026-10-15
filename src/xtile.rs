//! `quant`: compute phase of fastata's xtile and pctile (slice C). Not implemented yet: every
//! call falls back.

use crate::args::Args;
use crate::error::{Error, Res};
use crate::io::Io;

pub fn run<I: Io>(_io: &I, _a: &Args) -> Res<()> {
    Err(Error::fallback("not implemented"))
}
