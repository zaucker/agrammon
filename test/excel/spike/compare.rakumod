use Libarchive::Simple;

#| Unzip an in-memory .xlsx (a zip Blob) into its constituent parts.
#|
#| Returns a Hash mapping each archive entry's path (e.g. '[Content_Types].xml',
#| 'xl/workbook.xml', 'xl/worksheets/sheet1.xml') to its DECOMPRESSED bytes (Blob).
#|
#| Mechanism: Libarchive's in-memory read API. `archive-read(Blob)` opens the zip
#| straight from memory (archive_read_open_memory under the hood) and yields one
#| Libarchive::Entry::Read per entry; `.pathname` is the entry path and `.data`
#| returns the decompressed contents as a Blob. This is the READ counterpart of
#| the WRITE path used by lib/Agrammon/OutputFormatter/XLSXWriter.rakumod, which
#| also goes through Libarchive::Simple.
sub unzip-parts(Blob $zip --> Hash) is export {
    my %out;
    for archive-read($zip) -> $entry {
        # Skip directory entries (they carry no file data).
        next unless $entry.is-file;
        %out{$entry.pathname} = $entry.data;
    }
    %out
}

use Spreadsheet::XLSX;

#| Compare two .xlsx blobs SEMANTICALLY by re-loading each with the library's own
#| loader and diffing the resulting model: per sheet, per populated cell, compare
#| value + presence + type + style (bold + number-format). Returns a list of
#| human-readable discrepancy strings (empty list == equivalent).
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
            for 0..15 -> $c {
                my $ov = ($oc[$r;$c]:exists) ?? $oc[$r;$c] !! Nil;
                my $sv = ($sc[$r;$c]:exists) ?? $sc[$r;$c] !! Nil;
                next if !$ov.defined && !$sv.defined;
                if $ov.defined != $sv.defined {
                    @diffs.push: "sheet$si [$r;$c]: presence oracle={$ov.defined} spike={$sv.defined}";
                    next;
                }
                # Check cell TYPE first, then value. Type matters because a
                # NUMBER cell `6` and a TEXT cell "6" stringify identically, so a
                # value-only (Str-coerced) comparison would treat them as equal.
                # The string serializer under test can silently emit numbers as
                # inline strings; this catches that number-vs-text confusion.
                if !($ov.WHAT =:= $sv.WHAT) {
                    @diffs.push: "sheet$si [$r;$c]: type {$ov.^name} vs {$sv.^name}";
                }
                elsif ($ov.value // '') ne ($sv.value // '') {
                    @diffs.push: "sheet$si [$r;$c]: value '{$ov.value}' vs '{$sv.value}'";
                }

                # Style parity. We compare the two style features the fixture
                # exercises and that the library round-trips: bold and
                # number-format. `.style` is read from the RE-LOADED model, so
                # it reflects what each blob actually persisted (it does not
                # suffer the to-blob non-idempotency that the in-memory build
                # model does — see FINDINGS-spike.md, Task 6). Guard for cells
                # whose `.style` is undefined.
                my $os = $ov.?style;
                my $ss = $sv.?style;
                my $ob = $os.defined ?? ($os.bold // False) !! False;
                my $sb = $ss.defined ?? ($ss.bold // False) !! False;
                if ?$ob != ?$sb {
                    @diffs.push: "sheet$si [$r;$c]: bold oracle={?$ob} spike={?$sb}";
                }
                my $onf = $os.defined ?? ($os.number-format // '') !! '';
                my $snf = $ss.defined ?? ($ss.number-format // '') !! '';
                if $onf ne $snf {
                    @diffs.push: "sheet$si [$r;$c]: number-format oracle='$onf' spike='$snf'";
                }
            }
        }
    }
    return @diffs;
}
