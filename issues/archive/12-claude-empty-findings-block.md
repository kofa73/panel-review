# Empty Claude `new_findings` block is valid

Priority: 12

Status: Closed — working as designed

Source: review `panel-20260715-170356-97b133b8`, Claude round 4

## Report

The Claude raw response ended with a present but empty block:

````text
```new_findings
```
````

The concern was that the seat should have emitted `[]` instead.

## Triage

This is not a defect. The authoritative debate contract defines `new_findings` as
required-emptyable and explicitly permits either `[]` or an empty block when the seat found no new
issue. `README.md` and the referee protocol document the same parser behavior.

The runtime handled the cited response correctly:

- `write_seat_raw` found the one required `new_findings` fence and validated its contents;
- `parse_block` returned success for the whitespace-only body;
- `status.nf.4.claude.1` contains `0` and `nf.4.claude.1.json` is a zero-byte, zero-item JSONL stream;
- the complete round-4 Claude checkpoint was retained and the round committed.

Requiring the spelling `[]` would add a second representation rule without changing semantics or
downstream data. No code, prompt, or test change is needed.

## Existing coverage

- `scripts/seat_contract.py` says to use `[]` **or leave the block empty**.
- `scripts/parse_block` exits 0 for an empty or whitespace-only present block.
- `tests/python/test_parse_block.py` covers a present empty body through the same tag-generic parser
  path and covers explicit `[]` for `new_findings`; `tests/run_tests.sh` also covers the explicit
  empty-array form.
- `tests/python/test_write_seat_raw.py` covers debate delivery with an explicit empty array; the
  shared parser validation covers the equivalent empty-body form.
