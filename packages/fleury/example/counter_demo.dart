// A minimal interactive fleury app that exercises the whole stack:
//
//   - StatefulWidget with setState-driven updates
//   - Row + Column + Padding layout
//   - Terminal input dispatched into the widget tree
//   - Hot reload: edit this file, save, and the running app picks up
//     your changes WHILE preserving the counter's value
//
// How to run:
//
//   # From packages/fleury:
//   dart pub get
//   dart run example/counter_demo.dart
//
//   # Press + or - to change the counter.
//   # Press q or Ctrl+C to exit.
//
//   # For stateful hot reload, launch `fleury · counter demo` from this
//   # package in VS Code, save after editing source, and run
//   # `Dart: Hot Reload`.
//   # Dart-Code calls the VM's reloadSources RPC; the framework then
//   # reassembles automatically on the IsolateReload event.

import 'dart:async';

import 'package:fleury/fleury.dart';

Future<void> main() async {
  final driver = PosixTerminalDriver();
  await runApp(
    CounterApp(driver: driver),
    driver: driver,
    onEvent: (event) {
      if (event is TextInputEvent && event.text == 'q') {
        return const ExitRequested();
      }
      return null;
    },
  );
}

class CounterApp extends StatefulWidget {
  const CounterApp({super.key, required this.driver});
  final TerminalDriver driver;

  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int count = 0;
  StreamSubscription<TuiEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    _eventSub = widget.driver.events.listen(_handleEvent);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  void _handleEvent(TuiEvent event) {
    if (event is! TextInputEvent) return;
    switch (event.text) {
      case '+':
      case '=':
        setState(() => count += 1);
      case '-':
        setState(() => count -= 1);
      case '0':
        setState(() => count = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        children: [
          Text('fleury counter demo', style: const CellStyle(bold: true)),
          const Text(''),
          Text('Counter: $count'),
          const Text(''),
          const Text('Press + or = to increment'),
          const Text('Press - to decrement'),
          const Text('Press 0 to reset'),
          const Text('Press q or Ctrl+C to exit'),
          const Text(''),
          const Text(
            'Under Dart-Code, edit and save this file, then run Hot Reload; '
            'the counter is preserved.',
            style: CellStyle(dim: true),
          ),
        ],
      ),
    );
  }
}
