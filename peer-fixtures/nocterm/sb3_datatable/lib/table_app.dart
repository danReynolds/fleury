import 'dart:math' as math;

import 'package:nocterm/nocterm.dart';

const sb3DefaultColumns = 120;
const sb3DefaultRows = 32;

const _columns = <_ColumnSpec>[
  _ColumnSpec('ID', 12),
  _ColumnSpec('Status', 8),
  _ColumnSpec('Title', 24),
  _ColumnSpec('Owner', 12),
  _ColumnSpec('Duration', 10),
  _ColumnSpec('Progress', 8),
  _ColumnSpec('Warnings', 8),
  _ColumnSpec('Updated', 14),
];

final _oscPattern = RegExp('\x1B\\][\\s\\S]*?(?:\x07|\x1B\\\\)');
final _csiPattern = RegExp('\x1B\\[[0-?]*[ -/]*[@-~]');
final _secretPattern = RegExp('secret-[A-Za-z0-9_-]+');
final _controlPattern = RegExp('[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');

final class Sb3RowRecord {
  const Sb3RowRecord({
    required this.index,
    required this.id,
    required this.status,
    required this.title,
    required this.owner,
    required this.duration,
    required this.progress,
    required this.warnings,
    required this.updated,
  });

  final int index;
  final String id;
  final String status;
  final String title;
  final String owner;
  final String duration;
  final String progress;
  final String warnings;
  final String updated;

  List<String> get cells => <String>[
        id,
        status,
        title,
        owner,
        duration,
        progress,
        warnings,
        updated,
      ];
}

final class Sb3TableSnapshot {
  const Sb3TableSnapshot({
    required this.rowCount,
    required this.selectedRow,
    required this.selectedRowId,
    required this.visibleStart,
    required this.visibleEnd,
    required this.visibleWindowRows,
    required this.scrollY,
    required this.maxScrollY,
    required this.unsafeArtifactLeakCount,
  });

  final int rowCount;
  final int selectedRow;
  final String selectedRowId;
  final int visibleStart;
  final int visibleEnd;
  final int visibleWindowRows;
  final int scrollY;
  final int maxScrollY;
  final int unsafeArtifactLeakCount;
}

class Sb3NoctermDataTable extends StatefulComponent {
  const Sb3NoctermDataTable({
    super.key,
    required this.rowCount,
    this.width = sb3DefaultColumns,
    this.height = sb3DefaultRows,
  });

  final int rowCount;
  final int width;
  final int height;

  @override
  Sb3NoctermDataTableState createState() => Sb3NoctermDataTableState();
}

class Sb3NoctermDataTableState extends State<Sb3NoctermDataTable> {
  late final ScrollController scrollController;
  late final List<Sb3RowRecord> _rows;
  var _selectedRow = 0;
  var _lastCopiedText = '';
  var _unsafeArtifactLeakCount = 0;

  String get lastCopiedText => _lastCopiedText;
  List<Sb3RowRecord> get rows => List.unmodifiable(_rows);

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController();
    _rows = List<Sb3RowRecord>.generate(component.rowCount, makeRowRecord);
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  void arrowDown() {
    if (_rows.isEmpty) return;
    setState(() {
      _selectedRow = math.min(_selectedRow + 1, _rows.length - 1);
    });
    _keepSelectedVisible();
  }

  void pageDown() {
    if (_rows.isEmpty) return;
    final page = visibleCapacity();
    setState(() {
      _selectedRow = math.min(_selectedRow + page, _rows.length - 1);
    });
    _keepSelectedVisible();
  }

  void jumpToEnd() {
    if (_rows.isEmpty) return;
    setState(() {
      _selectedRow = _rows.length - 1;
    });
    scrollController.jumpTo(_maxVisibleStart().toDouble());
  }

  void copySelectedRow() {
    final row = selectedRowRecord;
    _lastCopiedText = row == null ? '' : tsvForRow(row);
    _unsafeArtifactLeakCount += unsafeCopyTextCount(_lastCopiedText);
  }

  Sb3RowRecord? get selectedRowRecord {
    if (_selectedRow < 0 || _selectedRow >= _rows.length) return null;
    return _rows[_selectedRow];
  }

  int visibleCapacity() {
    final viewport = scrollController.viewportDimension;
    if (viewport > 0) return math.max(1, viewport.round());
    return math.max(1, component.height - 1);
  }

  Sb3TableSnapshot snapshot() {
    final visibleRows = visibleCapacity();
    final visibleStart = scrollController.offset.round().clamp(
          0,
          _maxVisibleStart(),
        );
    final visibleEnd = math.min(visibleStart + visibleRows, _rows.length);
    return Sb3TableSnapshot(
      rowCount: _rows.length,
      selectedRow: _selectedRow,
      selectedRowId: selectedRowRecord?.id ?? '',
      visibleStart: visibleStart,
      visibleEnd: visibleEnd,
      visibleWindowRows: math.max(0, visibleEnd - visibleStart),
      scrollY: scrollController.offset.round(),
      maxScrollY: scrollController.maxScrollExtent.round(),
      unsafeArtifactLeakCount: _unsafeArtifactLeakCount,
    );
  }

  @override
  Component build(BuildContext context) {
    return SizedBox(
      width: component.width.toDouble(),
      height: component.height.toDouble(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Component>[
          Text(_formatHeader()),
          SizedBox(
            width: component.width.toDouble(),
            height: math.max(1, component.height - 1).toDouble(),
            child: ListView.builder(
              controller: scrollController,
              lazy: true,
              itemExtent: 1,
              keyboardScrollable: true,
              itemCount: _rows.length,
              itemBuilder: (context, index) {
                final row = _rows[index];
                final marker = index == _selectedRow ? '>' : ' ';
                return Text('$marker ${formatRow(row)}');
              },
            ),
          ),
        ],
      ),
    );
  }

  void _keepSelectedVisible() {
    final visibleRows = visibleCapacity();
    final currentStart = scrollController.offset.round().clamp(
          0,
          _maxVisibleStart(),
        );
    var nextStart = currentStart;
    if (_selectedRow < currentStart) {
      nextStart = _selectedRow;
    } else if (_selectedRow >= currentStart + visibleRows) {
      nextStart = _selectedRow + 1 - visibleRows;
    }
    nextStart = nextStart.clamp(0, _maxVisibleStart());
    scrollController.jumpTo(nextStart.toDouble());
  }

  int _maxVisibleStart() {
    return math.max(0, _rows.length - visibleCapacity());
  }
}

Sb3RowRecord makeRowRecord(int index) {
  final rawTitle = index % 97 == 0
      ? 'Build pipeline $index \x1B[31munsafe\x1B[0m secret-$index'
      : 'Build pipeline $index';
  return Sb3RowRecord(
    index: index,
    id: rowId(index),
    status: index % 5 == 0 ? 'failed' : 'ok',
    title: sanitizeDisplayText(rawTitle),
    owner: 'user-${index % 17}',
    duration: '${30 + index % 400}s',
    progress: '${index % 101}%',
    warnings: '${index % 4}',
    updated: '2026-06-${(1 + index % 28).toString().padLeft(2, '0')}',
  );
}

String rowId(int index) => 'RUN-${index.toString().padLeft(6, '0')}';

String expectedSelectedTsv(int index) => tsvForRow(makeRowRecord(index));

String tsvForRow(Sb3RowRecord row) {
  final headings = _columns.map((column) => column.label).join('\t');
  final cells = row.cells.map(sanitizeTsvCell).join('\t');
  return '$headings\n$cells';
}

String formatRow(Sb3RowRecord row) {
  final buffer = StringBuffer();
  for (var i = 0; i < _columns.length; i += 1) {
    if (i > 0) buffer.write(' ');
    buffer.write(_fit(row.cells[i], _columns[i].width));
  }
  return buffer.toString();
}

String _formatHeader() {
  final buffer = StringBuffer('  ');
  for (var i = 0; i < _columns.length; i += 1) {
    if (i > 0) buffer.write(' ');
    buffer.write(_fit(_columns[i].label, _columns[i].width));
  }
  return buffer.toString();
}

String sanitizeDisplayText(String value) {
  var result = value;
  result = result.replaceAll(_oscPattern, '');
  result = result.replaceAll(_csiPattern, '');
  result = result.replaceAll(_secretPattern, '[redacted]');
  result = result.replaceAll('\r', ' ');
  result = result.replaceAll(_controlPattern, ' ');
  result = result.replaceAll(RegExp(r'\s+'), ' ');
  return result.trim();
}

String sanitizeTsvCell(String value) {
  return sanitizeDisplayText(
    value,
  ).replaceAll('\t', ' ').replaceAll('\n', ' ').replaceAll('\r', ' ');
}

int unsafeVisibleTextCount(String value) {
  return '\x1B'.allMatches(value).length +
      _controlPattern.allMatches(value).length +
      _secretPattern.allMatches(value).length;
}

int unsafeCopyTextCount(String value) {
  final normalized =
      value.replaceAll('\t', '').replaceAll('\n', '').replaceAll('\r', '');
  return unsafeVisibleTextCount(normalized);
}

String _fit(String value, int width) {
  final sanitized = sanitizeDisplayText(value);
  if (sanitized.length == width) return sanitized;
  if (sanitized.length < width) return sanitized.padRight(width);
  if (width <= 1) return sanitized.substring(0, width);
  return sanitized.substring(0, width - 1);
}

final class _ColumnSpec {
  const _ColumnSpec(this.label, this.width);

  final String label;
  final int width;
}
