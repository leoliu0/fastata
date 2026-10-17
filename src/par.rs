//! Worker threads: the only place where threads are spawned. Work items run on
//! `std::thread::scope` workers that pull indices from an atomic counter. Results come back
//! ordered by item index, so callers stay deterministic whatever the scheduling.
//!
//! Writes go through the `emit` callback handed to each item. Under [`StoreMode::Parallel`] the
//! worker writes directly; under [`StoreMode::Serial`] the job travels through a bounded channel
//! to the calling thread, which performs every write. A region that only reads uses
//! [`StoreMode::Parallel`] (the calling thread then works on items too).
//!
//! When the OS refuses a thread, the region runs on the threads it has, the calling thread
//! included, rather than failing.

use std::ops::Range;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Mutex, PoisonError, mpsc};
use std::thread::{Scope, ScopedJoinHandle};

use crate::error::{Error, Res, vec_with_capacity};
use crate::io::{Io, Rows};

/// Default store mode: parallel stores into disjoint observations are safe. Decided by center2's
/// `tests/stata/stress_store.do` on StataNow 19.5 MP (Linux): 200 reps of 2e7 x 8 parallel
/// stores, 0 mismatches, no crash; 0.16 s parallel vs 0.64 s serial writes per rep.
pub const PARALLEL_STORE_DEFAULT: bool = true;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StoreMode {
    Parallel,
    Serial,
}

impl StoreMode {
    /// From the plugin key `serialstore` (absent: [`PARALLEL_STORE_DEFAULT`]).
    pub fn from_serial(serial: Option<bool>) -> StoreMode {
        match serial {
            Some(true) => StoreMode::Serial,
            Some(false) => StoreMode::Parallel,
            None if PARALLEL_STORE_DEFAULT => StoreMode::Parallel,
            None => StoreMode::Serial,
        }
    }
}

/// One `write_block` call over the observations `rows`: `vals`/`skip` are row-major over
/// `rows` x `vars`.
pub struct WriteJob {
    pub vars: Vec<i32>,
    pub rows: Range<usize>,
    pub vals: Vec<f64>,
    pub skip: Option<Vec<u8>>,
}

pub type Emit<'a> = dyn FnMut(WriteJob) -> Res<()> + 'a;

/// `threads` = 0 means every logical CPU; never more threads than work items.
pub fn resolve_threads(threads: usize, items: usize) -> usize {
    let t = if threads == 0 { std::thread::available_parallelism().map_or(1, |n| n.get()) } else { threads };
    t.min(items).max(1)
}

/// Fewest observations worth a worker thread of their own: starting a thread costs 30-40 µs,
/// about what one thread spends on this many rows in the cheapest pass.
pub const MIN_ROWS_PER_THREAD: usize = 1 << 16;

/// Threads for a region whose total work is `rows` observations, whatever its number of work
/// items: `threads` (0 = every logical CPU), at most one per [`MIN_ROWS_PER_THREAD`] rows, at
/// least 1. Work items stay fixed, so results do not depend on it.
pub fn threads_for_rows(threads: usize, rows: usize) -> usize {
    resolve_threads(threads, rows.div_ceil(MIN_ROWS_PER_THREAD))
}

fn write_job<I: Io + ?Sized>(io: &I, job: &WriteJob) -> Res<()> {
    io.write_block(&job.vars, Rows::Range { first: job.rows.start, n: job.rows.len() }, &job.vals, job.skip.as_deref())
}

fn join<T>(h: ScopedJoinHandle<'_, T>) -> T {
    h.join().unwrap_or_else(|p| std::panic::resume_unwind(p))
}

/// A scoped worker thread, or `None` when the OS cannot start one.
fn spawn<'scope, T, F>(s: &'scope Scope<'scope, '_>, f: F) -> Option<ScopedJoinHandle<'scope, T>>
where
    T: Send + 'scope,
    F: FnOnce() -> T + Send + 'scope,
{
    #[cfg(test)]
    if tests::refuse_spawn() {
        return None;
    }
    std::thread::Builder::new().spawn_scoped(s, f).ok()
}

/// Runs `f(item, emit)` for every item in `0..nitems` and returns the results in item order.
/// The first error stops further item pickup and is returned.
pub fn for_blocks<I, T, F>(io: &I, nitems: usize, threads: usize, store: StoreMode, f: F) -> Res<Vec<T>>
where
    I: Io + ?Sized,
    T: Send,
    F: Fn(usize, &mut Emit<'_>) -> Res<T> + Sync,
{
    if nitems == 0 {
        return Ok(Vec::new());
    }
    let t = resolve_threads(threads, nitems);
    if t == 1 {
        let mut out = vec_with_capacity(nitems)?;
        let mut emit = |job: WriteJob| write_job(io, &job);
        for i in 0..nitems {
            out.push(f(i, &mut emit)?);
        }
        return Ok(out);
    }

    let next = AtomicUsize::new(0);
    let failed = AtomicBool::new(false);
    let worker = |emit: &mut Emit<'_>| -> Res<Vec<(usize, T)>> {
        let mut done = Vec::new();
        while !failed.load(Ordering::Relaxed) {
            let i = next.fetch_add(1, Ordering::Relaxed);
            if i >= nitems {
                break;
            }
            let r = f(i, emit).and_then(|v| {
                done.try_reserve(1).map_err(|_| Error::oom())?;
                done.push((i, v));
                Ok(())
            });
            if let Err(e) = r {
                failed.store(true, Ordering::Relaxed);
                return Err(e);
            }
        }
        Ok(done)
    };
    let worker = &worker;

    let results: Vec<Res<Vec<(usize, T)>>> = match store {
        // t - 1 workers plus the calling thread
        StoreMode::Parallel => std::thread::scope(|s| {
            let mut hs = Vec::with_capacity(t - 1);
            for _ in 1..t {
                match spawn(s, move || worker(&mut |job: WriteJob| write_job(io, &job))) {
                    Some(h) => hs.push(h),
                    None => break,
                }
            }
            let mine = worker(&mut |job: WriteJob| write_job(io, &job));
            let mut rs = Vec::with_capacity(hs.len() + 1);
            rs.push(mine);
            rs.extend(hs.into_iter().map(join));
            rs
        }),
        StoreMode::Serial => std::thread::scope(|s| {
            let (tx, rx) = mpsc::sync_channel::<WriteJob>(2 * t);
            let mut hs = Vec::with_capacity(t);
            for _ in 0..t {
                let tx = tx.clone();
                let w = move || {
                    let mut emit =
                        |job: WriteJob| tx.send(job).map_err(|_| Error::new(9999, "fastata: the writer thread stopped"));
                    worker(&mut emit)
                };
                match spawn(s, w) {
                    Some(h) => hs.push(h),
                    None => break,
                }
            }
            drop(tx);
            if hs.is_empty() {
                // no worker thread: the calling thread runs every item and writes itself
                return vec![worker(&mut |job: WriteJob| write_job(io, &job))];
            }
            // The calling thread performs every write; after a failed write it keeps draining
            // the channel so that no worker blocks on a full channel.
            let mut write_err = None;
            for job in rx.iter() {
                if write_err.is_none()
                    && let Err(e) = write_job(io, &job)
                {
                    failed.store(true, Ordering::Relaxed);
                    write_err = Some(e);
                }
            }
            let mut rs: Vec<_> = hs.into_iter().map(join).collect();
            if let Some(e) = write_err {
                rs.insert(0, Err(e));
            }
            rs
        }),
    };

    let mut slots: Vec<Option<T>> = Vec::new();
    slots.try_reserve_exact(nitems).map_err(|_| Error::oom())?;
    slots.resize_with(nitems, || None);
    for r in results {
        for (i, v) in r? {
            slots[i] = Some(v);
        }
    }
    let mut out = vec_with_capacity(nitems)?;
    out.extend(slots.into_iter().map(|s| s.expect("every item was processed")));
    Ok(out)
}

/// Runs `f(item, chunk)` in parallel over row chunks of the equally long columns `cols`: item
/// `i` gets rows `i * rows ..` (at most `rows` of them) of every column, as `chunk[j]` for
/// column `j`, to fill or read in place. Results in item order, as [`for_blocks`].
pub fn for_chunks<I, T, R, F>(io: &I, cols: &mut [&mut [T]], rows: usize, threads: usize, f: F) -> Res<Vec<R>>
where
    I: Io + ?Sized,
    T: Send,
    R: Send,
    F: Fn(usize, &mut [&mut [T]]) -> Res<R> + Sync,
{
    assert!(rows > 0);
    let n = cols.first().map_or(0, |c| c.len());
    assert!(cols.iter().all(|c| c.len() == n), "for_chunks: columns of different lengths");
    let nitems = n.div_ceil(rows);
    let mut parts: Vec<Mutex<Vec<&mut [T]>>> = vec_with_capacity(nitems)?;
    for _ in 0..nitems {
        parts.push(Mutex::new(vec_with_capacity(cols.len())?));
    }
    for c in cols.iter_mut() {
        for (p, ch) in parts.iter_mut().zip(c.chunks_mut(rows)) {
            p.get_mut().unwrap_or_else(PoisonError::into_inner).push(ch);
        }
    }
    for_blocks(io, nitems, threads, StoreMode::Parallel, |i, _emit| {
        f(i, &mut parts[i].lock().unwrap_or_else(PoisonError::into_inner))
    })
}

#[cfg(test)]
pub(crate) mod tests {
    use std::cell::Cell;

    use super::*;
    use crate::io::MemIo;

    thread_local! {
        /// Thread starts the calling thread may still make (tests of a refused spawn).
        static SPAWNS_LEFT: Cell<usize> = const { Cell::new(usize::MAX) };
    }

    /// True when the next spawn on this thread must fail (and counts one spawn otherwise).
    pub fn refuse_spawn() -> bool {
        SPAWNS_LEFT.with(|c| {
            let left = c.get();
            if left == 0 {
                return true;
            }
            c.set(left - 1);
            false
        })
    }

    fn with_spawns<R>(left: usize, f: impl FnOnce() -> R) -> R {
        SPAWNS_LEFT.with(|c| c.set(left));
        let r = f();
        SPAWNS_LEFT.with(|c| c.set(usize::MAX));
        r
    }

    fn data(n: usize) -> MemIo {
        let mut io = MemIo::new(n);
        let x: Vec<f64> = (0..n).map(|i| i as f64).collect();
        let c = io.add_num(&x);
        io.push_var(c);
        let o = io.add_num(&vec![0.0; n]);
        io.push_var(o);
        io
    }

    #[test]
    fn results_come_back_in_item_order_whatever_the_threads() {
        let io = data(10);
        for store in [StoreMode::Parallel, StoreMode::Serial] {
            for threads in [1, 2, 7, 64] {
                let r = for_blocks(&io, 1000, threads, store, |i, _| Ok(i * 3)).unwrap();
                assert!(r.iter().enumerate().all(|(i, &v)| v == i * 3), "{store:?} threads={threads}");
            }
        }
    }

    #[test]
    fn a_refused_thread_runs_the_work_on_the_threads_there_are() {
        let n = 50_000;
        for store in [StoreMode::Parallel, StoreMode::Serial] {
            for left in [0, 1, 2] {
                let io = data(n);
                let r = with_spawns(left, || {
                    for_blocks(&io, n.div_ceil(1000), 8, store, |b, emit| {
                        let first = b * 1000;
                        let m = 1000.min(n - first);
                        let vals = (first..first + m).map(|i| -(i as f64)).collect();
                        emit(WriteJob { vars: vec![2], rows: first..first + m, vals, skip: None })?;
                        Ok(b)
                    })
                })
                .unwrap();
                assert_eq!(r, (0..n.div_ceil(1000)).collect::<Vec<_>>(), "{store:?} spawns={left}");
                assert!(io.col(1).iter().enumerate().all(|(i, &v)| v == -(i as f64)), "{store:?} spawns={left}");
            }
        }
    }

    #[test]
    fn the_first_error_is_returned() {
        let io = data(10);
        for threads in [1, 4] {
            let e = for_blocks(&io, 100, threads, StoreMode::Parallel, |i, _| {
                if i == 37 { Err(Error::new(459, "item 37")) } else { Ok(i) }
            })
            .unwrap_err();
            assert_eq!(e.rc, 459);
        }
    }

    #[test]
    fn chunks_cover_every_row_of_every_column_once() {
        let io = data(10);
        for (n, rows) in [(0, 3), (1, 3), (10, 3), (9, 3), (1000, 7)] {
            for threads in [1, 3] {
                let mut a = vec![0u32; n];
                let mut b = vec![0u32; n];
                let mut cols: Vec<&mut [u32]> = vec![&mut a, &mut b];
                let sizes = for_chunks(&io, &mut cols, rows, threads, |i, ch| {
                    let (c0, c1) = ch.split_at_mut(1);
                    for (r, (x, y)) in c0[0].iter_mut().zip(c1[0].iter_mut()).enumerate() {
                        *x += (i * rows + r) as u32;
                        *y += 1;
                    }
                    Ok(ch[0].len())
                })
                .unwrap();
                assert_eq!(sizes.iter().sum::<usize>(), n);
                assert!(a.iter().enumerate().all(|(i, &x)| x == i as u32));
                assert!(b.iter().all(|&y| y == 1));
            }
        }
    }
}
