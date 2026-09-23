import 'package:fleury/fleury_core.dart';

class SelectableNote extends StatefulWidget {
  const SelectableNote({super.key});

  @override
  State<SelectableNote> createState() => _SelectableNoteState();
}

class _SelectableNoteState extends State<SelectableNote> {
  String selected = '';

  // #docregion focus
  Widget get notePreview => SelectionArea(
    onSelectionChanged: (content) => setState(() {
      selected = content?.plainText ?? '';
    }),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Planning notes', style: CellStyle(bold: true)),
        Text('Meet on Tuesday.\nBring the sketches.'),
      ],
    ),
  );
  // #enddocregion focus

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      notePreview,
      const SizedBox(height: 1),
      Text(
        selected.isEmpty
            ? 'Drag across the note'
            : '${selected.length} characters selected',
      ),
      const Text(
        'Ctrl+A: all · Ctrl+C: copy · Esc',
        style: CellStyle(dim: true),
      ),
      const SizedBox(height: 1),
      const Text('REPLY', style: CellStyle(dim: true)),
      const TextInput(
        semanticLabel: 'Reply',
        placeholder: 'Type here, then select the note',
        autofocus: true,
      ),
    ],
  );
}
