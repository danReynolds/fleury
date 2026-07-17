<p align="center">
  <img src="assets/fleury-icon.png" alt="Fleury" width="120" height="120">
</p>

<h1 align="center">Fleury</h1>

<p align="center">
  A retained-mode UI framework for the terminal — and the browser.<br>
  One widget tree, two surfaces.
</p>

<p align="center">
  <a href="https://danreynolds.github.io/fleury/"><strong>Documentation</strong></a> ·
  <a href="https://danreynolds.github.io/fleury/getting-started/">Get started</a> ·
  <a href="https://danreynolds.github.io/fleury/widgets/">Widgets</a> ·
  <a href="https://danreynolds.github.io/fleury/showcases/">Showcases</a>
</p>

---

Fleury brings a Flutter-shaped authoring model to cell-based interfaces:
compose widgets, keep state with `StatefulWidget`, rebuild with `setState`, and
let the framework incrementally lay out and paint the result.

The same reusable widget tree can run in a native terminal or mount into a web
page. Alongside the visual tree, Fleury builds a semantic graph that tests and
AI agents can inspect and operate by meaning instead of terminal coordinates.

## Why Fleury

- **A familiar retained UI model.** Widgets, state, context, keys, constraints,
  focus, navigation, animation, and inherited dependencies compose the way
  application developers expect.
- **Terminal-native rendering.** Fleury paints grapheme-aware cells and sends
  diffed ANSI output instead of treating the terminal like a pixel canvas.
- **Terminal and browser targets.** Share application UI while choosing a
  native terminal host, a client-side web mount, or a served browser session.
- **A real widget library.** Forms, tables, trees, charts, document views, and
  agent-oriented surfaces live in `fleury_widgets`.
- **Semantics from the start.** The same semantic model supports testing,
  browser accessibility, inspection, and agent actions.

## A Fleury app

```dart
import 'package:fleury/fleury.dart';

void main() => runApp(
  const FleuryApp(
    title: 'My app',
    home: Center(child: Text('Hello, cells!')),
  ),
);
```

The [getting-started guide](https://danreynolds.github.io/fleury/getting-started/)
covers installation, state, higher-level widgets, and running the same tree in
a browser.

## Go deeper

- [Browse the widget catalog](https://danreynolds.github.io/fleury/widgets/)
- [Build a multi-screen app](https://danreynolds.github.io/fleury/guides/navigation/)
- [Understand the architecture](https://danreynolds.github.io/fleury/architecture/overview/)
- [Drive an app with an agent](https://danreynolds.github.io/fleury/guides/driving-with-agents/)

## Working on Fleury

From a checkout, bootstrap the workspace and run the normal validation gate:

```sh
dart tool/fleury_dev.dart bootstrap
dart tool/fleury_dev.dart check --quick
```

Contributor notes and architecture records live under [`docs/`](docs/); the
public documentation is built from `website/`.
