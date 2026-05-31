import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _screen(FleuryTester tester, {int cols = 16, int rows = 8}) =>
    tester.renderToString(size: CellSize(cols, rows), emptyMark: ' ');

/// First (col,row) where [needle] appears in the rendered buffer, or null.
({int col, int row})? _find(
  FleuryTester tester,
  String needle, {
  int cols = 16,
  int rows = 8,
}) {
  final buf = tester.render(size: CellSize(cols, rows));
  for (var r = 0; r < rows; r++) {
    final sb = StringBuffer();
    for (var c = 0; c < cols; c++) {
      sb.write(buf.atColRow(c, r).grapheme ?? ' ');
    }
    final idx = sb.toString().indexOf(needle);
    if (idx >= 0) return (col: idx, row: r);
  }
  return null;
}

const _options = <SelectOption<String>>[
  SelectOption(value: 'red', label: 'Red'),
  SelectOption(value: 'green', label: 'Green'),
  SelectOption(value: 'blue', label: 'Blue'),
];

/// Controlled host: holds the value and reports picks.
class _Host extends StatefulWidget {
  const _Host({this.initial, this.onPick, this.options = _options});
  final String? initial;
  final void Function(String)? onPick;
  final List<SelectOption<String>> options;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String? value;
  @override
  void initState() {
    super.initState();
    value = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Select<String>(
      autofocus: true,
      value: value,
      options: widget.options,
      onChanged: (v) {
        setState(() => value = v);
        widget.onPick?.call(v);
      },
    );
  }
}

void main() {
  group('Select', () {
    testWidgets('collapsed shows the placeholder when no value', (tester) {
      tester.pumpWidget(const _Host());
      expect(_screen(tester).contains('Select…'), isTrue);
      expect(_screen(tester).contains('Red'), isFalse, reason: 'closed');
    });

    testWidgets('collapsed shows the current value label', (tester) {
      tester.pumpWidget(const _Host(initial: 'green'));
      final out = _screen(tester);
      expect(out.contains('Green'), isTrue);
      expect(out.contains('▾'), isTrue);
    });

    testWidgets('Enter opens the list anchored below the trigger', (tester) {
      tester.pumpWidget(const _Host());
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      final out = _screen(tester);
      expect(out.contains('Red'), isTrue);
      expect(out.contains('Green'), isTrue);
      expect(out.contains('Blue'), isTrue);
    });

    testWidgets('Down then Enter picks the next option and closes', (tester) {
      String? picked;
      tester.pumpWidget(_Host(initial: 'red', onPick: (v) => picked = v));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // -> Green
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // pick
      expect(picked, 'green');
      final out = _screen(tester);
      expect(out.contains('Green'), isTrue, reason: 'trigger shows new value');
      // List is closed: Blue (an unselected option) is gone.
      expect(out.contains('Blue'), isFalse);
    });

    testWidgets('Esc closes without changing the value', (tester) {
      String? picked;
      tester.pumpWidget(_Host(initial: 'red', onPick: (v) => picked = v));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
      expect(picked, isNull);
      final out = _screen(tester);
      expect(out.contains('Red'), isTrue, reason: 'value unchanged');
      expect(out.contains('Blue'), isFalse, reason: 'list closed');
    });

    testWidgets('the open list marks the currently-selected option', (tester) {
      tester.pumpWidget(const _Host(initial: 'green'));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(_screen(tester).contains('• Green'), isTrue);
    });

    testWidgets('navigation skips a disabled option', (tester) {
      String? picked;
      tester.pumpWidget(
        _Host(
          initial: 'red',
          onPick: (v) => picked = v,
          options: const [
            SelectOption(value: 'red', label: 'Red'),
            SelectOption(value: 'green', label: 'Green', enabled: false),
            SelectOption(value: 'blue', label: 'Blue'),
          ],
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open at Red
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // skip Green
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(picked, 'blue');
    });

    testWidgets('a click opens the list and a click picks an option', (tester) {
      String? picked;
      tester.pumpWidget(_Host(initial: 'red', onPick: (v) => picked = v));

      // Click the trigger (row 0) to open.
      final trigger = _find(tester, 'Red')!;
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: trigger.col,
          row: trigger.row,
        ),
      );
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: trigger.col,
          row: trigger.row,
        ),
      );
      expect(_screen(tester).contains('Blue'), isTrue, reason: 'opened');

      // Click the Blue option.
      final blue = _find(tester, 'Blue')!;
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: blue.col,
          row: blue.row,
        ),
      );
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: blue.col,
          row: blue.row,
        ),
      );
      expect(picked, 'blue');
    });
  });
}
