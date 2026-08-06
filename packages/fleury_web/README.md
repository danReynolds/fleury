# Fleury Web

Run a [Fleury](https://github.com/danReynolds/fleury) widget tree in a browser.
`fleury_web` supplies the retained DOM host: it mounts the shared Fleury runtime
into an element, translates browser input, paints dirty cell rows, uses the
browser clipboard, and exposes an accessibility tree.

For the two supported browser architectures, see
[Serving and embedding](https://danreynolds.github.io/fleury/architecture/serving-and-embedding/).
For deployment and security options, see the
[deployment guide](https://danreynolds.github.io/fleury/guides/deployment/).

## Add it to an app

```yaml
dependencies:
  fleury: 0.1.0
  fleury_web: ^0.1.0
  web: ^1.1.1
```

The exact `fleury` pin is intentional: the browser host consumes Fleury's
lockstep remote wire, so the framework and web host must come from the matching
release.

Use Fleury's browser-safe core barrel in client code:

```dart
import 'package:fleury/fleury_core.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  final host = web.document.getElementById('app')!;
  await mountApp(
    () => const FleuryApp(title: 'My app', home: HomeScreen()),
    into: host,
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const Text('Hello from Fleury');
}
```

Add a sized host element and load the compiled Dart entry point:

```html
<div
  id="app"
  style="width: 80ch; height: 24em; font-family: monospace"
></div>
<script defer src="app.js"></script>
```

Then compile and serve the containing directory with any static file server:

```sh
dart compile js web/main.dart -o web/app.js -O2
```

The host needs an explicit size and a monospace font so Fleury can measure its
cell grid. `mountApp` accepts a root-widget factory and returns a
`Future<MountedApp>`. Keep the returned handle and call `dispose()` when an SPA
removes the mounted view.

Semantics are enabled by default and should remain enabled in product builds.
Disabling them requires the explicit `allowInaccessibleDiagnostics` opt-in and
is intended only for focused local performance diagnostics.

## Browser-safe imports

Browser entry points cannot import libraries backed by `dart:io`. Use:

- `package:fleury/fleury_core.dart` for the shared framework;
- `package:fleury_web/fleury_web.dart` for the browser host;
- `package:fleury_widgets/fleury_widgets_web.dart` when an app also depends on
  `fleury_widgets`.

The native `package:fleury/fleury.dart` and
`package:fleury_widgets/fleury_widgets.dart` barrels include terminal-only
APIs. Keep those imports in native entry points.

## Embed or serve

- **Embed with `mountApp`** when the Fleury widget tree runs in the browser.
  The application and retained DOM host compile together to JavaScript.
- **Serve a native process** when the application needs native Dart libraries
  or server-side resources. A browser client receives frames and sends input
  over the remote host protocol.

Both paths share Fleury's core widget, layout, painting, input, and semantics
contracts. The
[architecture guide](https://danreynolds.github.io/fleury/architecture/serving-and-embedding/)
explains where their host boundaries differ.

## Package examples

This package includes a counter and a retained-DOM demo under
[`web/`](https://github.com/danReynolds/fleury/tree/main/packages/fleury_web/web).
From a Fleury framework checkout:

```sh
cd packages/fleury_web
dart pub get
dart compile js web/dom_demo.dart -o web/dom_demo.dart.js
```

Serve `web/` and open `dom_demo.html`.

## Contributing and validation

Run the package tests with:

```sh
dart test -p vm,chrome
```

The browser capture, threshold, semantic-coverage, and readiness tools under
[`tool/`](https://github.com/danReynolds/fleury/tree/main/packages/fleury_web/tool)
are contributor infrastructure. Their evidence format and current commands live
in
[`profiling/web/README.md`](https://github.com/danReynolds/fleury/blob/main/profiling/web/README.md),
with release gates described in
[`docs/implementation/perf-gates.md`](https://github.com/danReynolds/fleury/blob/main/docs/implementation/perf-gates.md).
