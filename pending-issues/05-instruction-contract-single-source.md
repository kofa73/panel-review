# Establish one source of truth for executable instructions

Priority: 5

Status: Pending

Source: general agent, skill, protocol, and prompt-template consistency audit

## Problem

Required behavior is repeated across agent definitions, skills, the canonical phased protocol,
prompt templates, schema fragments, scripts, tests, and user-facing documentation. The copies have
drifted. Some contradictions merely confuse a model; others permit invalid output or send the
referee down an obsolete runtime path.

Adding more phrase-scanning tests will detect a few known wordings but will not solve the ownership
problem. The durable fix is to give every executable invariant one authoritative owner, derive model
instructions and validation from it where practical, and make other layers reference rather than
restate it.

"One source of truth" should mean one source **per invariant**, not one giant document containing
every concern. A monolithic source would couple unrelated changes and be harder for both scripts and
models to consume safely.

## Confirmed inconsistencies in scope

The following were found in the live tree. They are evidence for the architectural problem, not an
exhaustive list:

1. The common protocol says the CLI barrier watches the `--done` file, while the barrier agent,
   later protocol text, and `README.md` correctly say it watches a completion sentinel. The existing
   shell scan misses the contradiction because `watches` and `--done` are on separate lines.
2. The protocol calls the seat scratch path relative, then immediately constructs and requires an
   absolute path because the Gemini/agy tool cwd can drift.
3. `PANEL_VERDICT_WRITE_FAILED` is described as both a general review failure and a persistence
   failure. One stub cannot communicate both meanings reliably unless that broader meaning is made
   explicit everywhere.
4. Seat prompts say "two other AIs" even when graceful degradation configures only two seats.
5. Verdict Process-note guidance names only Codex and Gemini as potentially down, although the Claude
   seat can also fail a pass.
6. `skills/status/SKILL.md` says the verdict was shown in the transcript, which is stale after
   artifact-only filename delivery.
7. Issues 01, 03, and 04 demonstrate semantic drift in stance, mutation, and debate-block contracts.
   Their immediate fixes should land before this broader restructuring.

## Cause

The same facts are expressed in forms optimized for different audiences:

- concise agent identity and safety rules;
- detailed referee phase steps;
- seat-facing prompt prose and examples;
- machine validation and transition logic;
- shell tests that grep source phrases;
- README explanations for humans.

There is no explicit ownership map saying which layer defines a fact and which layers are generated,
derived, or explanatory. A change can therefore update the most visible copy while leaving an
always-loaded instruction or parser behind. Tests mostly assert that selected phrases exist; they do
not prove that rendered instructions and executable validation express the same contract.

## Recommended design

### 1. Assign an owner to each invariant

Use this ownership split unless implementation analysis reveals a concrete reason to change it:

| Concern | Authoritative owner | Other layers |
|---|---|---|
| Seat output fields, cardinality, and stance-dependent rules | structured seat-contract data plus deterministic validator | prompt fragments rendered from it; tests exercise rendered prompts and validation |
| Review phases, state transitions, gate behavior, and resume rules | canonical marked protocol plus transition scripts | agent and command skills reference the relevant phase/interface |
| CLI barrier execution and completion signal | barrier agent/script interface | protocol supplies invocation and consumes its result; it does not restate internals |
| Verdict persistence, artifact location, and failure classification | verdict persistence/delivery scripts | protocol calls the interface; command skills render validated outcomes |
| Agent identity, context isolation, and non-negotiable role limits | agent definition | protocol does not duplicate identity prose |
| Public behavior and operator guidance | README, derived from settled executable contracts | never treated as machine validation |

The structured seat contract need not be a new framework. A small declarative file or importable
Python data structure is sufficient if it can drive both validation and the exact schema/instruction
fragments seats receive. Choose the least complex representation that eliminates manual semantic
copies.

### 2. Render shared seat instructions

Extract common reviewer rules—blindness, output fences, field meanings, cardinality, and empty-block
behavior—into shared fragments assembled for all seat transports. Transport-specific wrappers should
only explain delivery mechanics such as the Claude atomic writer or an external CLI's response path.

Do not let agent summaries redefine phase-specific output requirements. They should name the shared
contract or defer to the assembled prompt.

### 3. Reduce orchestration duplication

Keep the phased protocol authoritative for orchestration. Replace descriptions of helper internals
with narrow interfaces: required inputs, success/failure outputs, and the next referee action. The
barrier agent alone should explain how it waits. Verdict scripts alone should classify persistence
outcomes.

### 4. Replace brittle source-phrase scans

Build a consistency checker around semantic assertions:

- load the structured contract and validate its internal completeness;
- assemble every meaningful prompt variant, including degraded panel sizes;
- verify required and forbidden blocks/fields in rendered output;
- run representative payloads through the same validator used at runtime;
- check that agent/skill/protocol ownership boundaries reference the contract rather than duplicate
  prohibited rules;
- retain only a small set of source scans for genuinely forbidden legacy phrases.

The checker should fail with an invariant name and conflicting file/fragment, not merely a missing
substring.

## Implementation sequence

This issue is a proposal and tracking document; no restructuring has been implemented. When
implementation is authorized:

1. Finish issues 01–04 so the intended behavior is explicit.
2. Inventory every normative statement across `agents/`, `skills/`, `prompts/`, scripts, tests,
   `README.md`, `AGENTS.md`, and any retained `CONTEXT.md`.
3. Classify each statement by invariant and assign its owner using the table above.
4. Add characterization tests for currently intended rendered prompts and runtime payload handling.
5. Introduce the structured seat contract and shared fragments without changing behavior.
6. Move validation to consume the authoritative contract; delete manual semantic copies only after
   parity tests pass.
7. Thin agent and protocol text to owned rules plus explicit references.
8. Add rendered-prompt and ownership consistency checks.
9. Correct the lower-severity wording drift listed above.
10. Update public documentation last, after executable sources have stabilized.

Each step should be independently reviewable. Avoid a single rewrite of every instruction file;
that would make behavior changes and deduplication impossible to distinguish.

## Acceptance criteria

- Every required behavior has one named authoritative owner.
- Seat block cardinality and stance field rules are generated from or validated against the same
  structured contract.
- Agent files do not restate phase-specific schemas or transition rules.
- The protocol does not describe barrier wait internals or maintain a second verdict persistence
  contract.
- All configured panel sizes receive grammatically and semantically correct rendered prompts.
- The consistency checker catches each confirmed inconsistency above when reintroduced.
- Existing behavioral tests and full review tests pass without depending on obsolete phrase copies.
- README and repository instructions accurately explain the resulting behavior.

## Non-goals

- Do not create security controls against a malicious seat; the project trust model explicitly rules
  out that form of security theatre.
- Do not merge unrelated review, persistence, and barrier behavior into one runtime module.
- Do not make Markdown the parser's only executable schema if deterministic code cannot consume it
  safely.
- Do not change public behavior merely to simplify deduplication; behavior changes need their own
  issue and tests.
