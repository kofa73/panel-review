# Stop a `continue` from reading the previous cycle's round-numbered files

Priority: 58

Status: Pending

Source: observed live in run `panel-20260822-162515-0c2ab5b1` (darktable review, workdir
`/workspace/dt-pr`), 2026-08-22

Triage: ready-for-agent

## Problem

`reopen` restarts the round counter at 1 for the next debate cycle
(`index reopen` sets `round = 0`, `scripts/index:539`), but every per-round file is named by round
number alone — `raw/round1.codex.1.txt`, `nf.1.codex.1.json`, `status.round1.codex.1`,
`await.round1.1.txt`, `await.round1.1.sentinel`, `cli_barrier.round1.1.sh`. The epoch appears in
`sweeps/round-N/.epoch` and in `index.json`, nowhere in a filename.

`reopen`'s header already names the collision and answers it by snapshotting the finished cycle into
`/tmp/<ID>/epochs/epoch-<prev>/`. That archive is a **copy**, not a move (`scripts/reopen:59-70`), so
the whole finished cycle stays at the top level of `/tmp/<ID>/` as well. The archive protects the
*record* from being overwritten; nothing protects the *new cycle* from reading what is still there.

Anything that treats such a file's existence — rather than its content — as a signal therefore fires
on the previous cycle's copy. The CLI barrier does exactly that.

## Verified failure

Run `panel-20260822-162515-0c2ab5b1`: rounds 0-4 completed as epoch 0, leaving issue `i15` contested;
`panel-review:continue contested` opened epoch 1, whose debate starts again at round 1.

| time | event |
|---|---|
| 16:46:47 | epoch 0's round 1 finishes; writes `await.round1.1.sentinel` = `0`, `status.round1.{codex,gemini}.1` = `0` |
| 18:53:56 | epoch 1 `round prepare-debate` — new plan (`sweeps/round-1/.epoch` = 1), new prompt; the six files above are untouched |
| 18:53:57 | referee writes `cli_barrier.round1.1.sh` |
| 18:54:05 | barrier launches; `run_seat` starts Codex and Gemini, truncating both raw files to 0 bytes |
| 18:54:05 | the barrier agent's first `until [ -f "<sentinel>" ]` matches the **16:46:47** file and returns |
| 18:54:13 | the barrier agent having returned, the harness reaps its background shell — agy logs `server.go:2656] Got signal terminated, shutting down` (`~/.gemini/antigravity-cli/log/cli-20260822_185405.log`), 8 s into the review; Codex dies with it |

The referee was told both CLI seats had settled, and read the stale `0`/`0` per-seat statuses as this
round's result. Both raw files are 0 bytes.

The barrier agent's contract states the precondition it cannot itself check
(`agents/panel-review-cli-barrier.md:57`): *"`sentinel=<path>` — does **not** exist yet; **you**
create it"*. Preparation is what must establish it.

`prepare-round0` does establish it — it clears `await.round0.txt`, `await.round0.sentinel`,
`cli_barrier.round0.sh` and each dispatched seat's raw/parsed/status before dispatch
(`scripts/round:413-426`), because Round 0 legitimately reruns in place on a retry.
`prepare-debate` cleared only the **Claude** seat's three files and nothing else, because within one
cycle a debate round number is never reused. `continue` is the case that reuses it.

### What was not damaged

`round collect-debate` re-parses the raw through `sweep ingest-batch` instead of trusting the status
file, so the 0-byte raws would have been recorded as non-engaged and the seats retried next round;
`sweeps/round-1/.epoch` correctly held `1` and nothing stale was ingested. The blast radius was the
wasted pass plus a false `barrier_rc: 0` in the collect report — but note the trap was armed for
**every** round of the new cycle, not just the first: epoch 0's `status.round{2,3,4}.*` and
`await.round{2,3,4}.1.sentinel` were all still in place, and the cycle's budget was `--max-rounds 4`.

## Fix

**Landed (small, mirrors the existing precedent):** `prepare-debate` now clears the barrier trio
(`await.round<N>.<batch>.txt`, `.sentinel`, `cli_barrier.round<N>.<batch>.sh`) and, for every CLI seat
it is about to dispatch, that seat's `raw`, `raw*.salvaged`, `nf`, `status.round*` and `status.nf*`
files — the same discipline `prepare-round0` already applies. Regression test:
`tests/python/test_round.py::test_prepare_debate_clears_stale_cli_and_barrier_files`.

**Still open (this issue):** removing the general hazard rather than the one instance of it. Two
candidates:

1. **Put the epoch in the filenames** — `round<E>.<N>.<seat>.<batch>.txt`, `await.<E>.<N>.<batch>.*`,
   and so on, so a reused round number cannot collide at all and the archive stops being load-bearing
   for correctness. Touches `round`, `await_seats` call sites, `sweep`'s per-batch paths, the
   barrier/Claude-seat prompt fragments, `inspect_run`, and the protocol's file table.
2. **Make `reopen` move instead of copy** — archive the finished cycle's per-round files into
   `epochs/epoch-<prev>/` and delete the originals, leaving the top level holding only the current
   cycle. Much smaller, but keeps the "the writer must clear its own leftovers" obligation for every
   future round-numbered file, and needs care over which top-level files are cycle-scoped
   (`raw/`, `status.*`, `await.*`, `nf.*`, prompts, `plan.*`, `stances.*`, `payload.*`, `cards.*`,
   `batch.*`) versus run-scoped (`manifest.json`, `index.json`, `diff.txt`, `review-profile.md`,
   `instructions.txt`, `guard/`, `origins/`, `audit/`, `work/`).

Option 1 is the durable one; option 2 is a cheap strict improvement over the landed fix. Either way
the invariant to state and test is: **no file a pass will produce may exist when that pass is
prepared.**

## Related

- The same class, opposite direction: `round0_checkpoint_complete` (`scripts/round:258-263`) already
  requires non-empty raw bytes rather than trusting `status.<seat>`, precisely so a stale success
  status cannot turn zero-byte output into an engaged seat. That defence exists for Round 0 only.
