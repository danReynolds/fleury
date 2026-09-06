import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

Widget button(
  String label, {
  VoidCallback? onPress,
  bool enabled = true,
  Key? key,
}) => Semantics(
  key: key,
  role: SemanticRole.button,
  label: label,
  enabled: enabled,
  actions: {if (onPress != null) SemanticAction.activate},
  onAction: (_) => onPress?.call(),
  child: Text(label),
);

class Editor extends StatelessWidget {
  const Editor({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class SpecialEditor extends Editor {
  const SpecialEditor({required super.child});
}

Matcher failure(String message) => throwsA(
  isA<TestFailure>().having(
    (error) => error.message,
    'message',
    contains(message),
  ),
);

Widget editable({
  Key? key,
  bool focused = false,
  bool readOnly = false,
  bool enabled = true,
  VoidCallback? onFocus,
  void Function(Object?)? onValue,
}) => Semantics(
  key: key,
  id: const SemanticNodeId('custom-field'),
  role: SemanticRole.spinButton,
  label: 'Amount',
  focused: focused,
  enabled: enabled,
  state: SemanticState({'textEditable': true, 'readOnly': readOnly}),
  actions: {SemanticAction.focus, if (onValue != null) SemanticAction.setValue},
  onAction: (_) => onFocus?.call(),
  onSetValue: onValue,
  child: const Text('Amount'),
);

void main() {
  testWidgets('declared roles work without adding a tester API', (
    tester,
  ) async {
    const approve = SemanticRole('reviewApproval', base: SemanticRole.button);
    var calls = 0;
    tester.pumpWidget(
      Semantics(
        role: approve,
        label: 'Approve',
        actions: {SemanticAction.activate},
        onAction: (_) => calls++,
        child: const Text('Approve'),
      ),
    );
    // A base describes projection; role selectors still match exact names.
    expect(tester.button('Approve'), hasCount(0));
    final approval = tester.target(role: approve, label: 'Approve');
    await approval.press();
    expect(calls, 1);
    expect(approval, isEnabled);
    expect(approval.snapshot.role.coreRole, SemanticRole.button);
  });

  testWidgets(
    'type scopes have no required semantic root; exact types and keys',
    (tester) async {
      var saved = 0;
      tester.pumpWidget(
        Column(
          children: [
            Editor(
              key: const ValueKey('first'),
              child: button('Save', onPress: () => saved++),
            ),
            const Editor(key: ValueKey('empty'), child: EmptyBox()),
            SpecialEditor(child: button('Save')),
          ],
        ),
      );
      expect(tester.target(type: Editor), hasCount(2));
      expect(tester.target(type: SpecialEditor), hasCount(1));
      final first = tester.target(type: Editor, key: const ValueKey('first'));
      await first.button('Save').press();
      expect(saved, 1);
      expect(
        tester
            .target(type: Editor, key: const ValueKey('empty'))
            .button('Save'),
        hasCount(0),
      );
      expect(() => first.snapshot, failure('widget scope'));
      expect(() => first.snapshots, failure('widget scope'));
      await expectLater(first.press(), failure('widget scope'));
      expect(saved, 1);
      expect(
        tester.target(
          type: Editor,
          key: const ValueKey('first'),
          role: SemanticRole.button,
        ),
        hasCount(1),
      );
    },
  );

  testWidgets(
    'missing and duplicate parents fail even for count zero and negation',
    (tester) {
      tester.pumpWidget(
        Column(
          children: [
            Editor(child: button('Save')),
            Editor(child: button('Save')),
          ],
        ),
      );
      expect(
        () =>
            expect(tester.target(type: Editor).button('Missing'), hasCount(0)),
        failure('found 2'),
      );
      expect(
        () => expect(
          tester.target(key: const ValueKey('missing')).button('Save'),
          hasCount(0),
        ),
        failure('found 0'),
      );
      expect(
        () => expect(tester.button('Missing'), isNot(isEnabled)),
        failure('found 0'),
      );
      expect(
        () => expect(tester.button('Save'), isNot(isDisabled)),
        failure('found 2'),
      );
    },
  );

  testWidgets(
    'colliding semantic ids cannot pass scoped count or negated assertions',
    (tester) async {
      var calls = 0;
      for (final scopeCount in [2, 3]) {
        tester.pumpWidget(
          Column(
            children: [
              for (var index = 0; index < scopeCount; index++)
                Editor(
                  key: ValueKey('editor-$index'),
                  child: Semantics(
                    id: const SemanticNodeId('reused-button'),
                    role: SemanticRole.button,
                    label: 'Save',
                    actions: {SemanticAction.activate},
                    onAction: (_) => calls++,
                    child: const Text('Save'),
                  ),
                ),
            ],
          ),
        );
        expect(tester.button('Save'), hasCount(scopeCount));
        for (var index = 0; index < scopeCount; index++) {
          final scope = tester.target(key: ValueKey('editor-$index'));
          expect(scope, hasCount(1));
          final save = scope.button('Save');
          for (final matcher in [
            hasCount(0),
            hasCount(1),
            isNot(hasCount(1)),
            isNot(isEnabled),
          ]) {
            expect(
              () => expect(save, matcher),
              failure('ambiguous contributor ownership'),
            );
          }
          expect(
            () => save.snapshots,
            failure('ambiguous contributor ownership'),
          );
          await expectLater(
            save.press(),
            failure('ambiguous contributor ownership'),
          );
          // Unmatched invalid nodes do not change a distinct query's result.
          expect(scope.button('Missing'), hasCount(0));
        }
      }
      expect(calls, 0);
    },
  );

  testWidgets(
    'widget scopes ignore the artificial root and excluded coverage markers',
    (tester) {
      tester.pumpWidget(
        const Editor(
          child: Column(
            children: [
              Semantics(
                role: SemanticRole.region,
                label: 'Public',
                child: Text('Visible'),
              ),
              ExcludeSemantics(child: Text('Hidden')),
            ],
          ),
        ),
      );
      expect(
        tester.semantics().nodes.any(
          (node) => node.state['semanticExcluded'] == true,
        ),
        isTrue,
      );
      final editor = tester.target(type: Editor);
      expect(editor.target(role: SemanticRole.region), hasCount(1));
      expect(editor.target(role: SemanticRole.app), hasCount(0));
      expect(editor.target(label: 'Hidden'), hasCount(0));
    },
  );

  testWidgets(
    'semantic scopes search strict descendants with no availability guessing',
    (tester) async {
      var calls = 0;
      tester.pumpWidget(
        Column(
          children: [
            Semantics(
              role: SemanticRole.form,
              label: 'Invoice',
              child: button('Save', onPress: () => calls++),
            ),
            button('Save', enabled: false),
          ],
        ),
      );
      final invoice = tester.target(role: SemanticRole.form, label: 'Invoice');
      expect(invoice.target(role: SemanticRole.form), hasCount(0));
      await invoice.button('Save').press();
      expect(calls, 1);
      await expectLater(tester.button('Save').press(), failure('found 2'));
      expect(() => invoice.target(type: Editor), throwsArgumentError);
      expect(() => tester.target(), throwsArgumentError);
      expect(tester.button('save'), hasCount(0));
      expect(tester.button('Save '), hasCount(0));
    },
  );

  testWidgets(
    'queries resolve replacement controls; stored snapshots remain historical',
    (tester) async {
      var oldCalls = 0;
      var newCalls = 0;
      final save = tester.button('Save');
      tester.pumpWidget(
        button('Save', key: const ValueKey('old'), onPress: () => oldCalls++),
      );
      final old = save.snapshot;
      final oldList = save.snapshots;
      await save.press();
      tester.pumpWidget(
        button('Save', key: const ValueKey('new'), onPress: () => newCalls++),
      );
      await save.press();
      expect(oldCalls, 1);
      expect(newCalls, 1);
      expect(save.snapshot.id, isNot(old.id));
      expect(oldList.single.id, old.id);
      expect(() => oldList.clear(), throwsUnsupportedError);
    },
  );

  testWidgets('keys scope reordered components and labels remain exact', (
    tester,
  ) async {
    var first = 0;
    var second = 0;
    final a = Editor(
      key: const ValueKey('a'),
      child: button('Save', onPress: () => first++),
    );
    final b = Editor(
      key: const ValueKey('b'),
      child: button('Save', onPress: () => second++),
    );
    final saved = tester
        .target(type: Editor, key: const ValueKey('a'))
        .button('Save');
    tester.pumpWidget(Column(children: [a, b]));
    tester.pumpWidget(Column(children: [b, a]));
    await saved.press();
    expect(first, 1);
    expect(second, 0);
  });

  testWidgets(
    'nested type scopes exclude self; semantic nodes owned by scope are included',
    (tester) {
      tester.pumpWidget(
        Editor(
          child: Editor(
            key: const ValueKey('inner'),
            child: button('Save', key: const ValueKey('control')),
          ),
        ),
      );
      final outer = tester.target(type: Editor).target(type: Editor);
      expect(() => outer.count, failure('found 2'));
      final inner = tester.target(key: const ValueKey('inner'));
      expect(inner.target(type: Editor), hasCount(0));
      final semanticWidget = inner.target(
        type: Semantics,
        key: const ValueKey('control'),
      );
      expect(semanticWidget.button('Save'), hasCount(1));
    },
  );

  testWidgets('handler actions complete layout without advancing time', (
    tester,
  ) async {
    tester.pumpWidget(const LayoutControl());
    final time = tester.clock.now;
    await tester.button('Save').press();
    expect(tester.exists(text('Saved')), isTrue);
    expect(tester.clock.now, time);
  });

  final direct = <SemanticAction, Future<void> Function(FleuryTarget)>{
    SemanticAction.activate: (target) => target.press(),
    SemanticAction.open: (target) => target.open(),
    SemanticAction.close: (target) => target.close(),
    SemanticAction.select: (target) => target.select(),
    SemanticAction.submit: (target) => target.submit(),
    SemanticAction.copy: (target) => target.copy(),
    SemanticAction.diagnose: (target) =>
        target.perform(SemanticAction.diagnose),
  };
  for (final entry in direct.entries) {
    testWidgets('${entry.key.name} uses shared dispatch exactly once', (
      tester,
    ) async {
      final seen = <SemanticAction>[];
      tester.pumpWidget(
        Semantics(
          role: SemanticRole.region,
          label: 'Control',
          actions: {entry.key},
          onAction: seen.add,
          child: const EmptyBox(),
        ),
      );
      await entry.value(tester.target(label: 'Control'));
      expect(seen, [entry.key]);
    });
  }

  testWidgets('missing, disabled and unsupported actions explain their stage', (
    tester,
  ) async {
    tester.pumpWidget(
      Column(
        children: [button('Disabled', enabled: false), button('Unsupported')],
      ),
    );
    await expectLater(tester.button('Missing').press(), failure('found 0'));
    await expectLater(tester.button('Disabled').press(), failure('disabled'));
    await expectLater(
      tester.button('Unsupported').press(),
      failure('Unsupported action activate'),
    );
    await expectLater(
      tester
          .button('Unsupported')
          .perform(SemanticAction.activate, payload: 'bad'),
      throwsArgumentError,
    );
  });

  testWidgets(
    'async handlers expose pending UI through an owned start signal',
    (tester) async {
      final started = Completer<void>();
      final request = Completer<void>();
      tester.pumpWidget(AsyncControl(started: started, request: request));
      final action = tester.button('Save').press();
      await started.future;
      tester.pump();
      expect(tester.exists(text('Saving')), isTrue);
      request.complete();
      await action;
      expect(tester.exists(text('Saved')), isTrue);
    },
  );

  testWidgets('real text controls focus, replace, and preserve filtering', (
    tester,
  ) async {
    final input = TextEditingController(text: 'Old');
    final area = TextEditingController();
    addTearDown(input.dispose);
    addTearDown(area.dispose);
    tester.pumpWidget(
      Column(
        children: [
          TextInput(
            controller: input,
            semanticLabel: 'Customer',
            enableBlink: false,
          ),
          SizedBox(
            height: 4,
            child: TextArea(controller: area, semanticLabel: 'Notes'),
          ),
        ],
      ),
    );
    await tester.field('Customer').fill('Acme');
    expect(input.text, 'Acme');
    expect(tester.field('Customer'), isFocused);
    expect(tester.field('Customer'), hasValue(startsWith('Ac')));
    await tester.field('Notes').fill('One\nTwo');
    expect(area.text, 'One\nTwo');
    expect(tester.field('Notes'), isFocused);
  });

  testWidgets(
    'custom editable roles work; generic value targets do not become fields',
    (tester) async {
      Object? changed;
      tester.pumpWidget(
        editable(focused: true, onValue: (value) => changed = value),
      );
      await tester.field('Amount').fill('12');
      expect(changed, '12');
      tester.pumpWidget(
        Semantics(
          role: SemanticRole.slider,
          label: 'Volume',
          actions: {SemanticAction.setValue},
          onSetValue: (_) {},
          child: const EmptyBox(),
        ),
      );
      expect(tester.field('Volume'), hasCount(0));
      await expectLater(
        tester.target(label: 'Volume').fill('12'),
        failure('text-editable'),
      );
    },
  );

  testWidgets(
    'fill validates before focus and never fills after focus refusal',
    (tester) async {
      var focusCalls = 0;
      var writes = 0;
      for (final readOnly in [true, false]) {
        tester.pumpWidget(
          editable(
            readOnly: readOnly,
            onFocus: () => focusCalls++,
            onValue: (_) => writes++,
          ),
        );
        await expectLater(
          tester.field('Amount').fill('12'),
          failure(readOnly ? 'non-read-only' : 'Focus was refused'),
        );
      }
      expect(focusCalls, 1);
      expect(writes, 0);
      tester.pumpWidget(
        editable(
          enabled: false,
          onFocus: () => focusCalls++,
          onValue: (_) => writes++,
        ),
      );
      await expectLater(tester.field('Amount').fill('12'), failure('disabled'));
      expect(focusCalls, 1);
    },
  );

  testWidgets(
    'fill refuses a remounted replacement even with the same explicit id',
    (tester) async {
      var writes = 0;
      tester.pumpWidget(
        editable(
          key: const ValueKey('old'),
          onValue: (_) => writes++,
          onFocus: () {
            tester.pumpWidget(
              editable(
                key: const ValueKey('new'),
                focused: true,
                onValue: (_) => writes++,
              ),
            );
          },
        ),
      );
      await expectLater(tester.field('Amount').fill('12'), failure('replaced'));
      expect(writes, 0);
    },
  );

  testWidgets('fill permits capabilities to change after gaining focus', (
    tester,
  ) async {
    var focused = false;
    String? written;
    Widget control() => Semantics(
      role: SemanticRole.textField,
      label: 'Name',
      focused: focused,
      actions: {if (!focused) SemanticAction.focus, SemanticAction.setValue},
      onAction: (_) {
        focused = true;
        tester.pumpWidget(control());
      },
      onSetValue: (value) => written = value as String,
      child: const EmptyBox(),
    );
    tester.pumpWidget(control());
    await tester.field('Name').fill('Ada');
    expect(written, 'Ada');
    expect(tester.field('Name'), isFocused);
  });

  testWidgets('focus is verified and does not claim keyboard traversal', (
    tester,
  ) async {
    tester.pumpWidget(editable());
    await expectLater(
      tester.field('Amount').focus(),
      failure('Focus was refused'),
    );
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    tester.pumpWidget(
      TextInput(
        controller: controller,
        semanticLabel: 'Customer',
        enableBlink: false,
      ),
    );
    await tester.field('Customer').focus();
    expect(tester.field('Customer'), isFocused);
  });

  testWidgets(
    'desired-state checks are idempotent and distinct from callback requests',
    (tester) async {
      var callbacks = 0;
      var value = false;
      Widget control() => Semantics(
        role: SemanticRole.checkbox,
        label: 'Wrap',
        value: 'wrap-key',
        checked: value,
        actions: {SemanticAction.setValue},
        onSetValue: (next) {
          callbacks++;
          value = next as bool;
          tester.pumpWidget(control());
        },
        child: const EmptyBox(),
      );
      tester.pumpWidget(control());
      final wrap = tester.checkbox('Wrap');
      await wrap.check();
      await wrap.check();
      expect(wrap, isChecked);
      expect(wrap, hasValue('wrap-key'));
      await wrap.uncheck();
      expect(wrap, isUnchecked);
      expect(callbacks, 2);

      tester.pumpWidget(
        Semantics(
          role: SemanticRole.checkbox,
          label: 'Wrap',
          checked: false,
          actions: {SemanticAction.setValue},
          onSetValue: (_) => callbacks++,
          child: const EmptyBox(),
        ),
      );
      await expectLater(wrap.check(), failure('observed checked=false'));
      await wrap.setValue(true);
      expect(callbacks, 4);
    },
  );

  testWidgets('check permits the control to disable after applying its value', (
    tester,
  ) async {
    var checked = false;
    Widget control() => Semantics(
      role: SemanticRole.checkbox,
      label: 'Confirm',
      checked: checked,
      enabled: !checked,
      actions: {if (!checked) SemanticAction.setValue},
      onSetValue: (value) {
        checked = value as bool;
        tester.pumpWidget(control());
      },
      child: const EmptyBox(),
    );
    tester.pumpWidget(control());
    await tester.checkbox('Confirm').check();
    expect(tester.checkbox('Confirm'), isChecked);
    expect(tester.checkbox('Confirm'), isDisabled);
  });

  testWidgets('already-correct disabled state succeeds without a setter', (
    tester,
  ) async {
    tester.pumpWidget(
      const Semantics(
        role: SemanticRole.checkbox,
        label: 'Required',
        checked: true,
        enabled: false,
        child: EmptyBox(),
      ),
    );
    final required = tester.checkbox('Required');
    await required.check();
    expect(required, isChecked);
    expect(required, isDisabled);
    await expectLater(required.uncheck(), failure('disabled'));
  });

  testWidgets(
    'absent checked state cannot pass an unchecked or negated assertion',
    (tester) async {
      tester.pumpWidget(button('Save'));
      final save = tester.button('Save');
      await expectLater(save.check(), failure('no checked state'));
      expect(() => expect(save, isUnchecked), failure('no checked state'));
      expect(() => expect(save, isNot(isChecked)), failure('no checked state'));
    },
  );

  testWidgets(
    'redacted diagnostics hide expected values and throwing setter payloads',
    (tester) async {
      const secret = 'private-secret-123';
      for (final flag in [
        'redactedValue',
        'obscureText',
        'clipboardRedacted',
      ]) {
        tester.pumpWidget(
          Semantics(
            role: SemanticRole.textField,
            label: 'Password',
            value: secret,
            state: SemanticState({flag: true}),
            actions: {SemanticAction.setValue},
            onSetValue: (value) => throw StateError('rejected $value'),
            child: const EmptyBox(),
          ),
        );
        final password = tester.field('Password');
        for (final action in <Future<void> Function()>[
          () => password.setValue(secret),
          () async => expect(password, hasValue(secret)),
          () async => expect(password, isNot(hasValue(secret))),
          () => tester.field('Missing').fill(secret),
        ]) {
          await expectLater(
            action(),
            throwsA(
              isA<TestFailure>().having(
                (error) => error.message,
                'message',
                isNot(contains(secret)),
              ),
            ),
          );
        }
      }
    },
  );

  test('queries before mounting and after disposal fail clearly', () {
    final tester = FleuryTester();
    final target = tester.button('Save');
    expect(() => target.count, failure('before pumpWidget'));
    tester.pumpWidget(button('Save'));
    tester.dispose();
    expect(() => target.count, throwsA(isA<TestFailure>()));
  });
}

class AsyncControl extends StatefulWidget {
  const AsyncControl({super.key, required this.started, required this.request});
  final Completer<void> started;
  final Completer<void> request;
  @override
  State<AsyncControl> createState() => _AsyncControlState();
}

class LayoutControl extends StatefulWidget {
  const LayoutControl({super.key});
  @override
  State<LayoutControl> createState() => _LayoutControlState();
}

class _LayoutControlState extends State<LayoutControl> {
  bool changed = false;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      button('Save', onPress: () => setState(() => changed = true)),
      LayoutBuilder(
        builder: (context, constraints) => Text(changed ? 'Saved' : 'Draft'),
      ),
    ],
  );
}

class _AsyncControlState extends State<AsyncControl> {
  String status = 'Draft';
  @override
  Widget build(BuildContext context) => Semantics(
    role: SemanticRole.button,
    label: 'Save',
    actions: {SemanticAction.activate},
    onAction: (_) async {
      setState(() => status = 'Saving');
      widget.started.complete();
      await widget.request.future;
      setState(() => status = 'Saved');
    },
    child: Text(status),
  );
}
