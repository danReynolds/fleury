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
        if (rows is int && rows > 0) 'maximum': rows - 1,
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
      final n = _coerceNum(value);
      if (n == null) return 'expected a number';
      return _rangeError(n, schema);
    case 'integer':
      if (!_isIntegerLike(value)) return 'expected an integer';
      return _rangeError(_coerceNum(value)!, schema);
    case 'boolean':
      return _isBoolLike(value) ? null : 'expected a boolean (true or false)';
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

// The coercion below MIRRORS fleury_widgets' semantic_coercion.dart so validation
// accepts exactly what the widgets accept — never rejecting a value that would in
// fact apply (a `bool` for a number, the many boolean spellings, any
// DateTime-parseable date). The MCP layer is widget-agnostic and can't import
// those helpers, so the rules are restated here; keep them in sync.

num? _coerceNum(Object? v) {
  if (v is num) return v;
  if (v is bool) return v ? 1 : 0;
  if (v is String) return num.tryParse(v.trim());
  return null;
}

bool _isIntegerLike(Object? v) {
  if (v is int || v is bool) return true;
  if (v is double) return v == v.roundToDouble();
  if (v is String) return int.tryParse(v.trim()) != null;
  return false;
}

bool _isBoolLike(Object? v) {
  if (v is bool || v is num) return true;
  if (v is String) {
    switch (v.trim().toLowerCase()) {
      case 'true' ||
          '1' ||
          'yes' ||
          'on' ||
          'checked' ||
          'enabled' ||
          'false' ||
          '0' ||
          'no' ||
          'off' ||
          'unchecked' ||
          'disabled':
        return true;
    }
  }
  return false;
}

String? _rangeError(num n, Map<String, Object?> schema) {
  final min = schema['minimum'];
  final max = schema['maximum'];
  if (min is num && n < min) return 'below the minimum ($min)';
  if (max is num && n > max) return 'above the maximum ($max)';
  return null;
}

String? _dateError(Object? value, Map<String, Object?> schema) {
  final parsed = value is String ? DateTime.tryParse(value.trim()) : null;
  if (parsed == null) return 'expected a date (ISO YYYY-MM-DD)';
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
