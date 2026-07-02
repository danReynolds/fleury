// End-to-end integration tests: build a widget tree, mount it, run a
// frame through the BuildOwner, and assert on either the resulting
// CellBuffer or the ANSI bytes the renderer emits.
//
// These tests are the highest-value defense-against-regression in the
// suite because a break anywhere in the stack — widgets, elements,
// render objects, layout, cell buffer, sanitizer, ANSI renderer — will
// surface here.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

String _flatten(CellBuffer buffer) {
  final out = StringBuffer();
  for (var row = 0; row < buffer.size.rows; row++) {
    for (var col = 0; col < buffer.size.cols; col++) {
      final c = buffer.atColRow(col, row);
      switch (c.role) {
        case CellRole.empty:
          out.write('·');
        case CellRole.leading:
          out.write(c.grapheme);
        case CellRole.continuation:
        case CellRole.overlay:
          // Continuation cells contribute nothing.
          break;
      }
    }
    if (row < buffer.size.rows - 1) out.write('\n');
  }
  return out.toString();
}

void main() {
  group('Single Text widget', () {
    test('mounts, lays out, paints into the buffer', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(const Text('hello'));
      final buf = CellBuffer(const CellSize(10, 1));

      owner.renderFrame(root, buf);

      expect(_flatten(buf), 'hello·····');
    });

    test('clips to buffer width when text overflows', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(const Text('hello world'));
      final buf = CellBuffer(const CellSize(5, 1));

      owner.renderFrame(root, buf);
      expect(_flatten(buf), 'hello');
    });

    test('sanitizes hostile input before painting', () {
      final owner = BuildOwner();
      const hostile = '\x1B[2Ja';
      final root = owner.mountRoot(const Text(hostile));
      final buf = CellBuffer(const CellSize(10, 1));

      owner.renderFrame(root, buf);

      // Sanitizer collapses the full CSI sequence to U+FFFD.
      final firstCell = buf.atColRow(0, 0);
      expect(firstCell.role, CellRole.leading);
      expect(firstCell.grapheme, replacementCharacter);
      expect(buf.atColRow(1, 0).grapheme, 'a');
    });
  });

  group('Padding around Text', () {
    test('shifts the text by the inset and grows total size', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(
        const Padding(padding: EdgeInsets.all(1), child: Text('hi')),
      );
      final buf = CellBuffer(const CellSize(4, 3));

      owner.renderFrame(root, buf);

      expect(_flatten(buf), '····\n·hi·\n····');
    });

    test('asymmetric padding positions the text precisely', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(
        const Padding(
          padding: EdgeInsets.only(left: 2, top: 1),
          child: Text('X'),
        ),
      );
      final buf = CellBuffer(const CellSize(4, 3));

      owner.renderFrame(root, buf);

      expect(_flatten(buf), '····\n··X·\n····');
    });
  });

  group('SizedBox', () {
    test('forces a fixed size on the subtree', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(
        const SizedBox(width: 3, height: 1, child: Text('hello')),
      );
      final buf = CellBuffer(const CellSize(8, 1));

      owner.renderFrame(root, buf);

      // Text inside the SizedBox is clipped to width 3.
      expect(_flatten(buf), 'hel·····');
    });
  });

  group('Container', () {
    test('composes Padding + SizedBox', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(
        const Container(
          width: 4,
          height: 3,
          padding: EdgeInsets.all(1),
          child: Text('A'),
        ),
      );
      final buf = CellBuffer(const CellSize(6, 4));

      owner.renderFrame(root, buf);

      // 4x3 container starting at (0,0); 1-cell padding on each side
      // places 'A' at (1,1). Remaining buffer is empty.
      expect(_flatten(buf), '······\n·A····\n······\n······');
    });
  });

  group('Renderer pipeline', () {
    test('paints + AnsiRenderer produces the expected SGR-free output', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(const Text('hi'));
      final buf = CellBuffer(const CellSize(3, 1));
      owner.renderFrame(root, buf);

      final sink = StringAnsiSink();
      const AnsiRenderer(synchronizedOutput: false).renderFull(buf, sink);

      // Default style → no SGR; just cursor + content.
      expect(sink.output, '\x1B[Hhi');
    });

    test('two-frame cycle: diff only emits changed cells', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(const _Counter(value: 1));
      final prev = CellBuffer(const CellSize(5, 1));
      final next = CellBuffer(const CellSize(5, 1));

      owner.renderFrame(root, prev);
      owner.updateRoot(root, const _Counter(value: 2));
      owner.renderFrame(root, next);

      final sink = StringAnsiSink();
      const AnsiRenderer(
        synchronizedOutput: false,
      ).renderDiff(prev, next, sink);

      // Only column 0 differs between '1····' and '2····'.
      expect(sink.output, '\x1B[H2');
    });
  });

  group('State preservation across rebuild', () {
    test('an internal counter survives a parent-driven rebuild', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(const _StatefulCounter()) as StatefulElement;
      final state = root.state as _StatefulCounterState;

      final buf1 = CellBuffer(const CellSize(5, 1));
      owner.renderFrame(root, buf1);
      expect(_flatten(buf1), '0····');

      state.poke(() => state.count = 7);
      final buf2 = CellBuffer(const CellSize(5, 1));
      owner.renderFrame(root, buf2);

      expect(_flatten(buf2), '7····');
    });
  });

  group('Row / Column / Expanded', () {
    test('Row places inflexible children left-to-right', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(
        const Row(children: [Text('hi'), Text('bye')]),
      );
      final buf = CellBuffer(const CellSize(8, 1));
      owner.renderFrame(root, buf);
      // 'hi' at cols 0-1, 'bye' at cols 2-4, rest empty.
      expect(_flatten(buf), 'hibye···');
    });

    test('Row with two Expanded splits the buffer evenly', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(
        const Row(
          children: [
            Expanded(child: Text('L')),
            Expanded(child: Text('R')),
          ],
        ),
      );
      final buf = CellBuffer(const CellSize(10, 1));
      owner.renderFrame(root, buf);
      // Left pane = 5 cells, right pane = 5 cells. Text lays out one
      // grapheme at the start of each pane.
      expect(buf.atColRow(0, 0).grapheme, 'L');
      expect(buf.atColRow(5, 0).grapheme, 'R');
    });

    test('Row sidebar + Expanded pane gets typical chat layout', () {
      // 20-col buffer, sidebar = fixed 5, pane = remaining 15.
      final owner = BuildOwner();
      final root = owner.mountRoot(
        const Row(
          children: [
            SizedBox(width: 5, child: Text('LIST')),
            Expanded(child: Text('PANE')),
          ],
        ),
      );
      final buf = CellBuffer(const CellSize(20, 1));
      owner.renderFrame(root, buf);
      expect(buf.atColRow(0, 0).grapheme, 'L');
      expect(buf.atColRow(3, 0).grapheme, 'T'); // 'LIST'
      expect(buf.atColRow(5, 0).grapheme, 'P');
      expect(buf.atColRow(8, 0).grapheme, 'E'); // 'PANE'
    });

    test('Row flex 1:4 distributes 120 cells as 24:96', () {
      // Maps to the RFC example.
      final owner = BuildOwner();
      final root = owner.mountRoot(
        const Row(
          children: [
            Expanded(flex: 1, child: Text('A')),
            Expanded(flex: 4, child: Text('B')),
          ],
        ),
      );
      final buf = CellBuffer(const CellSize(120, 1));
      owner.renderFrame(root, buf);
      // First pane starts at col 0, second pane starts at col 24.
      expect(buf.atColRow(0, 0).grapheme, 'A');
      expect(buf.atColRow(24, 0).grapheme, 'B');
    });

    test('Column stacks rows top-to-bottom', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(
        const Column(children: [Text('top'), Text('mid'), Text('bot')]),
      );
      final buf = CellBuffer(const CellSize(5, 3));
      owner.renderFrame(root, buf);
      expect(_flatten(buf), 'top··\nmid··\nbot··');
    });

    test('Column with Expanded splits height', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(
        const Column(
          children: [
            Expanded(child: Text('A')),
            Expanded(child: Text('B')),
          ],
        ),
      );
      final buf = CellBuffer(const CellSize(2, 4));
      owner.renderFrame(root, buf);
      // 4 rows split evenly: A at row 0, B at row 2.
      expect(buf.atColRow(0, 0).grapheme, 'A');
      expect(buf.atColRow(0, 2).grapheme, 'B');
    });
  });

  group('Stack', () {
    test('positioned overlay paints on top of base content', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(
        const Stack(
          children: [
            Text('hello'),
            Positioned(left: 2, top: 0, child: Text('!')),
          ],
        ),
      );
      final buf = CellBuffer(const CellSize(7, 1));
      owner.renderFrame(root, buf);
      // 'he!lo' — '!' at col 2 overwrites the 'l'.
      expect(_flatten(buf), 'he!lo··');
    });

    test('modal overlay overwrites the base text on the same row', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(
        const Stack(
          children: [
            Text('base text'),
            Positioned(
              left: 2,
              top: 0,
              width: 5,
              height: 1,
              child: Text('MODAL'),
            ),
          ],
        ),
      );
      final buf = CellBuffer(const CellSize(10, 1));
      owner.renderFrame(root, buf);
      // 'ba' from base; 'MODAL' from overlay; 'xt' from base (cols 7-8);
      // last col empty.
      expect(_flatten(buf), 'baMODALxt·');
    });

    test(
      'Stack at root: empty rows below the largest non-positioned child',
      () {
        final owner = BuildOwner();
        final root = owner.mountRoot(const Stack(children: [Text('hi')]));
        final buf = CellBuffer(const CellSize(5, 3));
        owner.renderFrame(root, buf);
        // Stack sizes to 'hi' (2x1). Buffer is 5x3; rest stays empty.
        expect(_flatten(buf), 'hi···\n·····\n·····');
      },
    );

    test('wide-grapheme eviction across overlapping Stack children', () {
      // RFC P0 gate #8: Stack overlays paint correctly, including
      // evicting any wide-grapheme continuations they cross.
      final owner = BuildOwner();
      final root = owner.mountRoot(
        const Stack(
          children: [
            Text('中文'), // 中(L)@0, cont@1, 文(L)@2, cont@3
            // Overlay at col 1 — the continuation of '中'.
            Positioned(left: 1, top: 0, width: 1, height: 1, child: Text('!')),
          ],
        ),
      );
      final buf = CellBuffer(const CellSize(5, 1));
      owner.renderFrame(root, buf);
      // Per CellBuffer eviction: writing at col 1 (continuation) clears
      // the leading '中' at col 0. Result: empty, '!', '文', cont, empty.
      expect(buf.atColRow(0, 0).role, CellRole.empty);
      expect(buf.atColRow(1, 0).grapheme, '!');
      expect(buf.atColRow(2, 0).grapheme, '文');
      expect(buf.atColRow(3, 0).role, CellRole.continuation);
      expect(buf.atColRow(4, 0).role, CellRole.empty);
    });
  });
}

class _Counter extends StatelessWidget {
  const _Counter({required this.value});
  final int value;

  @override
  Widget build(BuildContext context) => Text('$value');
}

class _StatefulCounter extends StatefulWidget {
  const _StatefulCounter();
  @override
  State<_StatefulCounter> createState() => _StatefulCounterState();
}

class _StatefulCounterState extends State<_StatefulCounter> {
  int count = 0;

  void poke(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) => Text('$count');
}
