// Live previews for widgets whose usual data source is native: the local disk
// (FileBrowser, FilePicker) and captured process output (LogRegion,
// TerminalOutputRegion). Each demo runs the real widget in the browser over
// a browser-side source: an in-memory project tree, or log lines a ticker
// appends the way a running build would.
import 'package:fleury/fleury_core.dart';

/// A small Fleury project, as a terminal app would see it on disk.
final projectFiles = MemoryFileSource(
  [
    '/my_app/.gitignore',
    '/my_app/README.md',
    '/my_app/analysis_options.yaml',
    '/my_app/pubspec.yaml',
    '/my_app/bin/run_app.dart',
    '/my_app/lib/app.dart',
    '/my_app/lib/src/status_panel.dart',
    '/my_app/lib/src/theme.dart',
    '/my_app/test/app_test.dart',
    '/my_app/web/index.html',
    '/my_app/web/main.dart',
  ],
  sizes: {
    '/my_app/README.md': 1840,
    '/my_app/pubspec.yaml': 412,
    '/my_app/lib/app.dart': 2231,
  },
);

class FileBrowserPreview extends StatefulWidget {
  const FileBrowserPreview({super.key});

  @override
  State<FileBrowserPreview> createState() => _FileBrowserPreviewState();
}

class _FileBrowserPreviewState extends State<FileBrowserPreview> {
  String _status = 'Enter opens · Backspace goes up';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: FileBrowser(
          source: projectFiles,
          initialDirectory: '/my_app',
          autofocus: true,
          maxVisible: 8,
          onActivate: (entry) =>
              setState(() => _status = 'opened ${entry.path}'),
        ),
      ),
      Text(_status, style: const CellStyle(dim: true)),
    ],
  );
}

class FilePickerPreview extends StatefulWidget {
  const FilePickerPreview({super.key});

  @override
  State<FilePickerPreview> createState() => _FilePickerPreviewState();
}

class _FilePickerPreviewState extends State<FilePickerPreview> {
  String _status = 'Pick a Dart file';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: FilePicker(
          source: projectFiles,
          initialDirectory: '/my_app',
          autofocus: true,
          maxVisible: 8,
          filter: (entry) => entry.isDirectory || entry.name.endsWith('.dart'),
          onSelect: (file) => setState(() => _status = 'picked ${file.path}'),
        ),
      ),
      Text(_status, style: const CellStyle(dim: true)),
    ],
  );
}

/// Appends the next scripted line every [interval] while mounted in a live
/// app, looping at the end, so log demos read as a running process.
mixin _Scripted<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  static const interval = Duration(milliseconds: 700);

  Ticker? _ticker;
  Duration _last = Duration.zero;

  void appendNext();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ticker == null && TuiBinding.maybeOf(context) != null) {
      _ticker = createTicker(_onTick)..start();
    }
  }

  void _onTick(Duration elapsed) {
    if (elapsed - _last < interval) return;
    _last = elapsed;
    appendNext();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }
}

const _deployLog = <(LogSeverity, String, String)>[
  (LogSeverity.info, 'deploy', 'Starting deploy of api@4.2.0'),
  (LogSeverity.info, 'build', 'Compiling 214 files'),
  (LogSeverity.success, 'build', 'Built in 3.8s'),
  (LogSeverity.info, 'deploy', 'Uploading image (48 MB)'),
  (LogSeverity.warning, 'probe', 'Health check slow: 1.9s'),
  (LogSeverity.info, 'deploy', 'Routing 10% of traffic'),
  (LogSeverity.error, 'probe', 'Health check failed: 503 on /ready'),
  (LogSeverity.info, 'deploy', 'Rolling back to api@4.1.3'),
  (LogSeverity.success, 'deploy', 'Rollback complete'),
];

class LogRegionPreview extends StatefulWidget {
  const LogRegionPreview({super.key});

  @override
  State<LogRegionPreview> createState() => _LogRegionPreviewState();
}

class _LogRegionPreviewState extends State<LogRegionPreview>
    with SingleTickerProviderStateMixin, _Scripted {
  final List<LogEntry> _entries = [];
  int _next = 0;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 4; i++) {
      _add();
    }
  }

  void _add() {
    final (severity, source, message) = _deployLog[_next % _deployLog.length];
    _entries.add(
      LogEntry(id: _next, severity: severity, source: source, message: message),
    );
    _next++;
    if (_entries.length > 200) _entries.removeAt(0);
  }

  @override
  void appendNext() => setState(_add);

  @override
  Widget build(BuildContext context) =>
      LogRegion(entries: List.of(_entries), autofocus: true);
}

const _buildOutput = <(LogSource, String)>[
  (LogSource.stdout, r'$ dart compile exe bin/server.dart'),
  (LogSource.stdout, 'Generated: bin/server.exe'),
  (LogSource.stdout, r'$ dart test'),
  (LogSource.stdout, '00:01 +12: All tests passed!'),
  (LogSource.stdout, r'$ dart analyze'),
  (
    LogSource.stderr,
    "warning - lib/cache.dart:14:7 - Unused import: 'dart:io'.",
  ),
  (LogSource.stdout, '1 issue found.'),
];

class TerminalOutputPreview extends StatefulWidget {
  const TerminalOutputPreview({super.key});

  @override
  State<TerminalOutputPreview> createState() => _TerminalOutputPreviewState();
}

class _TerminalOutputPreviewState extends State<TerminalOutputPreview>
    with SingleTickerProviderStateMixin, _Scripted {
  final LogBuffer _buffer = LogBuffer(capacity: 200);
  int _next = 0;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 3; i++) {
      appendNext();
    }
  }

  // The region listens to the buffer, so appending needs no setState.
  @override
  void appendNext() {
    final (source, text) = _buildOutput[_next++ % _buildOutput.length];
    _buffer.add(LogLine(text, source));
  }

  @override
  void dispose() {
    super.dispose();
    _buffer.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TerminalOutputRegion(buffer: _buffer, autofocus: true);
}

const _plan = <String>['Run tests', 'Build image', 'Deploy'];

class WorkflowSnapshotPreview extends StatefulWidget {
  const WorkflowSnapshotPreview({super.key});

  @override
  State<WorkflowSnapshotPreview> createState() =>
      _WorkflowSnapshotPreviewState();
}

class _WorkflowSnapshotPreviewState extends State<WorkflowSnapshotPreview> {
  List<TaskGraphStatus> _statuses = [
    TaskGraphStatus.succeeded,
    TaskGraphStatus.running,
    TaskGraphStatus.pending,
  ];

  WorkflowSnapshot get _snapshot => WorkflowSnapshot(
    title: 'Release',
    tasks: [
      for (var i = 0; i < _plan.length; i++)
        TaskGraphNode(id: 'task-$i', title: _plan[i], status: _statuses[i]),
    ],
  );

  void _advance() => setState(() {
    final running = _statuses.indexOf(TaskGraphStatus.running);
    final pending = _statuses.indexOf(TaskGraphStatus.pending);
    _statuses = [..._statuses];
    if (running >= 0) _statuses[running] = TaskGraphStatus.succeeded;
    if (pending >= 0) _statuses[pending] = TaskGraphStatus.running;
  });

  void _fail() => setState(() {
    final running = _statuses.indexOf(TaskGraphStatus.running);
    if (running < 0) return;
    _statuses = [..._statuses]..[running] = TaskGraphStatus.failed;
  });

  void _reset() => setState(() {
    _statuses = [
      TaskGraphStatus.running,
      TaskGraphStatus.pending,
      TaskGraphStatus.pending,
    ];
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final summary = snapshot.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 4, child: TaskGraph(nodes: snapshot.tasks)),
        Text(
          'health: ${summary.health.name} · '
          '${summary.activeTaskCount} of ${summary.taskCount} remaining · '
          '${summary.failedTaskCount} failed',
          style: const CellStyle(bold: true),
        ),
        const SizedBox(height: 1),
        Row(
          children: [
            Button(text: 'Advance', autofocus: true, onPressed: _advance),
            const SizedBox(width: 1),
            Button(text: 'Fail', onPressed: _fail),
            const SizedBox(width: 1),
            Button(text: 'Reset', onPressed: _reset),
          ],
        ),
      ],
    );
  }
}

class ToasterPreview extends StatelessWidget {
  const ToasterPreview({super.key});

  @override
  Widget build(BuildContext context) =>
      const Toaster(duration: Duration(seconds: 3), child: _ToastButtons());
}

class _ToastButtons extends StatelessWidget {
  const _ToastButtons();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Raise a toast:'),
      const SizedBox(height: 1),
      Row(
        children: [
          Button(
            text: 'Save',
            autofocus: true,
            onPressed: () =>
                Toaster.show(context, 'Saved', severity: ToastSeverity.success),
          ),
          const SizedBox(width: 1),
          Button(
            text: 'Retry',
            onPressed: () => Toaster.show(
              context,
              'Connection slow, retrying',
              severity: ToastSeverity.warning,
            ),
          ),
          const SizedBox(width: 1),
          Button(
            text: 'Fail',
            onPressed: () => Toaster.show(
              context,
              'Upload failed',
              severity: ToastSeverity.error,
            ),
          ),
        ],
      ),
    ],
  );
}
