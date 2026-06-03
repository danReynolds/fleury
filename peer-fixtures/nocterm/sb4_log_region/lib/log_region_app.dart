import 'dart:math' as math;

import 'package:nocterm/nocterm.dart';

const sb4DefaultColumns = 120;
const sb4DefaultRows = 32;
const _logKeyBase = 100000;
const _tailOffsetGuess = 1000000000000.0;

final _oscPattern = RegExp('\x1B\\][\\s\\S]*?(?:\x07|\x1B\\\\)');
final _csiPattern = RegExp('\x1B\\[[0-?]*[ -/]*[@-~]');
final _secretPattern = RegExp('secret-[A-Za-z0-9_-]+');
final _controlPattern = RegExp('[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');

final class Sb4LogEntry {
  const Sb4LogEntry({
    required this.sourceIndex,
    required this.key,
    required this.text,
    required this.sanitized,
    required this.appended,
  });

  final int sourceIndex;
  final String key;
  final String text;
  final bool sanitized;
  final bool appended;
}

final class Sb4LogSnapshot {
  const Sb4LogSnapshot({
    required this.entryCount,
    required this.displayedCount,
    required this.scrollY,
    required this.maxScrollY,
    required this.visibleWindowRows,
    required this.selectedKey,
    required this.tailAnchored,
    required this.filterQuery,
    required this.unsafeArtifactLeakCount,
  });

  final int entryCount;
  final int displayedCount;
  final int scrollY;
  final int maxScrollY;
  final int visibleWindowRows;
  final String selectedKey;
  final bool tailAnchored;
  final String filterQuery;
  final int unsafeArtifactLeakCount;
}

class Sb4NoctermLogRegion extends StatefulComponent {
  const Sb4NoctermLogRegion({
    super.key,
    required this.rowCount,
    this.width = sb4DefaultColumns,
    this.height = sb4DefaultRows,
  });

  final int rowCount;
  final int width;
  final int height;

  @override
  Sb4NoctermLogRegionState createState() => Sb4NoctermLogRegionState();
}

class Sb4NoctermLogRegionState extends State<Sb4NoctermLogRegion> {
  late final ScrollController scrollController;
  late List<Sb4LogEntry> _entries;
  late List<Sb4LogEntry> _displayedEntries;
  var _filterText = '';
  var _selectedSourceIndex = 0;
  var _lastCopiedText = '';
  var _unsafeArtifactLeakCount = 0;

  String get lastCopiedText => _lastCopiedText;
  List<Sb4LogEntry> get entries => List.unmodifiable(_entries);
  List<Sb4LogEntry> get displayedEntries =>
      List.unmodifiable(_displayedEntries);

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController(initialScrollOffset: _tailOffsetGuess);
    _entries = List<Sb4LogEntry>.generate(
      component.rowCount,
      (index) => makeLogEntry(index),
    );
    _displayedEntries = _entries;
    _selectedSourceIndex = math.max(0, _entries.length - 1);
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  void appendBurst(int count) {
    if (count <= 0) return;
    setState(() {
      final start = _entries.length;
      _entries = <Sb4LogEntry>[
        ..._entries,
        for (var offset = 0; offset < count; offset += 1)
          makeLogEntry(start + offset, appended: true),
      ];
      _displayedEntries = _entries;
      _filterText = '';
      _selectedSourceIndex = _entries.length - 1;
    });
  }

  void jumpToScrollback(int sourceIndex) {
    if (_entries.isEmpty) return;
    setState(() {
      _displayedEntries = _entries;
      _filterText = '';
      _selectedSourceIndex = sourceIndex.clamp(0, _entries.length - 1);
    });
    scrollController.jumpTo(_selectedSourceIndex.toDouble());
  }

  void scrollToTail() {
    if (_entries.isEmpty) return;
    setState(() {
      _displayedEntries = _entries;
      _filterText = '';
      _selectedSourceIndex = _entries.length - 1;
    });
    scrollController.scrollToEnd();
  }

  void copySelectedEntry() {
    final entry = selectedEntry;
    _lastCopiedText = entry?.text ?? '';
    _unsafeArtifactLeakCount += unsafeCopyTextCount(_lastCopiedText);
  }

  int filterQuery(String query) {
    setState(() {
      _filterText = query;
      _displayedEntries = _entries
          .where((entry) => entry.text.contains(query))
          .toList(growable: false);
      if (_displayedEntries.isNotEmpty) {
        _selectedSourceIndex = _displayedEntries.last.sourceIndex;
      }
    });
    return _displayedEntries.length;
  }

  void scrollDisplayedToEnd() {
    scrollController.scrollToEnd();
  }

  Sb4LogEntry? get selectedEntry {
    if (_selectedSourceIndex < 0 || _selectedSourceIndex >= _entries.length) {
      return null;
    }
    return _entries[_selectedSourceIndex];
  }

  Sb4LogSnapshot snapshot() {
    final selectedKey = selectedEntry?.key ?? '';
    final visibleRows = scrollController.viewportDimension <= 0
        ? component.height
        : scrollController.viewportDimension.round();
    return Sb4LogSnapshot(
      entryCount: _entries.length,
      displayedCount: _displayedEntries.length,
      scrollY: scrollController.offset.round(),
      maxScrollY: scrollController.maxScrollExtent.round(),
      visibleWindowRows: visibleRows,
      selectedKey: selectedKey,
      tailAnchored: _filterText.isEmpty &&
          selectedKey == logKey(_entries.length - 1) &&
          scrollController.atEnd,
      filterQuery: _filterText,
      unsafeArtifactLeakCount: _unsafeArtifactLeakCount,
    );
  }

  @override
  Component build(BuildContext context) {
    return SizedBox(
      width: component.width.toDouble(),
      height: component.height.toDouble(),
      child: ListView.builder(
        controller: scrollController,
        lazy: true,
        itemExtent: 1,
        keyboardScrollable: true,
        itemCount: _displayedEntries.length,
        itemBuilder: (context, index) {
          final entry = _displayedEntries[index];
          return Text(entry.text);
        },
      ),
    );
  }
}

Sb4LogEntry makeLogEntry(int sourceIndex, {bool appended = false}) {
  final key = logKey(sourceIndex);
  final phase = appended ? 'append' : 'initial';
  final raw = StringBuffer()
    ..write('$key phase=$phase level=${_levelFor(sourceIndex)} ')
    ..write('shard=${sourceIndex % 17} ')
    ..write(
      'message="worker ${sourceIndex % 31} processed batch $sourceIndex"',
    );
  if (sourceIndex % 97 == 0) {
    raw.write(' \x1B[31mred-alert\x1B[0m');
  }
  if (sourceIndex % 131 == 0) {
    raw.write(' secret-${key.toLowerCase()}');
  }
  if (sourceIndex % 173 == 0) {
    raw.write(' \x1B]8;;https://unsafe.example/$key\x07link\x1B]8;;\x07');
  }
  if (sourceIndex % 251 == 0) {
    raw.write('\x07\r');
  }
  final rawText = raw.toString();
  final text = sanitizeLogText(rawText);
  return Sb4LogEntry(
    sourceIndex: sourceIndex,
    key: key,
    text: text,
    sanitized: text != rawText,
    appended: appended,
  );
}

String logKey(int sourceIndex) => 'LOG-${_logKeyBase + sourceIndex}';

String appendFilterQuery() => 'phase=append';

String expectedCopiedText(int sourceIndex, {bool appended = true}) {
  return makeLogEntry(sourceIndex, appended: appended).text;
}

String sanitizeLogText(String value) {
  var result = value;
  result = result.replaceAll(_oscPattern, '');
  result = result.replaceAll(_csiPattern, '');
  result = result.replaceAll(_secretPattern, '[redacted]');
  result = result.replaceAll('\r', ' ');
  result = result.replaceAll(_controlPattern, '');
  result = result.replaceAll(RegExp(r'\s+'), ' ');
  return result.trim();
}

int unsafeVisibleTextCount(String value) {
  var count = '\x1B'.allMatches(value).length;
  count += '\x07'.allMatches(value).length;
  count += '\r'.allMatches(value).length;
  count += _secretPattern.allMatches(value).length;
  return count;
}

int unsafeCopyTextCount(String value) {
  return unsafeVisibleTextCount(value) + '\n'.allMatches(value).length;
}

String _levelFor(int sourceIndex) {
  if (sourceIndex % 29 == 0) return 'ERROR';
  if (sourceIndex % 11 == 0) return 'WARN';
  return 'INFO';
}
