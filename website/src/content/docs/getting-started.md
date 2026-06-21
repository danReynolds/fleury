---
title: Getting started
description: Install Fleury and build your first terminal app in a few minutes.
---

## Add Fleury

Fleury is a set of Dart packages. Add the core framework and the widget library
to your `pubspec.yaml`:

```yaml
dependencies:
  fleury:
    git: https://github.com/danReynolds/fleury.git
  fleury_widgets:
    git:
      url: https://github.com/danReynolds/fleury.git
      path: packages/fleury_widgets
```

Then run `dart pub get`.

## Your first app

A Fleury app is a widget tree handed to `runTui`. If you've written Flutter,
this will look immediately familiar:

```dart
import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

Future<void> main() => runTui(const StatusApp());

class StatusApp extends StatefulWidget {
  const StatusApp({super.key});

  @override
  State<StatusApp> createState() => _StatusAppState();
}

class _StatusAppState extends State<StatusApp> {
  var _tick = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _tick++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('uptime: ${_tick}s'),
          const SizedBox(height: 1),
          ProgressBar(value: (_tick % 60) / 60),
        ],
      ),
    );
  }
}
```

Run it:

```sh
dart run bin/main.dart
```

`setState` rebuilds only the dirty path; layout and paint run over a cell grid;
the terminal target diffs successive frames and emits byte-frugal ANSI. Frames
with no work are skipped entirely.

## Run it in a browser

The same app runs in the browser. You can **embed** it client-side (compile to
JS with dart2js — no server) or **serve** it from a native process. The two
modes, and when to pick each, are covered in
[Serving and embedding](/architecture/serving-and-embedding/).

## Where to next

- [Core and targets](/architecture/core-and-targets/) — how the framework is
  layered and why one app runs on multiple surfaces.
- [Serving and embedding](/architecture/serving-and-embedding/) — the two
  browser delivery modes.
