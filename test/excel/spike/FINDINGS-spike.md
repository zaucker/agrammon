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
