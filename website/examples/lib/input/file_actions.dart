import 'package:fleury/fleury_core.dart';
import 'note_preview.dart';

class FileActions extends StatefulWidget {
  const FileActions({super.key});

  @override
  State<FileActions> createState() => _FileActionsState();
}

class _FileActionsState extends State<FileActions> {
  String status = 'Ready';

  void open() => setState(() => status = 'Opened notes.md');
  void details() => setState(() => status = 'notes.md · Markdown · 2 KB');

  // #docregion focus
  Widget get openButton => Button(
    text: 'Open notes.md',
    autofocus: true,
    onPressed: open,
    onSecondaryPressed: details,
    style: const CellStyle.interactive(
      focused: CellStyle(underline: true),
      pressed: CellStyle(inverse: true),
    ),
  );
  // #enddocregion focus

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      openButton,
      const SizedBox(height: 1),
      Button(text: 'Details', onPressed: details),
      const SizedBox(height: 1),
      NotePreview(status: status),
      const SizedBox(height: 1),
      Button(
        text: 'Close preview',
        onPressed: () => setState(() => status = 'Ready'),
      ),
      const SizedBox(height: 1),
      const Text(
        'Tab: next · Enter / Space: activate',
        style: CellStyle(dim: true),
      ),
    ],
  );
}
