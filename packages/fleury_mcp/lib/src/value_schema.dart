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
      // settable domain under state.options (label + stringified value).
      final options = state['options'];
      if (options is List && options.isNotEmpty) {
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
      final n = _asNum(value);
      if (n == null) return 'expected a number';
      return _rangeError(n, schema);
    case 'integer':
      final n = _asNum(value);
      if (n == null || n != n.truncateToDouble()) return 'expected an integer';
      return _rangeError(n, schema);
    case 'boolean':
      if (value is bool) return null;
      if (value is String && (value == 'true' || value == 'false')) return null;
      return 'expected a boolean (true or false)';
    case 'string':
      if (schema['format'] == 'date') return _dateError(value, schema);
      return null;
    case 'enum':
      final options = schema['options'];
      if (options is! List || options.isEmpty) return null;
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

num? _asNum(Object? v) =>
    v is num ? v : (v is String ? num.tryParse(v.trim()) : null);

String? _rangeError(num n, Map<String, Object?> schema) {
  final min = schema['minimum'];
  final max = schema['maximum'];
  if (min is num && n < min) return 'below the minimum ($min)';
  if (max is num && n > max) return 'above the maximum ($max)';
  return null;
}

String? _dateError(Object? value, Map<String, Object?> schema) {
  final s = value?.toString() ?? '';
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
    return 'expected an ISO date (YYYY-MM-DD)';
  }
  final min = schema['minimum'];
  final max = schema['maximum'];
  if (min is String && s.compareTo(min) < 0) {
    return 'before the earliest allowed date ($min)';
  }
  if (max is String && s.compareTo(max) > 0) {
    return 'after the latest allowed date ($max)';
  }
  return null;
}
