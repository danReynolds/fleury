import 'dart:convert';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart';
import 'package:fleury_widgets/fleury_widgets.dart' as widgets;

MouseEvent at(
  MouseEventKind kind,
  int col,
  int row, [
  MouseButton button = MouseButton.left,
]) => MouseEvent(kind: kind, button: button, col: col, row: row);

void click(
  FleuryTester tester,
  int col,
  int row, [
  MouseButton button = MouseButton.left,
]) {
  tester.sendMouse(at(MouseEventKind.down, col, row, button));
  tester.pump();
  tester.sendMouse(at(MouseEventKind.up, col, row, button));
  tester.pump();
}

void main() {
  final findings = <String, Object?>{};
  for (final app in [false, true]) {
    final tester = FleuryTester(viewportSize: const CellSize(40, 12));
    final a = FocusNode(debugLabel: 'a');
    final b = FocusNode(debugLabel: 'b');
    final controller = TextEditingController(text: 'abcdef');
    final pair = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 20, child: TextInput(focusNode: a, autofocus: true)),
        SizedBox(
          width: 20,
          child: TextInput(focusNode: b, controller: controller),
        ),
      ],
    );
    tester.pumpWidget(app ? FleuryApp(title: 'Probe', home: pair) : pair);
    final rect = b.rect!;
    click(tester, rect.left + 2, rect.top);
    findings['textInput_${app ? 'app' : 'bare'}'] = {
      'clickedFieldFocused': b.hasFocus,
      'caretAfterClickAtColumn2': controller.caretOffset,
      'expectedCaret': 2,
    };
    tester.type('X');
    findings['textInput_${app ? 'app' : 'bare'}_text'] = controller.text;
    tester.dispose();
    a.dispose();
    b.dispose();
    controller.dispose();
  }

  {
    final tester = FleuryTester(viewportSize: const CellSize(20, 5));
    final node = FocusNode();
    final controller = TextEditingController(text: 'first\nsecond');
    tester.pumpWidget(
      SizedBox(
        width: 12,
        height: 3,
        child: TextArea(focusNode: node, controller: controller),
      ),
    );
    click(tester, 1, 0);
    final afterClick = controller.caretOffset;
    tester.sendMouse(at(MouseEventKind.down, 1, 0));
    tester.sendMouse(at(MouseEventKind.drag, 4, 0));
    tester.sendMouse(at(MouseEventKind.up, 4, 0));
    findings['textArea'] = {
      'focused': node.hasFocus,
      'caretAfterClickAtColumn1': afterClick,
      'selectionAfterDrag': controller.selection.toString(),
    };
    tester.dispose();
    node.dispose();
    controller.dispose();
  }

  {
    final tester = FleuryTester();
    var pressed = false;
    final log = <String>[];
    tester.pumpWidget(
      GestureDetector(
        onTapDown: (_, _) {
          pressed = true;
          log.add('down');
        },
        onTapUp: (_, _) {
          pressed = false;
          log.add('up');
        },
        child: const SizedBox(width: 5, height: 1),
      ),
    );
    tester.sendMouse(at(MouseEventKind.down, 1, 0));
    tester.sendMouse(at(MouseEventKind.up, 8, 0));
    findings['releaseOutside'] = {'pressed': pressed, 'callbacks': log};
    tester.dispose();
  }

  {
    final tester = FleuryTester();
    final moves = <String>[];
    tester.pumpWidget(
      GestureDetector(
        onDragUpdate: (col, row) => moves.add('$col,$row'),
        child: const SizedBox(width: 5, height: 1),
      ),
    );
    tester.sendMouse(at(MouseEventKind.down, 1, 0));
    tester.sendMouse(at(MouseEventKind.drag, 3, 0));
    tester.sendMouse(at(MouseEventKind.up, 3, 0));
    findings['updateOnlyDrag'] = {
      'callbacks': moves,
      'expected': ['3,0'],
    };
    tester.dispose();
  }

  {
    final tester = FleuryTester();
    var taps = 0;
    tester.pumpWidget(
      GestureDetector(
        onTap: () => taps++,
        child: const SizedBox(width: 5, height: 1),
      ),
    );
    tester.sendMouse(at(MouseEventKind.down, 1, 0));
    tester.sendMouse(at(MouseEventKind.up, 1, 0, MouseButton.right));
    findings['mismatchedRelease'] = {'leftTaps': taps, 'expected': 0};
    tester.dispose();
  }

  {
    final tester = FleuryTester();
    final log = <String>[];
    tester.pumpWidget(
      MouseRegion(
        onEnter: () => log.add('outer enter'),
        onExit: () => log.add('outer exit'),
        child: SizedBox(
          width: 10,
          height: 1,
          child: Row(
            children: [
              const SizedBox(width: 3),
              MouseRegion(
                onEnter: () => log.add('inner enter'),
                onExit: () => log.add('inner exit'),
                child: const SizedBox(width: 3, height: 1),
              ),
            ],
          ),
        ),
      ),
    );
    tester.sendMouse(at(MouseEventKind.moved, 1, 0, MouseButton.none));
    tester.sendMouse(at(MouseEventKind.moved, 4, 0, MouseButton.none));
    findings['nestedHover'] = log;
    tester.dispose();
  }

  {
    final tester = FleuryTester(viewportSize: const CellSize(10, 2));
    final behind = FocusNode(debugLabel: 'behind');
    final front = FocusNode(debugLabel: 'front');
    var frontTaps = 0;
    tester.pumpWidget(
      Stack(
        children: [
          Focus(focusNode: behind, child: const SizedBox(width: 5, height: 1)),
          Focus(
            focusNode: front,
            child: GestureDetector(
              onTap: () => frontTaps++,
              child: const SizedBox(width: 5, height: 1),
            ),
          ),
        ],
      ),
    );
    click(tester, 1, 0);
    findings['overlappingFocus'] = {
      'frontTaps': frontTaps,
      'frontFocused': front.hasFocus,
      'behindFocused': behind.hasFocus,
    };
    tester.dispose();
    behind.dispose();
    front.dispose();
  }

  {
    final tester = FleuryTester(viewportSize: const CellSize(30, 4));
    final node = FocusNode();
    tester.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [TextInput(focusNode: node)],
      ),
    );
    findings['emptyInputHitArea'] = node.rect.toString();
    click(tester, 3, 0);
    findings['emptyInputClickColumn3Focused'] = node.hasFocus;
    tester.dispose();
    node.dispose();
  }

  {
    final tester = FleuryTester(viewportSize: const CellSize(20, 5));
    final outer = ScrollController();
    final inner = ScrollController(offset: 3);
    tester.pumpWidget(
      SizedBox(
        width: 20,
        height: 4,
        child: ScrollView(
          controller: outer,
          child: Column(
            children: [
              SizedBox(
                height: 2,
                child: ScrollView(
                  controller: inner,
                  child: const Text('a\nb\nc\nd\ne'),
                ),
              ),
              const Text('1\n2\n3\n4\n5\n6'),
            ],
          ),
        ),
      ),
    );
    tester.sendMouse(at(MouseEventKind.scrollDown, 1, 0, MouseButton.none));
    tester.pump();
    findings['nestedWheelAtInnerEdge'] = {
      'inner': inner.offset,
      'innerMax': inner.maxOffset,
      'outer': outer.offset,
      'outerMax': outer.maxOffset,
    };
    tester.dispose();
    outer.dispose();
    inner.dispose();
  }

  {
    final tester = FleuryTester(viewportSize: const CellSize(20, 4));
    final log = <String>[];
    tester.pumpWidget(
      SizedBox(
        width: 20,
        child: widgets.RangeSlider(
          values: (20, 80),
          min: 0,
          max: 100,
          onChanged: (value) => log.add(value.toString()),
        ),
      ),
    );
    click(tester, 10, 0, MouseButton.right);
    findings['rangeSliderRightClickChanges'] = log;
    tester.dispose();
  }

  {
    final tester = FleuryTester(viewportSize: const CellSize(30, 6));
    final log = <String>[];
    tester.pumpWidget(
      Padding(
        padding: const EdgeInsets.only(left: 10, top: 2),
        child: GestureDetector(
          onTapDown: (c, r) => log.add('down $c,$r'),
          onDragStart: (c, r) => log.add('start $c,$r'),
          onDragUpdate: (c, r) => log.add('update $c,$r'),
          child: const SizedBox(width: 6, height: 1),
        ),
      ),
    );
    tester.sendMouse(at(MouseEventKind.down, 11, 2));
    tester.sendMouse(at(MouseEventKind.drag, 12, 2));
    tester.sendMouse(at(MouseEventKind.drag, 14, 2));
    findings['paddedDragCoordinates'] = log;
    tester.dispose();
  }

  {
    final tester = FleuryTester(viewportSize: const CellSize(20, 6));
    final node = FocusNode(debugLabel: 'partially clipped');
    final scroll = ScrollController(offset: 2);
    tester.pumpWidget(
      Column(
        children: [
          const SizedBox(height: 2),
          SizedBox(
            width: 10,
            height: 3,
            child: ScrollView(
              controller: scroll,
              child: Focus(
                focusNode: node,
                child: const SizedBox(width: 10, height: 6),
              ),
            ),
          ),
        ],
      ),
    );
    final before = node.hasFocus;
    click(tester, 1, 0);
    findings['clippedFocusOutsideViewport'] = {
      'before': before,
      'afterClickAboveViewport': node.hasFocus,
      'rect': node.rect.toString(),
      'viewportRows': '2..5',
    };
    tester.dispose();
    node.dispose();
    scroll.dispose();
  }

  print(const JsonEncoder.withIndent('  ').convert(findings));
}
