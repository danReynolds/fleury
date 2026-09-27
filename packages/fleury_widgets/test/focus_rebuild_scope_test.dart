// A focus move rebuilds the controls whose focus changed, not every
// focusable control in the tree. The library's controls listen to their own
// focus node rather than depending on the whole FocusManager.
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _options = [
  SelectOption(value: 'red', label: 'red'),
  SelectOption(value: 'teal', label: 'teal'),
];

Iterable<TextCompletionOption> _provider(TextCompletionRequest request) =>
    const [TextCompletionOption(label: 'checkout')];

List<Widget> _controls(int i) => [
  Select<String>(
    autofocus: i == 0,
    value: 'red',
    options: _options,
    onChanged: (_) {},
  ),
  MultiSelect<String>(
    values: const {'red'},
    options: _options,
    onChanged: (_) {},
  ),
  Stepper(value: i, onChanged: (_) {}),
  ColorPicker(value: const AnsiColor(1), onChanged: (_) {}),
  DatePicker(value: DateTime(2024, 3, 15), onChanged: (_) {}),
  const Autocomplete(options: ['apple']),
  CompletionTextInput(provider: _provider),
];

void main() {
  testWidgets('a focus move rebuilds only the controls it concerns', (tester) {
    tester.pumpWidget(
      FocusTraversalGroup(
        child: Column(
          children: [
            for (var i = 0; i < 4; i++)
              for (final control in _controls(i))
                SizedBox(height: 1, width: 30, child: control),
          ],
        ),
      ),
    );
    tester.render(size: const CellSize(40, 40));
    tester.owner.flushBuild();

    final rebuilt = <int>[];
    for (var move = 0; move < 7; move++) {
      tester.focusManager.focusNext();
      rebuilt.add(tester.owner.flushBuild().rebuiltElementCount);
    }

    for (final count in rebuilt) {
      expect(count, lessThan(12), reason: 'rebuilt per move: $rebuilt');
    }
  });
}
