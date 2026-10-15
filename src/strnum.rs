//! `destring` and `tostring`: compute phases of fastata's destring and tostring (slice D). Not
//! implemented yet: every call falls back.

use crate::args::Args;
use crate::error::{Error, Res};
use crate::io::Io;

pub fn run_destring<I: Io>(_io: &I, _a: &Args) -> Res<()> {
    Err(Error::fallback("not implemented"))
}

pub fn run_tostring<I: Io>(_io: &I, _a: &Args) -> Res<()> {
    Err(Error::fallback("not implemented"))
}
