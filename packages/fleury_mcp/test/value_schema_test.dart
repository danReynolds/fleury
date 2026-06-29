// Unit tests for the WS-9 typed-affordance normalizer + validator.

import 'package:fleury/fleury_host.dart';
import 'package:fleury_mcp/src/value_schema.dart';
import 'package:test/test.dart';

SemanticInspectionNode _node(
  String role, {
  List<String> actions = const <String>['setValue'],
  Map<String, Object?> state = const <String, Object?>{},
}) => SemanticInspectionNode.fromJson(<String, Object?>{
  'id': 'n',
  'role': role,
  'actions': actions,
  'state': state,
});

void main() {
  group('deriveValueSchema', () {
    test('numeric spinButton/slider → number with min/max/step', () {
      final s = deriveValueSchema(
        _node('spinButton', state: {'min': 0, 'max': 10, 'step': 2}),
      );
      expect(s, {'type': 'number', 'minimum': 0, 'maximum': 10, 'step': 2});
      expect(
        deriveValueSchema(_node('slider', state: {'min': 1, 'max': 5})),
        {'type': 'number', 'minimum': 1, 'maximum': 5},
      );
    });

    test('checkbox/toggle → boolean', () {
      expect(deriveValueSchema(_node('checkbox')), {'type': 'boolean'});
      expect(deriveValueSchema(_node('toggle')), {'type': 'boolean'});
    });

    test('datePicker → ISO date string with range', () {
      final s = deriveValueSchema(
        _node(
          'datePicker',
          state: {'firstDate': '2020-01-01', 'lastDate': '2020-12-31'},
        ),
      );
      expect(s, {
        'type': 'string',
        'format': 'date',
        'pattern': 'YYYY-MM-DD',
        'minimum': '2020-01-01',
        'maximum': '2020-12-31',
      });
    });

    test('table → integer row index bounded by row count', () {
      final s = deriveValueSchema(
        _node('table', state: {'collectionRowCount': 50}),
      );
      expect(s!['type'], 'integer');
      expect(s['minimum'], 0);
      expect(s['maximum'], 49);
    });

    test('select trigger (button + setValue + options) → enum', () {
      final s = deriveValueSchema(
        _node(
          'button',
          state: {
            'options': [
              {'label': 'Red', 'value': 'r'},
              {'label': 'Green', 'value': 'g'},
            ],
          },
        ),
      );
      expect(s!['type'], 'enum');
      expect(s['options'], hasLength(2));
    });

    test('null when not settable, or a plain button with no options', () {
      expect(deriveValueSchema(_node('spinButton', actions: ['activate'])),
          isNull);
      expect(deriveValueSchema(_node('button')), isNull); // no options
    });

    test('schema keys never contain redaction-trigger substrings', () {
      // value/text/token/query/secret/password would be swallowed on a redacted
      // node — guard against a future key regression.
      for (final s in <Map<String, Object?>?>[
        deriveValueSchema(_node('spinButton', state: {'min': 0, 'max': 9})),
        deriveValueSchema(_node('datePicker', state: {'firstDate': '2020-01-01'})),
        deriveValueSchema(_node('table', state: {'collectionRowCount': 3})),
        deriveValueSchema(_node('checkbox')),
      ]) {
        for (final key in s!.keys) {
          final lower = key.toLowerCase();
          for (final bad in ['value', 'text', 'token', 'query', 'secret',
              'password']) {
            expect(lower.contains(bad), isFalse, reason: '"$key" trips redaction');
          }
        }
      }
    });
  });

  group('validateValueForSchema', () {
    test('number: range + type (mirrors widget coercion)', () {
      final s = {'type': 'number', 'minimum': 0, 'maximum': 10};
      expect(validateValueForSchema(s, 5), isNull);
      expect(validateValueForSchema(s, '5'), isNull); // numeric string
      expect(validateValueForSchema(s, true), isNull); // bool → 1, like widget
      expect(validateValueForSchema(s, 11), contains('above the maximum'));
      expect(validateValueForSchema(s, -1), contains('below the minimum'));
      expect(validateValueForSchema(s, 'abc'), contains('expected a number'));
    });

    test('integer: rejects fractional', () {
      final s = {'type': 'integer', 'minimum': 0, 'maximum': 9};
      expect(validateValueForSchema(s, 3), isNull);
      expect(validateValueForSchema(s, 3.5), contains('expected an integer'));
      expect(validateValueForSchema(s, 10), contains('above the maximum'));
    });

    test('boolean (mirrors widget spellings, not just true/false)', () {
      const s = {'type': 'boolean'};
      expect(validateValueForSchema(s, true), isNull);
      expect(validateValueForSchema(s, 'false'), isNull);
      expect(validateValueForSchema(s, 'yes'), isNull); // widget spelling
      expect(validateValueForSchema(s, 'on'), isNull);
      expect(validateValueForSchema(s, 1), isNull); // num, like widget
      expect(validateValueForSchema(s, 'maybe'), contains('expected a boolean'));
    });

    test('date: format + range', () {
      final s = {
        'type': 'string',
        'format': 'date',
        'minimum': '2020-01-01',
        'maximum': '2020-12-31',
      };
      expect(validateValueForSchema(s, '2020-06-15'), isNull);
      // A non-ISO but DateTime-parseable form is accepted, like the widget.
      expect(validateValueForSchema(s, '2020-06-15T09:00:00'), isNull);
      expect(validateValueForSchema(s, '2019-12-31'), contains('earliest'));
      expect(validateValueForSchema(s, '2021-01-01'), contains('latest'));
      expect(validateValueForSchema(s, 'not a date'), contains('date'));
    });

    test('enum: matches label or value, case-insensitive', () {
      final s = {
        'type': 'enum',
        'options': [
          {'label': 'Red', 'value': 'r'},
          {'label': 'Green', 'value': 'g'},
        ],
      };
      expect(validateValueForSchema(s, 'Red'), isNull);
      expect(validateValueForSchema(s, 'green'), isNull); // label, ci
      expect(validateValueForSchema(s, 'r'), isNull); // value
      expect(validateValueForSchema(s, 'Blue'), contains('not one of'));
    });
  });
}
