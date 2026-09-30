// Shared, web-safe source for the Loading data guide's embeds and its
// compile-checked program. The guide shows the `#docregion` excerpts below,
// so they must stay readable.
// #docregion transmission
import 'dart:async';
// #enddocregion transmission

import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';
// #docregion fetch-photo
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
// #enddocregion fetch-photo

// #docregion fetch-photo
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
// #enddocregion fetch-photo

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.loadPhoto});

  final Future<img.Image> Function() loadPhoto;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

// #docregion photo-viewer
class _PhotoViewerState extends State<PhotoViewer> {
  late Future<img.Image> _photo = widget.loadPhoto();

  void _reload() => setState(() => _photo = widget.loadPhoto());

  @override
  Widget build(BuildContext context) => FutureBuilder<img.Image>(
    future: _photo,
    builder: (context, snapshot) {
      final loading = snapshot.connectionState == ConnectionState.waiting;
      if (snapshot.hasError && !loading) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Could not load a photo.'),
            Button(text: 'Retry', onPressed: _reload),
          ],
        );
      }

      final photo = snapshot.data;
      if (photo == null) return const Text('Loading a photo from the web…');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(loading ? 'Loading a new photo…' : 'Random landscape'),
          SizedBox(
            width: 48,
            height: 10,
            child: Image.decoded(
              photo,
              fit: ImageFit.cover,
              semanticLabel: 'Random landscape photo',
            ),
          ),
          Button(text: 'Load another', onPressed: loading ? null : _reload),
        ],
      );
    },
  );
}
// #enddocregion photo-viewer

// #docregion explorer
enum SnapshotPreview { disconnected, waiting, error, empty, success }

Future<List<String>>? futureFor(SnapshotPreview preview) => switch (preview) {
  SnapshotPreview.disconnected => null,
  SnapshotPreview.waiting => Completer<List<String>>().future,
  // Own the failure immediately, even if rendering is delayed or this preview
  // is replaced before a frame. FutureBuilder still receives the same error.
  SnapshotPreview.error => Future<List<String>>.error(
    StateError('Connection lost'),
  )..ignore(),
  SnapshotPreview.empty => Future<List<String>>.value(const <String>[]),
  SnapshotPreview.success => Future<List<String>>.value(const <String>[
    'alpha.log',
    'beta.log',
  ]),
};
// #enddocregion explorer

// #docregion describe
(String, String) describe(AsyncSnapshot<List<String>> snapshot) {
  if (snapshot.connectionState == ConnectionState.none) {
    return ('DISCONNECTED', 'Choose a source to begin.');
  }
  if (snapshot.connectionState == ConnectionState.waiting) {
    return ('LOADING', 'Loading files…');
  }
  if (snapshot.hasError) return ('ERROR', 'Connection lost. Try again.');
  final files = snapshot.requireData;
  if (files.isEmpty) return ('EMPTY', 'The request completed with no files.');
  return ('READY', '${files.length} files loaded');
}
// #enddocregion describe

class AsyncStateCard extends StatelessWidget {
  const AsyncStateCard({super.key, required this.snapshot});

  final AsyncSnapshot<List<String>> snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (label, detail) = describe(snapshot);
    final (symbol, accent) = switch (label) {
      'DISCONNECTED' => ('○', colors.foreground ?? Colors.white),
      'LOADING' => ('◌', colors.info),
      'ERROR' => ('×', colors.error),
      'EMPTY' => ('◇', colors.warning),
      _ => ('✓', colors.success),
    };
    final heading = CellStyle(foreground: accent, bold: true);
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
          Text('$symbol $label', style: heading),
          Text(detail),
          if (label == 'READY')
            for (final file in snapshot.requireData) Text('  $file'),
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

// #docregion explorer
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
    children: [
      Select<SnapshotPreview>(
        value: _preview,
        semanticLabel: 'Snapshot state',
        onChanged: _show,
        options: const [
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
// #enddocregion explorer

// #docregion transmission
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
// #enddocregion transmission

class TransmissionView extends StatefulWidget {
  const TransmissionView({super.key});

  @override
  State<TransmissionView> createState() => _TransmissionViewState();
}

// #docregion transmission-view
class _TransmissionViewState extends State<TransmissionView> {
  var _transmission = Transmission();
  late var _updates = _transmission.updates;

  void _restart() {
    _transmission.dispose();
    setState(() {
      _transmission = Transmission();
      _updates = _transmission.updates;
    });
  }

  @override
  void dispose() {
    _transmission.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<String>>(
    key: ValueKey(_transmission),
    stream: _updates,
    initialData: const [],
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Button(text: 'Signal lost. Restart', onPressed: _restart);
      }
      final lines = snapshot.requireData;
      final status = switch (snapshot.connectionState) {
        ConnectionState.none => 'OFFLINE',
        ConnectionState.waiting => 'CONNECTING',
        ConnectionState.active => 'LIVE',
        ConnectionState.done => 'COMPLETE',
      };
      final complete = snapshot.connectionState == ConnectionState.done;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$status · ${lines.length}/5 packets'),
          for (final line in lines) Text(line),
          Row(
            children: [
              Button(
                text: 'Next packet',
                onPressed: complete ? null : _transmission.receiveNext,
              ),
              const SizedBox(width: 1),
              Button(text: 'Restart', onPressed: _restart),
            ],
          ),
        ],
      );
    },
  );
}

// #enddocregion transmission-view
