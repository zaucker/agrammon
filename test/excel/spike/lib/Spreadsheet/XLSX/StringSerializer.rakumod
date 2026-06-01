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
# Value+TYPE parity is the gate here (Task 6 handles style parity): numbers are
# emitted as <v> number cells, text as t="inlineStr". See FINDINGS-spike.md re:
# why the style index s="..." is OMITTED (not publicly reachable in-memory).
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
# freshly *built* (not loaded) workbook it returns -1. So we probe a generous
# fixed grid via the public `:exists` API. Adequate for the spike fixture; a
# production in-place writer would walk the private @!rows directly.
my constant MAX-COL-PROBE = 64;
my constant MAX-ROW-PROBE = 1024;

#| Build the worksheet XML for one in-memory worksheet, as a STRING.
my sub sheet-xml($ws --> Str) {
    my $cells := $ws.cells;
    # Use the larger of the (possibly -1) backing max-row and our probe ceiling.
    my $max-row = (($cells.max-row // -1) max (MAX-ROW-PROBE - 1));

    my @p;
    @p.push: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
    @p.push: '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">';
    @p.push: '<sheetData>';

    for 0 .. $max-row -> $r {
        # Collect populated columns for this row.
        my @cols;
        for ^MAX-COL-PROBE -> $c {
            @cols.push: $c if $cells[$r;$c]:exists;
        }
        next unless @cols;

        my $rownum = $r + 1;
        @p.push: '<row r="' ~ $rownum ~ '">';
        for @cols -> $c {
            my $cell := $cells[$r;$c];
            my $ref  := col-name($c) ~ $rownum;
            # TYPE-aware: Number cells -> <v>; everything else -> inlineStr.
            if $cell ~~ Spreadsheet::XLSX::Cell::Number {
                @p.push: '<c r="' ~ $ref ~ '"><v>' ~ $cell.value ~ '</v></c>';
            }
            else {
                my $t = xml-escape($cell.value // '');
                @p.push: '<c r="' ~ $ref ~ '" t="inlineStr"><is><t xml:space="preserve">'
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
sub string-serialize(Spreadsheet::XLSX $wb --> Blob) is export {
    # 1. DOM baseline: all parts as bytes.
    my %parts := unzip-parts-local($wb.to-blob);

    # 2. Map worksheets[$i] to the i-th sheet part in numeric order, and replace
    #    its sheetData XML with the string-built version.
    my @sheet-paths = %parts.keys
        .grep(* ~~ /^ 'xl/worksheets/sheet' \d+ '.xml' $/)
        .sort(&sheet-num);

    my @worksheets = $wb.worksheets;
    for @sheet-paths.kv -> $i, $path {
        last if $i >= @worksheets.elems;
        %parts{$path} = sheet-xml(@worksheets[$i]).encode('utf-8');
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
