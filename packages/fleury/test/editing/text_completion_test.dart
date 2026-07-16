import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('TextCompletionOption', () {
    test('uses the label as the default replacement', () {
      const option = TextCompletionOption(label: 'checkout');

      expect(option.label, 'checkout');
      expect(option.replacement, 'checkout');
    });
  });

  group('TextCompletionController', () {
    test('opens with query, range, options, and selected index', () {
      final completions = TextCompletionController();

      completions.open(
        range: const TextRange(start: 4, end: 7),
        query: 'che',
        options: const [
          TextCompletionOption(label: 'checkout'),
          TextCompletionOption(label: 'cherry-pick'),
        ],
      );

      expect(completions.isOpen, isTrue);
      expect(completions.state.query, 'che');
      expect(completions.state.range, const TextRange(start: 4, end: 7));
      expect(completions.selectedIndex, 0);
      expect(completions.selectedOption?.label, 'checkout');
    });

    test('moves selection with wrapping', () {
      final completions = TextCompletionController()
        ..open(
          range: const TextRange.collapsed(0),
          options: const [
            TextCompletionOption(label: 'one'),
            TextCompletionOption(label: 'two'),
          ],
        );

      completions.moveSelection(1);
      expect(completions.selectedIndex, 1);

      completions.moveSelection(1);
      expect(completions.selectedIndex, 0);

      completions.moveSelection(-1);
      expect(completions.selectedIndex, 1);
    });

    test('accept applies selected replacement and closes', () {
      final completions = TextCompletionController()
        ..open(
          range: const TextRange(start: 4, end: 7),
          query: 'che',
          options: const [
            TextCompletionOption(
              label: 'checkout branch',
              replacement: 'checkout',
            ),
          ],
        );

      final next = completions.accept(TextEditingValue(text: 'git che'));

      expect(next?.text, 'git checkout');
      expect(next?.selection, const TextSelection.collapsed(offset: 12));
      expect(completions.isOpen, isFalse);
    });

    test('update keeps selected index in range', () {
      final completions = TextCompletionController()
        ..open(
          range: const TextRange(start: 0, end: 1),
          options: const [
            TextCompletionOption(label: 'one'),
            TextCompletionOption(label: 'two'),
          ],
          selectedIndex: 1,
        );

      completions.update(
        query: 't',
        options: const [TextCompletionOption(label: 'two')],
      );

      expect(completions.state.query, 't');
      expect(completions.selectedIndex, 0);
      expect(completions.selectedOption?.label, 'two');
    });

    test('dispose is idempotent and clears transient completion state', () {
      final completions = TextCompletionController()
        ..open(
          range: const TextRange(start: 0, end: 3),
          query: 'che',
          options: const [TextCompletionOption(label: 'checkout')],
        );

      completions.dispose();
      completions.dispose();

      expect(completions.isOpen, isFalse);
      expect(completions.state.active, isFalse);
      expect(completions.selectedIndex, isNull);
      expect(completions.selectedOption, isNull);
    });

    test('mutating after dispose throws a lifecycle error', () {
      final completions = TextCompletionController()..dispose();

      const message = 'TextCompletionController has been disposed.';
      expect(
        () => completions.open(range: const TextRange.collapsed(0)),
        _stateError(message),
      );
      expect(() => completions.update(query: 'x'), _stateError(message));
      expect(() => completions.close(), _stateError(message));
      expect(() => completions.select(0), _stateError(message));
      expect(() => completions.moveSelection(1), _stateError(message));
      expect(
        () => completions.accept(TextEditingValue(text: 'git che')),
        _stateError(message),
      );
    });
  });
}
