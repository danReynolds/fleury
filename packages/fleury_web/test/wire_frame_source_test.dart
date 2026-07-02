// The serve client's handling of the v3 parity frames, driven directly
// (no socket): CLIPBOARD_WRITE lands on the host-assembled clipboard and
// answers with CLIPBOARD_RESULT; CARET positions the IME capture element
// without error; a failed action result logs rather than throws.

@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:fleury_web/src/host/wire_frame_source.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

final class _RecordingClipboard extends Clipboard {
  final writes = <String>[];
  var deny = false;

  @override
  String? readInProcess() => writes.isEmpty ? null : writes.last;

  @override
  Future<ClipboardWriteReport> writeWithReport(
    String text, {
    ClipboardWritePolicy policy = ClipboardWritePolicy.standard,
  }) async {
    writes.add(text);
    return ClipboardWriteReport(
      result: deny
          ? ClipboardWriteResult.inProcessOnly
          : ClipboardWriteResult.platformTool,
      resolution: const CapabilityResolution(
        feature: TerminalFeature.clipboardWrite,
        level: CapabilityLevel.preferred,
        state: CapabilityResolutionState.available,
      ),
      policy: policy,
      payloadBytes: text.length,
      osc52EncodedLength: 0,
      overSsh: false,
      inProcessUpdated: true,
      platformToolAttempted: false,
      osc52Attempted: false,
      osc52Emitted: false,
    );
  }
}

List<RemoteFrame> _decodeAll(List<Uint8List> wire) {
  final decoder = FrameDecoder();
  for (final bytes in wire) {
    decoder.feed(bytes);
  }
  return decoder.drain().toList();
}

void main() {
  late web.HTMLElement into;
  late _RecordingClipboard clipboard;
  late WireFrameSource source;

  setUp(() {
    into = web.document.createElement('div') as web.HTMLElement;
    web.document.body!.appendChild(into);
    clipboard = _RecordingClipboard();
    final components = BrowserPresentationHost(
      into: into,
      clipboard: clipboard,
    ).assemble();
    source = WireFrameSource(url: 'ws://unused/')
      ..attachComponentsForTest(components);
    addTearDown(() {
      components.removeGeneratedRoots();
      into.remove();
    });
  });

  test('CLIPBOARD_WRITE lands on the host clipboard and answers', () async {
    source.handleFrameForTest(const ClipboardWriteFrame(9, 'from the app'));
    await Future<void>.delayed(Duration.zero);

    expect(clipboard.writes, ['from the app']);
    final results = _decodeAll(
      source.sentForTest,
    ).whereType<ClipboardResultFrame>().toList();
    expect(results, hasLength(1));
    expect(results.single.seq, 9);
    expect(results.single.status, RemoteClipboardStatus.written);
  });

  test('a denied clipboard write answers denied', () async {
    clipboard.deny = true;
    source.handleFrameForTest(const ClipboardWriteFrame(3, 'nope'));
    await Future<void>.delayed(Duration.zero);

    final results = _decodeAll(
      source.sentForTest,
    ).whereType<ClipboardResultFrame>().toList();
    expect(results.single.seq, 3);
    expect(results.single.status, RemoteClipboardStatus.denied);
  });

  test('CARET frames position the IME capture element without error', () {
    source.handleFrameForTest(CaretFrame(CellRect.fromLTWH(4, 2, 1, 1)));
    source.handleFrameForTest(const CaretFrame(null));
  });

  test('a failed action result is absorbed (logged), not thrown', () {
    source.handleFrameForTest(
      const SemanticActionResultFrame(
        SemanticNodeId('save'),
        SemanticAction.activate,
        SemanticActionInvocationStatus.failed,
      ),
    );
  });
}
