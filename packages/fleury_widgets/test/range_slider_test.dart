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
      // Both handles visible: the active (default low) handle is the solid
      // mark, the inactive high handle is hollow.
      expect(out.startsWith('●'), isTrue);
      expect(out.endsWith('○'), isTrue);
    });

    testWidgets('Up swaps the solid (active) handle to the high end', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 11,
          height: 1,
          child: RangeSlider(
            values: const (0, 10),
            min: 0,
            max: 10,
            autofocus: true,
            onChanged: (_) {},
          ),
        ),
      );
      // Low is active by default: solid ● at col 0, hollow ○ at col 10.
      var buf = tester.render(size: const CellSize(11, 1));
      expect(buf.atColRow(0, 0).grapheme, '●');
      expect(buf.atColRow(10, 0).grapheme, '○');
      // Up switches the active handle to the high end — the solid mark moves.
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
      buf = tester.render(size: const CellSize(11, 1));
      expect(buf.atColRow(0, 0).grapheme, '○');
      expect(buf.atColRow(10, 0).grapheme, '●');
    });

    testWidgets('shows a switch-ends hint in the readout while focused', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 40,
          height: 3,
          child: RangeSlider(
            values: const (2, 8),
            min: 0,
            max: 10,
            showValues: true,
            autofocus: true,
            onChanged: (_) {},
          ),
        ),
      );
      final out = tester.renderToString(size: const CellSize(40, 3));
      expect(out.contains('↕ switch ends'), isTrue);
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

    testWidgets('Up selects the high handle; then arrow Left moves it', (
      tester,
    ) {
      // The two handles are a 2-cell vertical axis: Up = high, Down = low.
      // Tab is reserved for moving between widgets.
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
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowLeft));
      expect(received, (0, 9));
    });

    testWidgets('Tab is not consumed — it bubbles so focus can leave', (
      tester,
    ) {
      // Universal escape: the slider must NOT swallow Tab (it used to swap
      // handles). With no traversal ancestor the key is simply unhandled.
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
      // Tab changed nothing on the slider (it bubbled, not swapped handles),
      // so the low handle is still active and at its min — Left then bubbles
      // too. Neither fires onChanged.
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowLeft));
      expect(received, isNull,
          reason: 'Tab and Left both bubble; nothing on the slider moved');
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
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp)); // active=high
      tester.sendKey(const KeyEvent(keyCode: KeyCode.end));
      expect(received, (2, 10));
    });

    testWidgets('null onChanged disables the slider', (tester) async {
      tester.pumpWidget(
        const SizedBox(
          width: 11,
          height: 1,
          child: RangeSlider(
            values: (2, 8),
            min: 0,
            max: 10,
            label: 'window',
            autofocus: true,
            onChanged: null,
          ),
        ),
      );

      final node = tester.semantics().single(
        role: SemanticRole.slider,
        label: 'window',
        enabled: false,
      );
      expect(node.actions, isEmpty);
      expect(node.value, '2-8');
      expect(node.state['canIncrement'], isFalse);
      expect(node.state['canDecrement'], isFalse);

      final buf = tester.render(size: const CellSize(11, 1));
      expect(buf.atColRow(2, 0).style.dim, isTrue);

      final result = await tester.invokeSemanticAction(
        SemanticAction.increment,
        node: node,
      );
      expect(result.status, SemanticActionInvocationStatus.disabled);
    });

    testWidgets('exposes slider semantics and increment/decrement actions', (
      tester,
    ) async {
      (num, num)? received;
      tester.pumpWidget(
        SizedBox(
          width: 11,
          height: 1,
          child: RangeSlider(
            values: const (2, 8),
            min: 0,
            max: 10,
            step: 2,
            largeStep: 4,
            label: 'window',
            autofocus: true,
            onChanged: (v) => received = v,
          ),
        ),
      );

      final node = tester.semantics().single(
        role: SemanticRole.slider,
        label: 'window',
        value: '2-8',
        action: SemanticAction.increment,
      );
      expect(node.actions, contains(SemanticAction.decrement));
      expect(node.state['lowValue'], 2);
      expect(node.state['highValue'], 8);
      expect(node.state['activeHandle'], 'low');
      expect(
        tester
            .accessibilitySnapshot()
            .single(role: SemanticRole.slider, label: 'window')
            .states,
        contains(
          'range 2-8, min 0, max 10, step 2, large step 4, active handle low',
        ),
      );

      final result = await tester.invokeSemanticAction(
        SemanticAction.increment,
        role: SemanticRole.slider,
        label: 'window',
      );

      expect(result.completed, isTrue);
      expect(received, (4, 8));
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.slider, label: 'window')
            .focused,
        isTrue,
      );
    });

    testWidgets('slider semantic actions reflect the active handle bounds', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 11,
          height: 1,
          child: RangeSlider(
            values: const (0, 8),
            min: 0,
            max: 10,
            label: 'window',
            autofocus: true,
            onChanged: (_) {},
          ),
        ),
      );

      final low = tester.semantics().single(
        role: SemanticRole.slider,
        label: 'window',
      );
      expect(low.actions, contains(SemanticAction.increment));
      expect(low.actions, isNot(contains(SemanticAction.decrement)));
      expect(low.state['activeHandle'], 'low');

      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
      final high = tester.semantics().single(
        role: SemanticRole.slider,
        label: 'window',
      );
      expect(high.actions, contains(SemanticAction.increment));
      expect(high.actions, contains(SemanticAction.decrement));
      expect(high.state['activeHandle'], 'high');
    });
  });
}
