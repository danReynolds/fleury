import 'package:fleury/fleury_host.dart';

/// The small app under inspection; the host supplies the real debug shell.
class DebuggingPlayground extends StatefulWidget {
  const DebuggingPlayground({super.key, required this.logs});

  final LogBuffer logs;

  @override
  State<DebuggingPlayground> createState() => _DebuggingPlaygroundState();
}

class _DebuggingPlaygroundState extends State<DebuggingPlayground> {
  bool _slowNextBuild = false;
  int _previews = 0;
  String _status = 'Ready';

  void _buildPreview() {
    widget.logs.add(
      const LogLine('preview: build requested', LogSource.stdout),
    );
    setState(() {
      _slowNextBuild = true;
      _previews++;
      _status = 'Preview $_previews built';
    });
  }

  void _saveNote() {
    widget.logs.add(const LogLine('save: opening notes.md', LogSource.stdout));
    throw StateError('Could not save notes.md: demo storage is unavailable');
  }

  void _writeLogs() {
    for (var i = 1; i <= 12; i++) {
      widget.logs.add(
        LogLine('sync: received note $i of 12', LogSource.stdout),
      );
    }
    setState(() => _status = '12 log lines written');
  }

  @override
  Widget build(BuildContext context) {
    if (_slowNextBuild) {
      _slowNextBuild = false;
      // Deliberately block ONE build. The debugger measures this actual work;
      // it is never fed a fabricated timing or a canned report.
      final watch = Stopwatch()..start();
      while (watch.elapsedMilliseconds < 100) {}
    }
    return Padding(
      padding: const EdgeInsets.all(1),
      child: SizedBox(
        width: 27,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('NOTES PREVIEW', style: CellStyle(bold: true)),
            const SizedBox(height: 1),
            const Text('Make a slow frame, then\nread Worst build.'),
            const SizedBox(height: 1),
            Button(
              text: 'Slow build',
              onPressed: _buildPreview,
              autofocus: true,
            ),
            const SizedBox(height: 1),
            Button(text: 'Throw error', onPressed: _saveNote),
            const SizedBox(height: 1),
            Button(text: 'Write logs', onPressed: _writeLogs),
            const SizedBox(height: 2),
            Text(
              _status,
              style: const CellStyle(foreground: RgbColor(61, 219, 158)),
            ),
            const SizedBox(height: 1),
            const Text(
              'Hide and reopen the panel:\nyour state stays here.',
              style: CellStyle(dim: true),
            ),
          ],
        ),
      ),
    );
  }
}
