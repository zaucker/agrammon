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
