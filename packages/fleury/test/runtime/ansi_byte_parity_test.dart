// Byte-parity guard for the FrameDriver extraction: a scripted scenario
// (mount → state-mutating key → no-work key → resize) recorded through
// FakeTerminalDriver as the exact ANSI byte stream. The extraction must
// keep this stream byte-identical — the ANSI path's contract is its
// bytes. Regenerate deliberately with FLEURY_UPDATE_GOLDENS=1 only for
// intentional renderer changes.

import 'dart:async';

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

class _Script extends StatefulWidget {
  const _Script();

  @override
  State<_Script> createState() => _ScriptState();
}

class _ScriptState extends State<_Script> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyChord.char('t'),
          onEvent: (_) => setState(() => _count++),
        ),
        KeyBinding(KeyChord.char('s'), onEvent: (_) {}),
      ],
      child: Focus(
        autofocus: true,
        child: Column(
          children: [Text('count: $_count'), const Text('steady line')],
        ),
      ),
    );
  }
}

void main() {
  test('scripted ANSI byte stream is stable across the scenario', () async {
    final driver = FakeTerminalDriver(size: const CellSize(32, 5));

    final done = runApp(
      const _Script(),
      driver: driver,
      enableHotReload: false,
      requireInteractiveTerminal: false,
    );
    await _settle();

    final chunks = <String>[];
    void take(String label) {
      chunks.add('=== $label ===\n${driver.output}');
      driver.clearOutput();
    }

    take('mount');

    driver.enqueue(const KeyEvent(char: 't'));
    await _settle();
    take('after t (rebuild)');

    driver.enqueue(const KeyEvent(char: 's'));
    await _settle();
    take('after s (no-work: must be empty)');

    driver.resize(const CellSize(28, 4));
    await _settle();
    take('after resize (full repaint)');

    // The no-work chunk carries only its header — zero bytes written.
    expect(chunks[2], '=== after s (no-work: must be empty) ===\n');

    expect(
      chunks.join('\n'),
      matchesGolden('runtime/frame_driver_ansi_scenario.txt'),
    );

    driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
    await done;
  });
}
