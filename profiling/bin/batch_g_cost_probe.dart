// Diagnostic wall-clock costs, not portable regression thresholds.
import 'dart:io';
import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart';

void main() {
  for (final history in [0, 20, 200]) {
    final samples = <int>[];
    final completionSamples = <int>[];
    for (var trial = 0; trial < 8; trial++) {
      final controller = TextEditingController(text: 'x' * 65536);
      final paste = controller.beginPaste();
      paste.append('a');
      for (var i = 0; i < history; i++) {
        controller.caretOffset = 0;
        controller.insert('z');
      }
      final watch = Stopwatch()..start();
      for (var i = 0; i < 16; i++) {
        paste.append('a' * 2048);
      }
      watch.stop();
      if (trial >= 3) samples.add(watch.elapsedMicroseconds);
      watch
        ..reset()
        ..start();
      paste.close();
      watch.stop();
      if (trial >= 3) completionSamples.add(watch.elapsedMicroseconds);
      controller.dispose();
    }
    samples.sort();
    completionSamples.sort();
    stdout.writeln('paste: 64 KiB document, $history intervening edits, '
        '16 x 2 KiB tails: median ${samples[2] / 1000} ms, '
        'completion ${completionSamples[2] / 1000} ms');
  }
  final points = [for (var i = 0; i < 10000; i++) (i, i % 100)];
  final series = [LineSeries(points)];
  for (final reuse in [true, false]) {
    final tester = FleuryTester();
    Widget chart() => RepaintBoundary(
        child: SizedBox(
            width: 60,
            height: 12,
            child: LineChart(series: series, interactive: true)));
    final cached = chart();
    tester.pumpWidget(cached);
    for (var i = 0; i < 10; i++) {
      tester.pumpWidget(reuse ? cached : chart());
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      tester.pumpWidget(reuse ? cached : chart());
    }
    watch.stop();
    stdout.writeln(
        '10k-point interactive chart, ${reuse ? 'same widget' : 'explicit refresh'}: '
        '${watch.elapsedMicroseconds / 50 / 1000} ms/update');
    tester.dispose();
  }
}
