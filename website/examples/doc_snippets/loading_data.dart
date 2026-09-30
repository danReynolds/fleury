// Compile-checked source for the Loading data guide. The web-safe widgets live
// in lib/loading_data_guide.dart, which the live docs embeds render too.

// #docregion decode-in-background
import 'dart:isolate';
import 'dart:typed_data';
// #enddocregion decode-in-background

import 'package:fleury/fleury.dart';
// #docregion decode-in-background
import 'package:image/image.dart' as img;
// #enddocregion decode-in-background

import '../lib/loading_data_guide.dart';

export '../lib/loading_data_guide.dart';

void main() => runApp(
  const FleuryApp(title: 'Loading data', home: LoadingDataDemo()),
  mode: const TerminalMode(mouse: true),
);

/// Decodes on another isolate, so frames, input, and Ctrl+C stay live while
/// the work runs. Terminal and `fleury serve` apps only: a browser embed
/// compiles to JavaScript, which has no isolates.
// #docregion decode-in-background
Future<img.Image> decodePhotoInBackground(Uint8List bytes) => Isolate.run(
  () =>
      img.decodeImage(bytes) ??
      (throw const FormatException('Response was not an image')),
);
// #enddocregion decode-in-background

class LoadingDataDemo extends StatelessWidget {
  const LoadingDataDemo({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      PhotoViewer(
        loadPhoto: () => fetchPhoto(DateTime.now().microsecondsSinceEpoch),
      ),
      const SizedBox(height: 1),
      const SnapshotExplorer(),
      const SizedBox(height: 1),
      const TransmissionView(),
    ],
  );
}
