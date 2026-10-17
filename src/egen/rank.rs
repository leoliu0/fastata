//! `rank()` over one large group (no by-groups, or a by-group of at least [`BIG`] sample
//! observations) in parallel: a sample sort of `(key, observation)` pairs. Splitters from a
//! sample of the keys cut the key range into buckets; per chunk of members, pass 1 counts the
//! pairs of each bucket and pass 2 writes them to their place; pass 3 sorts each bucket and
//! hands every observation its rank. Equal keys always fall into the same bucket, and a rank
//! (lowest rank, ties) depends only on the multiset of values, so the result is the same for any
//! thread count, bucket count or tie order.

use std::sync::{Mutex, PoisonError};

use super::spec::{OVERFLOW, is_code};
use crate::error::{Error, Res, vec_filled, vec_with_capacity, vec_zeroed};
use crate::io::Io;
use crate::par::{Shared, StoreMode, for_blocks, threads_for_rows};

/// Groups of at least this many sample observations are ranked here instead of by a worker of
/// `for_groups` that sorts the group on its own.
pub const BIG: usize = 1 << 17;

/// Members per chunk of passes 1 and 2.
const CHUNK: usize = 1 << 16;

/// Buckets per thread.
const BUCKETS_PER_THREAD: usize = 8;

/// Sample keys per bucket for the splitters.
const SAMPLE_PER_BUCKET: usize = 32;

/// Falls back [overflow] for an input value whose `field` rank differs from its raw rank: the
/// original ranks `-(exp)`, which turns a number at or below −`.` into a raw missing value and a
/// raw value beyond `.` into a number.
#[inline]
pub fn check_input(v: f64, field: bool, miss: f64) -> Res<()> {
    if field && (v <= -miss || (v >= miss && !is_code(v, miss))) { Err(Error::fallback(OVERFLOW)) } else { Ok(()) }
}

/// Order-preserving key of a nonmissing value, -0 as +0; descending for `field`.
#[inline]
fn key(v: f64, field: bool) -> u64 {
    let b = (if v == 0.0 { 0.0 } else { v }).to_bits();
    let k = if b >> 63 == 1 { !b } else { b | (1 << 63) };
    if field { !k } else { k }
}

/// Ranks the members with a nonmissing value `x[o]` (ascending, or descending for `field`):
/// `put(o, lowest rank, ties)` once for each of them, in no particular order. Returns the number
/// of members with a missing value (they get no call).
pub fn rank_big<I, F>(io: &I, x: &[f64], members: &[u32], field: bool, miss: f64, threads: usize, put: F) -> Res<usize>
where
    I: Io,
    F: Fn(u32, usize, usize) -> Res<()> + Sync,
{
    let m = members.len();
    let t = threads_for_rows(threads, m);
    let nc = m.div_ceil(CHUNK);
    let chunk = |c: usize| &members[c * CHUNK..((c + 1) * CHUNK).min(m)];

    // Splitters: evenly spaced members' keys, sorted; bucket(k) = splitters below k.
    let mut splitters: Vec<u64> = Vec::new();
    if t > 1 {
        let nb = t * BUCKETS_PER_THREAD;
        let step = (m / (nb * SAMPLE_PER_BUCKET)).max(1);
        let mut sample: Vec<u64> = vec_with_capacity(m / step + 1)?;
        sample.extend(members.iter().step_by(step).map(|&o| x[o as usize]).filter(|&v| v < miss).map(|v| key(v, field)));
        sample.sort_unstable();
        if !sample.is_empty() {
            splitters = vec_with_capacity(nb - 1)?;
            splitters.extend((1..nb).map(|b| sample[b * sample.len() / nb]));
        }
    }
    let nb = splitters.len() + 1;
    let bucket = |k: u64| splitters.partition_point(|&s| s < k);

    // Pass 1: pairs per (chunk, bucket), and missing values.
    let counts = for_blocks(io, nc, t, StoreMode::Parallel, |c, _emit| {
        let mut cnt = vec_filled(nb, 0usize)?;
        let mut nmiss = 0;
        for &o in chunk(c) {
            let v = x[o as usize];
            check_input(v, field, miss)?;
            if v < miss {
                cnt[bucket(key(v, field))] += 1;
            } else {
                nmiss += 1;
            }
        }
        Ok((cnt, nmiss))
    })?;

    // Offsets: bucket b starts at start[b]; chunk c writes its pairs of bucket b from off[c][b].
    let mut start = vec_filled(nb + 1, 0usize)?;
    for (cnt, _) in &counts {
        for b in 0..nb {
            start[b + 1] += cnt[b];
        }
    }
    for b in 0..nb {
        start[b + 1] += start[b];
    }
    let nn = start[nb];
    let mut off: Vec<Vec<usize>> = vec_with_capacity(nc)?;
    let mut next = start.clone();
    for (cnt, _) in &counts {
        let mut o = vec_filled(nb, 0usize)?;
        for b in 0..nb {
            o[b] = next[b];
            next[b] += cnt[b];
        }
        off.push(o);
    }
    let nmiss = counts.iter().map(|(_, k)| k).sum();
    drop(counts);

    // Pass 2: the pairs, in their buckets.
    let mut pairs: Vec<(u64, u32)> = vec_zeroed(nn)?;
    let dst = Shared::new(&mut pairs);
    for_blocks(io, nc, t, StoreMode::Parallel, |c, _emit| {
        let mut pos = vec_filled(nb, 0usize)?;
        pos.copy_from_slice(&off[c]);
        for &o in chunk(c) {
            let v = x[o as usize];
            if v < miss {
                let k = key(v, field);
                let b = bucket(k);
                debug_assert!(pos[b] < start[b + 1]);
                // SAFETY: chunk c owns positions off[c][b] .. off[c][b] + (its count of bucket
                // b), disjoint from every other chunk's and inside `pairs` (pass 1 counted them).
                unsafe { dst.set(pos[b], (k, o)) };
                pos[b] += 1;
            }
        }
        Ok(())
    })?;

    // Pass 3: sort each bucket, then ranks: the run of equal keys at [i, j) of bucket b has the
    // lowest rank start[b] + i + 1 and j - i ties.
    let mut slots: Vec<Mutex<&mut [(u64, u32)]>> = vec_with_capacity(nb)?;
    let mut rest = &mut pairs[..];
    for b in 0..nb {
        let (head, tail) = rest.split_at_mut(start[b + 1] - start[b]);
        slots.push(Mutex::new(head));
        rest = tail;
    }
    for_blocks(io, nb, t, StoreMode::Parallel, |b, _emit| {
        let mut s = slots[b].lock().unwrap_or_else(PoisonError::into_inner);
        s.sort_unstable_by_key(|p| p.0);
        let mut i = 0;
        while i < s.len() {
            let mut j = i + 1;
            while j < s.len() && s[j].0 == s[i].0 {
                j += 1;
            }
            for p in &s[i..j] {
                put(p.1, start[b] + i + 1, j - i)?;
            }
            i = j;
        }
        Ok(())
    })?;
    Ok(nmiss)
}
