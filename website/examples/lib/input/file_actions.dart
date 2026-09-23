import 'package:fleury/fleury_core.dart';

class FileActions extends StatefulWidget {
  const FileActions({super.key});

  @override
  State<FileActions> createState() => _FileActionsState();
}

class _FileActionsState extends State<FileActions> {
  String status = 'Ready';

  void open() => setState(() => status = 'Opened notes.md');
  void details() => setState(() => status = 'notes.md · Markdown · 2 KB');

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // #docregion interaction
      Button(
        text: 'Open notes.md',
        autofocus: true,
        onPressed: open,
        onSecondaryPressed: details,
        style: const CellStyle.interactive(
          focused: CellStyle(underline: true),
          pressed: CellStyle(inverse: true),
        ),
      ),
      Button(text: 'Details', onPressed: details),
      // #enddocregion interaction
      const SizedBox(height: 1),
      Text(status),
      const Text(
        'Tab: next · Enter / Space: activate',
        style: CellStyle(dim: true),
      ),
    ],
  );
}
