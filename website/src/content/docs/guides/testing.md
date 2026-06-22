---
title: Testing
description: Render and drive widgets headlessly with FleuryTester — no terminal.
---

Fleury widgets are tested without a real terminal: you pump a widget tree,
render it to a grid of cells, and assert on the output — the rendered cells or
the semantic graph. The harness is `FleuryTester`, exposed through `testWidgets`.

```dart
import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('renders a greeting', (tester) {
    tester.pumpWidget(const Text('hello'));
    final out = tester.renderToString(size: const CellSize(20, 3));
    expect(out, contains('hello'));
  });
}
```

## Render and assert

- `pumpWidget(widget)` mounts (or replaces) the tree.
- `render(size:)` returns a `CellBuffer` — inspect individual cells with
  `buf.atColRow(col, row)` (grapheme + style).
- `renderToString(size:)` flattens the buffer to text, which is the quickest
  thing to assert against.

## Drive input

Send key events and re-render to test interactions:

```dart
testWidgets('enter submits', (tester) {
  tester.pumpWidget(TextInput(controller: controller, onSubmit: onSubmit));
  tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
  tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
  expect(tester.renderToString(size: const CellSize(40, 5)), contains('…'));
});
```

## Advance time

`pump([duration])` advances the scheduler and any active tickers, so you can
test animations and streaming UIs deterministically:

```dart
tester.pumpWidget(const Dashboard());
tester.pump(const Duration(seconds: 1)); // ~30 ticks at the default cadence
// assert the chart scrolled, the clock advanced, etc.
```

`pumpAndSettle()` pumps until no tickers are active.

## The parity oracle

Because the framework targets both a terminal and the browser, the suite
includes an oracle that asserts the two surfaces render the *same* tree — so a
change can't silently diverge between ANSI output and the DOM grid.
