import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

class _HostedSlider extends StatefulWidget {
  const _HostedSlider({
    required this.initial,
    required this.min,
    required this.max,
  });
  final (num, num) initial;
  final num min;
  final num max;
  static (num, num)? lastValues;
  @override
  State<_HostedSlider> createState() => _HostedSliderState();
}

class _HostedSliderState extends State<_HostedSlider> {
  late (num, num) _values = widget.initial;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 11,
      height: 1,
      child: RangeSlider(
        values: _values,
        min: widget.min,
        max: widget.max,
        autofocus: true,
        onChanged: (v) => setState(() {
          _values = v;
          _HostedSlider.lastValues = v;
        }),
      ),
    );
  }
}

void main() {
  group('RangeSlider', () {
    testWidgets('renders both handles on the track', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 10,
          height: 1,
          child: RangeSlider(
            values: const (0, 9),
            min: 0,
            max: 9,
            onChanged: (_) {},
          ),
        ),
      );
      final out = tester
          .renderToString(size: const CellSize(10, 1), emptyMark: ' ')
          .trimRight();
      // Both handles visible.
      expect(out.startsWith('●'), isTrue);
      expect(out.endsWith('●'), isTrue);
    });

    testWidgets('fills the cells between the handles with ━', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 11,
          height: 1,
          child: RangeSlider(
            values: const (0, 10),
            min: 0,
            max: 10,
            onChanged: (_) {},
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(11, 1));
      // Between cols 1 and 9 (exclusive of handles at 0 and 10) → ━
      for (var c = 1; c < 10; c++) {
        expect(
          buf.atColRow(c, 0).grapheme,
          '━',
          reason: 'fill glyph expected at col $c',
        );
      }
    });

    testWidgets('arrow right moves the active (low) handle right', (tester) {
      (num, num)? received;
      tester.pumpWidget(
        SizedBox(
          width: 11,
          height: 1,
          child: RangeSlider(
            values: const (0, 10),
            min: 0,
            max: 10,
            autofocus: true,
            onChanged: (v) => received = v,
          ),
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
      expect(received, (1, 10));
    });

    testWidgets('Tab swaps to the high handle; then arrow Left moves it', (
      tester,
    ) {
      (num, num)? received;
      tester.pumpWidget(
        SizedBox(
          width: 11,
          height: 1,
          child: RangeSlider(
            values: const (0, 10),
            min: 0,
            max: 10,
            autofocus: true,
            onChanged: (v) => received = v,
          ),
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.tab));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowLeft));
      expect(received, (0, 9));
    });

    testWidgets('low handle clamps against high (no crossing)', (tester) {
      // Use a stateful wrapper so the controlled widget actually
      // reflects each onChanged — otherwise the slider keeps seeing
      // the original `values` prop and "clamp" never gets exercised.
      tester.pumpWidget(_HostedSlider(initial: const (4, 5), min: 0, max: 10));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
      // Two right-arrows from low=4 against high=5: first lands on 5,
      // second is clamped and discarded. Final state stays at (5, 5).
      expect(_HostedSlider.lastValues, (5, 5));
    });

    testWidgets('PageUp moves by largeStep on the active handle', (tester) {
      (num, num)? received;
      tester.pumpWidget(
        SizedBox(
          width: 21,
          height: 1,
          child: RangeSlider(
            values: const (0, 20),
            min: 0,
            max: 20,
            largeStep: 5,
            autofocus: true,
            onChanged: (v) => received = v,
          ),
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.pageUp));
      expect(received, (5, 20));
    });

    testWidgets('Home jumps the active handle to min', (tester) {
      (num, num)? received;
      tester.pumpWidget(
        SizedBox(
          width: 11,
          height: 1,
          child: RangeSlider(
            values: const (5, 9),
            min: 0,
            max: 10,
            autofocus: true,
            onChanged: (v) => received = v,
          ),
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.home));
      expect(received, (0, 9));
    });

    testWidgets('End jumps the high handle to max', (tester) {
      (num, num)? received;
      tester.pumpWidget(
        SizedBox(
          width: 11,
          height: 1,
          child: RangeSlider(
            values: const (2, 5),
            min: 0,
            max: 10,
            autofocus: true,
            onChanged: (v) => received = v,
          ),
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.tab)); // active=high
      tester.sendKey(const KeyEvent(keyCode: KeyCode.end));
      expect(received, (2, 10));
    });
  });
}
