// dart format width=50
import 'package:fleury/fleury_core.dart';

class FileList extends StatefulWidget {
  const FileList({super.key});

  @override
  State<FileList> createState() =>
      _FileListState();
}

class _FileListState extends State<FileList> {
  // #docregion interaction
  final files = [
    'README.md',
    'notes.md',
    'sketches.txt',
  ];
  String selected = 'None';
  // #enddocregion interaction

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // #docregion interaction
      SizedBox(
        height: 3,
        child: ListView.builder(
          autofocus: true,
          itemCount: files.length,
          onSelect: (i) =>
              setState(() => selected = files[i]),
          itemBuilder: (_, i, highlighted) => Text(
            '${highlighted ? '›' : ' '} ${files[i]}',
          ),
        ),
      ),
      // #enddocregion interaction
      const SizedBox(height: 1),
      Text('Selected: $selected'),
    ],
  );
}
