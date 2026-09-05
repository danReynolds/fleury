// Informational AOT workload: scrolling a plain-text document through the real
// frame loop. Includes scroll mutation, build/layout/paint, diff and commit;
// excludes terminal encoding/transport. Startup/layout are warmed separately.
// dart compile exe bin/scroll_text_probe.dart -o /tmp/scroll-text
// /tmp/scroll-text --lines 1000 --frames 200
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';

import 'sample_frame_host.dart';

void main(List<String> args) {
  final options = <String, String>{
    '--lines': '1000',
    '--frames': '200',
    '--kind': 'plain'
  };
  for (var i = 0; i < args.length; i += 2) {
    if (i + 1 == args.length || !options.containsKey(args[i])) {
      throw ArgumentError(
          'Expected --lines N, --frames N, or --kind plain|rich');
    }
    options[args[i]] = args[i + 1];
  }
  final lines = int.parse(options['--lines']!);
  final frames = int.parse(options['--frames']!);
  final kind = options['--kind']!;
  if (!['plain', 'rich'].contains(kind)) throw ArgumentError('Invalid kind');
  if (lines < 50 || frames < 1) throw ArgumentError('Invalid count');
  const size = CellSize(80, 24);
  final document = List.generate(
      lines,
      (i) => '${i.toString().padLeft(6, '0')}  INFO  worker accepted request; '
          'elapsed=12ms status=ok 漢字 👩‍💻').join('\n');
  final controller = ScrollController();
  final host = SampleFrameHost(
    ScrollView(
        controller: controller,
        child: kind == 'plain'
            ? Text(document, softWrap: false)
            : RichText(
                text: TextSpan(
                    text: document,
                    style: const CellStyle(foreground: AnsiColor(6))),
                softWrap: false)),
    size,
  );
  try {
    for (final (position, base) in [
      ('top', 0),
      ('middle', controller.maxOffset ~/ 2),
      ('bottom', controller.maxOffset - 1),
    ]) {
      void scroll(int i) => controller.jumpTo(base + (i & 1));
      for (var i = 0; i < 40; i++) {
        scroll(i);
        host.frame('clean', i);
      }
      final times = <int>[];
      final paints = <int>[];
      var changed = 0;
      for (var i = 0; i < frames; i++) {
        final watch = Stopwatch()..start();
        scroll(i);
        final frame = host.frame('clean', i);
        watch.stop();
        times.add(watch.elapsedMicroseconds);
        paints.add(frame.paint);
        if (frame.changed) changed++;
      }
      Map<String, int> distribution(List<int> values) {
        values.sort();
        return {
          'median': values[values.length ~/ 2],
          'p95': values[(values.length * .95).ceil() - 1]
        };
      }

      // Compare exact final cell values across builds, outside the timing.
      final buffer = host.tester.render(size: size);
      var fingerprint = 2166136261;
      for (var row = 0; row < size.rows; row++) {
        for (var col = 0; col < size.cols; col++) {
          final cell = buffer.atColRow(col, row);
          for (final code in '${cell.role.name}|${cell.grapheme}|${cell.style};'
              .codeUnits) {
            fingerprint = ((fingerprint ^ code) * 16777619) & 0xffffffff;
          }
        }
      }
      stdout.writeln(jsonEncode({
        'kind': kind,
        'lines': lines,
        'textCodeUnits': document.length,
        'position': position,
        'columns': size.cols,
        'rows': size.rows,
        'frames': frames,
        'changedFrames': changed,
        'maxOffset': controller.maxOffset,
        'offset': controller.offset,
        'fingerprint': fingerprint,
        'totalUs': distribution(times),
        'paintUs': distribution(paints),
        'dart': Platform.version,
      }));
    }
  } finally {
    host.tester.dispose();
    controller.dispose();
  }
}
