import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

class TableRows extends StatefulWidget {
  const TableRows({super.key});

  @override
  State<TableRows> createState() => _TableRowsState();
}

class _TableRowsState extends State<TableRows> {
  final table = DataTableController();
  String browsing = 'Row 1';
  String chosen = 'None';

  @override
  void dispose() {
    table.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // #docregion interaction
      SizedBox(
        height: 7,
        child: DataTable(
          controller: table,
          rowCount: 100,
          autofocus: true,
          onFocusedItemChanged: (row) =>
              setState(() => browsing = 'Row ${row + 1}'),
          onSelect: (row) => setState(() => chosen = 'Row ${row + 1}'),
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
      Text('Browsing: $browsing'),
      Text('Chosen: $chosen'),
    ],
  );
}
