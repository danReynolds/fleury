// Compile-checked source for the Loading data guide.

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

void main() => runApp(
  const FleuryApp(title: 'Loading data', home: LoadingDataDemo()),
  mode: const TerminalMode(mouse: true),
);

enum SnapshotPreview { disconnected, waiting, error, empty, success }

Future<List<String>>? futureFor(SnapshotPreview preview) => switch (preview) {
  SnapshotPreview.disconnected => null,
  SnapshotPreview.waiting => Completer<List<String>>().future,
  // Fails asynchronously, not at construction: a `Future.error(...)` is
  // already failed when `setState` assigns it, and FutureBuilder subscribes a
  // microtask later — too late to keep the error handled.
  SnapshotPreview.error => Future<List<String>>.delayed(
    Duration.zero,
    () => throw StateError('Connection lost'),
  ),
  SnapshotPreview.empty => Future<List<String>>.value(const <String>[]),
  SnapshotPreview.success => Future<List<String>>.value(const <String>[
    'alpha.log',
    'beta.log',
  ]),
};

class AsyncStateCard extends StatelessWidget {
  const AsyncStateCard({super.key, required this.snapshot});

  final AsyncSnapshot<List<String>> snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final files = snapshot.data ?? const <String>[];
    late final String symbol, label, detail;
    late final Color accent;

    if (snapshot.connectionState == ConnectionState.none) {
      (symbol, label, detail, accent) = (
        '○',
        'DISCONNECTED',
        'Choose a source to begin.',
        colors.foreground ?? Colors.white,
      );
    } else if (snapshot.hasError) {
      (symbol, label, detail, accent) = (
        '×',
        'ERROR',
        'Connection lost. Try again.',
        colors.error,
      );
    } else if (snapshot.connectionState == ConnectionState.waiting) {
      (symbol, label, detail, accent) = (
        '◌',
        'LOADING',
        'Loading files…',
        colors.info,
      );
    } else if (files.isEmpty) {
      (symbol, label, detail, accent) = (
        '◇',
        'EMPTY',
        'The request completed with no files.',
        colors.warning,
      );
    } else {
      (symbol, label, detail, accent) = (
        '✓',
        'READY',
        '${files.length} files loaded',
        colors.success,
      );
    }

    return Container(
      border: BoxBorder(
        style: Theme.of(context).borderStyle,
        cellStyle: CellStyle(foreground: accent),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(symbol, style: CellStyle(foreground: accent, bold: true)),
              const SizedBox(width: 1),
              Text(label, style: CellStyle(foreground: accent, bold: true)),
            ],
          ),
          Text(detail),
          if (label == 'READY')
            for (final file in files) Text('  $file'),
        ],
      ),
    );
  }
}

class SnapshotExplorer extends StatefulWidget {
  const SnapshotExplorer({super.key});

  @override
  State<SnapshotExplorer> createState() => _SnapshotExplorerState();
}

class _SnapshotExplorerState extends State<SnapshotExplorer> {
  var _preview = SnapshotPreview.waiting;
  late Future<List<String>>? _future = futureFor(_preview);

  void _show(SnapshotPreview preview) => setState(() {
    _preview = preview;
    _future = futureFor(preview);
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Select<SnapshotPreview>(
        value: _preview,
        semanticLabel: 'Snapshot state',
        onChanged: _show,
        options: const <SelectOption<SnapshotPreview>>[
          SelectOption(
            value: SnapshotPreview.disconnected,
            label: 'Disconnected',
          ),
          SelectOption(value: SnapshotPreview.waiting, label: 'Loading'),
          SelectOption(value: SnapshotPreview.error, label: 'Error'),
          SelectOption(value: SnapshotPreview.empty, label: 'Empty'),
          SelectOption(value: SnapshotPreview.success, label: 'Success'),
        ],
      ),
      FutureBuilder<List<String>>(
        future: _future,
        builder: (context, snapshot) => AsyncStateCard(snapshot: snapshot),
      ),
    ],
  );
}

Future<img.Image> fetchPhoto(int seed) async {
  final response = await http.get(
    Uri.parse('https://picsum.photos/seed/fleury-$seed/480/240.jpg'),
  );
  if (response.statusCode != 200) {
    throw StateError('Photo request failed (${response.statusCode})');
  }
  return img.decodeImage(response.bodyBytes) ??
      (throw const FormatException('Response was not an image'));
}

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.loadPhoto});

  final Future<img.Image> Function() loadPhoto;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late Future<img.Image> _photo = widget.loadPhoto();

  void _reload() => setState(() => _photo = widget.loadPhoto());

  @override
  Widget build(BuildContext context) => FutureBuilder<img.Image>(
    future: _photo,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Column(
          children: <Widget>[
            const Text('Could not load a photo.'),
            Button(label: 'Retry', onPressed: _reload),
          ],
        );
      }

      final photo = snapshot.data;
      if (photo == null) return const Text('Loading a photo from the web…');
      final refreshing = snapshot.connectionState == ConnectionState.waiting;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (refreshing) const Text('Loading a new photo…'),
          SizedBox(
            width: 48,
            height: 10,
            child: Image.decoded(
              photo,
              fit: ImageFit.cover,
              semanticLabel: 'Random landscape photo',
            ),
          ),
          Button(label: 'Load another', onPressed: refreshing ? null : _reload),
        ],
      );
    },
  );
}

class Transmission {
  static const chunks = <String>[
    '          *',
    '         / \\',
    '    *---*   *',
    '     \\   \\ /',
    '      *---*',
  ];

  final _controller = StreamController<List<String>>();
  var _received = 0;

  Stream<List<String>> get updates => _controller.stream;

  void receiveNext() {
    if (_received == chunks.length) return;
    _received++;
    _controller.add(chunks.take(_received).toList());
    if (_received == chunks.length) _controller.close();
  }

  void dispose() {
    if (!_controller.isClosed) _controller.close();
  }
}

class TransmissionView extends StatefulWidget {
  const TransmissionView({super.key});

  @override
  State<TransmissionView> createState() => _TransmissionViewState();
}

class _TransmissionViewState extends State<TransmissionView> {
  late Transmission _transmission;
  late Stream<List<String>> _updates;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _transmission = Transmission();
    _updates = _transmission.updates;
  }

  void _restart() {
    _transmission.dispose();
    setState(_start);
  }

  @override
  void dispose() {
    _transmission.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<String>>(
    stream: _updates,
    initialData: const <String>[],
    builder: (context, snapshot) {
      final lines = snapshot.requireData;
      final status = switch (snapshot.connectionState) {
        ConnectionState.none => 'OFFLINE',
        ConnectionState.waiting => 'CONNECTING',
        ConnectionState.active => 'LIVE',
        ConnectionState.done => 'COMPLETE',
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$status · ${lines.length}/${Transmission.chunks.length} packets',
          ),
          for (final line in lines) Text(line),
          Row(
            children: <Widget>[
              Button(
                label: 'Next packet',
                onPressed: snapshot.connectionState == ConnectionState.done
                    ? null
                    : _transmission.receiveNext,
              ),
              const SizedBox(width: 1),
              Button(label: 'Restart', onPressed: _restart),
            ],
          ),
        ],
      );
    },
  );
}

class LoadingDataDemo extends StatelessWidget {
  const LoadingDataDemo({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const SnapshotExplorer(),
      const SizedBox(height: 1),
      PhotoViewer(
        loadPhoto: () => fetchPhoto(DateTime.now().microsecondsSinceEpoch),
      ),
      const SizedBox(height: 1),
      const TransmissionView(),
    ],
  );
}
