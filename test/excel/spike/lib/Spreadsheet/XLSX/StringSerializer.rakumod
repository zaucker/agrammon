use v6;
use Libarchive::Simple;
use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Cell;

# ---------------------------------------------------------------------------
# Standalone STRING-based XLSX serializer (spike, Task 5).
#
# Strategy: take the DOM `.to-blob` output as the byte-for-byte baseline for
# every package part, then REPLACE only the `xl/worksheets/sheetN.xml` parts
# with string-built equivalents derived from the public in-memory cell model
# ($wb.worksheets[*].cells). Re-zip with Libarchive, using the SAME write API
# as lib/Agrammon/OutputFormatter/XLSXWriter.rakumod (archive-write +
# $archive.write(path, bytes) + $archive.close).
#
# This isolates the spike to the hot path (sheetData) while guaranteeing the
# small parts ([Content_Types].xml, styles.xml, rels, workbook.xml) are
# identical by construction.
#
# Value+TYPE+STYLE parity: numbers are emitted as <v> number cells, text as
# t="inlineStr", and the resolved style index is emitted as s="..." read from
# the PUBLIC $cell.style.style-id accessor. That id is only populated AFTER the
# DOM sync pass that $wb.to-blob performs (Task 6 finding), which is why this
# serializer's to-blob-first strategy makes it reachable. See FINDINGS-spike.md.
# ---------------------------------------------------------------------------

unit module Spreadsheet::XLSX::StringSerializer;

# ---- XML helpers (adapted from XLSXWriter.rakumod) --------------------------

my sub xml-escape(Str() $s --> Str) {
    $s.subst('&', '&amp;', :g)
      .subst('<', '&lt;',  :g)
      .subst('>', '&gt;',  :g)
}

#| Convert a 0-based column index to its A1-style column letter (0 -> A, 26 -> AA).
my sub col-name(Int() $col is copy --> Str) {
    my $s = '';
    loop {
        $s = chr(ord('A') + $col % 26) ~ $s;
        $col = $col div 26 - 1;
        last if $col < 0;
    }
    $s
}

# Probe bounds. The in-memory Cells model does not expose a public max-col, and
# its `max-row` only reflects rows loaded from a backing XML document — for a
# freshly *built* (not loaded) workbook it returns -1 (see FINDINGS-spike.md:
# the public Cells model exposes no usable max-row/max-col for a built
# workbook). So, with NO extent hints, we probe a generous fixed grid via the
# public `:exists` API.
#
# CONSEQUENCES of the no-hint probe:
#   (a) it does 1024 x 64 = 65536 `:exists` lookups per sheet REGARDLESS of how
#       many cells exist, and
#   (b) any cell at row >= MAX-ROW-PROBE or col >= MAX-COL-PROBE is SILENTLY
#       DROPPED.
#
# To avoid both, `string-serialize` / `sheet-xml` accept OPTIONAL :$max-row /
# :$max-col hints. A caller that knows its populated extent (the Task-7
# benchmark, or a real in-place writer that can read its own @!rows extent)
# passes them; the loop is then bounded by the hints and the phantom-grid probe
# is bypassed entirely. When a hint is absent we fall back to the probe ceiling,
# so the no-hint path (and the fixture round-trip test) is UNCHANGED.
my constant MAX-COL-PROBE = 64;
my constant MAX-ROW-PROBE = 1024;

#| Build the worksheet XML for one in-memory worksheet, as a STRING.
#| When :$max-row / :$max-col are given they bound the loop (no fixed-grid
#| probe); when absent they fall back to the probe ceiling (see above).
my sub sheet-xml($ws, Int :$max-row, Int :$max-col --> Str) {
    my $cells := $ws.cells;
    # Row bound: use the hint if given, else the probe ceiling (clamped up by
    # the backing max-row when that happens to be larger).
    my $rmax = $max-row // (($cells.max-row // -1) max (MAX-ROW-PROBE - 1));
    # Col bound: use the hint if given, else the fixed probe ceiling.
    my $cmax = $max-col // (MAX-COL-PROBE - 1);

    my @p;
    @p.push: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
    @p.push: '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">';
    @p.push: '<sheetData>';

    for 0 .. $rmax -> $r {
        # Collect populated columns for this row.
        my @cols;
        for 0 .. $cmax -> $c {
            @cols.push: $c if $cells[$r;$c]:exists;
        }
        next unless @cols;

        my $rownum = $r + 1;
        @p.push: '<row r="' ~ $rownum ~ '">';
        for @cols -> $c {
            my $cell := $cells[$r;$c];
            my $ref  := col-name($c) ~ $rownum;

            # Style index `s="..."`. The resolved integer style id is reachable
            # via the PUBLIC accessor $cell.style.style-id, but ONLY AFTER the
            # DOM `sync-to-archive`/sync-sheet-data-xml pass has assigned it.
            # string-serialize calls $wb.to-blob (which runs that pass) BEFORE
            # invoking sheet-xml, and $cell.style is memoized (Cell.rakumod:58),
            # so the same CellStyle the DOM mutated is what we read here. We emit
            # `s=` only when the id is a non-zero integer (id 0 is the default
            # cell format and is written WITHOUT an `s` attribute by the DOM
            # path, so we mirror that to stay byte-aligned with styles.xml /
            # cellXfs index 0). See FINDINGS-spike.md (Task 6).
            my $s  = $cell.style.style-id;
            my $sa = ($s.defined && $s != 0) ?? ' s="' ~ $s ~ '"' !! '';

            # TYPE-aware: Number cells -> <v>; everything else -> inlineStr.
            if $cell ~~ Spreadsheet::XLSX::Cell::Number {
                @p.push: '<c r="' ~ $ref ~ '"' ~ $sa ~ '><v>' ~ $cell.value ~ '</v></c>';
            }
            else {
                my $t = xml-escape($cell.value // '');
                @p.push: '<c r="' ~ $ref ~ '"' ~ $sa ~ ' t="inlineStr"><is><t xml:space="preserve">'
                         ~ $t ~ '</t></is></c>';
            }
        }
        @p.push: '</row>';
    }

    @p.push: '</sheetData></worksheet>';
    @p.join
}

#| Numeric-correct sort key for 'xl/worksheets/sheetN.xml' paths.
my sub sheet-num(Str $path --> Int) {
    $path ~~ /'sheet' (\d+) '.xml'/ ?? +$0 !! Int.MAX
}

#| Serialize the whole workbook to an .xlsx Blob, building sheetData as strings
#| while keeping every other part byte-for-byte from the DOM `.to-blob` output.
#|
#| Optional :$max-row / :$max-col are 0-based extent hints applied to EVERY
#| worksheet. When given they bound the sheet-xml loop and bypass the
#| fixed-grid `:exists` probe (see sheet-xml's comment); when omitted the
#| no-hint probe behaviour is preserved unchanged.
sub string-serialize(Spreadsheet::XLSX $wb, Int :$max-row, Int :$max-col --> Blob) is export {
    # ORDERING DEPENDENCY: sheet-xml reads $cell.style.style-id, which only
    #  resolves correctly AFTER $wb.to-blob has FULLY returned (all cell-formats
    #  committed). The Cell.style accessor (_src/Spreadsheet/XLSX/Cell.rakumod
    #  ~line 57-65) throws X::Spreadsheet::XLSX::Format if a cell's style-id
    #  isn't yet in styles.cell-formats — so never hoist sheet-xml into the DOM
    #  sync loop (matters for the Task 8 in-place seam). The to-blob call below
    #  MUST stay ahead of every sheet-xml call.
    # 1. DOM baseline: all parts as bytes.
    #    Capability-guarded so this serializer works under BOTH library copies:
    #      - _lib (Task 8 seam): $wb.dom-blob exists -> call it, which runs the
    #        DOM path directly and NEVER re-enters to-blob(:fast) -> no recursion.
    #      - _src (Phase 1, unmodified): no dom-blob -> fall back to to-blob,
    #        whose only path IS the DOM path -> also no recursion.
    #    ^can returns a (possibly empty) list of Method objects; an empty list is
    #    falsy, a non-empty one truthy, so it reads cleanly as a boolean here.
    my $baseline = $wb.^can('dom-blob') ?? $wb.dom-blob !! $wb.to-blob;
    my %parts := unzip-parts-local($baseline);

    # 2. Map worksheets[$i] to the i-th sheet part in numeric order, and replace
    #    its sheetData XML with the string-built version.
    my @sheet-paths = %parts.keys
        .grep(* ~~ /^ 'xl/worksheets/sheet' \d+ '.xml' $/)
        .sort(&sheet-num);

    my @worksheets = $wb.worksheets;
    for @sheet-paths.kv -> $i, $path {
        last if $i >= @worksheets.elems;
        %parts{$path} = sheet-xml(@worksheets[$i], :$max-row, :$max-col).encode('utf-8');
    }

    # 3. Re-zip every part. Preserve a sensible, deterministic part order:
    #    scaffolding first, worksheets last (matching XLSXWriter's ordering
    #    intent); exact order is not required for validity, but stable is nice.
    my @ordered = %parts.keys.sort: -> $a, $b {
        order-key($a) <=> order-key($b) || $a cmp $b
    };

    my $buffer = Buf.new;
    given archive-write($buffer, format => 'zip') -> $archive {
        for @ordered -> $path {
            $archive.write($path, %parts{$path});
        }
        $archive.close;
    }
    $buffer
}

# Stable ordering: content-types, rels, workbook, styles, then worksheets, then rest.
my sub order-key(Str $p --> Int) {
    return 0 if $p eq '[Content_Types].xml';
    return 1 if $p eq '_rels/.rels';
    return 2 if $p eq 'xl/workbook.xml';
    return 3 if $p eq 'xl/_rels/workbook.xml.rels';
    return 4 if $p eq 'xl/styles.xml';
    return 5 if $p ~~ /^ 'xl/worksheets/' /;
    return 9;
}

# Local copy of the read side (compare.rakumod's unzip-parts), so this module is
# self-contained and does not depend on the test helper at runtime.
my sub unzip-parts-local(Blob $zip --> Hash) {
    my %out;
    for archive-read($zip) -> $entry {
        next unless $entry.is-file;
        %out{$entry.pathname} = $entry.data;
    }
    %out
}
