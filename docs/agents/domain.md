# Domain Docs

This is a single-context repository.

## Before exploring

- Read `CONTEXT.md` at the repository root.
- Read relevant ADRs under `docs/adr/`.

If either location does not exist, proceed silently. Domain-modeling work creates or extends these
files when terminology or architectural decisions are actually resolved.

## Layout

- `CONTEXT.md` is the shared glossary and domain model.
- `docs/adr/` contains repository-wide architectural decisions.
- `docs/evolution.md` is the evidence-backed historical sequence behind those decisions. It records
  superseded and proposed work as history, not as current authority.
- A root `CONTEXT-MAP.md` or per-package context documents are not used unless the repository later
  becomes a genuine multi-context monorepo.

## Vocabulary

Use terms as defined in `CONTEXT.md`, including its explicitly avoided synonyms. If required
terminology is missing, either reconsider whether the term belongs to the project or record the gap
for domain-modeling work.

## ADR conflicts

If proposed work contradicts an existing ADR, identify the ADR and explain why the decision may need
to be reopened. Do not silently override it.
