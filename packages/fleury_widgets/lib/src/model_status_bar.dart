import 'package:fleury/fleury_core.dart';

/// Protocol-neutral lifecycle state for a model-backed workflow.
enum ModelRuntimeStatus {
  idle,
  connecting,
  ready,
  streaming,
  busy,
  degraded,
  error,
  offline,
}

/// Token and context-window usage for [TokenMeter] and [ModelStatusBar].
final class TokenUsage {
  const TokenUsage({
    this.input = 0,
    this.output = 0,
    this.cached = 0,
    this.contextUsed,
    this.contextLimit,
  }) : assert(input >= 0),
       assert(output >= 0),
       assert(cached >= 0),
       assert(contextUsed == null || contextUsed >= 0),
       assert(contextLimit == null || contextLimit >= 0);

  /// Input-token count reported for the current workflow.
  final int input;

  /// Output-token count reported for the current workflow.
  final int output;

  /// Cached-token count reported separately from [input] and [output].
  final int cached;

  /// Current context-window occupancy, when known explicitly.
  ///
  /// When absent, [effectiveContextUsed] falls back to a nonzero [total]; an
  /// all-zero usage remains unknown.
  final int? contextUsed;

  /// Maximum context-window capacity, when known.
  final int? contextLimit;

  int get total => input + output + cached;

  int? get effectiveContextUsed {
    if (contextUsed != null) return contextUsed;
    return total == 0 ? null : total;
  }

  int? get contextRemaining {
    final used = effectiveContextUsed;
    final limit = contextLimit;
    if (used == null || limit == null) return null;
    return limit - used < 0 ? 0 : limit - used;
  }

  double? get contextRatio {
    final used = effectiveContextUsed;
    final limit = contextLimit;
    if (used == null || limit == null || limit == 0) return null;
    return used / limit;
  }
}

/// Protocol-neutral model/runtime status used by [ModelStatusBar].
final class ModelStatusInfo {
  const ModelStatusInfo({
    required this.model,
    this.provider,
    this.status = ModelRuntimeStatus.ready,
    this.mode,
    this.detail,
    this.latency,
    this.queueDepth,
    this.tokenUsage = const TokenUsage(),
    this.error,
    this.metadata = const <String, Object?>{},
  });

  /// Model name or identifier displayed by the status bar.
  final String model;

  /// Optional provider name displayed before [model].
  final String? provider;

  /// Current lifecycle state used for text, color, and busy semantics.
  final ModelRuntimeStatus status;

  /// Optional operating mode appended to the status summary.
  final String? mode;

  /// Optional short status detail appended to the summary.
  final String? detail;

  /// Optional latency measurement displayed in milliseconds.
  final Duration? latency;

  /// Optional number of queued work items displayed in the summary.
  final int? queueDepth;

  /// Token and context-window metrics exposed by the status bar.
  final TokenUsage tokenUsage;

  /// Optional error exposed as the status bar's semantic validation error.
  final String? error;

  /// App-specific values merged into the status bar's semantic state.
  final Map<String, Object?> metadata;

  bool get busy =>
      status == ModelRuntimeStatus.connecting ||
      status == ModelRuntimeStatus.streaming ||
      status == ModelRuntimeStatus.busy;
}

/// A one-line context-window meter: used/limit token counts, a utilization
/// bar, and a percentage (`Context: 78k/200k [####......] 39%`). Nearing or
/// exceeding the limit is announced in words — `NEAR LIMIT`, `OVER LIMIT` —
/// not by color alone, so the state reads in monochrome.
class TokenMeter extends StatelessWidget {
  const TokenMeter({
    super.key,
    required this.usage,
    this.label = 'Context',
    this.width = 10,
    this.warningThreshold = 0.8,
    this.errorThreshold = 0.95,
  }) : assert(width >= 0),
       assert(warningThreshold >= 0),
       assert(errorThreshold >= warningThreshold);

  /// Token and context-window metrics to display.
  final TokenUsage usage;

  /// Visible and semantic label placed before the usage value.
  final String label;

  /// Number of cells used by the utilization bar; zero hides the bar.
  final int width;

  /// Context-usage ratio at which the near-limit state begins.
  final double warningThreshold;

  /// Context-usage ratio at which the over-limit state begins.
  final double errorThreshold;

  @override
  Widget build(BuildContext context) {
    final used = usage.effectiveContextUsed;
    final limit = usage.contextLimit;
    final ratio = usage.contextRatio;
    final percent = ratio == null ? null : (ratio * 100).round();
    final overLimit = ratio != null && ratio >= errorThreshold;
    final nearLimit =
        ratio != null && ratio >= warningThreshold && ratio < errorThreshold;
    final displayLabel = _sanitizeStatusText(label);
    // A text status pairs with the color so "near/over limit" reads in
    // monochrome (Cursor / Copilot surface the same as words, not color alone).
    final statusSuffix = overLimit
        ? '  OVER LIMIT'
        : nearLimit
        ? '  NEAR LIMIT'
        : '';
    final text =
        _tokenText(displayLabel, usage, width: width, percent: percent) +
        statusSuffix;

    final Widget meter = Semantics(
      role: SemanticRole.tokenMeter,
      label: displayLabel,
      value: used == null
          ? null
          : limit == null
          ? used
          : '$used/$limit',
      state: SemanticState({
        'tokenInput': usage.input,
        'tokenOutput': usage.output,
        'tokenCached': usage.cached,
        'tokenTotal': usage.total,
        'contextUsed': ?used,
        'contextLimit': ?limit,
        'contextRemaining': ?usage.contextRemaining,
        'contextRatioPercent': ?percent,
        'contextNearLimit': nearLimit,
        'contextOverLimit': overLimit,
        'warningThresholdPercent': (warningThreshold * 100).round(),
        'errorThresholdPercent': (errorThreshold * 100).round(),
      }),
      child: Text(
        text,
        style: _tokenStyle(context, nearLimit: nearLimit, overLimit: overLimit),
        softWrap: false,
        allowSelect: false,
      ),
    );
    // styled component, not selectable text
    return SelectionArea.disabled(child: meter);
  }
}

/// A one-line status bar for the active model: provider/name, lifecycle
/// state, and — when known — mode, latency, and queue depth, with a
/// [TokenMeter] beside it by default. The line recolors as the runtime moves
/// between states (connecting, ready, streaming, degraded, error).
class ModelStatusBar extends StatelessWidget {
  const ModelStatusBar({
    super.key,
    required this.info,
    this.label = 'Model status',
    this.showTokenMeter = true,
    this.tokenMeterWidth = 10,
  });

  /// Model, lifecycle, and token state to present.
  final ModelStatusInfo info;

  /// Semantic label for the complete status bar.
  final String label;

  /// Whether to show a [TokenMeter] beside the model summary.
  final bool showTokenMeter;

  /// Number of cells used by the optional token meter's bar.
  final int tokenMeterWidth;

  @override
  Widget build(BuildContext context) {
    final model = _sanitizeStatusText(info.model);
    final provider = info.provider == null
        ? null
        : _sanitizeStatusText(info.provider!);
    final mode = info.mode == null ? null : _sanitizeStatusText(info.mode!);
    final detail = info.detail == null
        ? null
        : _sanitizeStatusText(info.detail!);
    final error = info.error == null ? null : _sanitizeStatusText(info.error!);
    final latencyMs = info.latency?.inMilliseconds;
    final summary = _modelSummary(
      model: model,
      provider: provider,
      status: info.status,
      mode: mode,
      detail: detail,
      latencyMs: latencyMs,
      queueDepth: info.queueDepth,
    );

    final Widget bar = Semantics(
      role: SemanticRole.modelStatus,
      label: _sanitizeStatusText(label),
      value: info.status.name,
      busy: info.busy,
      validationError: error,
      state: SemanticState({
        'modelName': model,
        'modelStatus': info.status.name,
        'modelProvider': ?provider,
        'modelMode': ?mode,
        'modelLatencyMs': ?latencyMs,
        'modelQueueDepth': ?info.queueDepth,
        ..._tokenState(info.tokenUsage),
        ...info.metadata,
      }),
      child: Row(
        children: [
          Text(
            summary,
            style: _modelStyle(context, info.status),
            softWrap: false,
            allowSelect: false,
          ),
          if (showTokenMeter) ...[
            const Text('  ', allowSelect: false),
            TokenMeter(usage: info.tokenUsage, width: tokenMeterWidth),
          ],
        ],
      ),
    );
    // styled component, not selectable text
    return SelectionArea.disabled(child: bar);
  }
}

Map<String, Object?> _tokenState(TokenUsage usage) {
  final used = usage.effectiveContextUsed;
  final limit = usage.contextLimit;
  final ratio = usage.contextRatio;
  return <String, Object?>{
    'tokenInput': usage.input,
    'tokenOutput': usage.output,
    'tokenCached': usage.cached,
    'tokenTotal': usage.total,
    'contextUsed': ?used,
    'contextLimit': ?limit,
    'contextRemaining': ?usage.contextRemaining,
    'contextRatioPercent': ?(ratio == null ? null : (ratio * 100).round()),
  };
}

String _modelSummary({
  required String model,
  required ModelRuntimeStatus status,
  required String? provider,
  required String? mode,
  required String? detail,
  required int? latencyMs,
  required int? queueDepth,
}) {
  final parts = <String>[
    if (provider == null) model else '$provider/$model',
    status.name,
    ?mode,
    if (latencyMs != null) '${latencyMs}ms',
    if (queueDepth != null) 'q$queueDepth',
    ?detail,
  ];
  return 'Model: ${parts.join(' ')}';
}

String _tokenText(
  String label,
  TokenUsage usage, {
  required int width,
  required int? percent,
}) {
  final used = usage.effectiveContextUsed;
  final limit = usage.contextLimit;
  final usageText = used == null
      ? '${_formatTokenCount(usage.total)} tok'
      : limit == null
      ? _formatTokenCount(used)
      : '${_formatTokenCount(used)}/${_formatTokenCount(limit)}';
  final bar = _bar(usage.contextRatio, width);
  final percentText = percent == null ? '' : ' $percent%';
  return '$label: $usageText$bar$percentText';
}

String _bar(double? ratio, int width) {
  if (ratio == null || width == 0) return '';
  final clamped = ratio < 0
      ? 0.0
      : ratio > 1
      ? 1.0
      : ratio;
  final filled = (clamped * width).round();
  final empty = width - filled;
  return ' [${List.filled(filled, '#').join()}${List.filled(empty, '.').join()}]';
}

String _formatTokenCount(int value) {
  if (value.abs() >= 1000000) {
    final formatted = (value / 1000000).toStringAsFixed(1);
    return '${_trimTrailingZero(formatted)}m';
  }
  if (value.abs() >= 1000) {
    final formatted = (value / 1000).toStringAsFixed(1);
    return '${_trimTrailingZero(formatted)}k';
  }
  return value.toString();
}

String _trimTrailingZero(String value) {
  if (value.endsWith('.0')) return value.substring(0, value.length - 2);
  return value;
}

String _sanitizeStatusText(String text) => sanitizeForDisplay(text);

CellStyle _modelStyle(BuildContext context, ModelRuntimeStatus status) {
  final colors = Theme.of(context).colorScheme;
  return switch (status) {
    ModelRuntimeStatus.idle => Theme.of(context).mutedStyle,
    ModelRuntimeStatus.connecting => CellStyle(foreground: colors.warning),
    ModelRuntimeStatus.ready => CellStyle(foreground: colors.success),
    ModelRuntimeStatus.streaming => CellStyle(foreground: colors.info),
    ModelRuntimeStatus.busy => CellStyle(foreground: colors.warning),
    ModelRuntimeStatus.degraded => CellStyle(foreground: colors.warning),
    ModelRuntimeStatus.error => CellStyle(foreground: colors.error, bold: true),
    ModelRuntimeStatus.offline => Theme.of(context).mutedStyle,
  };
}

CellStyle _tokenStyle(
  BuildContext context, {
  required bool nearLimit,
  required bool overLimit,
}) {
  final colors = Theme.of(context).colorScheme;
  if (overLimit) return CellStyle(foreground: colors.error, bold: true);
  if (nearLimit) return CellStyle(foreground: colors.warning);
  return Theme.of(context).mutedStyle;
}
