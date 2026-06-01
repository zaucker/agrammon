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
