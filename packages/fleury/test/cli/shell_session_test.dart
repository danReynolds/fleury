// ShellSession's relay and lifecycle over a fake terminal and transport. The
// real terminal (termios, the native reader, the escape sequences) is proved
// in a PTY by test/remote/shell_pty_test.dart.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fleury/fleury.dart' show CellSize;
import 'package:fleury/fleury_wire.dart';
import 'package:fleury/src/cli/shell_session.dart';
import 'package:test/test.dart';

import '../remote/remote_test_support.dart';

/// No keyboard probe: tests that do not exercise it start immediately.
const _noProbe = <String, String>{'FLEURY_KEYBOARD_PROBE': '0'};

void main() {
  test('relays every byte typed, signal keys included, after INIT', () async {
    final terminal = _FakeTerminal();
    final transport = FakeFrameTransport();
    final session = ShellSession(
      transport,
      terminal: terminal,
      resizes: const Stream<Object?>.empty(),
      environment: _noProbe,
    );
    final run = session.run();
    await pumpEventQueue();

    // Ctrl+C, Ctrl+Z, Ctrl+\ and Ctrl+S: keys a terminal would otherwise
    // turn into SIGINT, SIGTSTP, SIGQUIT and flow control.
    terminal.type('\x03\x1a\x1c\x13');
    await pumpEventQueue();

    expect(transport.sent.first, isA<InitFrame>());
    expect(transport.sent.whereType<InputFrame>().single.bytes, [
      0x03,
      0x1a,
      0x1c,
      0x13,
    ]);
    transport.emit(const ByeFrame());
    await run;
  });

  test('writes app output to the terminal', () async {
    final terminal = _FakeTerminal();
    final transport = FakeFrameTransport();
    final run = ShellSession(
      transport,
      terminal: terminal,
      resizes: const Stream<Object?>.empty(),
      environment: _noProbe,
    ).run();
    await pumpEventQueue();

    transport.emit(OutputFrame(Uint8List.fromList(utf8.encode('frame'))));
    await pumpEventQueue();
    expect(terminal.output, 'frame');

    transport.emit(const ByeFrame());
    await run;
  });

  test('forwards a window resize with the new size', () async {
    final terminal = _FakeTerminal();
    final transport = FakeFrameTransport();
    final resizes = StreamController<Object?>();
    final run = ShellSession(
      transport,
      terminal: terminal,
      resizes: resizes.stream,
      environment: _noProbe,
    ).run();
    await pumpEventQueue();

    terminal.size = const CellSize(132, 41);
    resizes.add(null);
    await pumpEventQueue();
    expect(
      transport.sent.whereType<ResizeFrame>().single.size,
      const CellSize(132, 41),
    );

    transport.emit(const ByeFrame());
    await run;
    expect(resizes.hasListener, isFalse, reason: 'the watcher is released');
  });

  test('an app goodbye hands the terminal back once and closes', () async {
    final terminal = _FakeTerminal();
    final transport = FakeFrameTransport();
    final run = ShellSession(
      transport,
      terminal: terminal,
      resizes: const Stream<Object?>.empty(),
      environment: _noProbe,
    ).run();
    await pumpEventQueue();

    transport.emit(const ByeFrame());
    final end = await run;

    expect(end.reason, ShellSessionEndReason.appExited);
    expect(terminal.log, ['acquire', 'release']);
    expect(transport.closed, isTrue);
    expect(transport.sent.whereType<ByeFrame>(), isEmpty);
  });

  test('an app that drops the connection ends the session', () async {
    final terminal = _FakeTerminal();
    final transport = FakeFrameTransport();
    final run = ShellSession(
      transport,
      terminal: terminal,
      resizes: const Stream<Object?>.empty(),
      environment: _noProbe,
    ).run();
    await pumpEventQueue();

    await transport.disconnect();
    final end = await run;

    expect(end.reason, ShellSessionEndReason.appDisconnected);
    expect(terminal.log, ['acquire', 'release']);
  });

  test('shutdown hands the terminal back before waiting on the app', () async {
    // An app paused at a breakpoint does not read, so closing its
    // connection can stall. The terminal must not stay raw meanwhile.
    final terminal = _FakeTerminal();
    final transport = _StallingCloseTransport();
    final session = ShellSession(
      transport,
      terminal: terminal,
      resizes: const Stream<Object?>.empty(),
      environment: _noProbe,
    );
    final run = session.run();
    await pumpEventQueue();

    session.shutdown();
    await pumpEventQueue();

    expect(terminal.log, ['acquire', 'release']);
    expect(transport.sent.last, isA<ByeFrame>());
    expect(transport.closeStarted, isTrue);
    transport.finishClose();
    expect((await run).reason, ShellSessionEndReason.shutdown);
  });

  test('a terminal that goes away ends the session', () async {
    final terminal = _FakeTerminal();
    final transport = FakeFrameTransport();
    final run = ShellSession(
      transport,
      terminal: terminal,
      resizes: const Stream<Object?>.empty(),
      environment: _noProbe,
    ).run();
    await pumpEventQueue();

    terminal.hangUp();
    final end = await run;

    expect(end.reason, ShellSessionEndReason.terminalGone);
    expect(terminal.log, ['acquire', 'release']);
    expect(transport.sent.last, isA<ByeFrame>());
  });

  test('a failed takeover is rolled back and the app told goodbye', () async {
    final terminal = _FakeTerminal()..acquireError = StateError('no termios');
    final transport = FakeFrameTransport();
    final end = await ShellSession(
      transport,
      terminal: terminal,
      resizes: const Stream<Object?>.empty(),
      environment: _noProbe,
    ).run();

    expect(end.reason, ShellSessionEndReason.failed);
    expect(end.error, isA<StateError>());
    expect(terminal.log, ['acquire', 'release']);
    expect(transport.sent.whereType<InitFrame>(), isEmpty);
    expect(transport.sent.single, isA<ByeFrame>());
  });

  test('a failure to hand the terminal back is reported', () async {
    final terminal = _FakeTerminal()..releaseError = StateError('EIO');
    final transport = FakeFrameTransport();
    final run = ShellSession(
      transport,
      terminal: terminal,
      resizes: const Stream<Object?>.empty(),
      environment: _noProbe,
    ).run();
    await pumpEventQueue();

    transport.emit(const ByeFrame());
    final end = await run;

    expect(end.reason, ShellSessionEndReason.appExited);
    expect(end.restoreError, isA<StateError>());
    expect(transport.closed, isTrue);
  });

  test('a key typed during the keyboard probe follows INIT', () async {
    final terminal = _FakeTerminal();
    final transport = FakeFrameTransport();
    // The terminal answers the probe, and the user types in the same read.
    terminal.onWrite = (text) {
      if (text.contains('\x1B[?u')) terminal.type('\x1B[?3u\x1B[?62;22cz');
    };
    final run = ShellSession(
      transport,
      terminal: terminal,
      resizes: const Stream<Object?>.empty(),
      environment: const <String, String>{},
    ).run();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final init = transport.sent.first as InitFrame;
    expect(init.keyboard, isNotNull, reason: 'the reply confirmed flags');
    expect(
      utf8.decode(transport.sent.whereType<InputFrame>().single.bytes),
      'z',
      reason: 'the reply is stripped; the keystroke after it is relayed',
    );
    transport.emit(const ByeFrame());
    await run;
  });
}

final class _FakeTerminal implements ShellTerminal {
  final log = <String>[];
  final _output = StringBuffer();
  void Function(Uint8List bytes)? _onInput;
  void Function()? _onGone;
  Object? acquireError;
  Object? releaseError;
  void Function(String text)? onWrite;

  String get output => _output.toString();

  @override
  CellSize size = const CellSize(80, 24);

  @override
  Future<void> acquire({
    required void Function(Uint8List bytes) onInput,
    required void Function() onGone,
  }) async {
    log.add('acquire');
    _onInput = onInput;
    _onGone = onGone;
    final error = acquireError;
    if (error != null) throw error;
  }

  @override
  void write(List<int> bytes) {
    final text = utf8.decode(bytes);
    _output.write(text);
    onWrite?.call(text);
  }

  @override
  Future<void> release() async {
    log.add('release');
    final error = releaseError;
    if (error != null) throw error;
  }

  void type(String text) => _onInput!(Uint8List.fromList(utf8.encode(text)));

  void hangUp() => _onGone!();
}

/// A transport whose close pends until the test finishes it, as a socket
/// close does while the app on the far end is not reading.
final class _StallingCloseTransport extends FakeFrameTransport {
  final _closeGate = Completer<void>();
  bool closeStarted = false;

  void finishClose() => _closeGate.complete();

  @override
  Future<void> close() async {
    closeStarted = true;
    await _closeGate.future;
    await super.close();
  }
}
