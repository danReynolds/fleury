import 'package:fleury/fleury.dart';

import 'log_region.dart';

/// Converts captured terminal output into structured [LogRegion] entries.
List<LogEntry> buildTerminalOutputLogEntries(List<LogLine> lines) {
  return List<LogEntry>.unmodifiable(
    List<LogEntry>.generate(lines.length, (index) {
      final line = lines[index];
      return LogEntry(
        id: index,
        severity: line.source == LogSource.stderr
            ? LogSeverity.error
            : LogSeverity.info,
        source: line.source.name,
        message: line.text,
        metadata: <String, Object?>{
          'terminalOutputIndex': index,
          'terminalOutputSource': line.source.name,
        },
      );
    }),
  );
}

/// Structured terminal-output view backed by a runtime [LogBuffer].
///
/// Core [LogView] remains the minimal captured-output tail view used by the
/// debug console. [TerminalOutputRegion] is the app-facing surface for captured
/// stdout/stderr when apps need filtering, copy/export semantics, lazy rows, and
/// safety metadata from [LogRegion].
class TerminalOutputRegion extends StatelessWidget {
  const TerminalOutputRegion({
    super.key,
    this.buffer,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.label = 'Terminal output',
    this.showPrefix = true,
    this.maxLineLength = 1000,
    this.filter,
    this.copySelection = true,
    this.copyOptions = const LogRegionCopyOptions(),
    this.onCopy,
  }) : assert(maxLineLength == null || maxLineLength >= 0);

  final LogBuffer? buffer;
  final LogRegionController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final String label;
  final bool showPrefix;
  final int? maxLineLength;
  final LogRegionFilterDescriptor? filter;
  final bool copySelection;
  final LogRegionCopyOptions copyOptions;
  final void Function(LogRegionCopyResult result)? onCopy;

  @override
  Widget build(BuildContext context) {
    final buffer = this.buffer ?? LogBufferScope.of(context);
    return ListenableBuilder(
      listenable: buffer,
      builder: (context, _) {
        return LogRegion(
          entries: buildTerminalOutputLogEntries(buffer.lines),
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          label: label,
          showPrefix: showPrefix,
          maxLineLength: maxLineLength,
          filter: filter,
          copySelection: copySelection,
          copyOptions: copyOptions,
          onCopy: onCopy,
        );
      },
    );
  }
}
