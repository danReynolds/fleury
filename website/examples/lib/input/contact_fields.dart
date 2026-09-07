import 'package:fleury/fleury_core.dart';

class ContactFields extends StatefulWidget {
  const ContactFields({super.key});

  @override
  State<ContactFields> createState() => _ContactFieldsState();
}

class _ContactFieldsState extends State<ContactFields> {
  final name = TextEditingController(text: 'Ada Lovelace');
  final note = TextEditingController(
    text: 'Meet on Tuesday.\nBring the sketches.',
  );

  @override
  void dispose() {
    name.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // #docregion interaction
      const Text('NAME', style: CellStyle(dim: true)),
      TextInput(controller: name, semanticLabel: 'Name', autofocus: true),
      const SizedBox(height: 1),
      const Text('NOTE', style: CellStyle(dim: true)),
      TextArea(
        controller: note,
        semanticLabel: 'Note',
        minLines: 3,
        maxLines: 3,
      ),
      // #enddocregion interaction
    ],
  );
}
