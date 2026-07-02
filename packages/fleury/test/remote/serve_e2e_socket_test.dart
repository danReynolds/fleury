// End-to-end through a *live* WebSocket: the structured serve path carries
// both render-intent (PlanFrame) and semantics (SemanticsFrame) over a real
// socket — including Dart's default permessage-deflate — and the client
// composes them exactly as the browser client does (apply patches to a cell
// mirror; reconstruct a SemanticTree from the snapshot). The VM cannot paint
// the DOM, so the mirror→DOM step is covered by the Chrome surface tests; this
// closes the transport-composition half of the gap on a genuine socket.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

String _row(CellBuffer b, int r) {
  final sb = StringBuffer();
  for (var c = 0; c < b.size.cols; c++) {
    sb.write(b.atColRow(c, r).grapheme ?? ' ');
  }
  return sb.toString().trimRight();
}

void main() {
  test(
    'plan + semantics survive a live WebSocket and compose on the client',
    () async {
      const size = CellSize(24, 4);

      // Server side: render two frames (a full first paint, then a partial
      // update) and a semantic snapshot — the same outputs the serve host emits.
      final blank = CellBuffer(size);
      final frame0 = CellBuffer(size)
        ..writeText(const CellOffset(0, 0), 'status: ready')
        ..writeText(const CellOffset(0, 2), '[ Run ]');
      final plan0 = buildRemotePlan(blank, frame0, fullRepaint: true);

      final frame1 = CellBuffer(size)
        ..writeText(const CellOffset(0, 0), 'status: running')
        ..writeText(const CellOffset(0, 2), '[ Run ]');
      final plan1 = buildRemotePlan(frame0, frame1, fullRepaint: false);

      final tree = SemanticTree(
        root: SemanticNode(
          id: const SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            const SemanticNode(
              id: SemanticNodeId('status'),
              role: SemanticRole.status,
              label: 'running',
            ),
            SemanticNode(
              id: const SemanticNodeId('btn:run'),
              role: SemanticRole.button,
              label: 'Run',
              actions: const {SemanticAction.activate},
            ),
          ],
        ),
      );
      final semanticsBytes = SemanticsWireEncoder().encode(
        tree.toInspectionSnapshot(),
      )!;

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.transform(WebSocketTransformer()).listen((ws) {
        ws.add(encodeFrame(PlanFrame(plan0)));
        ws.add(encodeFrame(PlanFrame(plan1)));
        ws.add(encodeFrame(SemanticsFrame(semanticsBytes)));
      });

      // Client side: connect over the socket and run the exact composition the
      // browser client runs — decode → apply to a mirror; decode → reconstruct.
      final client = await WebSocket.connect('ws://127.0.0.1:${server.port}/');
      final mirror = CellBuffer(size);
      final decoder = FrameDecoder();
      final semanticsDecoder = SemanticsWireDecoder();
      SemanticTree? semantics;
      final done = Completer<void>();
      client.listen((data) {
        decoder.feed(
          data is Uint8List ? data : Uint8List.fromList(data as List<int>),
        );
        for (final frame in decoder.drain()) {
          switch (frame) {
            case PlanFrame f:
              applyRemotePlanToBuffer(f.plan, mirror);
            case SemanticsFrame f:
              semantics = semanticsDecoder.apply(f.json);
              if (!done.isCompleted) done.complete();
            default:
              break;
          }
        }
      });
      await done.future.timeout(const Duration(seconds: 5));
      await client.close();

      // The visual mirror reproduces the server's final frame, cell-for-cell.
      expect(_row(mirror, 0), 'status: running');
      expect(_row(mirror, 2), '[ Run ]');

      // The semantic tree arrived and reconstructs the app's roles and actions.
      final received = semantics;
      expect(received, isNotNull);
      expect(received!.root.role, SemanticRole.app);
      final button = received.root.children.firstWhere(
        (n) => n.role == SemanticRole.button,
      );
      expect(button.label, 'Run');
      expect(button.actions, {SemanticAction.activate});
    },
  );
}
