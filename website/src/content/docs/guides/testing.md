---
title: Testing
description: Render and drive widgets headlessly with FleuryTester — no terminal.
---

Fleury has no real terminal in its test loop. You mount a widget tree, render it
to a grid of cells, and assert on the output — the cells themselves, or the
semantic graph behind them. Two payoffs fall out of that: tests run at plain
unit-test speed and stay deterministic (you advance the clock yourself), and
assertions on *meaning* — "row 3 is selected", "the gauge reads 0.62" — survive a
re-theme, a relayout, or the port to the browser. The harness is `FleuryTester`,
exposed through `testWidgets`.

Add the companion package as a dev dependency so the test runner, matcher, and
golden-file I/O stay out of production applications:

```yaml
dev_dependencies:
  fleury_test:
    git:
      url: https://github.com/danReynolds/fleury.git
      path: packages/fleury_test
  test: ^1.26.3
```

While Fleury's packages are unpublished, keep the `fleury` dependency override
from [Getting started](/getting-started/) so the app and `fleury_test` resolve
the same Git checkout. After the packages are published together, replace the
Git entry with `fleury_test: ^0.1.0` and remove that temporary override.

```dart
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
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

- `pumpWidget(widget)` mounts (or replaces) the exact, bare tree. Use it for
  isolated widgets and custom shells.
- `pumpFleuryHome(widget)` mounts the widget as `FleuryApp(home: widget)`. Use it
  when the tester should construct the canonical route stack and app scopes. A
  complete application root still belongs in `pumpWidget`.
- `render(size:)` returns a `CellBuffer` — inspect individual cells with
  `buf.atColRow(col, row)` (grapheme + style).
- `renderToString(size:)` flattens the buffer to text, which is the quickest
  thing to assert against.

For example, a navigation test that wants the standard shell starts with
`pumpFleuryHome`:

```dart
testWidgets('opens details', (tester) async {
  tester.pumpFleuryHome(const HomeScreen());
  await tester.invokeSemanticAction(
    SemanticAction.activate,
    role: SemanticRole.button,
    label: 'Open details',
  );
  expect(tester.exists(text('Details')), isTrue);
});
```

## Drive input

Send key events and re-render to test interactions:

```dart
testWidgets('enter submits', (tester) {
  var submitted = false;
  final controller = TextEditingController(text: 'ship it');
  tester.pumpWidget(TextInput(
    controller: controller,
    onSubmit: (text) => submitted = true,
  ));
  tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
  expect(submitted, isTrue);
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
