import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_widget_support.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

// A consumer-defined appearance, using only supported package imports.
Widget _customControl({
  Key? key,
  required VoidCallback? activate,
  FocusNode? focusNode,
  bool participatesInForm = false,
}) => FocusableControl(
  key: key,
  focusNode: focusNode,
  onActivate: activate,
  semanticRole: SemanticRole.button,
  semanticLabel: 'Confirm',
  participatesInForm: participatesInForm,
  defaultStyle: const CellStyle.interactive(
    invalid: CellStyle(foreground: AnsiColor(1)),
    disabled: CellStyle(dim: true),
  ),
  builder: (style, enabled, states) => Text('confirm!', style: style),
);

void main() {
  testWidgets('custom appearance shares keyboard and semantic activation', (
    tester,
  ) async {
    var calls = 0;
    final node = FocusNode();
    addTearDown(node.dispose);
    tester.pumpWidget(_customControl(activate: () => calls++, focusNode: node));
    expect(tester.renderToString().trim(), 'confirm!');
    await tester.button('Confirm').press();
    expect(calls, 1);
    expect(node.hasFocus, isTrue);
    tester.sendKey(const KeyEvent(KeyCode.enter));
    tester.type(' ');
    expect(calls, 3);
    tester.paste(' ');
    expect(calls, 3);
  });

  testWidgets('custom control follows form validation and disabled state', (
    tester,
  ) async {
    final form = FormController();
    final node = FocusNode();
    addTearDown(node.dispose);
    var confirmed = false;
    Widget build({bool enabled = true}) => Form(
      controller: form,
      onSubmit: () {},
      child: FormField(
        validator: () => confirmed ? null : 'Confirm first.',
        child: _customControl(
          activate: enabled ? () => confirmed = true : null,
          focusNode: node,
          participatesInForm: true,
        ),
      ),
    );
    tester.pumpWidget(build());
    final validation = form.validate();
    tester.pump();
    expect(await validation, isFalse);
    expect(node.hasFocus, isTrue);
    expect(tester.renderToString(), contains('Confirm first.'));
    await tester.button('Confirm').press();
    await tester.settle();
    expect(confirmed, isTrue);
    final accepted = form.validate();
    tester.pump();
    expect(await accepted, isTrue);
    expect(tester.renderToString(), isNot(contains('Confirm first.')));
    tester.pumpWidget(build(enabled: false));
    expect(tester.button('Confirm'), isDisabled);
    expect(node.hasFocus, isFalse);
  });

  testWidgets('keyed custom controls keep their focus when reordered', (
    tester,
  ) async {
    Widget build(bool reversed) => Column(
      children: [
        if (reversed) const Text('before'),
        _customControl(key: const ValueKey('confirm'), activate: () {}),
        if (!reversed) const Text('after'),
      ],
    );
    tester.pumpWidget(build(false));
    await tester.button('Confirm').focus();
    tester.pumpWidget(build(true));
    expect(tester.button('Confirm'), isFocused);
  });

  test('custom painters project only the display spelling', () {
    const original = '👩‍💻';
    expect(
      projectDisplayText(original, policy: TextPresentationPolicy.spec),
      original,
    );
    expect(
      projectDisplayText(
        original,
        policy: const TextPresentationPolicy(lowering: ClusterLowering.split),
      ),
      '👩💻',
    );
  });
}
