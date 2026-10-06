import 'package:fleury/fleury_core.dart';

import 'draft_editor.dart';

/// A local save service with a visible delay and an offline switch.
class TestingEditorDemo extends StatefulWidget {
  const TestingEditorDemo({super.key});

  @override
  State<TestingEditorDemo> createState() => _TestingEditorDemoState();
}

class _TestingEditorDemoState extends State<TestingEditorDemo> {
  bool offline = false;

  Future<void> save(String text) async {
    final fail = offline;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (fail) throw StateError('Offline');
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: DraftEditor(save: save)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Checkbox(
          label: 'Offline',
          value: offline,
          onChanged: (value) => setState(() => offline = value),
        ),
      ),
    ],
  );
}
