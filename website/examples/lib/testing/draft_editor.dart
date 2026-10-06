import 'dart:async';

import 'package:fleury/fleury_core.dart';

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

  // #docregion save-command
  AppCommand get saveCommand => AppCommand(
    id: const CommandId('editor.save'),
    title: 'Save draft',
    shortcuts: [KeySequence.ctrl.s],
    enabled: (_) => dirty && !saving,
    run: (_) => save(),
  );
  // #enddocregion save-command

  @override
  Widget build(BuildContext context) => CommandScope(
    label: 'Draft commands',
    commands: [saveCommand],
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
              CommandButton(
                command: saveCommand.id,
                label: 'Save',
                variant: ButtonVariant.primary,
              ),
              const SizedBox(width: 1),
              Button(
                text: 'Discard',
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
                text: 'Keep editing',
                autofocus: true,
                onPressed: () => context.pop(false),
              ),
              const SizedBox(width: 1),
              Button(text: 'Discard draft', onPressed: () => context.pop(true)),
            ],
          ),
        ],
      ),
    ),
  );
}
