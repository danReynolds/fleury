// Informational rendering workload, not an end-to-end application benchmark.
// Run the same source on a baseline checkout to compare implementations:
//   dart run bin/layout_isolation_probe.dart [--frames 800]
// Each frame changes real wrapping text in one fixed-size status pane. Layout
// must update the pane while surrounding rows/columns retain their geometry.
import 'dart:convert';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart' show RenderLayoutDebugStats;

void main(List<String> args) {
  final frameFlag = args.indexOf('--frames');
  final frames = frameFlag < 0 ? 800 : int.parse(args[frameFlag + 1]);
  final results = <String, Object>{};
  for (final columns in [2, 5, 12]) {
    const rowCount = 8;
    final texts =
        List.generate(columns * rowCount, (i) => RenderText(text: 'idle $i'));
    final root = RenderFlex(direction: Axis.vertical)
      ..replaceAllChildren([
        for (var row = 0; row < rowCount; row++)
          RenderFlex(direction: Axis.horizontal)
            ..replaceAllChildren([
              for (var col = 0; col < columns; col++)
                RenderSizedBox(
                    width: 18, height: 3, child: texts[row * columns + col]),
            ]),
      ]);
    final size = CellSize(columns * 18, rowCount * 3);
    final constraints = CellConstraints.loose(size);
    final buffer = CellBuffer(size);
    final layoutTimes = <double>[];
    final frameTimes = <double>[];
    var performed = 0;
    final frameWatch = Stopwatch();
    final layoutWatch = Stopwatch();
    root.layout(constraints);
    for (var frame = 0; frame < frames + 200; frame++) {
      final index = frame % texts.length;
      final long = (frame ~/ texts.length).isEven;
      RenderLayoutDebugStats.beginFrame(enabled: true);
      frameWatch
        ..reset()
        ..start();
      texts[index].text = long
          ? 'pane $index: downloading a larger file; waiting for verification'
          : 'done $index';
      layoutWatch
        ..reset()
        ..start();
      root.layout(constraints);
      layoutWatch.stop();
      buffer.clear();
      root.paint(buffer, CellOffset.zero);
      frameWatch.stop();
      final stats = RenderLayoutDebugStats.takeFrameStats();
      if (frame >= 200) {
        performed += stats.performedCount;
        layoutTimes
            .add(layoutWatch.elapsedTicks * 1000000 / frameWatch.frequency);
        frameTimes
            .add(frameWatch.elapsedTicks * 1000000 / frameWatch.frequency);
      }
    }
    double percentile(List<double> values, double fraction) {
      values.sort();
      return double.parse(
          values[((values.length - 1) * fraction).round()].toStringAsFixed(2));
    }

    results['${texts.length}_panes'] = {
      'viewport': '${size.cols}x${size.rows}',
      'frames': frames,
      'layout_p50_us': percentile(layoutTimes, .5),
      'layout_p95_us': percentile(layoutTimes, .95),
      'frame_p50_us': percentile(frameTimes, .5),
      'frame_p95_us': percentile(frameTimes, .95),
      'layouts_per_frame': performed / frames,
    };
  }
  print(const JsonEncoder.withIndent('  ').convert(results));
}
