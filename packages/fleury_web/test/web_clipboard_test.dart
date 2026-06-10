@TestOn('browser')
library;

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/clipboard/web_clipboard.dart';
import 'package:test/test.dart';

void main() {
  test('WebClipboard reports browser write success', () async {
    final writes = <String>[];
    final clipboard = WebClipboard(
      secureContext: true,
      writeText: (text) async => writes.add(text),
    );

    final report = await clipboard.writeWithReport('copy');

    expect(writes, ['copy']);
    expect(clipboard.readInProcess(), 'copy');
    expect(report.result, ClipboardWriteResult.platformTool);
    expect(report.resolution.state, CapabilityResolutionState.available);
    expect(report.platformToolAttempted, isTrue);
    expect(report.platformTool, 'navigator.clipboard.writeText');
    expect(report.inProcessUpdated, isTrue);
  });

  test('WebClipboard falls back when browser write is denied', () async {
    final clipboard = WebClipboard(
      secureContext: true,
      writeText: (_) async => throw StateError('denied'),
    );

    final report = await clipboard.writeWithReport('copy');

    expect(clipboard.readInProcess(), 'copy');
    expect(report.result, ClipboardWriteResult.inProcessOnly);
    expect(report.resolution.state, CapabilityResolutionState.degraded);
    expect(report.resolution.fallbackLabel, 'in-process register');
    expect(report.resolution.warning, contains('denied'));
    expect(report.platformToolAttempted, isTrue);
    expect(report.platformTool, 'navigator.clipboard.writeText');
  });

  test(
    'WebClipboard records insecure-context fallback without attempting write',
    () async {
      var attempted = false;
      final clipboard = WebClipboard(
        secureContext: false,
        writeText: (_) async => attempted = true,
      );

      final report = await clipboard.writeWithReport('copy');

      expect(attempted, isFalse);
      expect(clipboard.readInProcess(), 'copy');
      expect(report.result, ClipboardWriteResult.inProcessOnly);
      expect(report.resolution.state, CapabilityResolutionState.unsafe);
      expect(report.resolution.fallbackLabel, 'in-process register');
      expect(report.platformToolAttempted, isFalse);
      expect(report.platformTool, isNull);
    },
  );

  test(
    'WebClipboard records unavailable API fallback without attempting write',
    () async {
      var attempted = false;
      final clipboard = WebClipboard(
        secureContext: true,
        clipboardAvailable: false,
        writeText: (_) async => attempted = true,
      );

      final report = await clipboard.writeWithReport('copy');

      expect(attempted, isFalse);
      expect(clipboard.readInProcess(), 'copy');
      expect(report.result, ClipboardWriteResult.inProcessOnly);
      expect(report.resolution.state, CapabilityResolutionState.degraded);
      expect(report.resolution.warning, contains('unavailable'));
      expect(report.resolution.fallbackLabel, 'in-process register');
      expect(report.platformToolAttempted, isFalse);
      expect(report.platformTool, isNull);
    },
  );
}
