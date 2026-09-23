import 'package:fleury/fleury_core.dart';

class ContactFields extends StatefulWidget {
  const ContactFields({super.key});

  @override
  State<ContactFields> createState() => _ContactFieldsState();
}

class _ContactFieldsState extends State<ContactFields> {
  final title = TextEditingController(text: 'Planning notes');
  final note = TextEditingController(
    text: 'Meet on Tuesday.\nBring the sketches.',
  );

  @override
  void dispose() {
    title.dispose();
    note.dispose();
    super.dispose();
  }

  // #docregion focus
  Widget get titleField => TextInput(
    controller: title,
    semanticLabel: 'Title',
    autofocus: true,
  );

  Widget get noteField => TextArea(
    controller: note,
    semanticLabel: 'Note',
    minLines: 3,
    maxLines: 3,
  );
  // #enddocregion focus

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('TITLE', style: CellStyle(dim: true)),
      titleField,
      const SizedBox(height: 1),
      const Text('NOTE', style: CellStyle(dim: true)),
      noteField,
    ],
  );
}
