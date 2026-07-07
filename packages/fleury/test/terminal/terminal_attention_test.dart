@Tags(['unit'])
library;

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// A driver that does NOT implement [TerminalAttentionDriver] — the helpers
/// must no-op on it rather than throw.
class _PlainDriver implements TerminalDriver {
  final List<String> written = [];

  @override
  CellSize get size => const CellSize(80, 24);
  @override
  TerminalCapabilities get capabilities =>
      TerminalCapabilities.defaultCapabilities;
  @override
  Stream<TuiEvent> get events => Stream<TuiEvent>.empty();
  @override
  bool get isActive => false;
  @override
  bool get isInteractive => true;
  @override
  RemoteSurfaceSink? get surfaceSink => null;
  @override
  Future<void> enter(TerminalMode mode) async {}
  @override
  Future<void> restore() async {}
  @override
  void write(String data) => written.add(data);
}

void main() {
  group('TerminalAttentionSequences (via FakeTerminalDriver)', () {
    test('setTitle emits OSC 0 + OSC 2', () {
      final d = FakeTerminalDriver();
      d.setTitle('Runs / build #42');
      expect(
        d.output,
        '\x1B]0;Runs / build #42\x07\x1B]2;Runs / build #42\x07',
      );
    });

    test('ringBell emits a bare BEL', () {
      final d = FakeTerminalDriver();
      d.ringBell();
      expect(d.output, '\x07');
    });

    test('notify emits an OSC 9 desktop notification', () {
      final d = FakeTerminalDriver();
      d.notify('Build finished');
      expect(d.output, '\x1B]9;Build finished\x07');
    });

    test('control chars in the payload are sanitized so they cannot terminate '
        'the sequence early', () {
      final d = FakeTerminalDriver();
      // A BEL and an ESC embedded in the title would otherwise close the OSC.
      d.setTitle('a\x07b\x1Bc');
      expect(d.output, '\x1B]0;a b c\x07\x1B]2;a b c\x07');
    });
  });

  group('helpers route to a capable driver, no-op otherwise', () {
    test('the helpers go through a TerminalAttentionDriver', () {
      final d = FakeTerminalDriver();
      setTerminalTitle(d, 'T');
      ringTerminalBell(d);
      notifyTerminal(d, 'N');
      expect(d.output, '\x1B]0;T\x07\x1B]2;T\x07\x07\x1B]9;N\x07');
    });

    test('the helpers no-op on a driver without the capability', () {
      final d = _PlainDriver();
      setTerminalTitle(d, 'T'); // must not throw
      ringTerminalBell(d);
      notifyTerminal(d, 'N');
      expect(d.written, isEmpty);
    });
  });
}
