// Shared by the live Testing guide and its executable tests.
import 'dart:async';

import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Count: $count'),
      Button(
        label: 'Add one',
        autofocus: true,
        onPressed: () => setState(() => count++),
      ),
    ],
  );
}

/// The application owns editing; its caller supplies persistence.
class DraftEditor extends StatefulWidget {
  const DraftEditor({super.key, required this.save});

  final Future<void> Function(String text) save;

  @override
  State<DraftEditor> createState() => _DraftEditorState();
}

class _DraftEditorState extends State<DraftEditor> {
  final document = TextEditingController(text: 'Ship the testing guide.');
  String savedText = 'Ship the testing guide.';
  String status = 'All changes saved';
  bool saving = false;

  bool get dirty => document.text != savedText;

  Future<void> save() async {
    if (saving || !dirty) return;
    final draft = document.text;
    setState(() {
      saving = true;
      status = 'Saving…';
    });
    try {
      await widget.save(draft);
      if (!mounted) return;
      setState(() {
        savedText = draft;
        status = 'All changes saved';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => status = 'Save failed. Your draft is safe.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> discard(BuildContext context) async {
    final confirmed = await context.present<bool>(const _DiscardDialog());
    if (!mounted || confirmed != true) return;
    setState(() {
      document.text = savedText;
      status = 'Changes discarded';
    });
  }

  @override
  void dispose() {
    document.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    bindings: [
      KeyBinding(KeySequence.ctrl.s, onTrigger: (_) => unawaited(save())),
    ],
    child: Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('release-notes.md', style: CellStyle(bold: true)),
          const SizedBox(height: 1),
          Expanded(
            child: TextArea(
              controller: document,
              autofocus: true,
              readOnly: saving,
              semanticLabel: 'Draft',
              onChanged: (_) => setState(() => status = 'Unsaved changes'),
            ),
          ),
          const SizedBox(height: 1),
          Row(
            children: [
              Button(
                label: 'Save',
                variant: ButtonVariant.primary,
                onPressed: saving || !dirty ? null : () => unawaited(save()),
              ),
              const SizedBox(width: 1),
              Button(
                label: 'Discard',
                onPressed: saving || !dirty
                    ? null
                    : () => unawaited(discard(context)),
              ),
              const Spacer(),
              const Text('Ctrl+S', style: CellStyle(dim: true)),
            ],
          ),
          const SizedBox(height: 1),
          Text(status),
        ],
      ),
    ),
  );
}

class _DiscardDialog extends StatelessWidget {
  const _DiscardDialog();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 38,
    height: 7,
    child: Dialog(
      title: 'Discard changes?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Return to the last saved draft.'),
          const SizedBox(height: 1),
          Row(
            children: [
              Button(
                label: 'Keep editing',
                autofocus: true,
                onPressed: () => context.pop(false),
              ),
              const SizedBox(width: 1),
              Button(
                label: 'Discard draft',
                onPressed: () => context.pop(true),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

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

/// An async control whose semantic handler returns the operation's Future.
class PublishControl extends StatefulWidget {
  const PublishControl({super.key, required this.publish, this.onStarted});
  final Future<void> Function() publish;
  final VoidCallback? onStarted;

  @override
  State<PublishControl> createState() => _PublishControlState();
}

class _PublishControlState extends State<PublishControl> {
  bool busy = false;
  String status = 'Ready';

  Future<void> publish() async {
    if (busy) return;
    setState(() {
      busy = true;
      status = 'Publishing…';
    });
    widget.onStarted?.call();
    try {
      await widget.publish();
      if (mounted) setState(() => status = 'Published');
    } catch (_) {
      if (mounted) setState(() => status = 'Publish failed');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    role: SemanticRole.button,
    label: 'Publish',
    value: status,
    enabled: !busy,
    busy: busy,
    includeChildren: false,
    actions: {if (!busy) SemanticAction.activate},
    onAction: (_) => publish(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Button(
          label: 'Publish',
          onPressed: busy ? null : () => unawaited(publish()),
        ),
        const SizedBox(height: 1),
        Text(status),
      ],
    ),
  );
}

class TestingPublishDemo extends StatelessWidget {
  const TestingPublishDemo({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: PublishControl(
      publish: () => Future<void>.delayed(const Duration(milliseconds: 800)),
    ),
  );
}
