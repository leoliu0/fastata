//! Grouping observations by key tuples (numeric, str# or strL keys), shared by egen (`by()`,
//! `group()`, `tag()`), `duplicates` and `isid`.
//!
//! Two observations are in one group when every numeric key has the same value (−0 equals +0;
//! each missing code is a value of its own) and every string key has the same bytes: the groups
//! of Stata's `by` on data sorted by the keys.
//!
//! [`Keyed::read`] reads the keys of the sample once:
//! - up to [`STORED_KEYS`] key variables it keeps the key values (a [`KeyView`]: numeric keys as
//!   bits with −0 stored as +0, string keys as one flat byte buffer each), so groups compare keys
//!   directly and callers can sort groups by key;
//! - with more key variables it keeps only a 64-bit hash per observation, so the working memory
//!   per observation does not grow with the number of keys; groups of equal hashes are then
//!   checked against the data (their rows read again) and split where rows differ.
//!
//! Numeric keys are read for every observation, so a NaN anywhere in a key falls back (the
//! originals sort by the keys, and Stata's sort never returns on a NaN). Strings are read on the
//! calling thread, at the sample observations only.
//!
//! [`Keyed::group`] groups data whose sample is already in key order by runs, other data by hash:
//! fixed partitions (none below [`KEY_CHUNK`] observations), each with a growable table sized by
//! its distinct keys. Group order is internal (partition, then first appearance) and never
//! depends on the thread count; observations are ascending inside a group, so the first is the
//! group's lowest.

use std::cmp::Ordering;

use crate::error::{Error, Res, Zeroable, vec_filled, vec_with_capacity, vec_zeroed};
use crate::io::{Io, Rows};
use crate::par::{Shared, StoreMode, for_blocks, threads_for_rows};

/// Positions per work item when scanning keys, samples and groups.
pub const KEY_CHUNK: usize = 65_536;

/// Hash partitions (top 8 hash bits) of samples of [`KEY_CHUNK`] observations or more.
const PARTS: usize = 256;

/// Key variables up to which [`Keyed`] keeps the key values; with more, it keeps hashes only.
pub const STORED_KEYS: usize = 4;

/// Values per numeric read buffer.
const BLOCK_VALUES: usize = 1 << 17;

/// Room for one str# value (str2045 plus its terminator), reserved before each string read.
const STR_ROOM: usize = 2046;

/// Item `c` of `len` positions cut into [`KEY_CHUNK`]s.
fn chunk(c: usize, len: usize) -> std::ops::Range<usize> {
    c * KEY_CHUNK..((c + 1) * KEY_CHUNK).min(len)
}

/// Runs `f(i)` for every `i` in `0..len`, in parallel chunks.
pub fn par_for<I, F>(io: &I, len: usize, threads: usize, f: F) -> Res<()>
where
    I: Io,
    F: Fn(usize) -> Res<()> + Sync,
{
    for_blocks(io, len.div_ceil(KEY_CHUNK), threads_for_rows(threads, len), StoreMode::Parallel, |c, _emit| {
        chunk(c, len).try_for_each(&f)
    })?;
    Ok(())
}

/// `[f(0), .., f(len - 1)]`, computed in parallel chunks.
pub fn par_map<I, T, F>(io: &I, len: usize, threads: usize, f: F) -> Res<Vec<T>>
where
    I: Io,
    T: Zeroable + Send,
    F: Fn(usize) -> Res<T> + Sync,
{
    let mut out = vec_zeroed(len)?;
    let sh = Shared::new(&mut out);
    par_for(io, len, threads, |i| {
        // SAFETY: each index is written by the one chunk that holds it.
        unsafe { sh.set(i, f(i)?) };
        Ok(())
    })?;
    Ok(out)
}

/// Sorts `v` by `cmp` in parallel (sorted chunks, then rounds of pairwise merges, each merge cut
/// into pieces along its merge path so every round uses every thread). The result is the same
/// for any thread count when `cmp` orders no two elements of `v` as equal.
pub fn par_sort_by<I, T, F>(io: &I, v: &mut Vec<T>, threads: usize, cmp: F) -> Res<()>
where
    I: Io,
    T: Copy + Send + Sync,
    F: Fn(&T, &T) -> Ordering + Sync,
{
    let n = v.len();
    let t = threads_for_rows(threads, n);
    if t <= 1 {
        v.sort_unstable_by(&cmp);
        return Ok(());
    }
    let width0 = n.div_ceil(t);
    {
        let sh = Shared::new(&mut v[..]);
        for_blocks(io, n.div_ceil(width0), t, StoreMode::Parallel, |c, _emit| {
            // SAFETY: chunks are disjoint.
            let s = unsafe { sh.slice(c * width0, ((c + 1) * width0).min(n)) };
            s.sort_unstable_by(&cmp);
            Ok(())
        })?;
    }
    // a before b on equal elements
    let before = |x: &T, y: &T| cmp(x, y) != Ordering::Greater;
    let mut src = std::mem::take(v);
    let mut dst = vec_filled(n, src[0])?;
    let mut width = width0;
    while width < n {
        let pairs = n.div_ceil(2 * width);
        let per = t.div_ceil(pairs);
        {
            let (s, d) = (&src, Shared::new(&mut dst));
            for_blocks(io, pairs * per, t, StoreMode::Parallel, |it, _emit| {
                let (k, piece) = (it / per, it % per);
                let lo = k * 2 * width;
                let mid = (lo + width).min(n);
                let hi = (lo + 2 * width).min(n);
                let (a, b) = (&s[lo..mid], &s[mid..hi]);
                let size = (hi - lo).div_ceil(per);
                let k0 = (piece * size).min(hi - lo);
                let k1 = (k0 + size).min(hi - lo);
                // elements of a among the first k outputs of the merge
                let corank = |k: usize| {
                    let (mut l, mut h) = (k.saturating_sub(b.len()), k.min(a.len()));
                    while l < h {
                        let i = (l + h) / 2;
                        if before(&a[i], &b[k - i - 1]) { l = i + 1 } else { h = i }
                    }
                    l
                };
                let (mut i, i1) = (corank(k0), corank(k1));
                let (mut j, j1) = (k0 - i, k1 - i1);
                // SAFETY: pieces are disjoint.
                for o in unsafe { d.slice(lo + k0, lo + k1) } {
                    *o = if j == j1 || (i < i1 && before(&a[i], &b[j])) {
                        i += 1;
                        a[i - 1]
                    } else {
                        j += 1;
                        b[j - 1]
                    };
                }
                Ok(())
            })?;
        }
        std::mem::swap(&mut src, &mut dst);
        width *= 2;
    }
    *v = src;
    Ok(())
}

/// Reads numeric variable `var` as flags (`!= 0`) for every observation.
pub fn read_flags<I: Io>(io: &I, var: i32, threads: usize) -> Res<Vec<bool>> {
    let n = io.nobs();
    let mut out = vec_zeroed(n)?;
    let sh = Shared::new(&mut out);
    for_blocks(io, n.div_ceil(KEY_CHUNK), threads_for_rows(threads, n), StoreMode::Parallel, |c, _emit| {
        let r = chunk(c, n);
        let mut buf = vec_filled(r.len(), 0.0)?;
        io.read_block(&[var], Rows::Range { first: r.start, n: r.len() }, &mut buf)?;
        // SAFETY: chunks are disjoint.
        let dst = unsafe { sh.slice(r.start, r.end) };
        for (d, &v) in dst.iter_mut().zip(&buf) {
            *d = v != 0.0;
        }
        Ok(())
    })?;
    Ok(out)
}

/// The observations with `touse[o]`, ascending (sample positions to observations).
pub fn sample_from_bools<I: Io>(io: &I, touse: &[bool], threads: usize) -> Res<Vec<u32>> {
    let n = touse.len();
    let nch = n.div_ceil(KEY_CHUNK);
    let th = threads_for_rows(threads, n);
    let counts = for_blocks(io, nch, th, StoreMode::Parallel, |c, _emit| Ok(touse[chunk(c, n)].iter().filter(|&&t| t).count()))?;
    let mut off = vec_with_capacity(nch)?;
    let mut acc = 0;
    for k in counts {
        off.push(acc);
        acc += k;
    }
    let mut samp = vec_zeroed(acc)?;
    let sh = Shared::new(&mut samp);
    for_blocks(io, nch, th, StoreMode::Parallel, |c, _emit| {
        let mut k = off[c];
        for o in chunk(c, n) {
            if touse[o] {
                // SAFETY: chunk c writes positions off[c]..off[c + 1] only.
                unsafe { sh.set(k, o as u32) };
                k += 1;
            }
        }
        Ok(())
    })?;
    Ok(samp)
}

/// Group starts over observations `0..n` of data sorted by `keys` (the `by` prefix guarantees
/// it): a group starts where any key differs from the previous observation under f64 `!=`, so
/// −0 equals +0 and `.` differs from `.a`, as in Stata's `by`. Returns `[0, starts.., n]`. A NaN
/// in a key falls back.
pub fn sorted_starts<I: Io>(io: &I, keys: &[i32], n: usize, threads: usize) -> Res<Vec<usize>> {
    let nk = keys.len();
    let parts = for_blocks(io, n.div_ceil(KEY_CHUNK), threads, StoreMode::Parallel, |c, _emit| {
        let r = chunk(c, n);
        let from = r.start.saturating_sub(1);
        let mut buf = vec_filled((r.end - from) * nk, 0.0)?;
        io.read_block(keys, Rows::Range { first: from, n: r.end - from }, &mut buf)?;
        crate::nan::check(&buf)?;
        let new = |i: usize| {
            let q = i - from;
            buf[q * nk..(q + 1) * nk] != buf[(q - 1) * nk..q * nk]
        };
        let firsts = r.start.max(1)..r.end;
        let mut out = vec_with_capacity(firsts.clone().filter(|&i| new(i)).count())?;
        out.extend(firsts.filter(|&i| new(i)));
        Ok(out)
    })?;
    let mut starts = vec_with_capacity(2 + parts.iter().map(Vec::len).sum::<usize>())?;
    starts.push(0);
    for p in parts {
        starts.extend(p);
    }
    starts.push(n);
    Ok(starts)
}

const SEED: u64 = 0x9e37_79b9_7f4a_7c15;

/// splitmix64 finalizer (a bijection of u64).
#[inline]
fn mix(mut z: u64) -> u64 {
    z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    z ^ (z >> 31)
}

fn fnv1a(bytes: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for &b in bytes {
        h ^= u64::from(b);
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    h
}

/// The bits of a key value, with −0 stored as +0.
#[inline]
fn canon(v: f64) -> u64 {
    if v == 0.0 { 0 } else { v.to_bits() }
}

/// Hash of the numeric keys of a row (bits from [`canon`]).
#[inline]
fn hash_num(bits: impl Iterator<Item = u64>) -> u64 {
    bits.fold(SEED, |h, b| mix(h ^ b))
}

/// Hash of a row from the hash of its numeric keys and, with string keys, of its strings.
#[inline]
fn finish(hn: u64, hs: Option<u64>) -> u64 {
    match hs {
        Some(s) => mix(hn ^ s),
        None => hn,
    }
}

/// Order-preserving map of [`canon`] bits to u64: Stata's numeric order, missing codes after
/// every number in the order `.` < `.a` < ... < `.z`.
#[inline]
pub fn okey(bits: u64) -> u64 {
    if bits >> 63 == 1 { !bits } else { bits | 1 << 63 }
}

#[derive(Clone, Copy)]
enum Kind {
    Num(usize),
    Str(usize),
}

struct StrCol {
    off: Vec<usize>,
    bytes: Vec<u8>,
}

impl StrCol {
    fn get(&self, p: usize) -> &[u8] {
        &self.bytes[self.off[p]..self.off[p + 1]]
    }
}

/// Key values by position.
pub struct KeyView {
    kinds: Vec<Kind>,
    nnum: usize,
    /// Numeric keys, `nnum` per position: [`canon`] bits.
    num: Vec<u64>,
    strs: Vec<StrCol>,
    /// Hash of the string keys of each position (empty without string keys).
    shash: Vec<u64>,
}

impl KeyView {
    fn row(&self, p: usize) -> &[u64] {
        &self.num[p * self.nnum..(p + 1) * self.nnum]
    }

    fn eq(&self, a: usize, b: usize) -> bool {
        self.row(a) == self.row(b) && self.strs.iter().all(|s| s.get(a) == s.get(b))
    }

    /// Stata's sort order of the key tuples at positions `a` and `b`: numbers ascending (missing
    /// codes after every number, `.` < `.a` < ... < `.z`), strings bytewise with a prefix first,
    /// lexicographic in varlist order.
    pub fn cmp(&self, a: usize, b: usize) -> Ordering {
        for kind in &self.kinds {
            let o = match *kind {
                Kind::Num(j) => okey(self.num[a * self.nnum + j]).cmp(&okey(self.num[b * self.nnum + j])),
                Kind::Str(c) => self.strs[c].get(a).cmp(self.strs[c].get(b)),
            };
            if o != Ordering::Equal {
                return o;
            }
        }
        Ordering::Equal
    }

    fn hash(&self, p: usize) -> u64 {
        finish(hash_num(self.row(p).iter().copied()), self.shash.get(p).copied())
    }

    /// Number of numeric keys; every key is numeric when it equals [`KeyView::nkeys`].
    pub fn nnum(&self) -> usize {
        self.nnum
    }

    pub fn nkeys(&self) -> usize {
        self.kinds.len()
    }

    /// [`okey`] of the `j`-th numeric key at position `p`.
    pub fn num_okey(&self, p: usize, j: usize) -> u64 {
        okey(self.num[p * self.nnum + j])
    }

    /// An order-preserving prefix of the keys at position `p`: two positions whose prefixes differ
    /// compare as their prefixes. A number contributes its [`okey`], a string its first bytes
    /// big-endian, padded with zero bytes (which no Stata string holds): the first key and, after
    /// a numeric first key, the second.
    pub fn prefix(&self, p: usize) -> (u64, u64) {
        let word = |s: &[u8], from: usize| {
            let mut w = [0u8; 8];
            let s = s.get(from..).unwrap_or(&[]);
            let m = s.len().min(8);
            w[..m].copy_from_slice(&s[..m]);
            u64::from_be_bytes(w)
        };
        let num = |j: usize| okey(self.num[p * self.nnum + j]);
        match self.kinds[0] {
            Kind::Str(c) => {
                let s = self.strs[c].get(p);
                (word(s, 0), word(s, 8))
            }
            Kind::Num(j) => match self.kinds.get(1) {
                Some(&Kind::Num(j1)) => (num(j), num(j1)),
                Some(&Kind::Str(c)) => (num(j), word(self.strs[c].get(p), 0)),
                None => (num(j), 0),
            },
        }
    }

    /// Whether key `k` (varlist order) is numeric and holds an integer at position `p`.
    pub fn is_int(&self, k: usize, p: usize) -> bool {
        match self.kinds[k] {
            Kind::Num(j) => {
                let v = f64::from_bits(self.num[p * self.nnum + j]);
                v == v.trunc()
            }
            Kind::Str(_) => false,
        }
    }
}

#[derive(Clone, Copy, Default)]
pub struct ReadOpts {
    /// Flag the positions with a missing key (a numeric missing code, or "" in a string).
    pub miss: bool,
    /// Fall back [string blanks] when a string value starts or ends with a byte outside
    /// 0x21..=0x7e (isid: the original may then print a note about blanks).
    pub blanks: bool,
}

/// Which observations a read covers.
#[derive(Clone, Copy)]
enum Src<'a> {
    /// Every observation `0..n` is read (the NaN check covers them all); the positions are the
    /// sample observations `samp` (all when `None`).
    All { n: usize, samp: Option<&'a [u32]> },
    /// Exactly these observations: position `p` is `list[p]`.
    List(&'a [u32]),
}

impl Src<'_> {
    fn len(&self) -> usize {
        match *self {
            Src::All { n, samp } => samp.map_or(n, <[u32]>::len),
            Src::List(l) => l.len(),
        }
    }

    fn obs(&self, p: usize) -> usize {
        match *self {
            Src::All { samp: Some(s), .. } => s[p] as usize,
            Src::All { samp: None, .. } => p,
            Src::List(l) => l[p] as usize,
        }
    }
}

struct Read {
    kv: Option<KeyView>,
    h: Vec<u64>,
    miss: Vec<bool>,
}

fn as_f64_mut(s: &mut [u64]) -> &mut [f64] {
    // SAFETY: u64 and f64 have the same size and alignment, and every bit pattern is valid for
    // both.
    unsafe { std::slice::from_raw_parts_mut(s.as_mut_ptr().cast::<f64>(), s.len()) }
}

/// Reads the keys at the positions of `src`: the values (`store`) or only a hash per position.
#[allow(clippy::too_many_arguments)]
fn read_keys<I: Io>(io: &I, kinds: &[Kind], numv: &[i32], strv: &[i32], src: Src<'_>, threads: usize, store: bool, opts: ReadOpts) -> Res<Read> {
    let ns = src.len();
    let nnum = numv.len();
    let mut miss = if opts.miss { vec_zeroed(ns)? } else { Vec::new() };
    // Without stored keys: the hash of each position (the string part first, from the string
    // pass; the numeric pass folds its part in).
    let mut h = if store { Vec::new() } else { vec_zeroed(ns)? };
    let mut strs = Vec::new();
    let mut shash = Vec::new();

    // 1. Strings, on this thread (stored strings are hashed afterwards, in parallel).
    if !strv.is_empty() {
        if store {
            for _ in strv {
                strs.push(StrCol { off: vec_zeroed(ns + 1)?, bytes: Vec::new() });
            }
        }
        let mut buf = Vec::new();
        let bad = |b: u8| b <= 0x20 || b >= 0x7f;
        for p in 0..ns {
            let o = src.obs(p);
            let mut hs = SEED;
            let mut m = false;
            for (c, &v) in strv.iter().enumerate() {
                let bytes = if store {
                    &mut strs[c].bytes
                } else {
                    buf.clear();
                    &mut buf
                };
                let start = bytes.len();
                if bytes.capacity() - start < STR_ROOM {
                    bytes.try_reserve(STR_ROOM).map_err(|_| Error::oom())?;
                }
                io.read_str(v, o, bytes)?;
                let end = bytes.len();
                let s = &bytes[start..];
                if opts.blanks && s.first().is_some_and(|&f| bad(f) || bad(s[s.len() - 1])) {
                    return Err(Error::fallback("string blanks"));
                }
                m |= s.is_empty();
                if store {
                    strs[c].off[p + 1] = end;
                } else {
                    hs = mix(hs ^ fnv1a(s));
                }
            }
            if !store {
                h[p] = hs;
            }
            if opts.miss {
                miss[p] = m;
            }
        }
        if store {
            shash = par_map(io, ns, threads, |p| Ok(strs.iter().fold(SEED, |hs, c| mix(hs ^ fnv1a(c.get(p))))))?;
        }
    }

    // 2. Numeric keys, in parallel blocks of observations.
    let mut num = if store { vec_zeroed(ns * nnum)? } else { Vec::new() };
    if nnum > 0 {
        let missval = io.missval();
        let total = match src {
            Src::All { n, .. } => n,
            Src::List(l) => l.len(),
        };
        let rows = (BLOCK_VALUES / nnum).clamp(1, KEY_CHUNK);
        let th = threads_for_rows(threads, total.saturating_mul(nnum));
        let has_str = !strv.is_empty();
        let samp = match src {
            Src::All { samp, .. } => samp,
            Src::List(_) => None,
        };
        let (s_num, s_h, s_m) = (Shared::new(&mut num), Shared::new(&mut h), Shared::new(&mut miss));
        for_blocks(io, total.div_ceil(rows), th, StoreMode::Parallel, |b, _emit| {
            let lo = b * rows;
            let hi = (lo + rows).min(total);
            // positions plo..phi lie in this block
            let (plo, phi) = match samp {
                Some(s) => (s.partition_point(|&o| (o as usize) < lo), s.partition_point(|&o| (o as usize) < hi)),
                None => (lo, hi),
            };
            let direct = store && samp.is_none();
            let mut own: Vec<f64>;
            let buf: &mut [f64] = if direct {
                // SAFETY: positions plo..phi belong to this block only.
                as_f64_mut(unsafe { s_num.slice(plo * nnum, phi * nnum) })
            } else {
                own = vec_filled((hi - lo) * nnum, 0.0)?;
                &mut own
            };
            let rows_read = match src {
                Src::All { .. } => Rows::Range { first: lo, n: hi - lo },
                Src::List(l) => Rows::List(&l[lo..hi]),
            };
            io.read_block(numv, rows_read, buf)?;
            crate::nan::check(buf)?;
            for p in plo..phi {
                let r = samp.map_or(p - lo, |s| s[p] as usize - lo);
                let row = &buf[r * nnum..(r + 1) * nnum];
                // SAFETY (all writes below): position p belongs to this block only.
                if opts.miss && row.iter().any(|&v| crate::io::is_miss(v, missval)) {
                    unsafe { s_m.set(p, true) };
                }
                if !store {
                    let hs = if has_str { Some(unsafe { s_h.get(p) }) } else { None };
                    unsafe { s_h.set(p, finish(hash_num(row.iter().map(|&v| canon(v))), hs)) };
                } else if !direct {
                    for (j, &v) in row.iter().enumerate() {
                        unsafe { s_num.set(p * nnum + j, canon(v)) };
                    }
                }
            }
            if direct {
                for x in buf.iter_mut() {
                    if *x == 0.0 {
                        *x = 0.0;
                    }
                }
            }
            Ok(())
        })?;
    }
    let kv = store.then(|| KeyView { kinds: kinds.to_vec(), nnum, num, strs, shash });
    Ok(Read { kv, h, miss })
}

/// Groups of the sample: what [`Keyed::group`] was asked for ([`Need`]).
#[derive(Default)]
pub struct Grouped {
    pub ngroups: usize,
    /// Group of each sample position.
    pub gid: Vec<u32>,
    /// Sample observations grouped, ascending inside a group: group `g` is
    /// `ord[starts[g]..starts[g + 1]]`.
    pub ord: Vec<u32>,
    pub starts: Vec<usize>,
    /// Position of each group's lowest observation.
    pub reps: Vec<u32>,
    /// Observations per group.
    pub sizes: Vec<u32>,
}

/// What [`Keyed::group`] returns besides the number of groups.
#[derive(Clone, Copy, Default)]
pub struct Need {
    pub gid: bool,
    /// `ord` and `starts`.
    pub ord: bool,
    pub reps: bool,
    pub sizes: bool,
}

impl Need {
    fn any(self) -> bool {
        self.gid || self.ord || self.reps || self.sizes
    }
}

/// Key values of some groups, by group index: the stored view, or one read for them.
pub struct RepKeys<'a> {
    stored: Option<&'a KeyView>,
    read: Option<KeyView>,
    reps: &'a [u32],
}

impl RepKeys<'_> {
    pub fn view(&self) -> &KeyView {
        self.stored.or(self.read.as_ref()).expect("a key view")
    }

    /// Position in [`RepKeys::view`] of group `i` (of the `reps` the keys were taken for).
    pub fn pos(&self, i: usize) -> usize {
        if self.stored.is_some() { self.reps[i] as usize } else { i }
    }
}

const EMPTY: u32 = u32::MAX;

/// Open addressing on the hash; grows at half load, so its size follows the distinct keys.
struct Table {
    slots: Vec<(u64, u32, u32)>,
    mask: usize,
    len: usize,
}

impl Table {
    fn new(members: usize) -> Res<Table> {
        let cap = (2 * members).next_power_of_two().clamp(16, 1024);
        Ok(Table { slots: vec_filled(cap, (0, EMPTY, 0))?, mask: cap - 1, len: 0 })
    }

    fn free_slot(&self, h: u64) -> usize {
        let mut s = h as usize & self.mask;
        while self.slots[s].1 != EMPTY {
            s = (s + 1) & self.mask;
        }
        s
    }

    fn grow(&mut self) -> Res<()> {
        let grown = vec_filled(2 * self.slots.len(), (0, EMPTY, 0))?;
        let old = std::mem::replace(&mut self.slots, grown);
        self.mask = self.slots.len() - 1;
        for e in old {
            if e.1 != EMPTY {
                let s = self.free_slot(e.0);
                self.slots[s] = e;
            }
        }
        Ok(())
    }

    /// The id of the entry with hash `h` whose representative satisfies `eq`; otherwise inserts
    /// `(h, p, next)` and returns `(next, true)`.
    #[inline]
    fn find_or_insert(&mut self, h: u64, p: u32, next: u32, eq: impl Fn(u32) -> bool) -> Res<(u32, bool)> {
        let mut s = h as usize & self.mask;
        loop {
            let (eh, rep, id) = self.slots[s];
            if rep == EMPTY {
                break;
            }
            if eh == h && eq(rep) {
                return Ok((id, false));
            }
            s = (s + 1) & self.mask;
        }
        if 2 * (self.len + 1) > self.slots.len() {
            self.grow()?;
            s = self.free_slot(h);
        }
        self.slots[s] = (h, p, next);
        self.len += 1;
        Ok((next, true))
    }
}

/// Pushes onto a vector whose growth is proportional to the data.
#[inline]
fn push<T>(v: &mut Vec<T>, x: T) -> Res<()> {
    if v.len() == v.capacity() {
        v.try_reserve(1).map_err(|_| Error::oom())?;
    }
    v.push(x);
    Ok(())
}

/// The keys of the sample, read once.
pub struct Keyed {
    kinds: Vec<Kind>,
    numv: Vec<i32>,
    strv: Vec<i32>,
    samp: Option<Vec<u32>>,
    ns: usize,
    kv: Option<KeyView>,
    /// Hash of each position when the keys are not kept.
    h: Vec<u64>,
    miss: Vec<bool>,
    /// Hash bits used (all but in tests that force collisions).
    mask: u64,
}

impl Keyed {
    /// Reads `keys` (varlist positions) at the sample observations `samp` (ascending; every
    /// observation when `None`).
    pub fn read<I: Io>(io: &I, keys: &[i32], samp: Option<Vec<u32>>, threads: usize, opts: ReadOpts) -> Res<Keyed> {
        Self::read_as(io, keys, samp, threads, opts, keys.len() <= STORED_KEYS)
    }

    fn read_as<I: Io>(io: &I, keys: &[i32], samp: Option<Vec<u32>>, threads: usize, opts: ReadOpts, store: bool) -> Res<Keyed> {
        let mut kinds = Vec::with_capacity(keys.len());
        let (mut numv, mut strv) = (Vec::new(), Vec::new());
        for &v in keys {
            if io.is_str(v) {
                kinds.push(Kind::Str(strv.len()));
                strv.push(v);
            } else {
                kinds.push(Kind::Num(numv.len()));
                numv.push(v);
            }
        }
        let src = Src::All { n: io.nobs(), samp: samp.as_deref() };
        let ns = src.len();
        let r = read_keys(io, &kinds, &numv, &strv, src, threads, store, opts)?;
        Ok(Keyed { kinds, numv, strv, samp, ns, kv: r.kv, h: r.h, miss: r.miss, mask: u64::MAX })
    }

    /// Sample size.
    pub fn len(&self) -> usize {
        self.ns
    }

    /// The observation at sample position `p`.
    #[inline]
    pub fn obs(&self, p: usize) -> usize {
        self.samp.as_ref().map_or(p, |s| s[p] as usize)
    }

    /// Whether position `p` has a missing key (read with [`ReadOpts::miss`]).
    #[inline]
    pub fn missing(&self, p: usize) -> bool {
        self.miss[p]
    }

    /// Positions with a missing key (read with [`ReadOpts::miss`]).
    pub fn nmiss(&self) -> usize {
        self.miss.iter().filter(|&&m| m).count()
    }

    fn pos_of_obs(&self, o: u32) -> usize {
        match &self.samp {
            Some(s) => s.binary_search(&o).expect("a sample observation"),
            None => o as usize,
        }
    }

    #[inline]
    fn hash(&self, p: usize) -> u64 {
        (match &self.kv {
            Some(kv) => kv.hash(p),
            None => self.h[p],
        }) & self.mask
    }

    /// Key values of the groups whose lowest positions are `reps`.
    pub fn rep_keys<'a, I: Io>(&'a self, io: &I, reps: &'a [u32], threads: usize) -> Res<RepKeys<'a>> {
        if let Some(kv) = &self.kv {
            return Ok(RepKeys { stored: Some(kv), read: None, reps });
        }
        let mut obs = vec_with_capacity(reps.len())?;
        obs.extend(reps.iter().map(|&p| self.obs(p as usize) as u32));
        let r = read_keys(io, &self.kinds, &self.numv, &self.strv, Src::List(&obs), threads, true, ReadOpts::default())?;
        Ok(RepKeys { stored: None, read: r.kv, reps })
    }

    /// Groups the sample.
    pub fn group<I: Io>(&self, io: &I, threads: usize, need: Need) -> Res<Grouped> {
        if self.ns == 0 {
            let starts = if need.ord { vec![0] } else { Vec::new() };
            return Ok(Grouped { starts, ..Grouped::default() });
        }
        if let Some(kv) = &self.kv {
            if let Some(g) = self.runs(io, kv, threads, need)? {
                return Ok(g);
            }
            return self.hashed(io, threads, need);
        }
        let mut g = self.hashed(io, threads, Need { gid: true, ord: true, reps: true, sizes: true })?;
        self.verify(io, threads, &mut g)?;
        for (want, v) in [(need.gid, &mut g.gid), (need.ord, &mut g.ord), (need.reps, &mut g.reps), (need.sizes, &mut g.sizes)] {
            if !want {
                *v = Vec::new();
            }
        }
        if !need.ord {
            g.starts = Vec::new();
        }
        Ok(g)
    }

    /// Groups by runs when the sample is already in key order (`None` otherwise).
    fn runs<I: Io>(&self, io: &I, kv: &KeyView, threads: usize, need: Need) -> Res<Option<Grouped>> {
        let ns = self.ns;
        let nch = ns.div_ceil(KEY_CHUNK);
        let th = threads_for_rows(threads, ns);
        let counts = for_blocks(io, nch, th, StoreMode::Parallel, |c, _emit| {
            let mut k = 0usize;
            for p in chunk(c, ns).start.max(1)..chunk(c, ns).end {
                match kv.cmp(p - 1, p) {
                    Ordering::Less => k += 1,
                    Ordering::Equal => {}
                    Ordering::Greater => return Ok(None),
                }
            }
            Ok(Some(k))
        })?;
        // groups started before each chunk (group 0 aside)
        let mut before = vec_with_capacity(nch)?;
        let mut acc = 0;
        for k in counts {
            let Some(k) = k else { return Ok(None) };
            before.push(acc);
            acc += k;
        }
        let ng = acc + 1;
        let mut g = Grouped { ngroups: ng, ..Grouped::default() };
        if !need.any() {
            return Ok(Some(g));
        }
        let mut starts = vec_zeroed(ng + 1)?;
        let mut gid = if need.gid { vec_zeroed(ns)? } else { Vec::new() };
        {
            let (s_st, s_gid) = (Shared::new(&mut starts), Shared::new(&mut gid));
            for_blocks(io, nch, th, StoreMode::Parallel, |c, _emit| {
                let mut cur = before[c];
                for p in chunk(c, ns) {
                    if p > 0 && kv.cmp(p - 1, p) == Ordering::Less {
                        cur += 1;
                        // SAFETY: group `cur` starts in this chunk only.
                        unsafe { s_st.set(cur, p) };
                    }
                    if need.gid {
                        // SAFETY: position p is in this chunk only.
                        unsafe { s_gid.set(p, cur as u32) };
                    }
                }
                Ok(())
            })?;
        }
        starts[ng] = ns;
        if need.reps {
            g.reps = par_map(io, ng, threads, |i| Ok(starts[i] as u32))?;
        }
        if need.sizes {
            g.sizes = par_map(io, ng, threads, |i| Ok((starts[i + 1] - starts[i]) as u32))?;
        }
        if need.ord {
            g.ord = par_map(io, ns, threads, |p| Ok(self.obs(p) as u32))?;
            g.starts = starts;
        }
        g.gid = gid;
        Ok(Some(g))
    }

    /// Groups by hash: stable bucketing into partitions, then one growable table per partition.
    /// With stored keys, keys are compared exactly; without, equal hashes group (see
    /// [`Keyed::verify`]).
    fn hashed<I: Io>(&self, io: &I, threads: usize, need: Need) -> Res<Grouped> {
        let ns = self.ns;
        let th = threads_for_rows(threads, ns);
        let kv = self.kv.as_ref();
        let eq = |a: usize, b: usize| kv.is_none_or(|kv| kv.eq(a, b));
        let nparts = if ns < KEY_CHUNK { 1 } else { PARTS };
        let part = |h: u64| if nparts == 1 { 0 } else { (h >> 56) as usize };

        // 1. Stable bucketing: per-chunk partition counts, offsets in (partition, chunk) order,
        //    then each chunk scatters its positions.
        let mut pidx = Vec::new();
        let mut pstart = vec_filled(nparts + 1, 0usize)?;
        pstart[nparts] = ns;
        if nparts > 1 {
            let nch = ns.div_ceil(KEY_CHUNK);
            let counts = for_blocks(io, nch, th, StoreMode::Parallel, |c, _emit| {
                let mut k = [0usize; PARTS];
                for p in chunk(c, ns) {
                    k[part(self.hash(p))] += 1;
                }
                Ok(k)
            })?;
            let mut off = vec_filled(nch * PARTS, 0usize)?;
            let mut acc = 0;
            for q in 0..PARTS {
                pstart[q] = acc;
                for (c, k) in counts.iter().enumerate() {
                    off[c * PARTS + q] = acc;
                    acc += k[q];
                }
            }
            pidx = vec_zeroed(ns)?;
            let sh = Shared::new(&mut pidx);
            for_blocks(io, nch, th, StoreMode::Parallel, |c, _emit| {
                let mut cur = [0usize; PARTS];
                cur.copy_from_slice(&off[c * PARTS..(c + 1) * PARTS]);
                for p in chunk(c, ns) {
                    let q = part(self.hash(p));
                    // SAFETY: chunk c owns slots off[c * PARTS + q].. of each partition q.
                    unsafe { sh.set(cur[q], p as u32) };
                    cur[q] += 1;
                }
                Ok(())
            })?;
        }
        let member = |i: usize| if nparts == 1 { i } else { pidx[i] as usize };

        // 2. Per partition: local ids in order of first appearance.
        let keep_lid = need.gid || need.ord;
        let mut lid = if keep_lid { vec_zeroed(ns)? } else { Vec::new() };
        let parts = {
            let s_lid = Shared::new(&mut lid);
            for_blocks(io, nparts, th, StoreMode::Parallel, |q, _emit| {
                let (a, b) = (pstart[q], pstart[q + 1]);
                let mut t = Table::new(b - a)?;
                let mut reps: Vec<u32> = Vec::new();
                let mut sizes: Vec<u32> = Vec::new();
                for i in a..b {
                    let p = member(i);
                    let (id, new) = t.find_or_insert(self.hash(p), p as u32, reps.len() as u32, |r| eq(r as usize, p))?;
                    if new {
                        push(&mut reps, p as u32)?;
                        push(&mut sizes, 1)?;
                    } else {
                        sizes[id as usize] += 1;
                    }
                    if keep_lid {
                        // SAFETY: bucket slot i belongs to partition q only.
                        unsafe { s_lid.set(i, id) };
                    }
                }
                Ok((reps, sizes))
            })?
        };

        // 3. Partition q's groups are base[q]..base[q + 1]; each partition writes its own slots.
        let mut base = vec_filled(nparts + 1, 0usize)?;
        for q in 0..nparts {
            base[q + 1] = base[q] + parts[q].0.len();
        }
        let ng = base[nparts];
        let mut g = Grouped { ngroups: ng, ..Grouped::default() };
        if !need.any() {
            return Ok(g);
        }
        let mut gid = if need.gid { vec_zeroed(ns)? } else { Vec::new() };
        let mut ord = if need.ord { vec_zeroed(ns)? } else { Vec::new() };
        let mut starts = if need.ord { vec_zeroed(ng + 1)? } else { Vec::new() };
        let mut reps = if need.reps { vec_zeroed(ng)? } else { Vec::new() };
        let mut sizes = if need.sizes { vec_zeroed(ng)? } else { Vec::new() };
        {
            let s_gid = Shared::new(&mut gid);
            let s_ord = Shared::new(&mut ord);
            let s_st = Shared::new(&mut starts);
            let s_rep = Shared::new(&mut reps);
            let s_sz = Shared::new(&mut sizes);
            for_blocks(io, nparts, th, StoreMode::Parallel, |q, _emit| {
                let (preps, psizes) = &parts[q];
                let (a, b, gb) = (pstart[q], pstart[q + 1], base[q]);
                // SAFETY (all writes): groups gb..base[q + 1], bucket slots a..b and their
                // positions belong to partition q only.
                if need.reps {
                    unsafe { s_rep.slice(gb, gb + preps.len()) }.copy_from_slice(preps);
                }
                if need.sizes {
                    unsafe { s_sz.slice(gb, gb + psizes.len()) }.copy_from_slice(psizes);
                }
                if need.gid {
                    for i in a..b {
                        unsafe { s_gid.set(member(i), gb as u32 + lid[i]) };
                    }
                }
                if need.ord {
                    let mut cur = vec_with_capacity(psizes.len())?;
                    let mut at = a;
                    for (l, &s) in psizes.iter().enumerate() {
                        unsafe { s_st.set(gb + l, at) };
                        cur.push(at);
                        at += s as usize;
                    }
                    for i in a..b {
                        let l = lid[i] as usize;
                        unsafe { s_ord.set(cur[l], self.obs(member(i)) as u32) };
                        cur[l] += 1;
                    }
                }
                Ok(())
            })?;
        }
        if need.ord {
            starts[ng] = ns;
        }
        g.gid = gid;
        g.ord = ord;
        g.starts = starts;
        g.reps = reps;
        g.sizes = sizes;
        Ok(g)
    }

    /// Without stored keys, groups hold equal hashes: checks every member of each group of two
    /// or more against the group's first member (their rows read again) and splits the groups
    /// where rows differ. `g` holds every [`Need`] output.
    fn verify<I: Io>(&self, io: &I, threads: usize, g: &mut Grouped) -> Res<()> {
        let ng = g.ngroups;
        let nnum = self.numv.len();
        let mut bad: Vec<u32> = Vec::new();
        if nnum > 0 {
            let rows = (BLOCK_VALUES / nnum).max(2);
            // items: groups of two or more holding at most `rows` observations together, or one
            // larger group
            let mut items: Vec<usize> = Vec::new();
            push(&mut items, 0)?;
            let (mut acc, mut total) = (0, 0usize);
            for gi in 0..ng {
                let s = g.sizes[gi] as usize;
                if s < 2 {
                    continue;
                }
                if acc > 0 && acc + s > rows {
                    push(&mut items, gi)?;
                    acc = 0;
                }
                acc += s;
                total += s;
            }
            push(&mut items, ng)?;
            let th = threads_for_rows(threads, total.saturating_mul(nnum));
            let (gr, items) = (&*g, &items);
            let found = for_blocks(io, items.len() - 1, th, StoreMode::Parallel, |it, _emit| {
                let groups = (items[it]..items[it + 1]).filter(|&gi| gr.sizes[gi] > 1);
                let members = |gi: usize| &gr.ord[gr.starts[gi]..gr.starts[gi + 1]];
                let n: usize = groups.clone().map(|gi| members(gi).len()).sum();
                let mut out: Vec<u32> = Vec::new();
                let mut buf = vec_filled(n.min(rows) * nnum, 0.0)?;
                let same = |rep: &[f64], row: &[f64]| rep.iter().zip(row).all(|(&a, &b)| canon(a) == canon(b));
                if n <= rows {
                    // every group of the item in one read
                    let mut list = vec_with_capacity(n)?;
                    for gi in groups.clone() {
                        list.extend_from_slice(members(gi));
                    }
                    io.read_block(&self.numv, Rows::List(&list), &mut buf)?;
                    let mut r = 0;
                    for gi in groups {
                        let m = members(gi).len();
                        let rep = &buf[r * nnum..(r + 1) * nnum];
                        if !(1..m).all(|k| same(rep, &buf[(r + k) * nnum..(r + k + 1) * nnum])) {
                            push(&mut out, gi as u32)?;
                        }
                        r += m;
                    }
                } else {
                    // one group, read in parts
                    for gi in groups {
                        let mut rep = vec_filled(nnum, 0.0)?;
                        let mut differs = false;
                        for (k, part) in members(gi).chunks(rows).enumerate() {
                            let b = &mut buf[..part.len() * nnum];
                            io.read_block(&self.numv, Rows::List(part), b)?;
                            if k == 0 {
                                rep.copy_from_slice(&b[..nnum]);
                            }
                            if !b.chunks_exact(nnum).all(|row| same(&rep, row)) {
                                differs = true;
                                break;
                            }
                        }
                        if differs {
                            push(&mut out, gi as u32)?;
                        }
                    }
                }
                Ok(out)
            })?;
            for f in found {
                for gi in f {
                    push(&mut bad, gi)?;
                }
            }
        }
        if !self.strv.is_empty() {
            let mut rep: Vec<Vec<u8>> = self.strv.iter().map(|_| Vec::new()).collect();
            let mut buf = Vec::new();
            let read = |v: i32, o: u32, b: &mut Vec<u8>| -> Res<()> {
                b.clear();
                if b.capacity() < STR_ROOM {
                    b.try_reserve(STR_ROOM).map_err(|_| Error::oom())?;
                }
                io.read_str(v, o as usize, b)
            };
            let nbad = bad.len();
            for gi in 0..ng {
                if g.sizes[gi] < 2 || bad[..nbad].binary_search(&(gi as u32)).is_ok() {
                    continue;
                }
                let members = &g.ord[g.starts[gi]..g.starts[gi + 1]];
                for (c, &v) in self.strv.iter().enumerate() {
                    read(v, members[0], &mut rep[c])?;
                }
                'm: for &o in &members[1..] {
                    for (c, &v) in self.strv.iter().enumerate() {
                        read(v, o, &mut buf)?;
                        if buf != rep[c] {
                            push(&mut bad, gi as u32)?;
                            break 'm;
                        }
                    }
                }
            }
        }
        if bad.is_empty() {
            return Ok(());
        }
        bad.sort_unstable();
        self.split(io, g, &bad)
    }

    /// Splits each group of `bad` (ascending) into its distinct rows, in order of first
    /// appearance: the first keeps the group's id, the others become new groups; then rebuilds
    /// `ord`, `starts` and `sizes`.
    fn split<I: Io>(&self, io: &I, g: &mut Grouped, bad: &[u32]) -> Res<()> {
        let nnum = self.numv.len();
        let mut next = g.ngroups;
        for &gi in bad {
            let gi = gi as usize;
            let mut members = vec_with_capacity(g.starts[gi + 1] - g.starts[gi])?;
            members.extend_from_slice(&g.ord[g.starts[gi]..g.starts[gi + 1]]);
            let m = members.len();
            let mut num = vec_filled(m * nnum, 0.0)?;
            if nnum > 0 {
                io.read_block(&self.numv, Rows::List(&members), &mut num)?;
            }
            let mut strs = Vec::new();
            for &v in &self.strv {
                let mut c = StrCol { off: vec_filled(m + 1, 0usize)?, bytes: Vec::new() };
                for (k, &o) in members.iter().enumerate() {
                    if c.bytes.capacity() - c.bytes.len() < STR_ROOM {
                        c.bytes.try_reserve(STR_ROOM).map_err(|_| Error::oom())?;
                    }
                    io.read_str(v, o as usize, &mut c.bytes)?;
                    c.off[k + 1] = c.bytes.len();
                }
                strs.push(c);
            }
            let row_eq = |a: usize, b: usize| {
                (0..nnum).all(|j| canon(num[a * nnum + j]) == canon(num[b * nnum + j])) && strs.iter().all(|s| s.get(a) == s.get(b))
            };
            // first member of each distinct row
            let mut subs: Vec<usize> = vec![0];
            for k in 1..m {
                let s = match subs.iter().position(|&f| row_eq(f, k)) {
                    Some(s) => s,
                    None => {
                        push(&mut subs, k)?;
                        subs.len() - 1
                    }
                };
                if s > 0 {
                    g.gid[self.pos_of_obs(members[k])] = (next + s - 1) as u32;
                }
            }
            for &f in &subs[1..] {
                push(&mut g.reps, self.pos_of_obs(members[f]) as u32)?;
            }
            next += subs.len() - 1;
        }
        let ng = next;
        let mut sizes = vec_filled(ng, 0u32)?;
        for &k in &g.gid {
            sizes[k as usize] += 1;
        }
        let mut starts = vec_filled(ng + 1, 0usize)?;
        for k in 0..ng {
            starts[k + 1] = starts[k] + sizes[k] as usize;
        }
        let mut cur = vec_with_capacity(ng)?;
        cur.extend_from_slice(&starts[..ng]);
        for (p, &k) in g.gid.iter().enumerate() {
            g.ord[cur[k as usize]] = self.obs(p) as u32;
            cur[k as usize] += 1;
        }
        g.ngroups = ng;
        g.sizes = sizes;
        g.starts = starts;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::*;
    use crate::io::{MISS, MemIo};
    use crate::testutil::*;

    #[test]
    fn sorted_starts_split_runs_like_stata_by_for_any_thread_count() {
        // Runs longer and shorter than KEY_CHUNK; −0 continues a +0 run, `.a` starts a new run
        // after `.`, and a change in the second key alone starts a group.
        let vals = [0.0, -0.0, 1.0, MISS, miss_a(), 2.5];
        let mut a = Vec::new();
        let mut b = Vec::new();
        let mut rng = Rng::new(7);
        let mut k = 0;
        while a.len() < 3 * KEY_CHUNK {
            let len = [1, 2, 3, KEY_CHUNK - 1, KEY_CHUNK, KEY_CHUNK + 1, 17][k % 7];
            let v = vals[k % vals.len()];
            let w = (rng.next_u64() % 2) as f64;
            a.extend(std::iter::repeat_n(v, len));
            b.extend(std::iter::repeat_n(w, len));
            k += 1;
        }
        let n = a.len();
        let mut want = vec![0];
        for i in 1..n {
            if a[i] != a[i - 1] || b[i] != b[i - 1] {
                want.push(i);
            }
        }
        want.push(n);
        let mut io = MemIo::new(n);
        let (ca, cb) = (io.add_num(&a), io.add_num(&b));
        let keys = [io.push_var(ca), io.push_var(cb)];
        for threads in [1, 4] {
            assert_eq!(sorted_starts(&io, &keys, n, threads).unwrap(), want, "threads={threads}");
        }
        // a NaN in a key falls back
        let mut c = b.clone();
        c[n - 2] = stata_nan();
        let cc = io.add_num(&c);
        let kc = io.push_var(cc);
        let e = sorted_starts(&io, &[keys[0], kc], n, 4).unwrap_err();
        assert!(e.is_fallback() && e.msg == crate::nan::REASON);
    }

    #[derive(PartialEq, Eq, PartialOrd, Ord, Clone, Debug)]
    enum K {
        N(u64),
        S(Vec<u8>),
    }

    struct Data {
        io: MemIo,
        /// key varlist positions (`nnum` numeric keys, then `nstr` string keys)
        keys: Vec<i32>,
        /// key tuples in Stata's order
        tuples: Vec<Vec<K>>,
        touse: Vec<bool>,
    }

    /// `nnum` numeric keys (missing codes, −0, few or many distinct values) and `nstr` string
    /// keys ("" and prefixes), `n` observations; `sorted` puts them in key order.
    fn data(n: usize, nnum: usize, nstr: usize, distinct: u64, sorted: bool, seed: u64) -> Data {
        let num = [0.0, -0.0, MISS, miss_a(), 1.5, -2.0, 1e300];
        let strs: [&[u8]; 5] = [b"", b"ab", b"abc", b"B", b"z\xc3\xa9z"];
        let mut rng = Rng::new(seed);
        let mut rows: Vec<(Vec<f64>, Vec<Vec<u8>>, bool)> = (0..n)
            .map(|_| {
                let nv: Vec<f64> = (0..nnum)
                    .map(|j| {
                        let r = rng.next_u64();
                        if j == 0 && r % 4 == 0 { num[(r / 4 % num.len() as u64) as usize] } else { (r % distinct) as f64 }
                    })
                    .collect();
                let sv = (0..nstr).map(|_| strs[(rng.next_u64() % strs.len() as u64) as usize].to_vec()).collect();
                (nv, sv, rng.unif() >= 0.2)
            })
            .collect();
        let tup = |r: &(Vec<f64>, Vec<Vec<u8>>, bool)| -> Vec<K> {
            r.0.iter().map(|&v| K::N(okey(canon(v)))).chain(r.1.iter().map(|s| K::S(s.clone()))).collect()
        };
        if sorted {
            rows.sort_by_key(|r| tup(r));
        }
        let mut io = MemIo::new(n);
        let mut keys = Vec::new();
        for j in 0..nnum {
            let c = io.add_num(&rows.iter().map(|r| r.0[j]).collect::<Vec<_>>());
            keys.push(io.push_var(c));
        }
        for j in 0..nstr {
            let c = io.add_str(rows.iter().map(|r| r.1[j].clone()).collect());
            keys.push(io.push_var(c));
        }
        let tuples = rows.iter().map(tup).collect();
        let touse = rows.iter().map(|r| r.2).collect();
        Data { io, keys, tuples, touse }
    }

    /// Naive groups: tuple -> sample observations ascending.
    fn naive(d: &Data, samp: Option<&[u32]>) -> BTreeMap<Vec<K>, Vec<u32>> {
        let mut m: BTreeMap<Vec<K>, Vec<u32>> = BTreeMap::new();
        for (o, t) in d.tuples.iter().enumerate() {
            if samp.is_none_or(|s| s.binary_search(&(o as u32)).is_ok()) {
                m.entry(t.clone()).or_default().push(o as u32);
            }
        }
        m
    }

    /// Every output of `g` against the naive groups; returns the groups as sorted member lists.
    fn check(k: &Keyed, g: &Grouped, want: &BTreeMap<Vec<K>, Vec<u32>>) -> Vec<Vec<u32>> {
        assert_eq!(g.ngroups, want.len());
        let mut got: Vec<Vec<u32>> = (0..g.ngroups).map(|gi| g.ord[g.starts[gi]..g.starts[gi + 1]].to_vec()).collect();
        for (gi, m) in got.iter().enumerate() {
            assert!(m.windows(2).all(|w| w[0] < w[1]));
            assert_eq!(g.sizes[gi] as usize, m.len());
            assert_eq!(k.obs(g.reps[gi] as usize), m[0] as usize);
        }
        for p in 0..k.len() {
            let gi = g.gid[p] as usize;
            assert!(got[gi].contains(&(k.obs(p) as u32)));
        }
        got.sort();
        let mut w: Vec<Vec<u32>> = want.values().cloned().collect();
        w.sort();
        assert_eq!(got, w);
        got
    }

    const ALL: Need = Need { gid: true, ord: true, reps: true, sizes: true };

    /// Narrow (stored) and wide (hash) reads, sorted and unsorted, with and without a sample,
    /// sizes around KEY_CHUNK, forced hash collisions: the groups match the naive reference and
    /// are identical for 1 and 5 threads.
    #[test]
    fn groups_match_naive_reference_for_any_thread_count() {
        let shapes = [(1, 1, 0, 3), (300, 2, 1, 5), (KEY_CHUNK - 1, 1, 0, 1 << 40), (KEY_CHUNK + 7, 2, 0, 50), (140_000, 1, 1, 60_000), (9000, 6, 0, 2), (9000, 5, 2, 3)];
        for &(n, nnum, nstr, distinct) in &shapes {
            for sorted in [false, true] {
                let d = data(n, nnum, nstr, distinct, sorted, n as u64 + 3);
                let samp: Vec<u32> = (0..n as u32).filter(|&o| d.touse[o as usize]).collect();
                for with_samp in [false, true] {
                    let s = with_samp.then(|| samp.clone());
                    let want = naive(&d, s.as_deref());
                    for store in [true, false] {
                        for mask in [u64::MAX, 0] {
                            if mask == 0 && n > 20_000 {
                                continue;
                            }
                            let mut prev: Option<Grouped> = None;
                            for threads in [1, 5] {
                                let mut k = Keyed::read_as(&d.io, &d.keys, s.clone(), threads, ReadOpts { miss: true, blanks: false }, store).unwrap();
                                k.mask = mask;
                                let g = k.group(&d.io, threads, ALL).unwrap();
                                check(&k, &g, &want);
                                let c = k.group(&d.io, threads, Need::default()).unwrap();
                                assert_eq!(c.ngroups, want.len());
                                if let Some(p) = &prev {
                                    assert_eq!((&p.gid, &p.ord, &p.starts, &p.reps, &p.sizes), (&g.gid, &g.ord, &g.starts, &g.reps, &g.sizes), "n={n} store={store} threads");
                                }
                                prev = Some(g);
                                let nm = (0..k.len()).filter(|&p| d.tuples[k.obs(p)].iter().any(|t| matches!(t, K::N(x) if *x >= okey(MISS.to_bits())) || *t == K::S(Vec::new()))).count();
                                assert_eq!(k.nmiss(), nm);
                            }
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn rep_keys_sort_groups_in_stata_order() {
        let d = data(5000, 2, 1, 4, false, 9);
        for store in [true, false] {
            let k = Keyed::read_as(&d.io, &d.keys, None, 3, ReadOpts::default(), store).unwrap();
            let g = k.group(&d.io, 3, ALL).unwrap();
            let rk = k.rep_keys(&d.io, &g.reps, 3).unwrap();
            let mut idx: Vec<u32> = (0..g.ngroups as u32).collect();
            par_sort_by(&d.io, &mut idx, 3, |&a, &b| rk.view().cmp(rk.pos(a as usize), rk.pos(b as usize))).unwrap();
            let got: Vec<Vec<K>> = idx.iter().map(|&gi| d.tuples[k.obs(g.reps[gi as usize] as usize)].clone()).collect();
            let want: Vec<Vec<K>> = naive(&d, None).into_keys().collect();
            assert_eq!(got, want, "store={store}");
        }
    }

    #[test]
    fn a_nan_anywhere_in_a_numeric_key_falls_back_and_blanks_fall_back() {
        let d = data(9000, 2, 1, 7, false, 4);
        let mut io = d.io;
        let mut v: Vec<f64> = (0..9000).map(|i| (i % 5) as f64).collect();
        v[8999] = stata_nan();
        let c = io.add_num(&v);
        let kn = io.push_var(c);
        for store in [true, false] {
            // outside the sample too
            let e = Keyed::read_as(&io, &[d.keys[0], kn], Some(vec![1, 2, 3]), 4, ReadOpts::default(), store).err().unwrap();
            assert!(e.is_fallback() && e.msg == crate::nan::REASON);
        }
        for bad in [&b" a"[..], b"a ", b"a\t", b"\xc2\xa0a", b"a\x7f"] {
            let mut io = MemIo::new(3);
            let c = io.add_str(vec![b"x".to_vec(), bad.to_vec(), b"a b".to_vec()]);
            let v = io.push_var(c);
            for store in [true, false] {
                let e = Keyed::read_as(&io, &[v], None, 1, ReadOpts { miss: true, blanks: true }, store).err().unwrap();
                assert!(e.is_fallback() && e.msg == "string blanks");
            }
        }
    }

    #[test]
    fn par_sort_matches_sort_for_any_thread_count() {
        let mut rng = Rng::new(5);
        for n in [0, 1, 7, 70_000, 300_001] {
            let v: Vec<(u64, u32)> = (0..n).map(|i| (rng.next_u64() % 1000, i as u32)).collect();
            let mut want = v.clone();
            want.sort();
            for threads in [1, 3, 8] {
                let mut got = v.clone();
                par_sort_by(&MemIo::new(0), &mut got, threads, |a, b| a.cmp(b)).unwrap();
                assert_eq!(got, want);
            }
        }
    }

    #[test]
    fn samples_and_flags() {
        let n = 3 * KEY_CHUNK + 11;
        let t: Vec<f64> = (0..n).map(|i| f64::from(u8::from(i % 3 != 1))).collect();
        let mut io = MemIo::new(n);
        let c = io.add_num(&t);
        let v = io.push_var(c);
        for threads in [1, 4] {
            let f = read_flags(&io, v, threads).unwrap();
            assert!(f.iter().zip(&t).all(|(&a, &b)| a == (b != 0.0)));
            let s = sample_from_bools(&io, &f, threads).unwrap();
            assert_eq!(s, (0..n as u32).filter(|&i| i % 3 != 1).collect::<Vec<_>>());
        }
    }
}
