import 'package:fleury/fleury_core.dart';

class FileActions extends StatefulWidget {
  const FileActions({super.key});

  @override
  State<FileActions> createState() => _FileActionsState();
}

class _FileActionsState extends State<FileActions> {
  // #docregion focus
  bool open = false;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Button(
        text: open ? 'Close note' : 'Open note',
        onPressed: () => setState(() => open = !open),
        autofocus: true,
        style: const CellStyle.interactive(
          focused: CellStyle(underline: true),
          pressed: CellStyle(inverse: true),
        ),
      ),
      const SizedBox(height: 1),
      Container.framed(
        padding: const EdgeInsets.all(1),
        child: Text(
          open
              ? 'Planning notes\nMeet on Tuesday.\nBring the sketches.'
              : 'Preview closed',
        ),
      ),
    ],
  );
  // #enddocregion focus
}
