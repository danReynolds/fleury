import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
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

void _press(FleuryTester tester, int col) => tester.sendMouse(
  MouseEvent(
    kind: MouseEventKind.down,
    button: MouseButton.left,
    col: col,
    row: 0,
  ),
);
void _moveTo(FleuryTester tester, int col) => tester.sendMouse(
  MouseEvent(
    kind: MouseEventKind.drag,
    button: MouseButton.left,
    col: col,
    row: 0,
  ),
);
void _release(FleuryTester tester, int col) => tester.sendMouse(
  MouseEvent(
    kind: MouseEventKind.up,
    button: MouseButton.left,
    col: col,
    row: 0,
  ),
);

void _click(FleuryTester tester, int col) {
  _press(tester, col);
  _release(tester, col);
}

void main() {
  group('RangeSlider', () {
    testWidgets('clicking the track moves the nearest handle there', (tester) {
      _HostedSlider.lastValues = null;
      tester.pumpWidget(const _HostedSlider(initial: (0, 10), min: 0, max: 10));
      // Track is 11 cols wide at col 0, so column == value. Column 3 is nearer
      // the low handle (col 0) than the high (col 10) → low jumps to 3.
      tester.render(size: const CellSize(11, 1));
      _click(tester, 3);
      expect(_HostedSlider.lastValues, (3, 10));
    });

    testWidgets('clicking near the high handle moves it, not the low', (
      tester,
    ) {
      _HostedSlider.lastValues = null;
      tester.pumpWidget(const _HostedSlider(initial: (0, 10), min: 0, max: 10));
      tester.render(size: const CellSize(11, 1));
      _click(tester, 7); // nearer the high handle at col 10
      expect(_HostedSlider.lastValues, (0, 7));
    });

    testWidgets('dragging slides the grabbed handle across the track', (
      tester,
    ) {
      _HostedSlider.lastValues = null;
      tester.pumpWidget(const _HostedSlider(initial: (0, 10), min: 0, max: 10));
      tester.render(size: const CellSize(11, 1));
      // Grab the low handle at col 0 and drag it right to col 5.
      _press(tester, 0);
      _moveTo(tester, 3);
      _moveTo(tester, 5);
      _release(tester, 5);
      expect(_HostedSlider.lastValues, (5, 10));
    });

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

    testWidgets('Right swaps the solid (active) handle to the high end', (
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
      // Right moves to the high handle — the solid mark moves with it.
      tester.sendKey(const KeyEvent(KeyCode.arrowRight));
      buf = tester.render(size: const CellSize(11, 1));
      expect(buf.atColRow(0, 0).grapheme, '○');
      expect(buf.atColRow(10, 0).grapheme, '●');
    });

    testWidgets('shows the key-model hint in the readout while focused', (
      tester,
    ) {
      tester.pumpWidget(
        SizedBox(
          width: 44,
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
      final out = tester.renderToString(size: const CellSize(44, 3));
      expect(out.contains('↑↓ value · ←→ ends'), isTrue);
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

    testWidgets('Up increases the active (low) handle value', (tester) {
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
      tester.sendKey(const KeyEvent(KeyCode.arrowUp));
      expect(received, (1, 10));
    });

    testWidgets('Right switches to the high handle; then Down lowers it', (
      tester,
    ) {
      // Left/Right move between the two handles (low-left, high-right);
      // Up/Down change the active handle's value.
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
      tester.sendKey(const KeyEvent(KeyCode.arrowRight)); // → high
      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // lower high
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
      tester.sendKey(const KeyEvent(KeyCode.tab));
      // Tab changed nothing on the slider (it bubbled, not swapped handles),
      // so the low handle is still active and at its min — Left then bubbles
      // too. Neither fires onChanged.
      tester.sendKey(const KeyEvent(KeyCode.arrowLeft));
      expect(
        received,
        isNull,
        reason: 'Tab and Left both bubble; nothing on the slider moved',
      );
    });

    testWidgets('low handle clamps against high (no crossing)', (tester) {
      // Use a stateful wrapper so the controlled widget actually
      // reflects each onChanged — otherwise the slider keeps seeing
      // the original `values` prop and "clamp" never gets exercised.
      tester.pumpWidget(_HostedSlider(initial: const (4, 5), min: 0, max: 10));
      tester.sendKey(const KeyEvent(KeyCode.arrowUp));
      tester.sendKey(const KeyEvent(KeyCode.arrowUp));
      // Two Up-arrows raise low=4 against high=5: first lands on 5,
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
      tester.sendKey(const KeyEvent(KeyCode.pageUp));
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
      tester.sendKey(const KeyEvent(KeyCode.home));
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
      tester.sendKey(const KeyEvent(KeyCode.arrowRight)); // active=high
      tester.sendKey(const KeyEvent(KeyCode.end));
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

      tester.sendKey(const KeyEvent(KeyCode.arrowRight));
      final high = tester.semantics().single(
        role: SemanticRole.slider,
        label: 'window',
      );
      expect(high.actions, contains(SemanticAction.increment));
      expect(high.actions, contains(SemanticAction.decrement));
      expect(high.state['activeHandle'], 'high');
    });

    testWidgets('semantic setValue sets the active handle to an exact value '
        '(B4)', (tester) async {
      _HostedSlider.lastValues = null;
      tester.pumpWidget(const _HostedSlider(initial: (2, 8), min: 0, max: 10));
      final node = tester.semantics().single(role: SemanticRole.slider);
      expect(node.actions, contains(SemanticAction.setValue));
      expect(node.state['activeHandle'], 'low'); // default active handle

      await tester.invokeSemanticAction(
        SemanticAction.setValue,
        node: node,
        payload: 5,
      );
      expect(_HostedSlider.lastValues!.$1, 5, reason: 'low handle moved to 5');
      expect(_HostedSlider.lastValues!.$2, 8, reason: 'high handle unchanged');

      // Switch the active handle, then set it — reaches the other handle
      // without an increment loop.
      tester.sendKey(const KeyEvent(KeyCode.arrowRight));
      await tester.invokeSemanticAction(
        SemanticAction.setValue,
        role: SemanticRole.slider,
        payload: 9,
      );
      expect(_HostedSlider.lastValues!.$2, 9, reason: 'high handle moved to 9');
    });
  });
}
