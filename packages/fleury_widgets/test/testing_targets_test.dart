import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

class Host extends StatefulWidget {
  const Host(this.builder, {super.key});
  final Widget Function(void Function(VoidCallback)) builder;
  @override
  State<Host> createState() => _HostState();
}

class _HostState extends State<Host> {
  @override
  Widget build(BuildContext context) => widget.builder(setState);
}

void main() {
  testWidgets(
    'shared checks work across checkbox, toggle, and switch widgets',
    (tester) async {
      var checked = false;
      var changed = 0;
      for (final kind in ['checkbox', 'toggle', 'switch']) {
        checked = false;
        changed = 0;
        tester.pumpWidget(
          Host((update) {
            void change(bool value) => update(() {
              checked = value;
              changed++;
            });
            return switch (kind) {
              'checkbox' => Checkbox(
                label: 'Enabled',
                value: checked,
                onChanged: change,
              ),
              'toggle' => Toggle(
                label: 'Enabled',
                value: checked,
                onChanged: change,
              ),
              _ => Switch(label: 'Enabled', value: checked, onChanged: change),
            };
          }),
        );
        final target = tester.target(label: 'Enabled');
        await target.check();
        await target.check();
        expect(target, isChecked, reason: kind);
        expect(changed, 1, reason: kind);
        await target.uncheck();
        expect(target, isUnchecked, reason: kind);
        expect(changed, 2, reason: kind);
      }
    },
  );

  testWidgets(
    'password fill uses the editing callback while assertions redact',
    (tester) async {
      String? edited;
      tester.pumpWidget(
        PasswordInput(
          semanticLabel: 'Password',
          onChanged: (value) => edited = value,
        ),
      );
      final password = tester.field('Password');
      await password.fill('fixture-secret');
      expect(edited, 'fixture-secret');
      expect(password, isFocused);
      expect(
        () => expect(password, hasValue('fixture-secret')),
        throwsA(
          isA<TestFailure>().having(
            (error) => error.message,
            'diagnostics',
            allOf(contains('redacted'), isNot(contains('fixture-secret'))),
          ),
        ),
      );
    },
  );

  testWidgets(
    'MultiSelect supports desired state without changing option keys or focus',
    (tester) async {
      var selected = <String>{};
      var changes = 0;
      tester.pumpWidget(
        Host(
          (update) => MultiSelect<String>(
            semanticLabel: 'Colours',
            options: const [
              SelectOption(value: 'red', label: 'Red'),
              SelectOption(value: 'blue', label: 'Blue', enabled: false),
            ],
            values: selected,
            onChanged: (value) => update(() {
              selected = value;
              changes++;
            }),
          ),
        ),
      );
      final colours = tester.target(type: MultiSelect<String>);
      final red = colours.checkbox('Red');
      await red.check();
      await red.check();
      expect(selected, {'red'});
      expect(red, isChecked);
      expect(red, hasValue('red'));
      expect(changes, 1);
      await red.uncheck();
      expect(selected, isEmpty);
      expect(changes, 2);
      await colours
          .checkbox('Blue')
          .uncheck(); // Already false despite disabled.
      await expectLater(
        colours.checkbox('Blue').check(),
        throwsA(isA<TestFailure>()),
      );
      expect(changes, 2);
      // The ordinary keyboard path still uses the same update operation.
      await red.focus();
      tester.press(KeySequence.enter);
      expect(selected, {'red'});
    },
  );

  testWidgets(
    'form validation, submission, and custom widget type scopes compose',
    (tester) async {
      final controller = TextEditingController();
      final form = FormController();
      addTearDown(controller.dispose);
      addTearDown(form.dispose);
      var submits = 0;
      tester.pumpWidget(
        Form(
          controller: form,
          onSubmit: () => submits++,
          child: FormField(
            validator: () => controller.text.isEmpty ? 'Required' : null,
            child: TextInput(controller: controller, semanticLabel: 'Customer'),
          ),
        ),
      );
      final target = tester.target(type: Form).target(role: SemanticRole.form);
      await target.submit();
      await tester.settle();
      expect(submits, 0);
      await target.field('Customer').fill('Acme');
      await target.submit();
      await tester.settle();
      expect(submits, 1);
    },
  );

  testWidgets(
    'Select has a stable purpose label across value changes and a separate popup scope',
    (tester) async {
      var value = 'red';
      tester.pumpWidget(
        Host(
          (update) => Select<String>(
            semanticLabel: 'Colour',
            options: const [
              SelectOption(value: 'red', label: 'Red'),
              SelectOption(value: 'blue', label: 'Blue'),
            ],
            value: value,
            onChanged: (next) => update(() => value = next),
          ),
        ),
      );
      final scope = tester.target(type: Select<String>);
      final colour = scope.button('Colour');
      await colour.setValue('Blue');
      expect(value, 'blue');
      expect(colour, hasValue('Blue'));
      await colour.setValue('Unknown');
      expect(colour, hasValue('Blue'));
      await colour.open();
      expect(tester.target(role: SemanticRole.menu), hasCount(1));
      expect(scope.target(role: SemanticRole.menu), hasCount(0));
      await tester.target(role: SemanticRole.menuItem, label: 'Red').press();
      expect(value, 'red');
    },
  );

  testWidgets(
    'numeric and autocomplete fields preserve normal editing behavior',
    (tester) async {
      final number = TextEditingController(text: '12');
      final customer = TextEditingController();
      addTearDown(number.dispose);
      addTearDown(customer.dispose);
      tester.pumpWidget(
        Column(
          children: [
            NumberInput(controller: number, semanticLabel: 'Amount'),
            Autocomplete<String>(
              controller: customer,
              options: const ['Acme', 'Bravo'],
              fieldSemanticLabel: 'Customer',
              semanticLabel: 'Customers',
            ),
          ],
        ),
      );
      await tester.field('Amount').fill('invalid');
      expect(number.text, '12');
      await tester.field('Amount').fill('25');
      expect(number.text, '25');
      await tester.field('Customer').fill('Ac');
      expect(customer.text, 'Ac');
      expect(tester.field('Customer'), isFocused);
      tester.press(KeySequence.enter);
      expect(customer.text, 'Acme');
    },
  );

  testWidgets(
    'tabs hide retained content from semantic queries inside type scopes',
    (tester) async {
      tester.pumpWidget(
        Tabs(
          tabs: [
            TabItem(
              label: 'Edit',
              content: Host((_) => Button(label: 'Save', onPressed: () {})),
            ),
            const TabItem(label: 'Preview', content: Text('Preview')),
          ],
        ),
      );
      final editor = tester.target(type: Host);
      expect(editor.button('Save'), hasCount(1));
      await tester.target(role: SemanticRole.tab, label: 'Preview').select();
      // Tabs keeps its pages mounted; published semantics exposes only the active one.
      expect(editor, hasCount(1));
      expect(editor.button('Save'), hasCount(0));
    },
  );

  testWidgets('tree branches and children share one target API', (
    tester,
  ) async {
    String? picked;
    tester.pumpWidget(
      Tree<String>(
        semanticLabel: 'Project',
        roots: const [
          TreeNode('src', children: [TreeNode('main.dart')]),
        ],
        onSelect: (node) => picked = node.label,
      ),
    );
    final project = tester.target(role: SemanticRole.tree, label: 'Project');
    final source = project.target(role: SemanticRole.treeItem, label: 'src');
    await source.open();
    expect(source.snapshot.expanded, isTrue);
    await project
        .target(role: SemanticRole.treeItem, label: 'main.dart')
        .press();
    expect(picked, 'main.dart');
  });

  testWidgets(
    'synthetic rows scope by semantic ancestry and dispatch through their owner',
    (tester) async {
      tester.viewportSize = const CellSize(30, 8);
      final controller = DataTableController();
      addTearDown(controller.dispose);
      tester.pumpWidget(
        DataTable(
          semanticLabel: 'Runs',
          controller: controller,
          rowCount: 10000,
          rowKeyBuilder: (row) => 'run-$row',
          columns: const [
            DataTableColumn(
              id: 'run',
              title: 'Run',
              width: FixedColumnWidth(14),
            ),
          ],
          cellBuilder: (row, column) => 'Run $row',
        ),
      );
      final table = tester
          .target(type: DataTable)
          .target(role: SemanticRole.table, label: 'Runs');
      expect(
        table.target(role: SemanticRole.tableRow, label: 'run-5000'),
        hasCount(0),
      );
      await table.setValue(5000);
      expect(controller.currentRowIndex, 5000);
      expect(table.snapshot.state.visibleRangeStart, lessThanOrEqualTo(5000));
      expect(table.snapshot.state.visibleRangeEnd, greaterThanOrEqualTo(5000));
      final row = table.target(role: SemanticRole.tableRow, label: 'run-5000');
      expect(row, hasCount(1));
      expect(row.target(role: SemanticRole.tableCell), hasCount(1));
      expect(row.target(role: SemanticRole.tableRow), hasCount(0));
      await row.select();
      expect(controller.currentRowIndex, 5000);
    },
  );
}
