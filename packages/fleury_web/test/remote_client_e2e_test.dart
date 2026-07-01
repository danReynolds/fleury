// End-to-end composition in a real browser: server-encoded wire bytes (a
// PlanFrame + a SemanticsFrame, produced by the actual serve encoder) are
// decoded and rendered through the real DOM surface AND the real accessible
// semantic presenter — the same two calls RemoteSurfaceClient makes per frame.
// The live-socket transport half is covered by the VM `serve_e2e_socket_test`;
// this closes the browser-DOM half of the composition gap, for both the visual
// grid and the semantics a terminal-emulator relay tool structurally cannot
// carry.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:fleury/fleury_host.dart';
import 'package:fleury/src/remote/remote_codec.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:fleury/src/remote/remote_semantics.dart';
import 'package:fleury_web/src/dom_grid/dom_grid_surface.dart';
import 'package:fleury_web/src/remote_client/plan_adapter.dart';
import 'package:fleury_web/src/semantics/semantic_dom_presenter.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  test(
    'server-encoded plan + semantics render to grid DOM and accessible DOM',
    () {
      const size = CellSize(24, 4);

      // --- Server side: render two frames + a semantic snapshot, encode. ---
      final blank = CellBuffer(size);
      final frame0 = CellBuffer(size)
        ..writeText(const CellOffset(0, 0), 'status: ready')
        ..writeText(const CellOffset(0, 2), '[ Run ]');
      final frame1 = CellBuffer(size)
        ..writeText(const CellOffset(0, 0), 'status: running')
        ..writeText(const CellOffset(0, 2), '[ Run ]');

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

      final wire = <int>[
        ...encodeFrame(
          PlanFrame(buildRemotePlan(blank, frame0, fullRepaint: true)),
        ),
        ...encodeFrame(
          PlanFrame(buildRemotePlan(frame0, frame1, fullRepaint: false)),
        ),
        ...encodeFrame(
          SemanticsFrame(
            SemanticsWireEncoder().encode(tree.toInspectionSnapshot())!,
          ),
        ),
      ];

      // --- Client side: build the real surfaces, decode, and compose. ---
      final gridRoot = web.document.createElement('div');
      final semanticRoot = web.document.createElement('div');
      web.document.body!.append(gridRoot);
      web.document.body!.append(semanticRoot);
      addTearDown(() {
        gridRoot.remove();
        semanticRoot.remove();
      });

      final surface = DomGridSurface(root: gridRoot, size: size);
      final presenter = SemanticDomPresenter(root: semanticRoot);
      addTearDown(presenter.dispose);
      final mirror = CellBuffer(size);
      final semanticsDecoder = SemanticsWireDecoder();

      for (final frame
          in (FrameDecoder()..feed(Uint8List.fromList(wire))).drain()) {
        switch (frame) {
          case PlanFrame f:
            final plan = applyRemotePlan(f.plan, mirror);
            surface.present(mirror, mirror, plan);
          case SemanticsFrame f:
            final tree = semanticsDecoder.apply(f.json);
            if (tree != null) presenter.present(tree);
          default:
            break;
        }
      }

      // The visual grid DOM shows the server's final frame.
      expect(
        surface.rowElements[0].textContent?.trimRight(),
        'status: running',
      );
      expect(surface.rowElements[2].textContent?.trimRight(), '[ Run ]');

      // The accessible DOM exposes the app's roles, labels, and actions — the
      // path that keeps a served session screen-reader- and agent-readable.
      final button = semanticRoot.querySelector(
        '[data-fleury-semantic-id="btn:run"]',
      )!;
      expect(button.getAttribute('role'), 'button');
      expect(button.getAttribute('aria-label'), 'Run');
      expect(button.getAttribute('data-fleury-actions'), 'activate');

      final status = semanticRoot.querySelector(
        '[data-fleury-semantic-id="status"]',
      )!;
      expect(status.getAttribute('role'), 'status');
      expect(status.getAttribute('aria-live'), 'polite');
    },
  );
}
