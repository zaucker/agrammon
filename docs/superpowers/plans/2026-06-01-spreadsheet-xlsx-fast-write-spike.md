# Spreadsheet::XLSX fast-write spike — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Determine, with evidence, whether `Spreadsheet::XLSX` can gain an opt-in fast string-based write path covering its full current write capability, mounted behind its own API — or whether a standalone writer is the better contribution.

**Architecture:** Approach C (hybrid). Phase 1 builds a standalone string serializer that consumes a `Spreadsheet::XLSX` workbook's public model and emits the `.xlsx` zip, validated against the existing DOM `to-blob` via a round-trip oracle. Phase 2 mounts that same serializer behind a `to-blob(:fast)` seam in a local copy of the library and runs the library's own test suite through it. Output is a `SPIKE.md` report that resolves the in-place-vs-standalone decision.

**Tech Stack:** Raku (Rakudo 2026.04), `Spreadsheet::XLSX` v0.3.5 source (extracted in `test/excel/_src/`), LibXML (oracle/compare only), Libarchive (zip), Raku `Test`.

**Spec:** `docs/superpowers/specs/2026-06-01-spreadsheet-xlsx-fast-write-spike-design.md`

**Conventions for every task below:**
- Always run Raku with `PERL5LIB=Inline/perl5` exported and from repo root `/home/zaucker/checkouts/agrammon/agrammon6`.
- Spike workspace is `test/excel/spike/`. It is scratch (the whole `test/excel/` tree is untracked and not in `make dist`); commits here are for spike history only.
- The standalone serializer must use ONLY public accessors of `Spreadsheet::XLSX` (no `!private` calls). If a needed value is only reachable privately, that is a *finding* — record it in `FINDINGS-spike.md`, do not reach into privates.
- Reference serializer logic already proven: `lib/Agrammon/OutputFormatter/XLSXWriter.rakumod` (string cell XML, `xml-escape`, `col-name`, Libarchive zip). Reuse its patterns; do not import it (it has its own model).

---

## File structure

- `test/excel/spike/lib/Spreadsheet/XLSX/StringSerializer.rakumod` — Phase 1 standalone serializer. Input: a `Spreadsheet::XLSX` workbook. Output: a `Blob`. Walks worksheets→rows→cells emitting `sheetData` as strings; delegates the small one-shot parts to the workbook's existing DOM `to-blob` output (extracted from the oracle zip). One responsibility: model → zip via strings.
- `test/excel/spike/fixture.rakumod` — builds ONE workbook through the public write API exercising every writable feature. Single source of truth for both serialize paths. `sub build-fixture(--> Spreadsheet::XLSX) is export`.
- `test/excel/spike/compare.rakumod` — the round-trip oracle. `sub unzip-parts(Blob --> Hash) is export` and `sub compare-workbooks(Blob $oracle, Blob $spike --> List) is export` returning structured discrepancies.
- `test/excel/spike/t/01-roundtrip.rakutest` — Phase 1 gate: fixture → both paths → oracle compares clean (or every discrepancy asserted+documented).
- `test/excel/spike/bench.raku` — perf: standalone vs DOM (and, after Phase 2, `:fast`), micro7 methodology.
- `test/excel/spike/_lib/` — Phase 2: a COPY of `test/excel/_src/Spreadsheet/` with the `to-blob(:fast)` seam added.
- `test/excel/spike/t/02-fast-seam.rakutest` — Phase 2 gate driver (runs library's own suite through `:fast`).
- `test/excel/spike/SPIKE.md` — the report (final deliverable).
- `test/excel/spike/FINDINGS-spike.md` — running log of findings/blockers as they surface.

---

## Task 1: Spike workspace skeleton

**Files:**
- Create: `test/excel/spike/FINDINGS-spike.md`
- Create: `test/excel/spike/.gitkeep-note.md` (note that this tree is scratch)

- [ ] **Step 1: Create the workspace and a findings log**

```bash
cd /home/zaucker/checkouts/agrammon/agrammon6
mkdir -p test/excel/spike/lib/Spreadsheet/XLSX test/excel/spike/t
cat > test/excel/spike/FINDINGS-spike.md <<'EOF'
# Spike findings log (running)

Append-only notes as the spike progresses. Each entry: date, phase, what was tried,
what was learned. Feeds SPIKE.md at the end.
EOF
cat > test/excel/spike/.gitkeep-note.md <<'EOF'
This directory is spike scratch under test/excel/ (untracked, not in `make dist`).
Spec: docs/superpowers/specs/2026-06-01-spreadsheet-xlsx-fast-write-spike-design.md
EOF
```

- [ ] **Step 2: Verify the library source substrate is present**

Run:
```bash
ls test/excel/_src/Spreadsheet/XLSX.rakumod && \
ls test/excel/_src/Spreadsheet/XLSX/Worksheet.rakumod
```
Expected: both paths listed (no "No such file"). If missing, STOP and record in FINDINGS-spike.md — the rest depends on it.

- [ ] **Step 3: Verify the library loads from the extracted source**

Run:
```bash
PERL5LIB=Inline/perl5 raku -Itest/excel/_src -e 'use Spreadsheet::XLSX; say "loads OK"'
```
Expected: `loads OK`. If it fails, record the error in FINDINGS-spike.md (the extracted source may need its META/deps) and STOP for a human.

- [ ] **Step 4: Commit**

```bash
git add -f test/excel/spike/FINDINGS-spike.md test/excel/spike/.gitkeep-note.md
git commit -m "spike(xlsx): workspace skeleton + substrate check"
```

Note: `git add -f` because `test/excel/` may be gitignored implicitly by being scratch; force-add only these two small text files so the spike has history. If the user prefers zero spike commits, skip all commit steps — they are optional history, not deliverables.

---

## Task 2: Fixture — one workbook exercising the write API

**Files:**
- Create: `test/excel/spike/fixture.rakumod`
- Test: `test/excel/spike/t/00-fixture.rakutest`

- [ ] **Step 1: Write the failing test**

```raku
# test/excel/spike/t/00-fixture.rakutest
use lib $*PROGRAM.parent.parent.add('_src').Str;
use lib $*PROGRAM.parent.parent.add('spike').Str;
use Test;
use Spreadsheet::XLSX;
use fixture;

plan 4;

my $wb = build-fixture();
isa-ok $wb, Spreadsheet::XLSX, 'fixture returns a workbook';
is $wb.worksheets.elems, 2, 'fixture has 2 worksheets';

my $blob = $wb.to-blob;
isa-ok $blob, Blob, 'fixture workbook serializes via DOM to a Blob';
ok $blob.bytes > 0, 'DOM blob is non-empty';
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
PERL5LIB=Inline/perl5 raku -Itest/excel/_src -Itest/excel/spike test/excel/spike/t/00-fixture.rakutest
```
Expected: FAIL — `Could not find fixture` (module not written yet).

- [ ] **Step 3: Write the fixture**

```raku
# test/excel/spike/fixture.rakumod
use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Cell;

#| Build ONE workbook through the PUBLIC write API, exercising every writable
#| feature we can reach: text + number cells, bold font, number-format, and a
#| second sheet. (Extend as the spike discovers more reachable features; each
#| addition is also added to the oracle comparison in compare.rakumod.)
sub build-fixture(--> Spreadsheet::XLSX) is export {
    my $wb = Spreadsheet::XLSX.new;

    my $a = $wb.create-worksheet('Data');
    # header row: text + bold
    $a.cells[0;0] = Spreadsheet::XLSX::Cell::Text.new(value => 'Name');
    $a.cells[0;0].style.bold = True;
    $a.cells[0;1] = Spreadsheet::XLSX::Cell::Text.new(value => 'Amount');
    $a.cells[0;1].style.bold = True;
    # data rows: text + numbers, one with a number-format, one needing XML escaping
    $a.cells[1;0] = Spreadsheet::XLSX::Cell::Text.new(value => 'Eggs & Ham <b>');
    $a.cells[1;1] = Spreadsheet::XLSX::Cell::Number.new(value => 6);
    $a.cells[2;0] = Spreadsheet::XLSX::Cell::Text.new(value => 'Flour');
    $a.cells[2;1] = Spreadsheet::XLSX::Cell::Number.new(value => 1.5);
    $a.cells[2;1].style.number-format = '#,##0.00';

    my $b = $wb.create-worksheet('Notes');
    $b.cells[0;0] = Spreadsheet::XLSX::Cell::Text.new(value => 'umlauts: äöü ß');

    return $wb;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
PERL5LIB=Inline/perl5 raku -Itest/excel/_src -Itest/excel/spike test/excel/spike/t/00-fixture.rakutest
```
Expected: PASS (4 tests). If `.style.bold`/`.style.number-format` or `.cells[r;c] =` raise, that is a Phase-1 finding about the write API surface — record exact error in FINDINGS-spike.md, then reduce the fixture to what the API actually supports and note the gap.

- [ ] **Step 5: Commit**

```bash
git add -f test/excel/spike/fixture.rakumod test/excel/spike/t/00-fixture.rakutest
git commit -m "spike(xlsx): fixture workbook via public write API"
```

---

## Task 3: Unzip helper for the oracle

**Files:**
- Create: `test/excel/spike/compare.rakumod`
- Test: `test/excel/spike/t/01a-unzip.rakutest`

- [ ] **Step 1: Write the failing test**

```raku
# test/excel/spike/t/01a-unzip.rakutest
use lib $*PROGRAM.parent.parent.add('_src').Str;
use lib $*PROGRAM.parent.parent.add('spike').Str;
use Test;
use Spreadsheet::XLSX;
use fixture;
use compare;

plan 3;

my $blob = build-fixture().to-blob;
my %parts = unzip-parts($blob);
ok %parts{'[Content_Types].xml'}:exists, 'zip contains [Content_Types].xml';
ok %parts.keys.grep(*.starts-with('xl/worksheets/')), 'zip contains worksheet parts';
ok %parts{'xl/workbook.xml'}:exists, 'zip contains workbook.xml';
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
PERL5LIB=Inline/perl5 raku -Itest/excel/_src -Itest/excel/spike test/excel/spike/t/01a-unzip.rakutest
```
Expected: FAIL — `Could not find compare`.

- [ ] **Step 3: Implement unzip-parts**

```raku
# test/excel/spike/compare.rakumod
use Archive::Libarchive;
use Archive::Libarchive::Constants;

#| Unzip an .xlsx Blob into a map of part-path => Blob.
sub unzip-parts(Blob $zip --> Hash) is export {
    my %out;
    my $a = Archive::Libarchive.new(operation => LibarchiveRead, file => $zip);
    my Archive::Libarchive::Entry $e .= new;
    while $a.next-header($e) {
        my $name = $e.pathname;
        my $buf = Buf.new;
        $a.data-skip; # placeholder; replaced below if API differs
        %out{$name} = $buf;
    }
    $a.close;
    return %out;
}
```

NOTE: the exact Libarchive read API may differ from the guess above. Before relying on it, verify the read API in one probe (Step 3b). The reference writer (`XLSXWriter.rakumod`) only uses the WRITE side, so the read side must be confirmed here.

- [ ] **Step 3b: Probe the Libarchive read API and correct the implementation**

Run:
```bash
PERL5LIB=Inline/perl5 raku -e 'use Archive::Libarchive; .say for Archive::Libarchive.^methods.map(*.name).sort.unique'
```
Expected: a list of methods. Identify the read-extract call (e.g. `read`, `extract`, `data`, `read-file-content`). Rewrite `unzip-parts` to use the confirmed call so each `%out{$name}` holds the real decompressed bytes. Record the confirmed API in FINDINGS-spike.md.

If `Archive::Libarchive` has no usable in-memory read API, fall back to shelling out:
```raku
sub unzip-parts(Blob $zip --> Hash) is export {
    use File::Temp;
    my ($p,$fh) = tempfile(:suffix<.xlsx>); $fh.write($zip); $fh.close;
    my $dir = tempdir;
    run 'unzip', '-o', '-q', $p, '-d', $dir;
    my %out;
    for $dir.IO.&{ .dir(:recursive) // () }».&{ $_ } -> $f {
        next unless $f.f;
        %out{$f.relative($dir)} = $f.slurp(:bin);
    }
    return %out;
}
```
Use whichever of the two actually yields correct bytes; keep only that one.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
PERL5LIB=Inline/perl5 raku -Itest/excel/_src -Itest/excel/spike test/excel/spike/t/01a-unzip.rakutest
```
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add -f test/excel/spike/compare.rakumod test/excel/spike/t/01a-unzip.rakutest
git commit -m "spike(xlsx): unzip-parts oracle helper"
```

---

## Task 4: Round-trip comparator (model in → model out)

**Files:**
- Modify: `test/excel/spike/compare.rakumod` (add `compare-workbooks`)
- Test: `test/excel/spike/t/01b-compare-self.rakutest`

- [ ] **Step 1: Write the failing test (oracle compared against itself must be clean)**

```raku
# test/excel/spike/t/01b-compare-self.rakutest
use lib $*PROGRAM.parent.parent.add('_src').Str;
use lib $*PROGRAM.parent.parent.add('spike').Str;
use Test;
use Spreadsheet::XLSX;
use fixture;
use compare;

plan 1;

# Serialize the same workbook twice via the DOM path; the comparator must find
# them equivalent (sanity-checks the comparator itself before we trust it on the
# spike serializer).
my $a = build-fixture().to-blob;
my $b = build-fixture().to-blob;
my @diffs = compare-workbooks($a, $b);
is @diffs.elems, 0, "comparator: DOM-vs-DOM has no discrepancies (got: {@diffs.gist})";
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
PERL5LIB=Inline/perl5 raku -Itest/excel/_src -Itest/excel/spike test/excel/spike/t/01b-compare-self.rakutest
```
Expected: FAIL — `compare-workbooks` not defined.

- [ ] **Step 3: Implement compare-workbooks via the library's own loader**

```raku
# append to test/excel/spike/compare.rakumod
use Spreadsheet::XLSX;

#| Compare two .xlsx blobs SEMANTICALLY by re-loading each with the library's own
#| loader and diffing the resulting model: per sheet, per populated cell, compare
#| (value, type-ish) and the resolved style attributes we set in the fixture.
#| Returns a list of human-readable discrepancy strings ('' none == equivalent).
sub compare-workbooks(Blob $oracle, Blob $spike --> List) is export {
    my @diffs;
    my $o = Spreadsheet::XLSX.load($oracle);
    my $s = Spreadsheet::XLSX.load($spike);

    my @osheets = $o.worksheets;
    my @ssheets = $s.worksheets;
    if @osheets.elems != @ssheets.elems {
        @diffs.push: "sheet count: oracle {@osheets.elems} vs spike {@ssheets.elems}";
        return @diffs;
    }

    for ^@osheets.elems -> $si {
        my $oc = @osheets[$si].cells;
        my $sc = @ssheets[$si].cells;
        my $maxrow = ($oc.max-row // -1) max ($sc.max-row // -1);
        for 0..$maxrow -> $r {
            # scan a generous column window; fixture stays small
            for 0..15 -> $c {
                my $ov = ($oc[$r;$c]:exists) ?? $oc[$r;$c] !! Nil;
                my $sv = ($sc[$r;$c]:exists) ?? $sc[$r;$c] !! Nil;
                next if !$ov.defined && !$sv.defined;
                if $ov.defined != $sv.defined {
                    @diffs.push: "sheet$si [$r;$c]: presence oracle={$ov.defined} spike={$sv.defined}";
                    next;
                }
                if ($ov.value // '') ne ($sv.value // '') {
                    @diffs.push: "sheet$si [$r;$c]: value '{$ov.value}' vs '{$sv.value}'";
                }
            }
        }
    }
    return @diffs;
}
```

NOTE: cell accessor shape (`.value`, `:exists`, `.max-row`) is taken from
`Worksheet.rakumod` (`Cells` is `Positional`, has `max-row`, `EXISTS-POS`). If a method
name differs at runtime, fix to the real name and record it in FINDINGS-spike.md. Style
comparison (bold / number-format) is added in Task 6 once the spike serializer emits
styles; for now value+presence is the sanity bar.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
PERL5LIB=Inline/perl5 raku -Itest/excel/_src -Itest/excel/spike test/excel/spike/t/01b-compare-self.rakutest
```
Expected: PASS (1 test). If DOM-vs-DOM shows diffs, the comparator is wrong — fix it before trusting it on the serializer.

- [ ] **Step 5: Commit**

```bash
git add -f test/excel/spike/compare.rakumod test/excel/spike/t/01b-compare-self.rakutest
git commit -m "spike(xlsx): semantic round-trip comparator (DOM-vs-DOM clean)"
```

---

## Task 5: Standalone string serializer — sheetData as strings, small parts delegated

**Files:**
- Create: `test/excel/spike/lib/Spreadsheet/XLSX/StringSerializer.rakumod`
- Test: `test/excel/spike/t/01-roundtrip.rakutest`

- [ ] **Step 1: Write the failing test (the Phase 1 gate)**

```raku
# test/excel/spike/t/01-roundtrip.rakutest
use lib $*PROGRAM.parent.parent.add('_src').Str;
use lib $*PROGRAM.parent.parent.add('spike').Str;
use lib $*PROGRAM.parent.parent.add('spike/lib').Str;
use Test;
use Spreadsheet::XLSX;
use fixture;
use compare;
use Spreadsheet::XLSX::StringSerializer;

plan 3;

my $wb = build-fixture();
my $oracle = $wb.to-blob;                    # DOM path
my $spike  = string-serialize($wb);          # spike path, same in-memory workbook
isa-ok $spike, Blob, 'string serializer returns a Blob';
ok $spike.bytes > 0, 'spike blob non-empty';

my @diffs = compare-workbooks($oracle, $spike);
is @diffs.elems, 0, "round-trip: oracle vs spike equivalent (diffs: {@diffs.gist})";
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
PERL5LIB=Inline/perl5 raku -Itest/excel/_src -Itest/excel/spike -Itest/excel/spike/lib test/excel/spike/t/01-roundtrip.rakutest
```
Expected: FAIL — `Could not find Spreadsheet::XLSX::StringSerializer`.

- [ ] **Step 3: Implement the serializer (delegate small parts, rewrite sheetData)**

Strategy that reaches "full capability" cheaply and honestly: take the workbook's own
DOM `to-blob` output as the baseline zip, then **replace only the `xl/worksheets/sheetN.xml`
parts** with string-built equivalents read from the public cell model; keep every other
part (styles, content-types, rels, workbook.xml, shared strings) byte-for-byte from the
DOM output. This guarantees the non-hot parts are identical by construction, isolates the
spike to the hot path, and still produces a complete, valid workbook.

```raku
# test/excel/spike/lib/Spreadsheet/XLSX/StringSerializer.rakumod
use Spreadsheet::XLSX;
use compare;   # for unzip-parts
use Archive::Libarchive;
use Archive::Libarchive::Constants;

my sub xml-escape(Str() $s --> Str) {
    $s.subst('&','&amp;',:g).subst('<','&lt;',:g).subst('>','&gt;',:g)
}
my sub col-name(Int() $col is copy --> Str) {
    my $s = ''; $col++;
    while $col > 0 { my $r = ($col - 1) % 26; $s = chr(ord('A') + $r) ~ $s; $col = ($col - 1) div 26; }
    $s
}

#| Build one sheetData XML string from a worksheet's public cell model.
my sub sheet-xml($ws --> Str) {
    my @p;
    @p.push: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
    @p.push: '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">';
    @p.push: '<sheetData>';
    my $cells = $ws.cells;
    my $maxrow = $cells.max-row // -1;
    for 0..$maxrow -> $r {
        my @rowcells;
        for 0..15 -> $c {
            next unless $cells[$r;$c]:exists;
            my $cell = $cells[$r;$c];
            my $ref = col-name($c) ~ ($r + 1);
            # style index: reuse the cell's resolved style-id if exposed, else omit
            my $sid = ($cell.can('style-id') ?? $cell.style-id !! Nil);
            my $sa  = $sid ?? qq{ s="$sid"} !! '';
            if $cell ~~ Spreadsheet::XLSX::Cell::Number {
                @rowcells.push: qq{<c r="$ref"$sa><v>{$cell.value}</v></c>};
            }
            else {
                my $t = xml-escape($cell.value // '');
                @rowcells.push: qq{<c r="$ref"$sa t="inlineStr"><is><t xml:space="preserve">$t</t></is></c>};
            }
        }
        next unless @rowcells;
        @p.push: qq{<row r="{$r + 1}">} ~ @rowcells.join ~ '</row>';
    }
    @p.push: '</sheetData></worksheet>';
    @p.join
}

#| Serialize a workbook: DOM output as baseline, sheetData parts string-rebuilt.
sub string-serialize(Spreadsheet::XLSX $wb --> Blob) is export {
    my %parts = unzip-parts($wb.to-blob);    # baseline: everything from DOM

    # Replace each worksheet part with the string-built version, in sheet order.
    my @ws = $wb.worksheets;
    my @sheet-parts = %parts.keys.grep(*.match: /^ 'xl/worksheets/sheet' \d+ '.xml' $/).sort;
    for @ws.kv -> $i, $w {
        my $part = @sheet-parts[$i] // next;
        %parts{$part} = sheet-xml($w).encode('utf-8');
    }

    # Re-zip in a stable order.
    my $buf = Buf.new;
    my $a = Archive::Libarchive.new(operation => LibarchiveWrite, file => $buf, format => 'zip');
    for %parts.keys.sort -> $name {
        $a.write-header($name, size => %parts{$name}.bytes);  # confirm exact write API in Step 3b
        $a.write-data(%parts{$name});
    }
    $a.close;
    return $buf;
}
```

NOTE: the Libarchive WRITE calls above are modeled on the existing
`XLSXWriter.rakumod`. Open that file and copy its exact zip-writing calls
(`archive`, `write`, `close` shapes) rather than guessing — replace the
`write-header`/`write-data` lines with whatever `XLSXWriter` actually uses. Same for
`max-row` / `:exists` / `.style-id` accessor names: confirm against `Worksheet.rakumod`
and `Cell.rakumod`; if `style-id` is not publicly reachable, omit the `s=` attribute and
record it as a finding (styles then fall back to whatever the DOM baseline encoded — note
that the value round-trip still holds, style parity is assessed in Task 6).

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
PERL5LIB=Inline/perl5 raku -Itest/excel/_src -Itest/excel/spike -Itest/excel/spike/lib test/excel/spike/t/01-roundtrip.rakutest
```
Expected: PASS (3 tests). If value diffs appear, fix the serializer until oracle-clean. If a diff is a genuine impractical-parity case (e.g. inline-vs-shared string), record it in FINDINGS-spike.md and adjust the test to assert the documented discrepancy explicitly rather than zero.

- [ ] **Step 5: Commit**

```bash
git add -f test/excel/spike/lib/Spreadsheet/XLSX/StringSerializer.rakumod test/excel/spike/t/01-roundtrip.rakutest
git commit -m "spike(xlsx): standalone string serializer, value round-trip clean"
```

---

## Task 6: Extend oracle to style attributes; close Phase 1

**Files:**
- Modify: `test/excel/spike/compare.rakumod` (compare bold + number-format)
- Modify: `test/excel/spike/t/01-roundtrip.rakutest` (assert styles too)
- Modify: `test/excel/spike/FINDINGS-spike.md` (Phase 1 conclusions)

- [ ] **Step 1: Add a failing style-parity assertion**

Append to `test/excel/spike/t/01-roundtrip.rakutest`:
```raku
# style parity: the bold header cell and the number-formatted cell must survive
my $o2 = Spreadsheet::XLSX.load($oracle);
my $s2 = Spreadsheet::XLSX.load($spike);
my $ob = $o2.worksheets[0].cells[0;0].style.bold;
my $sb = $s2.worksheets[0].cells[0;0].style.bold;
is $sb, $ob, "bold style preserved on A1 (oracle=$ob spike=$sb)";
```
Bump `plan 3` → `plan 4`.

- [ ] **Step 2: Run to verify the new assertion's status**

Run:
```bash
PERL5LIB=Inline/perl5 raku -Itest/excel/_src -Itest/excel/spike -Itest/excel/spike/lib test/excel/spike/t/01-roundtrip.rakutest
```
Expected: either PASS (styles already round-trip because the `s=` index + delegated `styles.xml` line up) or FAIL (spike dropped the style index). Both are informative.

- [ ] **Step 3: Resolve based on outcome**

- If PASS: styles survive because the serializer kept the `s=` index and delegated `styles.xml` — record in FINDINGS-spike.md that full styling is reachable via the index-reuse approach.
- If FAIL: the public model doesn't expose the resolved `style-id` at serialize time. Record this as the key Phase-1 finding (it constrains the in-place design: the seam must run where style ids ARE resolved). Then make the spike serializer obtain the id from wherever it IS reachable (e.g. after `sync-to-archive` has assigned ids), update `string-serialize` accordingly, and re-run until the assertion passes or the limitation is proven.

- [ ] **Step 4: Verify the full Phase 1 gate passes**

Run:
```bash
PERL5LIB=Inline/perl5 raku -Itest/excel/_src -Itest/excel/spike -Itest/excel/spike/lib test/excel/spike/t/01-roundtrip.rakutest
```
Expected: PASS (4 tests), or PASS with explicitly-asserted documented discrepancies.

- [ ] **Step 5: Write the Phase 1 conclusion + commit**

Append a "Phase 1 result" section to FINDINGS-spike.md: which features round-trip via the string path, which are delegated to DOM, which (if any) are not reachable via public API, and what that implies for where the in-place seam must live.

```bash
git add -f test/excel/spike/compare.rakumod test/excel/spike/t/01-roundtrip.rakutest test/excel/spike/FINDINGS-spike.md
git commit -m "spike(xlsx): style parity in oracle; Phase 1 conclusions"
```

---

## Task 7: Benchmark standalone vs DOM

**Files:**
- Create: `test/excel/spike/bench.raku`

- [ ] **Step 1: Write the benchmark (no test; it prints a table)**

```raku
# test/excel/spike/bench.raku
use lib $*PROGRAM.parent.parent.add('_src').Str;
use lib $*PROGRAM.parent.add('').Str;
use lib $*PROGRAM.parent.add('lib').Str;
use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Cell;
use Spreadsheet::XLSX::StringSerializer;

sub big-wb(Int $rows --> Spreadsheet::XLSX) {
    my $wb = Spreadsheet::XLSX.new;
    my $s = $wb.create-worksheet('S');
    for ^$rows -> $r {
        for ^8 -> $c {
            $s.cells[$r;$c] = $c %% 2
                ?? Spreadsheet::XLSX::Cell::Number.new(value => ($r * 8 + $c) * 1.5)
                !! Spreadsheet::XLSX::Cell::Text.new(value => "r{$r}c{$c}");
        }
    }
    $wb
}

sub med(@t) { @t.sort[@t.elems div 2] }

say "# rows | DOM to-blob (s) | string-serialize (s) | speedup";
for 200, 800, 2000 -> $rows {
    my @dom; my @str;
    for ^3 {
        my $wb = big-wb($rows);
        my $t0 = now; $wb.to-blob;            @dom.push: (now - $t0).Num;
        my $wb2 = big-wb($rows);
        my $t1 = now; string-serialize($wb2); @str.push: (now - $t1).Num;
    }
    printf "%5d | %14.3f | %18.3f | %6.1fx\n",
        $rows, med(@dom), med(@str), med(@dom) / med(@str);
}
say "# DONE";
```

- [ ] **Step 2: Run the benchmark**

Run:
```bash
PERL5LIB=Inline/perl5 raku -Itest/excel/_src -Itest/excel/spike -Itest/excel/spike/lib test/excel/spike/bench.raku
```
Expected: a 3-row table ending `# DONE`. Note: `string-serialize` includes one DOM `to-blob` internally (for the delegated parts), so this measures the *realistic* opt-in speedup, not the bare sheet-only floor. Record numbers in FINDINGS-spike.md and note this caveat.

- [ ] **Step 3: Commit**

```bash
git add -f test/excel/spike/bench.raku
git commit -m "spike(xlsx): standalone vs DOM benchmark"
```

---

## Task 8: Phase 2 — mount the serializer behind `to-blob(:fast)`

**Files:**
- Create: `test/excel/spike/_lib/Spreadsheet/…` (copy of `_src`)
- Modify: `test/excel/spike/_lib/Spreadsheet/XLSX.rakumod` (add `:fast` seam)
- Test: `test/excel/spike/t/02-fast-seam.rakutest`

- [ ] **Step 1: Copy the library source for editing**

```bash
cd /home/zaucker/checkouts/agrammon/agrammon6
cp -r test/excel/_src/Spreadsheet test/excel/spike/_lib/
ls test/excel/spike/_lib/Spreadsheet/XLSX.rakumod
```
Expected: the path lists.

- [ ] **Step 2: Write the failing seam test**

```raku
# test/excel/spike/t/02-fast-seam.rakutest
use lib $*PROGRAM.parent.parent.add('spike/_lib').Str;
use lib $*PROGRAM.parent.parent.add('spike').Str;
use lib $*PROGRAM.parent.parent.add('spike/lib').Str;
use Test;
use Spreadsheet::XLSX;
use fixture;
use compare;

plan 2;

my $wb = build-fixture();
my $slow = $wb.to-blob;             # DOM
my $fast = build-fixture().to-blob(:fast);   # seam under test (fresh wb; to-blob may mutate)
isa-ok $fast, Blob, 'to-blob(:fast) returns a Blob';
my @diffs = compare-workbooks($slow, $fast);
is @diffs.elems, 0, "to-blob(:fast) equivalent to DOM (diffs: {@diffs.gist})";
```

- [ ] **Step 3: Run to verify it fails**

Run:
```bash
PERL5LIB=Inline/perl5 raku -Itest/excel/spike/_lib -Itest/excel/spike -Itest/excel/spike/lib test/excel/spike/t/02-fast-seam.rakutest
```
Expected: FAIL — `to-blob` has no `:fast` named param (extra named arg, or it's ignored). 

- [ ] **Step 4: Add the seam to the copied `_lib` XLSX.rakumod**

In `test/excel/spike/_lib/Spreadsheet/XLSX.rakumod`, change the `to-blob` signature to accept `:$fast` and, when set, delegate to the string serializer instead of building the DOM zip. Locate the existing method (was at ~line 284):

```raku
    method to-blob(Bool :$fast --> Blob) {
        if $fast {
            # Spike seam: produce the workbook via the string serializer.
            # Imported lazily so the slow path has no new dependency.
            require Spreadsheet::XLSX::StringSerializer <&string-serialize>;
            return string-serialize(self);
        }
        # ---- original DOM path unchanged below ----
        self.sync-to-archive();
        my $buffer = Buf.new;
        given archive-write($buffer, format => 'zip') -> $archive {
            for $!archive.kv -> $path, $blob {
                $archive.write($path, $blob);
            }
            $archive.close;
        }
        return $buffer;
    }
```

NOTE: `string-serialize` currently calls `self.to-blob` internally for the delegated
parts — that recursion would re-enter the fast path. Fix by having the serializer call the
DOM path explicitly. Add a private `method !to-blob-dom(--> Blob)` containing the original
body, have `to-blob(:!fast)` call it, and make `StringSerializer` call `$wb!to-blob-dom`
via a tiny public shim `method dom-blob(--> Blob) { self!to-blob-dom }`. Update
`string-serialize` to call `$wb.dom-blob` instead of `$wb.to-blob`. Record this seam
detail (recursion avoidance) in FINDINGS-spike.md — it is exactly the kind of wiring
friction the spike is meant to surface.

- [ ] **Step 5: Run to verify it passes**

Run:
```bash
PERL5LIB=Inline/perl5 raku -Itest/excel/spike/_lib -Itest/excel/spike -Itest/excel/spike/lib test/excel/spike/t/02-fast-seam.rakutest
```
Expected: PASS (2 tests). Capture how invasive the change was (signature + private extraction + shim) for the report.

- [ ] **Step 6: Commit**

```bash
git add -f test/excel/spike/_lib test/excel/spike/t/02-fast-seam.rakutest
git commit -m "spike(xlsx): to-blob(:fast) seam in local lib copy"
```

---

## Task 9: Phase 2 gate — run the library's own test suite through `:fast`

**Files:**
- Create: `test/excel/spike/run-upstream-tests.sh`
- Modify: `test/excel/spike/FINDINGS-spike.md`

- [ ] **Step 1: Fetch the upstream test suite into the spike (read-only)**

The extracted `_src` has no `t/`. Get the suite matching v0.3.5:
```bash
cd /home/zaucker/checkouts/agrammon/agrammon6/test/excel/spike
git clone --depth 1 --branch 0.3.5 https://github.com/raku-community-modules/Spreadsheet-XLSX upstream-checkout 2>/dev/null \
  || git clone --depth 1 https://github.com/raku-community-modules/Spreadsheet-XLSX upstream-checkout
ls upstream-checkout/t/ | head
```
Expected: a list of `.rakutest`/`.t` files. If the tag doesn't exist, clone default branch and record the exact commit in FINDINGS-spike.md (note any version drift from 0.3.5).

- [ ] **Step 2: Identify which upstream tests exercise WRITE/`to-blob`**

Run:
```bash
grep -rl "to-blob\|create-worksheet\|\.save" test/excel/spike/upstream-checkout/t/ 2>/dev/null
```
Expected: the subset of write-exercising test files. Only these are meaningful for the `:fast` path. Record the list.

- [ ] **Step 3: Run that subset against the `_lib` copy, normal path (baseline)**

```bash
cd /home/zaucker/checkouts/agrammon/agrammon6
PERL5LIB=Inline/perl5 raku -Itest/excel/spike/_lib test/excel/spike/upstream-checkout/t/<write-test>.rakutest
```
(substitute each write-test identified). Expected: PASS — confirms the copied `_lib` is itself sound before we touch `:fast`. Record any pre-existing failures (they are not ours).

- [ ] **Step 4: Make a `:fast` variant runner and run the write subset through it**

```bash
cat > test/excel/spike/run-upstream-tests.sh <<'EOF'
#!/bin/bash
# Run upstream WRITE tests with to-blob transparently routed through :fast.
# We inject a wrapper lib that overrides to-blob to call to-blob(:fast).
set -e
cd "$(dirname "$0")/../../.."   # repo root
export PERL5LIB=Inline/perl5
for t in "$@"; do
  echo "=== $t (via :fast) ==="
  AGRAMMON_XLSX_FORCE_FAST=1 raku -Itest/excel/spike/_fastwrap -Itest/excel/spike/_lib -Itest/excel/spike -Itest/excel/spike/lib "$t"
done
EOF
chmod +x test/excel/spike/run-upstream-tests.sh
```

Create the override wrapper `test/excel/spike/_fastwrap/Spreadsheet/XLSX.rakumod` that
`use`s the real `_lib` class and wraps `to-blob` to force `:fast` when
`%*ENV<AGRAMMON_XLSX_FORCE_FAST>` is set:
```raku
# test/excel/spike/_fastwrap/Spreadsheet/XLSX.rakumod
# Thin shim: re-export the real class but force :fast on to-blob when env set.
use Spreadsheet::XLSX:auth<spike-lib>;   # if auth/alias not available, see NOTE
```

NOTE: Raku does not allow two modules with the same name on `-I` paths cleanly, so the
env-based override may not work via a same-named shim. If so, fall back to the simpler,
robust approach: make the `:fast` decision in `_lib`'s `to-blob` itself honor the env var —
change the seam to `my $fast = $fast // ?%*ENV<AGRAMMON_XLSX_FORCE_FAST>;` Then the
unmodified upstream tests (which call plain `to-blob`) run through the fast path whenever
the env var is set, with NO shim needed. Prefer this; delete the `_fastwrap` idea if used.
Record the chosen mechanism in FINDINGS-spike.md.

- [ ] **Step 5: Run the write subset through `:fast` and record results**

```bash
./test/excel/spike/run-upstream-tests.sh test/excel/spike/upstream-checkout/t/<write-test>.rakutest
```
Expected: ideally all PASS (the strongest "drop-in" evidence). For each failure, record in FINDINGS-spike.md: test name, what feature it exercises, whether the fast path produced wrong output or just different-but-equivalent output (re-check with the comparator). This per-feature pass/fail IS the Phase 2 correctness bar.

- [ ] **Step 6: Commit**

```bash
git add -f test/excel/spike/run-upstream-tests.sh test/excel/spike/_fastwrap test/excel/spike/FINDINGS-spike.md
git commit -m "spike(xlsx): run upstream write tests through :fast path"
```

---

## Task 10: Write SPIKE.md report and recommendation

**Files:**
- Create: `test/excel/spike/SPIKE.md`

- [ ] **Step 1: Assemble the report from the findings log**

Write `test/excel/spike/SPIKE.md` with exactly these sections (fill from
FINDINGS-spike.md + bench output + test results — no placeholders, real numbers):

1. **Per-feature correctness table** — columns: feature | string-path / delegated-to-DOM / not-reachable | oracle result | semantic discrepancy (if any).
2. **Perf table** — rows vs DOM `to-blob` vs `string-serialize` vs `to-blob(:fast)`, by size, with the "fast includes one DOM pass for delegated parts" caveat stated.
3. **Wiring verdict** — what the `:fast` seam required (signature change, private `!to-blob-dom` extraction, recursion-avoidance shim), how many upstream write tests passed through it, and a clean/messy judgement.
4. **Recommendation** — one of: pursue in-place upstream PR / publish standalone module / both — with the reasoning that resolves the deferred productization decision.

- [ ] **Step 2: Sanity-check the report answers the spike's 4 questions**

Re-read the spec's "Success criteria for the spike itself". Confirm SPIKE.md answers, with evidence: (a) full write capability reproducible? (b) mounts cleanly without read-path disturbance? (c) measured speed-up? (d) which productization path? Fill any gap.

- [ ] **Step 3: Commit**

```bash
git add -f test/excel/spike/SPIKE.md
git commit -m "spike(xlsx): SPIKE.md report + productization recommendation"
```

---

## Done criteria

The spike is complete when `test/excel/spike/SPIKE.md` answers all four spike questions
with evidence and states a clear recommendation. No production or library code has been
changed; all work is under `test/excel/spike/`. The recommendation feeds a SEPARATE,
later brainstorm/plan cycle for the actual contribution (upstream PR or standalone
module) — that productization is explicitly NOT part of this spike.
