import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

/// The workspace preview shared by the button and custom-tile examples.
class NotePreview extends StatelessWidget {
  const NotePreview({required this.status, this.feedback, super.key});

  final String status;
  final String? feedback;

  @override
  Widget build(BuildContext context) {
    final opened = status == 'Opened notes.md';
    final inspecting = status.contains('Markdown');
    final held = feedback == 'Pressed…';
    return SizedBox(
      height: 7,
      child: Panel(
        title: opened
            ? 'PREVIEW OPEN'
            : inspecting
            ? 'FILE DETAILS'
            : 'PREVIEW',
        focused: opened || held,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              feedback ?? status,
              style: CellStyle(
                bold: true,
                foreground: feedback != null ? Colors.yellow : Colors.cyan,
              ),
            ),
            Text(
              opened
                  ? 'Planning notes\nMeet on Tuesday.\nBring the sketches.'
                  : inspecting
                  ? 'Type: Markdown\nSize: 2 KB\nLocation: /notes'
                  : 'Your note will appear here.\nOpen notes.md to read it.',
            ),
          ],
        ),
      ),
    );
  }
}
