// Live previews for FileBrowser and FilePicker, whose usual data source is the
// local disk: each runs the real widget in the browser over an in-memory
// project tree. Also the Toaster preview's buttons.
import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

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
