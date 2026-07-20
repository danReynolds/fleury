import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

class _Host extends StatefulWidget {
  const _Host({required this.picked, this.options});
  final List<String> picked;
  final List<RadioOption<String>>? options;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String value = 'a';
  @override
  Widget build(BuildContext context) {
    return RadioGroup<String>(
      value: value,
      autofocus: true,
      options:
          widget.options ??
          const <RadioOption<String>>[
            RadioOption(value: 'a', label: 'A'),
            RadioOption(value: 'b', label: 'B'),
            RadioOption(value: 'c', label: 'C'),
          ],
      onChanged: (v) {
        widget.picked.add(v);
        setState(() => value = v);
      },
    );
  }
}

void main() {
  testWidgets('arrows move and select the adjacent option, wrapping', (tester) {
    final picked = <String>[];
    tester.pumpWidget(_Host(picked: picked));
    tester.render(size: const CellSize(20, 4));

    tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // a -> b
    tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // b -> c
    tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // c -> a (wrap)
    tester.sendKey(const KeyEvent(KeyCode.arrowUp)); // a -> c (wrap)
    expect(picked, ['b', 'c', 'a', 'c']);
  });

  testWidgets('skips a disabled option', (tester) {
    final picked = <String>[];
    tester.pumpWidget(
      _Host(
        picked: picked,
        options: const <RadioOption<String>>[
          RadioOption(value: 'a', label: 'A'),
          RadioOption(value: 'b', label: 'B', enabled: false),
          RadioOption(value: 'c', label: 'C'),
        ],
      ),
    );
    tester.render(size: const CellSize(20, 4));
    tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // a -> c (skip b)
    expect(picked, ['c']);
  });

  testWidgets('autofocus falls back from a disabled selection', (tester) {
    tester.pumpWidget(
      RadioGroup<String>(
        value: 'a',
        autofocus: true,
        options: const <RadioOption<String>>[
          RadioOption(value: 'a', label: 'A', enabled: false),
          RadioOption(value: 'b', label: 'B'),
        ],
        onChanged: (_) {},
      ),
    );
    tester.render(size: const CellSize(20, 3));

    expect(tester.focusManager.focusedNode?.debugLabel, 'radio-1');
  });
}
