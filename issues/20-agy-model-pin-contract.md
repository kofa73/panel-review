# Correct the agy model-pin contract

Priority: 20

Status: Completed

Source: external CLI update review (agy 1.1.10), 2026-08-05

Triage: ready-for-agent

## Problem

`scripts/run_agy` pins the Gemini seat by exact display label (`Gemini 3.1 Pro (High)`). That is
correct on agy 1.1.10, but the wrapper does not say that the label form is the contract, and its own
header sends a maintainer to the interface that is broken:

```text
scripts/run_agy:34   Verify names with `agy models`; do NOT use agy's Claude/GPT-OSS entries.
```

`agy models` prints slugs, and slugs do not bind reliably. A maintainer who follows that instruction
and replaces the pins with the slugs it printed silently downgrades a review seat: agy exits 0,
prints a complete review, and nothing in the panel's output reveals that the pinned model never ran.

This is an honest-accident hazard of exactly the kind the trust model says guards should target.

## Verified evidence (2026-08-05, agy 1.1.10)

Label form binds exactly. Measured through agy's own CLI log line
`Propagating selected model override to backend: label="…"`, using `run_agy`'s invocation form
(prompt on stdin, no `--print`):

| Requested `--model` | Bound |
|---|---|
| `Gemini 3.1 Pro (High)` | Gemini 3.1 Pro (High) |
| `Gemini 3.5 Flash (High)` | Gemini 3.5 Flash (High) |
| `Gemini 3.6 Flash (High)` | Gemini 3.6 Flash (High) |

Slug form does not (user report, same version):

| Requested `--model` | Bound |
|---|---|
| `gemini-3.1-pro-high` | Gemini 3.6 Flash (High) — wrong family |
| `gemini-3.5-flash-low` | Gemini 3.5 Flash (Medium) — wrong effort |
| `gemini-3.1-pro-low` | Gemini 3.1 Pro (Low) — correct |
| `something-silly` | Gemini 3.6 Flash (Medium) — the `settings.json` default, no error |

`agy models` prints only slugs when its output is piped (the two-column slug + label listing appears
on a TTY), so any scripted "verify the pins" step sees the broken form exclusively.

An unrecognized value is never an error. It resolves to whatever
`~/.gemini/antigravity-cli/settings.json` has as `model` — a per-user value the plugin does not
control and cannot see.

## Expected behavior

1. `scripts/run_agy`'s model-pin comment states the contract: pin the **exact display label**; never
   a slug; slugs remap unpredictably on 1.1.10; an unrecognized value falls back silently to the
   user's `settings.json` default rather than failing.
2. The same fact appears once in `AGENTS.md` "Non-obvious facts (hard-won)", next to the existing
   agy working-directory entry, because it is a property of agy and not of one script.
3. The instruction to verify names with `agy models` is corrected, not deleted: the listing is still
   the source of *which models exist*, but the label column (TTY output) is the value to copy.
4. A contract check rejects a slug-shaped pin. `PRIMARY_MODEL` and `FALLBACK_MODEL` must match the
   display-label shape (`Gemini <version> <Tier> (<Effort>)`), so a future slug substitution fails
   `scripts/check_contracts` instead of silently downgrading a seat.

## Open decision — post-hoc bind verification

Optional, and a separate call from items 1–4. `run_agy` could confirm after each attempt that the
model it asked for is the model that ran, by reading the newest
`~/.gemini/antigravity-cli/log/cli-*.log` for the `Propagating selected model override to backend:
label="…"` line and warning (or failing the attempt, so the fallback is tried) on a mismatch.

For it:

- it is the only signal that closes the silent-fallback failure entirely;
- it targets misconfiguration and model confusion, not a tampering seat, so it is not theatre.

Against it:

- it depends on an undocumented log line and file layout, so it can rot without notice;
- it is best-effort under the single-session assumption: it identifies the newest log, not
  provably *this* invocation's log.

Recommended: implement items 1–4 now; take the guard only if it is labelled a convenience in the
header, degrades to silence when the log line is absent, and never fails a run on its own.

## Verification

- `scripts/check_contracts --root .` passes and rejects a slug-form pin in `run_agy`.
- The `run_agy` header and the `AGENTS.md` entry state the same contract with no third copy.
- `./tests/run_tests.sh` passes.
- `git diff --check` passes.

## Non-goals

- Do not change which model is pinned as primary. That is issue 21.
- Do not add `--effort`. With label pins the effort is already part of the label, and agy 1.1.10
  documents a fixed bug where a bare `--effort` resolved against the default model instead of the
  selected one.
- Do not add any guard that assumes a tampering seat.

## Comments

**2026-08-15 (agy 1.1.13). All four items done; the open decision settled.**

- **Item 1** — `scripts/run_agy`'s header states the label contract: exact display label, never a
  slug, effort carried by the label, and how a wrong value fails on each version tested.
- **Item 2** — one entry in `AGENTS.md` "Non-obvious facts (hard-won)", next to the agy
  working-directory fact. It states the fact and points at `run_agy`'s header and this issue for the
  measurements, so there is no third copy of the contract.
- **Item 3** — the `agy models` instruction is corrected rather than deleted: copy the **label**
  column (the second tab-separated field on 1.1.13; slug-only when piped on 1.1.10, hence the TTY
  note for older versions). `--output-format json`, announced in the 1.1.12 changelog, does not
  exist for `models` on 1.1.13.
- **Item 4** — `scripts/check_contracts` owns the pin form under the invariant
  **`agy-model-pin-form`**: both pins must match the display-label shape (which also keeps them on
  Gemini rather than agy's Claude/GPT-OSS entries) and the fallback must differ from the primary.
  `tests/python/test_contract_consistency.py` reintroduces each drift — a slug of the pinned model,
  and a fallback repeating the primary — and requires the invariant name in the failure. The
  duplicated assertions in `tests/run_tests.sh` were removed; the bash suite now only checks that
  the pinned string reaches agy's argv intact.
- **Open decision** — settled as "no runtime bind check"; see the resolution section below.

The pins themselves became `Gemini 3.7 Flash (High)` primary / `Gemini 3.1 Pro (High)` fallback in
issue 21.

New evidence, same measurement method as above: on 1.1.13 the slug form bound *correctly* in a spot
check — `gemini-3.1-pro-high` → Gemini 3.1 Pro (High), `gemini-3.5-flash-low` → Gemini 3.5 Flash
(Low), `gemini-3.7-flash-high` → Gemini 3.7 Flash (High) — i.e. the 1.1.10 misbind appears to be a
version-specific regression that has since been fixed. This does **not** relax the contract: the
label form is the one that bound on every version tested, and a slug's behavior has already changed
once between releases without any error surfacing.

**2026-08-15, the premise itself changed: an unrecognized `--model` is now a hard error.** Measured
on 1.1.13 with `--model "Gemini 0.0 Nonexistent (High)"`:

```text
Error: invalid model selection (--model "Gemini 0.0 Nonexistent (High)" --effort ""): model
Gemini 0.0 Nonexistent (High) is not recognized as a known model or custom model in settings
Available models: …
```

Exit 1, and the seat never runs. On 1.1.10 the same input silently ran the `settings.json` default.
So on current agy the invisible-downgrade hazard this issue was opened for does not exist: a stale
pin fails its attempt loudly, `run_agy`'s `attempt()` treats the nonzero exit as a failure, and the
other pin is tried. `scripts/run_agy`'s header now states both behaviors, because the behavior has
changed once already and may change back.

### Primary record of the 1.1.10 measurement

Absorbed 2026-08-15 from the maintainer's original measurement note of 2026-08-05, which was
discarded afterwards — this issue is the only remaining record. The tables above are the
conclusions; what follows are the raw conditions they were measured under.

The CLI was **agy 1.1.10**, and the user's `~/.gemini/antigravity-cli/settings.json` carried
`"model": "Gemini 3.6 Flash (Medium)"` — which is what every unrecognized `--model` value silently
resolved to, and the reason `something-silly` lands on that particular label in the table above.

`agy models` on 1.1.10 offered exactly:

```text
gemini-3.6-flash-high     Gemini 3.6 Flash (High)
gemini-3.6-flash-medium   Gemini 3.6 Flash (Medium)
gemini-3.6-flash-low      Gemini 3.6 Flash (Low)
gemini-3.5-flash-high     Gemini 3.5 Flash (High)
gemini-3.5-flash-medium   Gemini 3.5 Flash (Medium)
gemini-3.5-flash-low      Gemini 3.5 Flash (Low)
gemini-3.1-pro-high       Gemini 3.1 Pro (High)
gemini-3.1-pro-low        Gemini 3.1 Pro (Low)
claude-sonnet-4-6         Claude Sonnet 4.6 (Thinking)
claude-opus-4-6-thinking  Claude Opus 4.6 (Thinking)
gpt-oss-120b-medium       GPT-OSS 120B (Medium)
```

So `gemini-3.1-pro-high` was a listed, valid slug — not a typo — and it still bound the wrong model.
The model said so itself when asked:

```console
$ agy --model gemini-3.1-pro-high -p "say hello and tell me what model this is"
Hello. I am running Gemini 3.6 Flash.
```

The measurement loop behind the tables, which reads what agy propagated to its backend rather than
trusting the model's self-report:

```bash
for slug in gemini-3.1-pro-high gemini-3.1-pro-low gemini-3.5-flash-low "Gemini 3.1 Pro (High)" something-silly; do
  agy --model "$slug" -p "ok" >/dev/null 2>&1
  log="$(ls -t "$LOGDIR"/*.log | head -1)"
  echo "$slug -> $(grep -oE 'Propagating selected model override to backend: label="[^"]+"' "$log" | head -1 | sed 's/.*label="//;s/"$//')"
done
```

`tests/live/agy_model_binding.sh` is the maintained form of this loop: same log line, but scoped to
the logs a single call wrote, matched exactly, and reporting a missing line as a stale check.

## Resolution of the open decision — no runtime bind check; an on-demand test instead

Implemented 2026-08-15 as **`tests/live/agy_model_binding.sh`** (documented in `tests/README.md`),
which is the "post-hoc bind verification" above, moved out of the run loop:

- it dispatches through `scripts/run_agy` itself for the primary pin (so a quoting bug in the
  wrapper's argv fails there, not only in the offline argv test) and directly for the fallback,
  reads the `Propagating selected model override to backend: label="…"` line from the logs written
  by *that* call, and requires an exact label match — effort included, since the label carries it;
- it checks both pins against `agy models` first, which costs no quota;
- `--model "<label>"` vets a candidate before it is pinned; `--negative-control` demonstrates how a
  bad pin fails on the installed version (that flag is what surfaced the 1.1.13 behavior change);
- a missing log line is reported as **the check being stale**, never as a pass;
- it is opt-in: `PANEL_REVIEW_LIVE=1 ./tests/run_tests.sh`, or run the script directly. It exits 3
  (skip) without agy.

Rationale for rejecting the in-wrapper guard: it depends on an undocumented log line and file
layout, so it can rot into false failures inside a real review; "newest log file" is a heuristic,
not proof of *this* invocation; and it would cost a second 15-minute fallback attempt whenever it
misfires. With unknown models now rejected outright, the residual risk it covered is small, and the
same evidence is available on demand from the test. Revisit only if agy returns to silent fallback.
