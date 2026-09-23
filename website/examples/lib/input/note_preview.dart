import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

/// The workspace preview shared by the button and custom-tile examples.
class NotePreview extends StatelessWidget {
  const NotePreview({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final opened = status == 'Opened notes.md';
    final inspecting = status.contains('Markdown');
    final cancelled = status == 'Cancelled';
    final held = status == 'Pressed…';
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
              status,
              style: CellStyle(
                bold: true,
                foreground: cancelled || held ? Colors.yellow : Colors.cyan,
              ),
            ),
            Text(
              opened
                  ? 'Planning notes\nMeet on Tuesday.\nBring the sketches.'
                  : inspecting
                  ? 'Type: Markdown\nSize: 2 KB\nLocation: /notes'
                  : held
                  ? 'Release here to open.\nMove away to cancel.'
                  : cancelled
                  ? 'Preview stayed closed.\nTry a click without moving.'
                  : 'Your note will appear here.\nOpen notes.md to read it.',
            ),
          ],
        ),
      ),
    );
  }
}
