# Spike: opt-in fast write path for Spreadsheet::XLSX

**Date:** 2026-06-01
**Status:** design approved, spec for review
**Type:** spike (time-boxed feasibility investigation; code is throwaway-or-evolve)

## Background

Agrammon's Excel export was profiled in `test/excel/FINDINGS.md`. The canonical
`Spreadsheet::XLSX` module (v0.3.5, `zef:raku-community-modules`, repo
`raku-community-modules/Spreadsheet-XLSX`, originally Jonathan Worthington, now
community-maintained) builds the workbook as a libxml2 DOM cell-by-cell. That makes
large writes 16–32× slower than the Perl baseline; the cost is the volume of small
Raku↔libxml2 FFI calls + GC, **not** libxml2 itself, **not** zip (see FINDINGS §1–6).

Agrammon already ships a fast, write-only, string-based serializer
(`lib/Agrammon/OutputFormatter/XLSXWriter.rakumod`). The maintainer (Fritz) wants to
**give this capability back to the community** in the form most useful to the ecosystem:
an **opt-in fast write path inside `Spreadsheet::XLSX`** — uncritical because it is
opt-in, and easy for him to help maintain because the module is under the Raku Community
Modules org (contributions go through that org's review, not a single absent author).

FINDINGS §8 (micro7) separately established that, for write-only output, a string
serializer is ~12–56× faster than building any DOM, and that "run it through LibXML once
as a whole" is only cheap as *parse-a-string*, never as *build-the-DOM-node-by-node*.

## What we are designing

**A spike, not the finished extension.** It resolves the two deferred unknowns and
produces the evidence to choose the final shape. It does **not** open the upstream PR,
publish anything, change the read path, or touch the installed/production library.

The spike answers two separable questions:

1. **Serialization feasibility** — can a string-based serializer reproduce
   `Spreadsheet::XLSX`'s *full current write capability* correctly?
2. **In-place wiring** — can that serializer mount behind the library's own API
   (`to-blob(:fast)` and/or a role), reusing the existing Workbook/Worksheet/Cell model
   — or does it only work as a separate writer class?

The final productization choice (opt-in inside the library **vs** a standalone
`Spreadsheet::XLSX::…Writer` module) was deliberately deferred "until after a spike."
This spike is structured to make exactly that call, with evidence.

### Deliverables

All under `test/excel/spike/`. Nothing is committed into the library itself yet; the
`test/excel/` tree is scratch and is not part of `make dist`.

- A **standalone string serializer** that walks a `Spreadsheet::XLSX` workbook's public
  model and emits the `.xlsx` zip.
- A **prototype in-place mounting** of that same serializer behind a `to-blob(:fast)`
  seam in a **local copy** of the library source (we have it extracted in
  `test/excel/_src/`).
- A **spike report** (`test/excel/spike/SPIKE.md`) covering, per feature: the
  correctness bar actually reached (DOM path as oracle), perf vs the DOM path, and a
  clean/messy verdict on each mounting — ending in a recommendation: pursue in-place PR,
  publish standalone, or both.

### Out of scope

- Opening the upstream PR or publishing to the ecosystem.
- Any read-path change.
- Any edit to the installed module (`~/opt/.../site/`) or to Agrammon production code.
- Guaranteeing byte-identical output or features beyond what the oracle/test suite
  actually exercises (the report states exactly what was covered).

## Architecture: the oracle

"Full write capability, DOM path as oracle" is the load-bearing mechanism.

A single fixture builds **one workbook through the public write API**, exercising every
writable feature the library supports (numbers; inline and shared strings; all style
attributes — fonts, fills, borders, number-formats, alignment; column widths; multiple
sheets; merged cells if supported; etc.). Then:

- **Path 1 (oracle):** serialize it the existing way → `to-blob` (DOM).
- **Path 2 (spike):** serialize the *same in-memory workbook* with the string serializer.

Compare by **round-trip**: unzip both; for each part either (a) parse both XMLs and
compare semantically (cell ref → value, type, `s=` style index resolved to the actual
style record, column widths), or (b) for tiny one-shot parts, compare after
canonicalization. Crucially, the spike **re-loads each output with the library's own
loader** and asserts the model comes back equal — so the DOM path is a true oracle:
*same model in → same model out*, independent of attribute order or whitespace.

Where exact parity is impractical (attribute ordering; inline-string vs shared-string
choice), the spike **records the discrepancy and its semantic impact** rather than
forcing byte-equality. This is the agreed "spike decides the bar," made concrete per
feature.

Consequence: only `sheetData` (the hot ~98%) is a genuine string rewrite. The small,
one-shot, non-hot parts (`styles.xml`, `[Content_Types].xml`, rels, `workbook.xml`) can
legitimately **delegate to the existing DOM `to-xml`**. So "full capability" is reached
without rewriting everything, and the oracle confirms the delegated parts are identical.

## Workspace

- Everything in `test/excel/spike/`.
- Library substrate: copy the already-extracted `test/excel/_src/Spreadsheet/` into the
  spike so the prototype edits a **local** copy via `raku -I`, never the installed module.
- The standalone serializer and the in-place-mounted copy both live under the spike dir.

## Components & phases

The spike runs in two phases mirroring the two unknowns. Each has an explicit gate that
feeds the report.

### Phase 1 — Standalone serializer (de-risk "can we serialize correctly?")

- **`spike/lib/XLSXStringSerializer.rakumod`** — one unit.
  - *Input:* a `Spreadsheet::XLSX` workbook (its public model objects).
  - *Output:* a `Blob` (the zip).
  - *Behaviour:* walks worksheets → rows → cells, emitting `sheetData` as strings (reusing
    the proven `XLSXWriter` cell logic + escaping); for the small parts, delegates to the
    existing `to-xml` of styles/content-types/rels/workbook; zips with Libarchive.
  - *Depends on:* the model's public accessors + Libarchive. Nothing else.
- **`spike/fixture.rakumod`** — builds the "exercise every writable feature" workbook
  through the public API. Single source of truth, used by both paths.
- **`spike/compare.rakumod`** — the round-trip oracle: unzip both blobs, re-load each via
  the library loader, assert model-equality; for parts that can't be reloaded, parse and
  compare semantically; collect discrepancies as structured data.
- **Phase 1 gate:** the standalone serializer reproduces the fixture workbook — oracle
  green, or every red documented with its semantic impact. If a writable feature cannot
  be reached through public accessors, that is itself a finding (it means in-place wiring
  would require internals — informs Phase 2).

### Phase 2 — In-place mounting (answer "can it live inside, same API?")

- Copy library source into `spike/lib/_lib/`; add a `to-blob(:fast)` parameter (and/or a
  `does` role) on `Spreadsheet::XLSX` that routes serialization to the Phase-1 serializer
  instead of the DOM build in `sync-to-archive`.
- **Phase 2 gate:** the library's **own existing test suite** runs through the `:fast`
  path (point its `to-blob` calls at `:fast`) and passes — the strongest "drop-in for any
  writer" evidence, using the maintainers' tests as an independent oracle. Plus a
  clean/messy assessment of how invasive the seam was (did it stay in the serialize path,
  or did it have to disturb read/archive plumbing?).

### Cross-cutting

- **`spike/bench.raku`** — perf of standalone vs `:fast`-mounted vs DOM at a few sizes,
  reusing micro7's methodology (median of repeated runs, µs/cell, vs-DOM ratio).

## Honesty constraints (what counts as success)

- If Phase 1 finds the public model cannot express some writable feature, or Phase 2
  finds the seam requires touching read-path plumbing, those are **successful spike
  outcomes** — they answer the question. They are reported, not papered over.
- The library test suite passing through `:fast` is the Phase 2 bar. The report will not
  claim "full capability" beyond what those tests actually exercise; it states exactly
  what was covered and what fell back to DOM.
- Perf numbers follow the FINDINGS discipline: reproduced, median-of-runs, methodology
  stated; no single-run or hand-waved figures.

## Spike report (`SPIKE.md`) — required contents

1. Per-feature correctness table: feature → covered by string path / delegated to DOM /
   not reachable, with oracle result and any semantic discrepancy.
2. Perf table: standalone vs in-place `:fast` vs DOM, by size.
3. Wiring verdict: how clean the `to-blob(:fast)` seam was; what (if anything) it forced
   to change beyond the serialize path.
4. Recommendation: in-place upstream PR / standalone module / both — with the reasoning,
   so the deferred productization decision is resolved on evidence.

## Success criteria for the spike itself

The spike is **done** when `SPIKE.md` can answer, with evidence:

- Can a string serializer reproduce the full current write capability? (yes / yes-except-X)
- Does it mount cleanly behind the existing API without disturbing the read path? (yes / no / yes-with-caveats)
- What is the speed-up, measured? 
- Therefore: which productization path do we pursue?

Reaching a well-evidenced **"no, in-place is too invasive — publish standalone instead"**
is a valid and successful conclusion.
