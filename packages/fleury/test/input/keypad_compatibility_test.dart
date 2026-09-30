// These tests intentionally cover the source-compatible migration aliases.
// ignore_for_file: deprecated_member_use_from_same_package
import 'package:fleury/fleury.dart';
import 'package:fleury/src/input/key_tables.dart';
import 'package:test/test.dart';

void main() {
  test(
    'legacy keypad bindings match canonical events by meaning and position',
    () {
      for (final entry in keypadMeaning.entries) {
        final alias = KeyCode.forSpecial(entry.key);
        final event = KeyEvent(
          entry.value,
          position: positionBySpecial[entry.key],
        );
        expect(event.matches(alias), isTrue, reason: entry.key.name);
        expect(alias.matches(event), isTrue, reason: entry.key.name);
        expect(KeyEvent(entry.value).matches(alias), isFalse);
      }
    },
  );
  test('decimal alias accepts a localized decimal but not keypad Delete', () {
    expect(
      const KeyEvent(
        KeyCode.char(','),
        position: KeyPosition.numpadDecimal,
      ).matches(KeyCode.keypadDecimal),
      isTrue,
    );
    expect(
      const KeyEvent(
        KeyCode.delete,
        position: KeyPosition.numpadDecimal,
      ).matches(KeyCode.keypadDecimal),
      isFalse,
    );
    expect(
      const KeyEvent(
        KeyCode.end,
        position: KeyPosition.numpad1,
      ).matches(KeyCode.keypad1),
      isFalse,
    );
    expect(
      KeySequence.parse('kp1').matches(
        const KeyEvent(KeyCode.char('1'), position: KeyPosition.numpad1),
      ),
      isTrue,
    );
  });
}
