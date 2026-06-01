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
