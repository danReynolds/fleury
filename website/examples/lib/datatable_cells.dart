import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

class TableCells extends StatefulWidget {
  const TableCells({super.key});

  @override
  State<TableCells> createState() => _TableCellsState();
}

class _TableCellsState extends State<TableCells> {
  String range = '1 × 1';
  String status = 'No row opened';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // #docregion interaction
      SizedBox(
        height: 7,
        child: DataTable(
          rowCount: 100,
          autofocus: true,
          selectionMode: DataTableSelectionMode.cell,
          onRangeChanged: (selection) => setState(() {
            range = '${selection.rowCount} × ${selection.columnCount}';
          }),
          onAction: (row) => setState(() => status = 'Opened row ${row + 1}'),
          onCopy: (result) => setState(
            () => status =
                'Copied ${result.export.rowCount} × ${result.export.columnCount}',
          ),
          columns: const [
            DataTableColumn(
              id: 'name',
              title: 'Name',
              width: FixedColumnWidth(12),
            ),
            DataTableColumn(id: 'status', title: 'Status'),
          ],
          cellBuilder: (row, column) =>
              column == 'name' ? 'Row ${row + 1}' : 'Ready',
        ),
      ),
      // #enddocregion interaction
      Text('Range: $range'),
      Text(status),
    ],
  );
}
