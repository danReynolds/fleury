import 'package:fleury/fleury_core.dart';

import 'log_region.dart';

/// Converts captured terminal output into structured [LogRegion] entries.
///
/// [baseIndex] is the monotonic index of `lines.first` in the producer
/// sequence (typically [LogBuffer.baseIndex]). Entry [LogEntry.id] values are
/// `baseIndex + index` so a capacity head trim does not shift identity.
List<LogEntry> buildTerminalOutputLogEntries(
  List<LogLine> lines, {
  int baseIndex = 0,
}) {
  assert(baseIndex >= 0);
  return List<LogEntry>.unmodifiable(
    List<LogEntry>.generate(lines.length, (index) {
      final line = lines[index];
      final id = baseIndex + index;
      return LogEntry(
        id: id,
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

/// Shows captured stdout and stderr (a [LogBuffer]) as a [LogRegion]:
/// filterable, copyable rows that follow new output, with stderr lines styled
/// as errors.
///
/// By default it reads the [LogBuffer] from the nearest [LogBufferScope],
/// which `runApp` provides in a terminal app; pass [buffer] to show another.
/// For a minimal tail view without filtering or copy, use
/// [OutputCaptureView].
class TerminalOutputRegion extends StatelessWidget {
  const TerminalOutputRegion({
    super.key,
    this.buffer,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel = 'Terminal output',
    this.showPrefix = true,
    this.maxLineLength = 1000,
    this.filter,
    this.copySelection = true,
    this.copyOptions = const LogRegionCopyOptions(),
    this.onCopy,
  }) : assert(maxLineLength == null || maxLineLength >= 0);

  /// Runtime output buffer to render; defaults to the ambient [LogBufferScope].
  final LogBuffer? buffer;

  /// External selection and tail-follow controller.
  final LogRegionController? controller;

  /// Focus node used by the rendered log region.
  final FocusNode? focusNode;

  /// Whether the rendered log region should request focus when mounted.
  final bool autofocus;

  /// Semantic label (the accessibility name; not rendered) for the output region.
  final String semanticLabel;

  /// Whether each row starts with an `[INFO stdout]` or `[ERROR stderr]`
  /// prefix.
  final bool showPrefix;

  /// Cuts each output line to this many characters, with no ellipsis, on
  /// screen and when copied; null never cuts. The prefix doesn't count.
  final int? maxLineLength;

  /// Optional filter applied to captured output rows.
  final LogRegionFilterDescriptor? filter;

  /// Whether Ctrl+C (and the semantic copy action) copies the output line
  /// under the cursor.
  final bool copySelection;

  /// Clipboard/export options for copied output.
  final LogRegionCopyOptions copyOptions;

  /// Called after a copy attempt completes.
  final void Function(LogRegionCopyResult result)? onCopy;

  @override
  Widget build(BuildContext context) {
    final buffer = this.buffer ?? LogBufferScope.of(context);
    return NotifierBuilder(
      notifier: buffer,
      builder: (context, _) {
        return LogRegion(
          entries: buildTerminalOutputLogEntries(
            buffer.lines,
            baseIndex: buffer.baseIndex,
          ),
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          semanticLabel: semanticLabel,
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
