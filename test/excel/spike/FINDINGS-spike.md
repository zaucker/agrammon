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
