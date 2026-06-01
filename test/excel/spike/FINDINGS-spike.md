# Spike findings log (running)

Append-only notes as the spike progresses. Each entry: date, phase, what was tried,
what was learned. Feeds SPIKE.md at the end.

## 2026-06-01 — Task 1: substrate loads OK
Workspace skeleton created under test/excel/spike/. Verified test/excel/_src/Spreadsheet/XLSX.rakumod
and XLSX/Worksheet.rakumod present. `raku -Itest/excel/_src -e 'use Spreadsheet::XLSX'` → "loads OK".

## 2026-06-01 — Task 3: unzip-parts oracle helper (READ side)
Goal: unzip an in-memory .xlsx (zip Blob) into a map of part-path => decompressed Blob,
as the first step of the round-trip comparison oracle.

Read mechanism CONFIRMED: **Libarchive in-memory read API**, imported via
`use Libarchive::Simple` (same module the repo's WRITE-side
lib/Agrammon/OutputFormatter/XLSXWriter.rakumod uses, which only exercises
`archive-write`). The Simple layer re-exports `archive-read`, `archive-slurp`,
`archive-write`, `archive-new` from the `Libarchive` dist (installed at
~/.zef/store/Libarchive-0.1/.../lib/Libarchive/).

API discovered by reading Libarchive source (NOT guessed):
- `archive-read($blob)` accepts a `Blob` source -> `Libarchive::Read.new`, which on a
  Blob calls `archive_read_open_memory` (Read.pm6:114-116). It `does Iterable/Iterator`,
  yielding one `Libarchive::Entry::Read` per archive member.
- Entry methods (Entry.pm6, Entry/Read.pm6): `.pathname(--> Str)`, `.is-file(--> Bool)`,
  `.size`, and `.data($size = $.size)` which returns the DECOMPRESSED bytes as a Blob
  (`.content` would decode to Str). We use `.data`.
So `unzip-parts` iterates `archive-read($zip)`, skips non-files via `.is-file`, and stores
`%out{$entry.pathname} = $entry.data`. No `unzip` shell fallback needed.

Bytes verified REAL & non-empty (test only checks key presence, so checked independently):
all 7 parts have >0 bytes — [Content_Types].xml 816, _rels/.rels 296,
xl/_rels/workbook.xml.rels 565, xl/styles.xml 416, xl/workbook.xml 327,
xl/worksheets/sheet1.xml 630, xl/worksheets/sheet2.xml 343. Each decodes as valid UTF-8
XML; sheet1 contains `<worksheet`, workbook.xml decodes to `<?xml ...><workbook ...>`.

NOTE / gotcha: the task's suggested sanity check ("[Content_Types].xml must contain the
string 'Content_Types' when decoded") is WRONG for content — that underscore token is only
the PART FILENAME (`[Content_Types].xml`). The DOM writer's actual XML body is
`<Types xmlns=".../package/2006/content-types">...ContentType="..."...`, i.e. it contains
`ContentType` / `content-types` but not the literal `Content_Types`. The decompressed
content is genuine; only the assumed marker string differed. Verified via decode + substr.

Test: test/excel/spike/t/01a-unzip.rakutest — 3/3 PASS.
Helper: test/excel/spike/compare.rakumod exporting `unzip-parts(Blob --> Hash)`.

## 2026-06-01 — Task 4 follow-up: comparator now flags number-vs-text type mismatch
Code review found a trust hole: `compare-workbooks` compared cells via
`($ov.value // '') ne ($sv.value // '')`, which Str-coerces both sides. A NUMBER cell `6`
and a TEXT cell "6" therefore compared EQUAL. This matters because Task 5's string
serializer's key failure mode is emitting numbers as inline strings — the oracle must
catch exactly that.

Fix: per-cell comparison now checks cell TYPE first (`$ov.WHAT =:= $sv.WHAT`), pushing
`"sheet$si [$r;$c]: type {oracle.^name} vs {spike.^name}"` on mismatch; value comparison
still runs for same-typed cells. Presence + sheet-count logic unchanged.

ORACLE CAPABILITY CONFIRMED (good news): the library PRESERVES the number-vs-text
distinction across a save→reload round-trip. After `Spreadsheet::XLSX.load`, a number cell
reloads as `Spreadsheet::XLSX::Cell::Number` (with `.value` an Int/Numeric) and a text cell
as `Spreadsheet::XLSX::Cell::Text` (`.value` a Str). So comparing `.^name` / `.WHAT` on the
loaded model reliably distinguishes them — no need to fall back to inspecting `.value`'s
Numeric-vs-Str-ness. The reload preserves type, so the round-trip oracle CAN detect a
serializer that mis-encodes numbers as inline strings.

Verification (all pass):
- Existing DOM-vs-DOM self-compare: t/01b-compare-self.rakutest → 1/1 (got: []).
- Planted VALUE diff (text[0;0] "Name"→"CHANGED"): diffs=1 →
  `sheet0 [0;0]: value 'Name' vs 'CHANGED'`.
- Planted TYPE diff (number[1;1] value 6 → Text "6"): diffs=1 →
  `sheet0 [1;1]: type Spreadsheet::XLSX::Cell::Number vs Spreadsheet::XLSX::Cell::Text`.
  (Before this fix the same scenario gave diffs=0 — the bug.)

## 2026-06-01 — Task 5: standalone string serializer, value round-trip clean
Implemented `string-serialize(Spreadsheet::XLSX $wb --> Blob)` in
test/excel/spike/lib/Spreadsheet/XLSX/StringSerializer.rakumod.

Approach (as designed): call DOM `$wb.to-blob` once for the byte-for-byte
baseline of every package part, unzip it (local copy of the read side from
compare.rakumod), then REPLACE only `xl/worksheets/sheetN.xml` with
string-built sheetData read from the public `$wb.worksheets[*].cells` model,
and re-zip with Libarchive. Result: t/01-roundtrip.rakutest → **3/3 PASS, 0
diffs** (oracle vs spike semantically equivalent, type+value+presence).

Libarchive WRITE API copied verbatim from
lib/Agrammon/OutputFormatter/XLSXWriter.rakumod (`Workbook.to-blob`):
```
my $buffer = Buf.new;
given archive-write($buffer, format => 'zip') -> $archive {
    for ... { $archive.write($path, $bytes); }
    $archive.close;
}
$buffer   # the filled Buf is the .xlsx Blob
```
i.e. `archive-write(Buf, format => 'zip')` -> object with `.write(path, Blob)`
and `.close`; the Buf passed in is mutated in place and returned. Parts are
written as `%parts{$path}` (already-decompressed bytes); the replaced
sheet parts are `sheet-xml($ws).encode('utf-8')`.

KEY FINDING — style index `s="..."` is OMITTED (intentionally, per task gate
= value+type parity; Task 6 owns style parity). Reason it MUST be omitted now:
the resolved style id is **not publicly reachable from the in-memory cell
model pre-serialize**. In XLSX/Cell.rakumod the style index is a *private*
attribute `has UInt $!style-id is built is xml-attr<s>` with NO public
accessor. The only public surface is `.style`, which lazily constructs a
`Spreadsheet::XLSX::CellStyle` object (Cell.rakumod:57-65) — it does not return
the integer index, and reaching `$!style-id` would require touching a private
attr (forbidden). So the string path cannot carry `s=` from the in-memory
model without either (a) the DOM serialization step assigning indices, or (b)
the library exposing a public style-id accessor. This is a load-bearing
constraint for the in-place (Task 8) design: the fast path must run AFTER (or
as part of) the style-resolution the DOM path performs, or the library needs a
public style-id getter added.

SECONDARY GOTCHA — `Cells.max-row` is unreliable for a *built* (vs *loaded*)
workbook. `max-row` returns `@!backing-rows.end` (Worksheet.rakumod:108-111),
and `@!backing-rows` is only populated from a backing XML document
(`!load-backing-rows`, lines 137-148). A freshly `create-worksheet`+assigned
workbook has NO backing, so `max-row` == -1 even though `@!rows` holds data.
Likewise there is no public max-col. The in-memory data is only reachable via
the public `:exists` / AT-POS grid API. The spike therefore probes a fixed
grid (rows 0..1023 × cols 0..63) via `:exists`; ample for the fixture. A
production in-place writer should instead walk the worksheet's private
`@!rows` directly (it lives inside the library, so that's legitimate there).

Caveats / non-issues for value round-trip:
- Did NOT reproduce the DOM's column `spans` attribute, `<cols>`, or original
  column ordering — not needed; the loader reconstructs values regardless and
  the comparator (value+type+presence) reports 0 diffs.
- DOM output uses inline strings (not sharedStrings) for these cells, and so
  do we, so string representation matches; no shared-string discrepancy arose.

## 2026-06-01 — Task 5 follow-up: optional extent hints (benchmark-safe)
Code review (must-fix-before-benchmarking): the no-hint `sheet-xml` probes a
FIXED grid rows 0..1023 × cols 0..63 via `:exists` = 65,536 lookups per sheet
regardless of how many cells exist, AND silently drops any cell at row>=1024 or
col>=64. On the sparse/tall sheets Task 7 will benchmark, that phantom-grid
probe would dominate the timing → the benchmark would measure probing, not the
serializer.

Fix (minimal, default behaviour UNCHANGED): added OPTIONAL 0-based extent hints.
- `string-serialize(Spreadsheet::XLSX $wb, Int :$max-row, Int :$max-col --> Blob)`
  threads both hints to every worksheet's `sheet-xml`.
- `sheet-xml($ws, Int :$max-row, Int :$max-col)`:
  - row bound `$rmax = $max-row // (($cells.max-row // -1) max (MAX-ROW-PROBE-1))`
  - col bound `$cmax = $max-col // (MAX-COL-PROBE-1)`
  i.e. a hint, when given, becomes the loop bound and the fixed-grid probe is
  bypassed; when absent it falls back to the EXISTING probe ceiling. So the
  no-hint path (and the fixture round-trip test, which calls
  `string-serialize($wb)`) is byte-identical to before.
This is the seam a real in-place writer uses too: it knows its own `@!rows`
extent and would pass it, never probing. (Recall the public Cells model exposes
no usable max-row/max-col for a *built* workbook — see Task 5 entry above — which
is exactly why hints have to come from the caller.)

Verification:
- t/01-roundtrip.rakutest (no-hint path) → 3/3 PASS, diffs [].
- Fixture data fits both bounds, so hinted == probed: `string-serialize($wb)`
  vs `string-serialize($wb, :max-row(2), :max-col(1))` → same-bytes:True,
  and compare-workbooks(oracle, hinted) → 0 diffs. Byte-identical (the probe
  emitted no trailing empty rows/cols for this fixture, so trimming changed
  nothing).

## 2026-06-01 — Task 6: style parity in the oracle + Phase 1 conclusions

Goal: make the round-trip oracle style-aware (bold + number-format) and decide,
from EVIDENCE, whether the standalone *public-API-only* string serializer can
preserve cell styles.

### TDD outcome
Added the bold-parity assertion (`is $sb, $ob, ...`) and bumped `plan 3 → 4`.
First run FAILED exactly as the Task-5 finding predicted:
```
not ok 4 - bold style preserved on A1 (oracle=True spike=)
#   expected: 'True'
#        got: (Any)
```
The spike dropped `s=`, so the reloaded A1 had no style → `.style.bold` = Any.

### Investigation — the resolved style-id IS reachable via PUBLIC API (revises the Task-5 finding)
The Task-5 note said the id is "not publicly reachable". That is true of the
*Cell* object (`has UInt $!style-id` is private, Cell.rakumod:45, no accessor),
but it is the WRONG place to look. The id lives on the **CellStyle**, which has
a **PUBLIC** accessor `has Int $.style-id;` (CellStyle.rakumod:198), and the
DOM sync pass populates it:
- `Worksheet::Cells.sync-sheet-data-xml` calls `$cell.style.sync-style-id($styles)`
  (Worksheet.rakumod:211-212).
- `CellStyle.sync-style-id` (public, CellStyle.rakumod:283-303) resolves the id,
  **assigns `$!style-id = $styles.id-for(...)`** (line 299), and returns it.
- `$cell.style` is memoized (`$!style //= ...`, Cell.rakumod:58), so the very
  object the DOM mutated is what the public `.style` accessor returns afterward.

Because `string-serialize` calls `$wb.to-blob` FIRST (its byte baseline), that
sync pass has already run by the time `sheet-xml` reads cells. Empirically, after
ONE `to-blob` on the fixture:
```
A1.style.style-id = 1   B1 = 1   A2/B2 = 0   B3 = 2
```
So the serializer now emits `s="<id>"` from `$cell.style.style-id` (omitting it
for id 0, the default cellXfs entry, to mirror the DOM which writes `s="0"` but
the loader treats absent==0 identically; round-trip confirms equivalence). The
`styles.xml`/`cellXfs` that those ids index into is byte-identical to the DOM
output (we delegate styles.xml unchanged) — verified `styles.xml SAME? True`.
Result: bold AND number-format now round-trip; **plan 5, all green.**

### KEY NEW FINDING — `to-blob` is NOT idempotent w.r.t. style resolution
`sync-style-id` mutates shared `$!format`/`%!changes` state and calls `!RESET`,
which consumes the pending changes. A SECOND `to-blob` on the SAME workbook
therefore re-resolves every cell to **style-id 0** (bold/number-format lost):
```
after 1st to-blob: A1.style-id=1 B3.style-id=2
after 2nd to-blob: A1.style-id=0 B3.style-id=0
```
Consequence for the TEST: the original `my $wb = build-fixture(); $oracle =
$wb.to-blob; $spike = string-serialize($wb)` double-serialized ONE object — by
the spike's (2nd) to-blob the style state was already destroyed, so even with
correct code the spike read 0s. Fix: the test now builds a SEPARATE fixture per
serialization (`build-fixture().to-blob` and `string-serialize(build-fixture())`),
i.e. each workbook is serialized exactly once — which is also how a real caller
uses it. This is a property of the LIBRARY, not the spike, and it constrains any
fast-write design: the seam must read style-ids from the SAME (first) sync pass,
never re-run to-blob on an already-serialized workbook.

### Oracle is now style-aware
`compare-workbooks` (compare.rakumod) now diffs, per populated cell, `.style.bold`
and `.style.number-format` (guarded for undefined `.style`), in addition to
presence/type/value. Negative control confirms it bites: comparing a bold/
number-formatted oracle against a plain workbook yields exactly
`bold oracle=True spike=False` (×2) + `number-format oracle='#,##0.00' spike=''`.
On the real oracle-vs-spike it reports 0 diffs.

---

## ✅ PHASE 1 RESULT (conclusions)

What the standalone STRING serializer carries, and how:
- **Values** (text + number) — built as strings from the public cell model
  (`<v>` for Number, `t="inlineStr"` for text). Round-trips, type-preserving.
- **Cell styles (bold + number-format)** — carried as the `s="<id>"` index,
  read from the PUBLIC `$cell.style.style-id` AFTER the DOM sync pass. Reachable
  via public API, **but only on the first/single to-blob** (non-idempotent).
- **styles.xml / cellXfs / fonts / numFmts** — DELEGATED to DOM verbatim (the
  string path only rewrites `xl/worksheets/sheetN.xml`; every other part is the
  byte-for-byte `to-blob` baseline). So styling correctness rides on the DOM
  having already produced styles.xml + resolved the indices.

Not reachable / not attempted via public API:
- A resolved style-id from the cell model WITHOUT first running the DOM sync
  (i.e. there is no standalone "resolve styles" public entry point); and the id
  is corrupted by a second to-blob. So a purely-public standalone writer is
  viable ONLY in the to-blob-first shape used here (DOM does styles+resolution,
  string path does sheetData). It cannot independently resolve styles.
- Per-built-workbook extent: `Cells.max-row` returns -1 for a built (non-loaded)
  workbook and there is no public max-col (Task-5 finding, still stands) — hence
  the extent hints.

Implication for the in-place seam (Task 8): the seam must run **inside / right
after** the existing style-resolution sync (where ids ARE assigned and BEFORE
the state is reset), reading the worksheet's own `@!rows` and each cell's
resolved style-id directly. That is strictly cleaner than the standalone shape,
which is forced to (a) run the full DOM pass anyway for styles.xml + id
resolution and (b) tiptoe around to-blob's non-idempotency. Net: full
value+style fidelity IS achievable; the only open question Phase 2 answers is
whether replacing just sheetData is actually faster than the DOM, and whether
the in-place seam removes the redundant double work.

---

## ⏯️ RESUME POINTER (session clear, 2026-06-01)

**Where we are:** Phase 1 of the Spreadsheet::XLSX fast-write spike is COMPLETE
(Tasks 1–5 done, both Task 5 code-review fixes applied). HEAD = `46d10f8f` on branch
`feature/model-run-perf`.

**To resume in a fresh session, say:**
> Continue the Spreadsheet::XLSX fast-write spike. Plan:
> `docs/superpowers/plans/2026-06-01-spreadsheet-xlsx-fast-write-spike.md`.
> Tasks 1–5 done (HEAD 46d10f8f); next is Task 6. Execute remaining tasks 6–10
> via superpowers:subagent-driven-development (fresh implementer per task +
> spec-review then code-quality-review, proportionate to spike code). Read this
> FINDINGS-spike.md first.

**Tasks remaining (from the plan):**
- Task 6 — Style parity in the oracle (bold + number-format) + write Phase 1
  conclusions. NOTE: depends on the key finding below — style-id is NOT publicly
  reachable from the in-memory cell model pre-serialize, so the standalone
  serializer currently omits `s=`. Task 6 must either obtain the id where it IS
  reachable (after sync/load) or document the limitation; this directly shapes
  where the Task 8 in-place seam must live.
- Task 7 — Benchmark standalone vs DOM. USE THE EXTENT HINTS
  (`string-serialize($wb, :max-row(...), :max-col(...))`) so the benchmark does NOT
  measure the 1024×64 `:exists` grid probe (the no-hint default still probes). Build
  realistic sheet sizes; reuse micro7 methodology (median of runs, µs/cell, vs-DOM).
- Task 8 — Copy `_src` → `test/excel/spike/_lib/`, add `to-blob(:fast)` seam routing to
  the string serializer; extract original DOM body to `!to-blob-dom` + public `dom-blob`
  shim to avoid recursion (string-serialize calls `$wb.dom-blob`, not `to-blob`).
- Task 9 — Clone upstream `raku-community-modules/Spreadsheet-XLSX` (tag 0.3.5) tests;
  run the WRITE subset through `:fast` (env-forced via `AGRAMMON_XLSX_FORCE_FAST` in the
  `_lib` to-blob, no shim — see plan Task 9 Step 4 NOTE); record per-feature pass/fail.
- Task 10 — Write `test/excel/spike/SPIKE.md`: correctness table, perf table, wiring
  verdict, productization recommendation (in-place PR vs standalone module vs both).

**Key findings so far (full detail above in this file):**
1. Libarchive read = `Libarchive::Simple` `archive-read` → `.pathname`/`.is-file`/`.data`
   (decompressed Blob). Write = `archive-write(Buf,:format<zip>).write(path,blob).close`.
2. The round-trip comparator IS a trustworthy oracle: type-aware (catches number-vs-text),
   and the library loader PRESERVES cell type across save→reload, so it can detect a
   serializer that mis-encodes numbers as inline strings.
3. Serializer strategy = DOM `.to-blob` as byte baseline, replace ONLY
   `xl/worksheets/sheetN.xml` with string-built sheetData; all other parts byte-identical.
   Verified: worksheet parts DIFF, all other parts SAME.
4. CONSTRAINTS for productization: (a) resolved style-id is a private attr with no public
   accessor pre-serialize; (b) `Cells.max-row` is unreliable for a BUILT (non-loaded)
   workbook (returns -1) and there's no public max-col — a real in-place writer must walk
   the worksheet's private `@!rows`. Both are why an in-place seam (Task 8) may be cleaner
   than a standalone-on-public-API writer.

**Spike commits (all on feature/model-run-perf):** b0fe3f6b, 6dbd2a40, 39bc8ebf, 5d2e09c6,
6aec518e, 51e3ff69, 46d10f8f. All spike work is under `test/excel/spike/` (scratch); no
library or production code touched. Pre-existing uncommitted change `Applrate.nhd` is
unrelated — leave it.

## 2026-06-01 — Task 7: standalone string-serialize vs DOM benchmark
Benchmark: `test/excel/spike/bench.raku`. Method = micro7-style median of 3 per size,
8 columns/row (alternating Number/Text), sizes 200/800/2000 rows. Run:
`PERL5LIB=Inline/perl5 raku -Itest/excel/_src -Itest/excel/spike -Itest/excel/spike/lib test/excel/spike/bench.raku`

Result table (seconds, median of 3):

```
# rows | DOM to-blob (s) | string-serialize (s) | speedup
  200 |          4.521 |              4.686 |    1.0x
  800 |         18.347 |             19.506 |    0.9x
 2000 |         46.294 |             49.227 |    0.9x
# DONE
```

EXTENT-HINTS NOTE: `string-serialize` is called WITH the extent hints matching
big-wb's geometry — `:max-row($rows-1), :max-col(7)` (8 cols -> max-col 7). This is
MANDATORY: without hints, sheet-xml probes a fixed 1024x64 grid (65,536 `:exists`
lookups/sheet) — that would measure the phantom-grid probe, not the serializer, AND
would SILENTLY DROP every cell at row >= 1024 (the 2000-row case exceeds that).
Sanity-checked: the 2000-row hinted serialize round-trips to a 74,308-byte blob whose
reloaded `max-row = 1999` (all 2000 rows present) — hint is effective. (No-hint path
would have truncated at row 1023.)

"ONE INTERNAL DOM PASS" CAVEAT (decisive): `string-serialize` calls `$wb.to-blob`
ONCE internally for the byte baseline of every non-sheet part, THEN rebuilds sheetData
as strings, THEN re-zips. So this measures DOM-pass + string-rebuild + re-zip — it can
only ever be SLOWER than a bare DOM `.to-blob`, and indeed it is (~0.9-1.0x, i.e. 3-6%
slower). This is the REALISTIC standalone opt-in number, NOT the bare sheet-only floor.

ORDERING NOTE (transparency): within each iteration the benchmark always times the DOM
`.to-blob` path FIRST and the string-serialize path SECOND (fixed ordering, not
interleaved/randomized) — a minor uncontrolled variable (slight JIT/GC warmup favoring
the second-timed path) that does NOT reverse the negative "no speedup" verdict; recorded
for completeness.

VERDICT (honest negative): the STANDALONE serializer offers NO speedup — it strictly
adds work on top of the DOM pass it cannot avoid. Any real win must come from an
IN-PLACE seam (Task 8) that REPLACES the DOM sheetData build instead of duplicating it
(skip the DOM `<sheetData>` construction entirely, keep only the cheap scaffold parts).
The Task-7 numbers therefore set the conservative ceiling: standalone = break-even at
best; the in-place path is the only one that can beat DOM. The absolute per-call times
(seconds, not ms) also confirm the DOM sheetData build is the dominant cost worth
targeting in Task 8.

---

## Task 8 — `to-blob(:fast)` seam in a local library copy

**Goal:** mount the standalone string serializer behind a `:fast` flag on
`Spreadsheet::XLSX.to-blob`, in an EDITABLE copy of the library (`_lib`), without
breaking the Phase 1 round-trip test (which runs against the UNMODIFIED `_src`).

### How invasive was the library edit?
Small and localized to a single method. In `_lib/Spreadsheet/XLSX.rakumod`:

1. **Signature change:** `method to-blob(--> Blob)` → `method to-blob(Bool :$fast --> Blob)`.
   (Note: the original already accepted extra named args via the implicit `*%_`,
   so a `:fast` call against the *unmodified* method silently no-ops — meaning a
   naive seam test passes trivially against the DOM path. The real seam below is
   what makes `:fast` actually route to the string serializer.)
2. **Private extraction:** the original DOM body (sync-to-archive + archive-write
   loop) moved VERBATIM into `method !to-blob-dom(--> Blob)`. Byte-identical
   logic; no behavioural change to the DOM path.
3. **Public shim:** `method dom-blob(--> Blob) { self!to-blob-dom }` — lets the
   string serializer fetch the DOM baseline WITHOUT re-entering the fast path.
4. **Dispatch:** `to-blob(:fast)` does a lazy `require` of the serializer and
   delegates; `to-blob` (no flag) calls `!to-blob-dom`.

Verdict: **low-friction**. Three additions (one renamed/extracted method, one
one-line shim, a 4-line dispatch guard) plus a signature widening. No other
library code touched. A real upstream patch would be of comparable size.

### Recursion avoidance
`string-serialize` needs the DOM bytes as its baseline (it only replaces
`sheetData`). If it called `$wb.to-blob` under the `:fast` seam it would re-enter
the fast path → infinite recursion. Fix: it requests the baseline through the new
`dom-blob` shim, which goes straight to `!to-blob-dom` (the DOM path), never back
through the `:fast` branch.

### Keeping BOTH phases green (capability guard)
`StringSerializer.rakumod` is SHARED: Phase 1 runs it against `_src` (no
`dom-blob`), Phase 2 against `_lib` (has `dom-blob`). A hard `$wb.dom-blob` call
would crash Phase 1 with "no such method". The serializer therefore uses a
capability-guarded baseline:

```raku
my $baseline = $wb.^can('dom-blob') ?? $wb.dom-blob !! $wb.to-blob;
```

- Under `_lib` (Phase 2): `dom-blob` exists → call it → DOM path, no recursion.
- Under `_src` (Phase 1): no `dom-blob` → fall back to `to-blob`, whose ONLY path
  is the DOM path → also no recursion.

`^can('dom-blob')` returns a (possibly empty) list of `Method`s; empty is falsy,
non-empty truthy, so it reads cleanly as a boolean. Verified, not assumed.

### Import mechanism: lazy `require`, not top-of-file `use`
Used `require Spreadsheet::XLSX::StringSerializer <&string-serialize>;` INSIDE
the `:fast` branch. A top-of-file `use` would create a load CYCLE
(`Spreadsheet::XLSX` → StringSerializer → `compare` → `Spreadsheet::XLSX`). The
lazy `require` defers the import to call time, breaking the cycle. It worked
cleanly on the first try (Rakudo current): `&string-serialize` resolves to the
copy on the `-I` path (`test/excel/spike/lib`) with the expected signature
`(Spreadsheet::XLSX $wb, Int :$max-row, Int :$max-col --> Blob)`. No adjustment
needed.

### Verification
- `t/02-fast-seam.rakutest` (Phase 2, `-Itest/excel/spike/_lib`): **2/2 pass**,
  0 semantic diffs vs DOM.
- `t/01-roundtrip.rakutest` (Phase 1, `-Itest/excel/_src`): **5/5 still pass**.
- Proof the `:fast` path REALLY routes through the string serializer (not the
  swallowed-`*%_` no-op): the fast blob is NOT byte-identical to the DOM blob
  (2943 vs 2998 bytes) and its `sheet1.xml` carries `xml:space="preserve"` (a
  string-serializer-only artifact; the DOM path emits no such attribute), while
  `compare-workbooks` still reports 0 diffs. So: real delegation, byte-different,
  semantically identical, no recursion.

## 2026-06-01 — Task 9: upstream WRITE tests through the `:fast` path

### Upstream source
Cloned the matching suite into `test/excel/spike/upstream-checkout/`
(git-ignored; nested clone, NOT committed):

    git clone --depth 1 --branch 0.3.5 \
      https://github.com/raku-community-modules/Spreadsheet-XLSX upstream-checkout

- Tag: **0.3.5** (clean — META6.json `"version": "0.3.5"`).
- Commit: **0a1d559b3ee2bd844fdcc5b58dfd26c58e21facd**.
- No version drift: the suite matches the `_src`/`_lib` we extracted from 0.3.5.

### Write subset identified
`grep -rl "to-blob\|create-worksheet\|\.save" upstream-checkout/t/`:

- `new-basic.rakutest`     — create-worksheet, Text+Number cells, **column widths (`<cols>`)**, full `to-blob` → `load` round-trip, core-properties.
- `set-convenience.rakutest` — `.set` convenience (bold/font/number-format styles), round-trip of styled Text+Number cells.
- `styles.rakutest`        — loads `test-data/stylish.xlsx` (rich styles + **rich-text / shared-string** cells), then `to-blob` → `load` and re-asserts the full style + cell model.
- `escaping.rakutest`      — Text cells with `&` and `<`, round-trip.

OUT OF SCOPE (read-only, never call `to-blob`/create/save): `0-load-test`,
`1-README-examples`, `read-basic`. Not run against `:fast`.

### Step 3 — BASELINE (normal DOM path, `-Itest/excel/spike/_lib`)
All four write tests **PASS** unmodified — confirms the copied `_lib` is sound
before touching `:fast`. No pre-existing baseline failures.
(styles resolves its fixture via `$*PROGRAM.parent.add('test-data/stylish.xlsx')`,
so no `-I` / CWD adjustment was needed; the only delta vs the fast run is the
env var.)

    PERL5LIB=Inline/perl5 raku -Itest/excel/spike/_lib <test-file>   # all 4: exit 0

### Step 4 — env-var fast trigger
`_lib/Spreadsheet/XLSX.rakumod` `to-blob` now honors
`AGRAMMON_XLSX_FORCE_FAST` as a FALLBACK; explicit `:fast` / `:!fast` still wins:

    my $use-fast = $fast // ?%*ENV<AGRAMMON_XLSX_FORCE_FAST>;

Verified the `//` precedence empirically: unset `:fast` is the `Bool` type
object (undefined) so it falls through to the env check; `:fast`/`:!fast`
override. Re-ran the spike's own `t/02-fast-seam.rakutest` after the edit:
**still 3/3** (incl. "0 diffs vs DOM" and the `xml:space` delegation proof).

Runner: `test/excel/spike/run-upstream-tests.sh` (chmod +x) — same `-I` set as
the baseline, only adds `AGRAMMON_XLSX_FORCE_FAST=1`.

### Step 5 — RESULTS through `:fast`

| upstream test       | feature(s) exercised                                  | baseline | fast | failure class |
|---------------------|-------------------------------------------------------|----------|------|---------------|
| escaping            | Text cells w/ `&` `<` (xml-escape), round-trip        | PASS     | **PASS** | — |
| set-convenience     | `.set` styles (bold/font/number-format), Text+Number round-trip | PASS | **PASS** | — |
| new-basic           | Text+Number round-trip PASS, then **column widths** round-trip | PASS | **FAIL** (got 59/68 ok, then dies) | GENUINE GAP |
| styles              | round-trip of **rich-text / shared-string** cells     | PASS     | **FAIL** (dies in deserialization subtest) | GENUINE GAP |

**Headline: 2 of 4 upstream write tests pass through `:fast`.**

Both failures are GENUINE correctness gaps (not pre-existing `_lib` issues, not
cosmetic exact-XML mismatches). Each is a KNOWN limitation of the string path:

1. **new-basic — column widths dropped.** The fast serializer rebuilds only
   `<sheetData>`; it does not re-emit `<cols>` (column `custom-width`/`width`).
   On reload `worksheets[0].columns[0]` is an undefined `Any`, so the test dies:
   `No such method 'custom-width' for invocant of type 'Any'` (new-basic.rakutest:176).
   Everything BEFORE the column assertions passed under fast, including the
   Text-cell and Number-cell value round-trips (tests 56–59) — so the cell
   payload is correct; the gap is purely the missing `<cols>` block.

2. **styles — rich-text / shared-string cells produce unreadable XML.** The
   stylish.xlsx fixture has a shared-string rich-text cell (A7 = 5 styled runs)
   and other shared-string cells. The fast path emits EVERY non-Number cell as
   an `inlineStr` `<is><t xml:space="preserve">…</t></is>` built from
   `$cell.value`. For shared-string / empty-value cells this yields a `<t>`
   the loader rejects on reload:

       Simple property element 't' doesn't have a value
         in sub bad-property (XMLHelpers.rakumod:108)
         in sub cell-from-xml (Cell.rakumod:190)
         ... in styles.rakutest:162

   i.e. the fast sheet round-trips its cells back through the loader and the
   loader cannot parse the inlineStr `<t>` the fast path wrote for these cells.
   This is WRONG output (data the library can't read back), not merely
   different-but-equivalent.

### Root cause (systemic, not 2 unrelated bugs)
Both failures trace to the SAME design choice: the fast path rebuilds ONLY
`<sheetData>` for the cell kinds it understands (Number → `<v>`, everything
else → `inlineStr`) and reproduces nothing else of the worksheet. So:
- structural worksheet features outside `<sheetData>` are lost → `<cols>`
  (new-basic), and by the same token merged cells / spans / formulas would be
  too;
- cell kinds beyond Number/plain-Text are coerced to a single flattened
  `inlineStr`, which (a) loses the rich-text run structure / shared-string
  identity and (b) for empty/structured values emits a `<t>` the loader can't
  reload (styles).

The two tests that PASS (escaping, set-convenience) only ever write plain
Text + Number cells with simple styles and no `<cols>` — exactly the subset the
fast path supports — which is why they round-trip cleanly.

### Bearing on the recommendation
For the Agrammon exporter (its real workload is plain Number/Text cells with
styles, no rich-text, no per-column width round-trip dependence) the fast path
is adequate — and the upstream tests that match that profile pass. But as a
*drop-in* `Spreadsheet::XLSX` replacement it is NOT complete: `<cols>` and
rich-text/shared-string round-trip are genuine gaps that must be closed (or the
fast path gated to "Number/Text + styles only" workbooks) before it could pass
the full upstream write suite.

