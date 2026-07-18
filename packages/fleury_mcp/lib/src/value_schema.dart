// Typed affordances (WS-9): a normalized value-input schema for each settable
// semantic node, plus validation of an incoming set_value against it.
//
// Each widget already emits its constraints into the node's free-form `state`
// (a Stepper's min/max/step, a Select's options, a DatePicker's date range).
// This normalizes those per-widget keys into ONE documented `valueSchema` block
// the agent can rely on, and validates a value against it BEFORE dispatch — so an
// out-of-domain set_value fails by contract with the accepted domain spelled out,
// instead of the silent clamp/no-op the widget would do.
//
// Schema key names deliberately avoid the redaction-trigger substrings
// (value/text/token/query/secret/password) so a schema is never swallowed when a
// node is redacted — hence `minimum`/`maximum`, not `minValue`/`maxValue`.

import 'package:fleury/fleury_core.dart';

/// Derives the value schema for [node], or null when it does not advertise
/// setValue or carries no known typed domain.
Map<String, Object?>? deriveValueSchema(SemanticInspectionNode node) {
  if (!node.actions.contains(SemanticAction.setValue.name)) return null;
  final state = node.state;
  switch (node.role) {
    case 'spinButton':
    case 'slider':
      return <String, Object?>{
        'type': 'number',
        if (state['min'] is num) 'minimum': state['min'],
        if (state['max'] is num) 'maximum': state['max'],
        if (state['step'] is num) 'step': state['step'],
        // A 2-handle range slider sets only its *active* handle — the [min,max]
        // domain alone reads like a single-value control, so spell it out.
        if (node.role == 'slider' && state['activeHandle'] != null)
          'description':
              'moves the active handle of a range (see state.activeHandle / '
              'lowValue / highValue); the other handle constrains it',
      };
    case 'checkbox':
    case 'toggle':
      return <String, Object?>{'type': 'boolean'};
    case 'datePicker':
      return <String, Object?>{
        'type': 'string',
        'format': 'date',
        'pattern': 'YYYY-MM-DD',
        if (state['firstDate'] is String) 'minimum': state['firstDate'],
        if (state['lastDate'] is String) 'maximum': state['lastDate'],
      };
    case 'textField':
    case 'textArea':
      return <String, Object?>{'type': 'string'};
    case 'table':
      final rows = state['collectionRowCount'];
      return <String, Object?>{
        'type': 'integer',
        'description':
            'a 0-based row index; jumps a windowed grid so that row scrolls in',
        'minimum': 0,
        // When the row count is known, bound it — including rows==0 (an empty
        // grid → maximum -1, so every index is rejected rather than silently
        // clamped to a no-op). Only an unknown/non-int count leaves it open.
        if (rows is int) 'maximum': rows - 1,
      };
    case 'button':
      // A Select trigger is a button that advertises setValue and lists its
      // settable domain under state.options (label + stringified value). Emit
      // the enum even when the list is EMPTY (an all-disabled Select still
      // advertises setValue) so validation rejects it rather than letting an
      // unguarded value through to a silent no-op. A plain button with setValue
      // but no options key (a custom widget) gets no schema — domain unknown.
      final options = state['options'];
      if (options is List) {
        return <String, Object?>{'type': 'enum', 'options': options};
      }
      return null;
    default:
      return null;
  }
}

/// Validates [value] against a [schema] from [deriveValueSchema]. Returns a
/// short human-readable rejection reason, or null when the value is in-domain.
/// Mirrors what each widget actually accepts, so a rejection here means the
/// widget would have silently no-op'd.
String? validateValueForSchema(Map<String, Object?> schema, Object? value) {
  switch (schema['type']) {
    case 'number':
      final n = coerceSemanticNum(value);
      if (n == null) return 'expected a number';
      return _numberDomainError(n, schema);
    case 'integer':
      // coerceSemanticInt rejects a non-integral number (2.5) by returning null,
      // so an off-target index/step can't slip through as "integer-ish".
      final n = coerceSemanticInt(value);
      if (n == null) return 'expected an integer';
      return _numberDomainError(n.toDouble(), schema);
    case 'boolean':
      return coerceSemanticBool(value) != null
          ? null
          : 'expected a boolean (true or false)';
    case 'string':
      if (schema['format'] == 'date') return _dateError(value, schema);
      return null;
    case 'enum':
      final options = schema['options'];
      if (options is! List) return null;
      if (options.isEmpty) return 'no options are currently available to set';
      final wanted = value?.toString().trim().toLowerCase() ?? '';
      for (final o in options) {
        if (o is Map &&
            ('${o['label']}'.toLowerCase() == wanted ||
                '${o['value']}'.toLowerCase() == wanted)) {
          return null;
        }
      }
      final labels = <Object?>[
        for (final o in options)
          if (o is Map) o['label'],
      ];
      return 'not one of the accepted options: ${labels.join(', ')}';
    default:
      return null;
  }
}

// Numeric/bool coercion uses fleury core's shared coerceSemantic* helpers — the
// SAME ones the widgets apply — so validation accepts exactly what the widget
// would, with no second copy of the rules to drift. (Date handling stays here,
// below, since it layers the YYYY-MM-DD contract on top.)

String? _numberDomainError(num n, Map<String, Object?> schema) {
  final min = schema['minimum'];
  final max = schema['maximum'];
  if (min is num && n < min) return 'below the minimum ($min)';
  if (max is num && n > max) return 'above the maximum ($max)';
  // A stepped control (Stepper/spinButton) only lands on min + k·step; an
  // off-grid value would otherwise pass and the widget would apply it un-snapped,
  // reaching a state the keyboard can't produce. Reject it by contract instead.
  final step = schema['step'];
  if (step is num && step > 0) {
    final base = min is num ? min : 0;
    final k = (n - base) / step;
    if ((k - k.roundToDouble()).abs() > 1e-9) {
      return 'not on the step grid (step $step from $base)';
    }
  }
  return null;
}

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String? _dateError(Object? value, Map<String, Object?> schema) {
  final text = value is String ? value.trim() : null;
  if (text == null) return 'expected a date (ISO YYYY-MM-DD)';
  // The advertised contract is date-only. Reject a full date-time rather than
  // silently discarding its time component, so the agent's value means what the
  // schema says it does.
  if (!_isoDate.hasMatch(text)) return 'expected a date in YYYY-MM-DD form';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return 'expected a date (ISO YYYY-MM-DD)';
  // DateTime.tryParse NORMALIZES an out-of-range calendar date rather than
  // failing (2026-02-31 → 2026-03-03, month 13 → next January), so a
  // regex-shaped but impossible date would otherwise validate in-domain and the
  // widget would silently apply a DIFFERENT day. Reject anything that doesn't
  // round-trip to the exact components the agent sent — the regex fixes their
  // positions, so this reads them back off `text` directly.
  final year = int.parse(text.substring(0, 4));
  final month = int.parse(text.substring(5, 7));
  final dayOfMonth = int.parse(text.substring(8, 10));
  if (parsed.year != year ||
      parsed.month != month ||
      parsed.day != dayOfMonth) {
    return 'not a real calendar date (e.g. 2026-02-31 does not exist)';
  }
  final day = DateTime(parsed.year, parsed.month, parsed.day);
  final min = schema['minimum'];
  final max = schema['maximum'];
  if (min is String) {
    final earliest = DateTime.tryParse(min);
    if (earliest != null && day.isBefore(earliest)) {
      return 'before the earliest allowed date ($min)';
    }
  }
  if (max is String) {
    final latest = DateTime.tryParse(max);
    if (latest != null && day.isAfter(latest)) {
      return 'after the latest allowed date ($max)';
    }
  }
  return null;
}
