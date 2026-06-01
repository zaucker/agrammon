# test/excel/spike/bench.raku
#
# Task 7 — standalone string-serializer vs DOM `.to-blob` benchmark.
#
# CAVEAT 1 (extent hints are MANDATORY here):
#   string-serialize / sheet-xml, when called WITHOUT :max-row / :max-col, probe
#   a FIXED 1024x64 grid via the `:exists` API — that's 65,536 lookups per sheet
#   REGARDLESS of cell count. Benchmarking the no-hint path would measure the
#   phantom-grid probe, not the serializer. Worse, the no-hint probe SILENTLY
#   DROPS any cell at row >= 1024 / col >= 64 (Task-5 finding), and the 2000-row
#   case below EXCEEDS row 1024 — so its output would be wrong, not just slow.
#   We therefore pass the hints matching big-wb's exact extent (8 cols -> max-col
#   7; $rows rows -> max-row $rows-1). This mirrors how a real in-place writer —
#   which knows its own @!rows extent — would call the serializer.
#
# CAVEAT 2 (the "fast" timing still pays ONE DOM pass):
#   string-serialize calls $wb.to-blob ONCE internally to obtain the byte
#   baseline for every non-sheet part, then replaces only the sheetData XML.
#   So the "speedup" reported here is the REALISTIC opt-in speedup of the
#   STANDALONE approach (which still pays one full DOM pass), NOT the bare
#   sheet-only floor. A true in-place writer (Task 8) that skips the DOM sheet
#   build entirely would show a larger gap; this number is the conservative one.

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

# --- Sanity check: confirm the extent hint is effective for the 2000-row case
#     (the no-hint path would have dropped every row >= 1024). We count the
#     <row r="..."> entries in the string-serialized output by reloading it and
#     checking the populated max-row, and we record the blob size so a reader
#     can confirm bytes scale with row count.
{
    my $rows = 2000;
    my $wb = big-wb($rows);
    my $blob = string-serialize($wb, :max-row($rows - 1), :max-col(7));
    # Reload the produced .xlsx and ask the library for the populated extent.
    my $rt = Spreadsheet::XLSX.load($blob);
    my $got = $rt.worksheets[0].cells.max-row;
    say "# SANITY: 2000-row string-serialize -> blob {$blob.bytes} bytes, "
        ~ "reloaded max-row = $got (expect 1999)";
    note "WARNING: 2000-row case did NOT serialize all rows (max-row=$got, expected 1999) "
         ~ "— extent hint not effective!" unless $got == $rows - 1;
}

say "# rows | DOM to-blob (s) | string-serialize (s) | speedup";
for 200, 800, 2000 -> $rows {
    my @dom; my @str;
    for ^3 {
        my $wb = big-wb($rows);
        my $t0 = now; $wb.to-blob;            @dom.push: (now - $t0).Num;
        my $wb2 = big-wb($rows);
        # Hints REQUIRED — see CAVEAT 1 at top of file.
        my $t1 = now; string-serialize($wb2, :max-row($rows - 1), :max-col(7));
        @str.push: (now - $t1).Num;
    }
    printf "%5d | %14.3f | %18.3f | %6.1fx\n",
        $rows, med(@dom), med(@str), med(@dom) / med(@str);
}
say "# DONE";
