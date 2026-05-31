import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _line(FleuryTester tester, {int cols = 16}) {
  final buf = tester.render(size: CellSize(cols, 1));
  final sb = StringBuffer();
  for (var c = 0; c < cols; c++) {
    final cell = buf.atColRow(c, 0);
    sb.write(cell.role == CellRole.leading ? cell.grapheme! : ' ');
  }
  return sb.toString().trimRight();
}

void main() {
  group('Checkbox', () {
    testWidgets('renders state and label', (tester) {
      tester.pumpWidget(
        Checkbox(value: false, label: 'Wrap', onChanged: (_) {}),
      );
      expect(_line(tester), '[ ] Wrap');
      tester.pumpWidget(
        Checkbox(value: true, label: 'Wrap', onChanged: (_) {}),
      );
      expect(_line(tester), '[x] Wrap');
    });

    testWidgets('Enter toggles when focused', (tester) {
      bool? changed;
      tester.pumpWidget(
        Checkbox(value: false, autofocus: true, onChanged: (v) => changed = v),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(changed, isTrue);
    });

    testWidgets('does not toggle when unfocused', (tester) {
      var calls = 0;
      tester.pumpWidget(Checkbox(value: false, onChanged: (_) => calls++));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(calls, 0);
    });

    testWidgets('Space toggles when focused', (tester) {
      bool? changed;
      tester.pumpWidget(
        Checkbox(value: false, autofocus: true, onChanged: (v) => changed = v),
      );
      tester.type(' '); // Space arrives as inserted text
      expect(changed, isTrue);
    });
  });

  group('Toggle', () {
    testWidgets('renders the knob position', (tester) {
      tester.pumpWidget(Toggle(value: false, onChanged: (_) {}));
      expect(_line(tester), '[o ]');
      tester.pumpWidget(Toggle(value: true, onChanged: (_) {}));
      expect(_line(tester), '[ o]');
    });
  });

  group('Radio', () {
    testWidgets('selected when value == groupValue', (tester) {
      tester.pumpWidget(
        Radio<int>(value: 1, groupValue: 2, label: 'One', onChanged: (_) {}),
      );
      expect(_line(tester), '( ) One');
      tester.pumpWidget(
        Radio<int>(value: 1, groupValue: 1, label: 'One', onChanged: (_) {}),
      );
      expect(_line(tester), '(o) One');
    });

    testWidgets('Enter selects this radio value', (tester) {
      int? picked;
      tester.pumpWidget(
        Radio<int>(
          value: 3,
          groupValue: 1,
          autofocus: true,
          onChanged: (v) => picked = v,
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(picked, 3);
    });

    testWidgets('Space selects this radio value', (tester) {
      int? picked;
      tester.pumpWidget(
        Radio<int>(
          value: 3,
          groupValue: 1,
          autofocus: true,
          onChanged: (v) => picked = v,
        ),
      );
      tester.type(' ');
      expect(picked, 3);
    });
  });

  testWidgets('focused control shows a bold cue', (tester) {
    tester.pumpWidget(
      Checkbox(value: false, autofocus: true, onChanged: (_) {}),
    );
    final buf = tester.render(size: const CellSize(4, 1));
    expect(buf.atColRow(0, 0).style.bold, isTrue);
  });
}
