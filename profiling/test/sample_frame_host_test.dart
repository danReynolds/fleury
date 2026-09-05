import 'package:fleury/fleury.dart';
// This unpublished host regression checks the runtime's internal input policy.
// ignore_for_file: invalid_use_of_internal_member
import 'package:test/test.dart';

import '../bin/sample_frame_host.dart';

void main() {
  test('failed paint aborts pointer and focus input, then a frame recovers',
      () {
    final toggle = _FailureToggle();
    final focus = FocusNode();
    var taps = 0;
    final host = SampleFrameHost(
      Focus(
          focusNode: focus,
          autofocus: true,
          child:
              GestureDetector(onTap: () => taps++, child: _PaintProbe(toggle))),
      const CellSize(5, 1),
    );
    addTearDown(() {
      host.tester.dispose();
      focus.dispose();
    });
    PointerRouter? router;
    void visit(Element element) {
      if (element.widget case PointerRouterScope(router: final currentRouter)) {
        // The tester installs one root router around this app.
        router = currentRouter;
      }
      element.visitChildren(visit);
    }

    visit(host.tester.root!);
    expect(router, isNotNull);
    expect(focus.acceptsInput, isTrue);

    toggle.fail = true;
    expect(() => host.frame('full', 0), throwsStateError);
    expect(focus.acceptsInput, isFalse);
    const events = [
      MouseEvent(
          kind: MouseEventKind.down, button: MouseButton.left, col: 1, row: 0),
      MouseEvent(
          kind: MouseEventKind.up, button: MouseButton.left, col: 1, row: 0),
    ];
    for (final event in events) {
      expect(router!.route(event), isFalse);
    }
    expect(taps, 0);
    toggle.fail = false;
    host.frame('full', 1);
    expect(focus.acceptsInput, isTrue);
    for (final event in events) {
      router!.route(event);
    }
    expect(taps, 1);
  });
}

class _FailureToggle {
  bool fail = false;
}

class _PaintProbe extends LeafRenderObjectWidget {
  const _PaintProbe(this.toggle);
  final _FailureToggle toggle;
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderProbe(toggle);
}

class _RenderProbe extends RenderObject {
  _RenderProbe(this.toggle);
  final _FailureToggle toggle;
  @override
  CellSize performLayout(CellConstraints constraints) =>
      constraints.constrain(const CellSize(5, 1));
  @override
  void paint(CellBuffer buffer, CellOffset offset,
      {CellOffset? screenOffset, CellRect? clipRect}) {
    if (toggle.fail) throw StateError('probe paint failure');
    buffer.writeText(offset, 'probe');
  }
}
