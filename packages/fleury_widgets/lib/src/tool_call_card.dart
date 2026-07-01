import 'dart:async' show unawaited;

import 'package:characters/characters.dart';
import 'package:fleury/fleury_core.dart';

import 'controls.dart' show Button, ButtonVariant;

/// Protocol-neutral status for one tool call.
enum ToolCallStatus { queued, running, succeeded, failed, cancelled }

/// Protocol-neutral tool call data rendered by [ToolCallCard].
final class ToolCallRecord {
  const ToolCallRecord({
    required this.id,
    required this.name,
    this.title,
    this.description,
    this.status = ToolCallStatus.queued,
    this.arguments = const <String, Object?>{},
    this.output,
    this.error,
    this.progressCurrent,
    this.progressTotal,
    this.metadata = const <String, Object?>{},
  });

  /// Stable tool-call identity.
  final String id;

  /// Tool name or command identifier.
  final String name;

  /// Optional display title; defaults to [name].
  final String? title;

  /// Optional human-readable description.
  final String? description;

  /// Current lifecycle status.
  final ToolCallStatus status;

  /// Sanitized argument summary for the call.
  final Map<String, Object?> arguments;

  /// Optional captured output text.
  final String? output;

  /// Optional error text; shown instead of [output] when present.
  final String? error;

  /// Current progress value, when known.
  final num? progressCurrent;

  /// Total progress value, when known.
  final num? progressTotal;

  /// App-specific semantic state carried by the record.
  final Map<String, Object?> metadata;

  String get displayTitle => title ?? name;
  bool get busy =>
      status == ToolCallStatus.queued || status == ToolCallStatus.running;
}

/// Options for copying a [ToolCallRecord].
final class ToolCallCopyOptions {
  const ToolCallCopyOptions({
    this.includeArguments = true,
    this.includeOutput = true,
    this.maxOutputLength = 1000,
    this.clipboardPolicy = ClipboardWritePolicy.standard,
  }) : assert(maxOutputLength == null || maxOutputLength >= 0);

  /// Whether copied summaries include [ToolCallRecord.arguments].
  final bool includeArguments;

  /// Whether copied summaries include output or error text.
  final bool includeOutput;

  /// Maximum copied output/error length.
  final int? maxOutputLength;

  /// Clipboard write behavior for copied tool-call text.
  final ClipboardWritePolicy clipboardPolicy;
}

/// Result delivered after [ToolCallCard] copies a tool call summary.
final class ToolCallCopyResult {
  const ToolCallCopyResult({
    required this.record,
    required this.text,
    required this.report,
  });

  final ToolCallRecord record;
  final String text;
  final ClipboardWriteReport report;
}

/// Exports one tool call as sanitized text suitable for copy/debug evidence.
String exportToolCallSummary(
  ToolCallRecord record, {
  ToolCallCopyOptions options = const ToolCallCopyOptions(),
}) {
  final lines = <String>[
    'Tool: ${_sanitizeToolText(record.name)}',
    'Status: ${record.status.name}',
    if (record.description != null)
      'Description: ${_sanitizeToolText(record.description!)}',
  ];
  if (options.includeArguments && record.arguments.isNotEmpty) {
    lines.add('Arguments: ${_formatArguments(record.arguments)}');
  }
  final output = record.error ?? record.output;
  if (options.includeOutput && output != null) {
    lines.add(
      'Output: ${_truncateGraphemes(_sanitizeToolText(output), options.maxOutputLength)}',
    );
  }
  return lines.join('\n');
}

/// Compact tool-call surface for developer and agent-style workflows.
class ToolCallCard extends StatefulWidget {
  const ToolCallCard({
    super.key,
    required this.record,
    this.copyEnabled = true,
    this.copyOptions = const ToolCallCopyOptions(),
    this.onCopy,
    this.onCancel,
    this.width,
  });

  /// Tool-call data to render.
  final ToolCallRecord record;

  /// Whether the card exposes copy UI and semantic copy.
  final bool copyEnabled;

  /// Clipboard/export options for copied tool-call summaries.
  final ToolCallCopyOptions copyOptions;

  /// Called after a copy attempt completes.
  final void Function(ToolCallCopyResult result)? onCopy;

  /// Called when the cancel action is invoked while the record is busy.
  final VoidCallback? onCancel;

  /// Optional fixed width for the card content.
  final int? width;

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  Future<void> _copy() async {
    if (!widget.copyEnabled) return;
    final text = exportToolCallSummary(
      widget.record,
      options: widget.copyOptions,
    );
    final report = await Clipboard.instance.writeWithReport(
      text,
      policy: widget.copyOptions.clipboardPolicy,
    );
    if (!mounted) return;
    widget.onCopy?.call(
      ToolCallCopyResult(record: widget.record, text: text, report: report),
    );
  }

  void _cancel() => widget.onCancel?.call();

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final canCancel = widget.onCancel != null && record.busy;
    final actions = <SemanticAction>{
      if (widget.copyEnabled) SemanticAction.copy,
      if (canCancel) SemanticAction.cancel,
    };
    final output = record.error ?? record.output;
    final formattedOutput = output == null
        ? null
        : _formatOutput(output, maxLength: widget.copyOptions.maxOutputLength);

    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_statusGlyph(record.status)} ${_sanitizeToolText(record.displayTitle)}'
          ' [${record.status.name}]',
          style: _styleForStatus(record.status),
        ),
        if (record.description != null)
          Text(
            _sanitizeToolText(record.description!),
            style: Theme.of(context).mutedStyle,
          ),
        if (record.arguments.isNotEmpty)
          Text('Args: ${_formatArguments(record.arguments)}'),
        if (formattedOutput != null)
          Text(
            '${record.error == null ? 'Output' : 'Error'}: ${formattedOutput.text}',
            style: record.error == null
                ? CellStyle.empty
                : const CellStyle(foreground: AnsiColor(9)),
          ),
        if (record.progressCurrent != null || record.progressTotal != null)
          Text(_progressText(record)),
        if (widget.copyEnabled || canCancel) ...[
          const SizedBox(height: 1),
          Row(
            children: [
              if (widget.copyEnabled)
                Button(
                  label: 'Copy',
                  variant: ButtonVariant.normal,
                  onPressed: () => unawaited(_copy()),
                ),
              if (widget.copyEnabled && canCancel) const SizedBox(width: 1),
              if (canCancel)
                Button(
                  label: 'Cancel',
                  variant: ButtonVariant.warning,
                  onPressed: _cancel,
                ),
            ],
          ),
        ],
      ],
    );

    if (widget.width != null) {
      body = SizedBox(width: widget.width, child: body);
    }

    return Semantics(
      role: SemanticRole.toolCall,
      label: record.displayTitle,
      value: record.status.name,
      busy: record.busy,
      validationError: record.error,
      actions: actions,
      onAction: (action) async {
        switch (action) {
          case SemanticAction.copy when widget.copyEnabled:
            await _copy();
          case SemanticAction.cancel when canCancel:
            _cancel();
          case _:
            return;
        }
      },
      state: SemanticState({
        'toolCallId': record.id,
        'toolName': record.name,
        'toolStatus': record.status.name,
        'argumentCount': record.arguments.length,
        'copyEnabled': widget.copyEnabled,
        'clipboardPolicy': widget.copyOptions.clipboardPolicy.name,
        'canCancel': canCancel,
        if (record.progressCurrent != null)
          'progressCurrent': record.progressCurrent,
        if (record.progressTotal != null) 'progressTotal': record.progressTotal,
        if (formattedOutput != null) ...{
          'outputSanitized': formattedOutput.sanitized,
          'outputTruncated': formattedOutput.truncated,
          'outputOriginalLength': formattedOutput.originalLength,
        },
        ...record.metadata,
      }),
      child: body,
    );
  }
}

final class _FormattedToolOutput {
  const _FormattedToolOutput({
    required this.text,
    required this.sanitized,
    required this.truncated,
    required this.originalLength,
  });

  final String text;
  final bool sanitized;
  final bool truncated;
  final int originalLength;
}

_FormattedToolOutput _formatOutput(String text, {required int? maxLength}) {
  final sanitized = _sanitizeToolText(text);
  final truncated = _truncateGraphemes(sanitized, maxLength);
  return _FormattedToolOutput(
    text: truncated,
    sanitized: sanitized != text,
    truncated: truncated != sanitized,
    originalLength: text.length,
  );
}

String _progressText(ToolCallRecord record) {
  final current = record.progressCurrent;
  final total = record.progressTotal;
  if (current != null && total != null) return 'Progress: $current / $total';
  if (current != null) return 'Progress: $current';
  return 'Progress: pending';
}

String _formatArguments(Map<String, Object?> arguments) {
  final parts = <String>[];
  for (final entry in arguments.entries) {
    final value = entry.value;
    parts.add('${_sanitizeToolText(entry.key)}=${_sanitizeToolText('$value')}');
  }
  return parts.join(' ');
}

String _sanitizeToolText(String original) {
  if (!_needsToolSanitization(original)) return original;
  return sanitizeForDisplay(original).replaceAll(_toolLineBreakPattern, ' ');
}

final _toolLineBreakPattern = RegExp(r'[\r\n\t]');

bool _needsToolSanitization(String text) {
  for (final codeUnit in text.codeUnits) {
    if (codeUnit == 0x1b ||
        codeUnit == 0x9b ||
        codeUnit == 0x9d ||
        codeUnit == 0x90 ||
        codeUnit == 0x98 ||
        codeUnit == 0x9e ||
        codeUnit == 0x9f ||
        codeUnit == 0x0a ||
        codeUnit == 0x0d ||
        codeUnit == 0x09) {
      return true;
    }
  }
  return false;
}

String _truncateGraphemes(String text, int? maxLineLength) {
  if (maxLineLength == null) return text;
  if (maxLineLength == 0) return '';
  final characters = text.characters;
  if (characters.length <= maxLineLength) return text;
  return characters.take(maxLineLength).toString();
}

// A scannable, color-independent status marker (matches the TaskGraph set).
String _statusGlyph(ToolCallStatus status) {
  return switch (status) {
    ToolCallStatus.queued => '[ ]',
    ToolCallStatus.running => '[>]',
    ToolCallStatus.succeeded => '[x]',
    ToolCallStatus.failed => '[!]',
    ToolCallStatus.cancelled => '[-]',
  };
}

CellStyle _styleForStatus(ToolCallStatus status) {
  return switch (status) {
    ToolCallStatus.queued => const CellStyle(dim: true),
    ToolCallStatus.running => const CellStyle(foreground: AnsiColor(11)),
    ToolCallStatus.succeeded => const CellStyle(foreground: AnsiColor(10)),
    ToolCallStatus.failed => const CellStyle(foreground: AnsiColor(9)),
    ToolCallStatus.cancelled => const CellStyle(foreground: AnsiColor(8)),
  };
}
