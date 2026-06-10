import 'dart:io';

import 'package:fleury/fleury_host.dart';
import 'package:test/test.dart';

void main() {
  test('host library exports the browser/native host SPI', () {
    final runtime = TuiRuntime();
    addTearDown(runtime.dispose);

    final frameLoop = TuiFrameLoop();
    final frame = frameLoop.render(
      size: const CellSize(1, 1),
      paint: (buffer) => buffer.writeText(CellOffset.zero, 'x'),
    );
    expect(frame, isNotNull);
    expect(frame!.damage.fullRepaint, isTrue);

    final rows = TuiDirtyRows.full(2);
    expect(rows.rows, [0, 1]);

    final scheduler = FrameScheduler(
      clock: SystemClock(),
      onRender: (_) {},
      flushScheduler: (_, flush) => flush(),
    );
    addTearDown(scheduler.dispose);
    scheduler.requestFrame('host-smoke');

    final semanticsOwner = SemanticsOwner();
    final update = semanticsOwner.update(
      SemanticTree(
        root: const SemanticNode(
          id: SemanticNodeId('root'),
          role: SemanticRole.app,
        ),
      ),
    );
    expect(update.added, {const SemanticNodeId('root')});
  });

  test('host-only symbols stay out of app-facing core exports', () {
    final coreExports = _exportLines('lib/fleury_core.dart');
    final nativeExports = _exportLines('lib/fleury.dart');
    final hostText = File('lib/fleury_host.dart').readAsStringSync();

    expect(hostText, contains("export 'fleury_core.dart';"));
    for (final symbol in <String>[
      'RenderDamageTracker',
      'FrameScheduler',
      'FrameFlushScheduler',
      'InputDispatcher',
      'TuiRuntime',
      'TuiFrameLoop',
      'TuiDirtyRows',
      'SemanticsOwner',
      'SemanticTreeUpdate',
      'invokeSemanticActionFromElement',
    ]) {
      expect(
        hostText,
        contains(symbol),
        reason: '$symbol belongs to package:fleury/fleury_host.dart.',
      );
      expect(
        coreExports,
        isNot(contains(symbol)),
        reason:
            '$symbol is host SPI and should not leak through '
            'package:fleury/fleury_core.dart.',
      );
      expect(
        nativeExports,
        isNot(contains(symbol)),
        reason:
            '$symbol is host SPI and should not leak directly through '
            'package:fleury/fleury.dart.',
      );
    }
  });
}

String _exportLines(String path) {
  return File(path)
      .readAsLinesSync()
      .map((line) => line.trimLeft())
      .where((line) => line.startsWith('export '))
      .join('\n');
}
