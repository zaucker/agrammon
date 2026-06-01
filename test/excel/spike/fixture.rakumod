use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Cell;

#| Build ONE workbook through the PUBLIC write API, exercising every writable
#| feature we can reach: text + number cells, bold font, number-format, and a
#| second sheet.
sub build-fixture(--> Spreadsheet::XLSX) is export {
    my $wb = Spreadsheet::XLSX.new;

    my $a = $wb.create-worksheet('Data');
    $a.cells[0;0] = Spreadsheet::XLSX::Cell::Text.new(value => 'Name');
    $a.cells[0;0].style.bold = True;
    $a.cells[0;1] = Spreadsheet::XLSX::Cell::Text.new(value => 'Amount');
    $a.cells[0;1].style.bold = True;
    $a.cells[1;0] = Spreadsheet::XLSX::Cell::Text.new(value => 'Eggs & Ham <b>');
    $a.cells[1;1] = Spreadsheet::XLSX::Cell::Number.new(value => 6);
    $a.cells[2;0] = Spreadsheet::XLSX::Cell::Text.new(value => 'Flour');
    $a.cells[2;1] = Spreadsheet::XLSX::Cell::Number.new(value => 1.5);
    $a.cells[2;1].style.number-format = '#,##0.00';

    my $b = $wb.create-worksheet('Notes');
    $b.cells[0;0] = Spreadsheet::XLSX::Cell::Text.new(value => 'umlauts: äöü ß');

    return $wb;
}
