// ShellSession's relay and lifecycle over a fake terminal and transport. The
// real terminal (termios, the native reader, the escape sequences) is proved
// in a PTY by test/remote/shell_pty_test.dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:fleury/fleury.dart'
    show CellSize, ColorMode, ImageProtocol, KeyboardProtocolMode, TerminalMode;
import 'package:fleury/fleury_wire.dart';
import 'package:fleury/src/cli/shell_session.dart';
import 'package:test/test.dart';

import '../remote/remote_test_support.dart';

/// No keyboard probe: tests that do not exercise it start immediately.
const _noProbe = <String, String>{'FLEURY_KEYBOARD_PROBE': '0'};

/// What the scaffold `fleury create` writes asks for: clicks, not hover.
const _mouseApp = TerminalInputModes(
  mouse: true,
  mouseMotion: false,
  bracketedPaste: true,
  focusReporting: true,
  keyboardProtocol: KeyboardProtocolMode.lifecycle,
);

/// An app's answer to the shell's INIT: this build's shell protocol, and the
/// input the app reads, unless told otherwise.
InitFrame _answer({
  RemoteWireProtocol protocol = RemoteWireProtocol.shell,
  int? version,
  TerminalInputModes? input = _mouseApp,
}) => InitFrame(
  size: const CellSize(80, 24),
  colorMode: ColorMode.truecolor,
  imageProtocol: ImageProtocol.halfBlock,
  tmuxPassthrough: false,
  protocol: protocol,
  protocolVersion: version,
  terminalInput: input,
);

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

    transport.emit(_answer());
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
    transport.emit(_answer());
    await pumpEventQueue();

    await transport.disconnect();
    final end = await run;

    expect(end.reason, ShellSessionEndReason.appDisconnected);
    expect(terminal.log, ['acquire', 'input', 'release']);
  });

  test('a reset connection is the app disconnecting, not a failure', () async {
    // Linux resets the socket when a killed app leaves input unread, which is
    // how an IDE's Stop often looks from here.
    final terminal = _FakeTerminal();
    final transport = _ErroringTransport();
    final run = ShellSession(
      transport,
      terminal: terminal,
      resizes: const Stream<Object?>.empty(),
      environment: _noProbe,
    ).run();
    await pumpEventQueue();
    transport.emit(_answer());
    await pumpEventQueue();

    transport.fail(const SocketException('Connection reset by peer'));
    final end = await run;

    expect(end.reason, ShellSessionEndReason.appDisconnected);
    expect(terminal.log, ['acquire', 'input', 'release']);
  });

  test('a protocol error from the app fails the session', () async {
    final terminal = _FakeTerminal();
    final transport = _ErroringTransport();
    final run = ShellSession(
      transport,
      terminal: terminal,
      resizes: const Stream<Object?>.empty(),
      environment: _noProbe,
    ).run();
    await pumpEventQueue();

    transport.fail(const RemoteProtocolException('unknown frame type 0x7f'));
    final end = await run;

    expect(end.reason, ShellSessionEndReason.failed);
    expect(end.error, isA<RemoteProtocolException>());
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

  group('the handshake', () {
    test('the shell declares its own protocol, and the app\'s answer turns on '
        'the input it reads before anything it draws is shown', () async {
      final terminal = _FakeTerminal();
      final transport = FakeFrameTransport();
      final run = ShellSession(
        transport,
        terminal: terminal,
        resizes: const Stream<Object?>.empty(),
        environment: _noProbe,
      ).run();
      await pumpEventQueue();

      final init = transport.sent.first as InitFrame;
      expect(init.protocol, RemoteWireProtocol.shell);
      expect(init.protocolVersion, shellProtocolVersion);

      transport.emit(_answer());
      transport.emit(OutputFrame(Uint8List.fromList(utf8.encode('frame'))));
      await pumpEventQueue();
      expect(terminal.input, _mouseApp);
      expect(terminal.log, ['acquire', 'input', 'output']);

      transport.emit(const ByeFrame());
      expect((await run).reason, ShellSessionEndReason.appExited);
      expect(terminal.log, ['acquire', 'input', 'output', 'release']);
    });

    test('an app at another shell protocol version is turned away, both '
        'versions named, and nothing it sends is shown', () async {
      for (final version in [
        shellProtocolVersion - 1,
        shellProtocolVersion + 1,
      ]) {
        final terminal = _FakeTerminal();
        final transport = FakeFrameTransport();
        final run = ShellSession(
          transport,
          terminal: terminal,
          resizes: const Stream<Object?>.empty(),
          environment: _noProbe,
        ).run();
        await pumpEventQueue();

        transport.emit(_answer(version: version));
        transport.emit(OutputFrame(Uint8List.fromList(utf8.encode('frame'))));
        final end = await run;

        expect(end.reason, ShellSessionEndReason.handshakeFailed);
        expect(end.error, isA<ShellHandshakeException>());
        expect(
          '${end.error}',
          allOf(
            contains('it speaks shell protocol v$version'),
            contains('this shell speaks v$shellProtocolVersion'),
            contains('dart run fleury shell'),
          ),
        );
        expect(terminal.input, isNull, reason: 'v$version');
        expect(terminal.output, isEmpty, reason: 'v$version');
        expect(terminal.log, ['acquire', 'release'], reason: 'v$version');
        expect(transport.sent.last, isA<ByeFrame>());
        expect(transport.closed, isTrue);
      }
    });

    test('an answer in the structured protocol, or without terminal input, '
        'is turned away', () async {
      for (final (answer, message) in [
        (
          _answer(protocol: RemoteWireProtocol.structured, input: null),
          'structured wire protocol (v$remoteProtocolVersion)',
        ),
        (_answer(input: null), 'declared no terminal input'),
      ]) {
        final terminal = _FakeTerminal();
        final transport = FakeFrameTransport();
        final run = ShellSession(
          transport,
          terminal: terminal,
          resizes: const Stream<Object?>.empty(),
          environment: _noProbe,
        ).run();
        await pumpEventQueue();

        transport.emit(answer);
        final end = await run;
        expect(end.reason, ShellSessionEndReason.handshakeFailed);
        expect('${end.error}', contains(message));
        expect(terminal.log, ['acquire', 'release']);
      }
    });

    test(
      'output before the answer is never shown: the app is turned away',
      () async {
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
        final end = await run;

        expect(end.reason, ShellSessionEndReason.handshakeFailed);
        expect(
          '${end.error}',
          contains("sent OutputFrame before answering the shell's handshake"),
        );
        expect(terminal.output, isEmpty);
        expect(terminal.log, ['acquire', 'release']);
      },
    );

    test('an app that hangs up before answering — as one built before shell '
        'protocol 2 does — is reported, not taken for a crash', () async {
      for (final hangUp in <Future<void> Function(_ErroringTransport)>[
        (transport) => transport.close(),
        (transport) async =>
            transport.fail(const SocketException('Connection reset by peer')),
      ]) {
        final terminal = _FakeTerminal();
        final transport = _ErroringTransport();
        final run = ShellSession(
          transport,
          terminal: terminal,
          resizes: const Stream<Object?>.empty(),
          environment: _noProbe,
        ).run();
        await pumpEventQueue();

        await hangUp(transport);
        final end = await run;

        expect(end.reason, ShellSessionEndReason.handshakeFailed);
        expect(
          '${end.error}',
          allOf(
            contains("disconnected before answering the shell's handshake"),
            contains('older Fleury'),
            contains('dart run fleury shell'),
          ),
        );
        expect(terminal.log, ['acquire', 'release']);
      }
    });

    test('a goodbye before the answer is the app exiting', () async {
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
      expect((await run).reason, ShellSessionEndReason.appExited);
    });
  });

  group("the terminal follows the app's input", () {
    test('mouse tracking, pastes and focus reports as the app asks', () {
      expect(
        buildShellInputSequences(_mouseApp),
        '\x1B[?2004h\x1B[?1004h\x1B[?1000h\x1B[?1002h\x1B[?1006h',
      );
      const hover = TerminalInputModes(
        mouse: false,
        mouseMotion: true,
        bracketedPaste: false,
        focusReporting: false,
        keyboardProtocol: KeyboardProtocolMode.disambiguated,
      );
      expect(
        buildShellInputSequences(hover),
        '\x1B[?1000h\x1B[?1002h\x1B[?1003h\x1B[?1006h',
      );
    });

    test('an app that reads legacy keys gets the probe\'s keyboard flags '
        'popped; any other keeps the shell\'s disambiguated tier', () {
      for (final tier in KeyboardProtocolMode.values) {
        final input = TerminalInputModes(
          mouse: false,
          mouseMotion: false,
          bracketedPaste: false,
          focusReporting: false,
          keyboardProtocol: tier,
        );
        final legacy = tier == KeyboardProtocolMode.legacy;
        expect(
          buildShellInputSequences(input),
          legacy ? '\x1B[<1u' : '',
          reason: '$tier',
        );
        expect(
          shellTerminalModeFor(input).keyboardProtocol,
          legacy
              ? KeyboardProtocolMode.legacy
              : KeyboardProtocolMode.disambiguated,
          reason: '$tier',
        );
      }
    });

    test('before an app answers, the shell turns on no input reporting', () {
      expect(shellTerminalMode.mouse, isFalse);
      expect(shellTerminalMode.mouseMotion, isFalse);
      expect(shellTerminalMode.bracketedPaste, isFalse);
      expect(shellTerminalMode.focusReporting, isFalse);
      expect(
        shellTerminalMode.keyboardProtocol,
        KeyboardProtocolMode.disambiguated,
        reason: 'the tier the shell probes the terminal at',
      );
    });

    test("the app's mode reaches the shell's terminal whole", () {
      // Whatever the app's TerminalMode asks for, the shell's terminal ends
      // up asking for the same input, at the shell's keyboard ceiling.
      for (final mode in const [
        TerminalMode(mouse: true),
        TerminalMode(mouseMotion: true),
        TerminalMode(bracketedPaste: false, focusReporting: false),
        TerminalMode(keyboardProtocol: KeyboardProtocolMode.legacy),
      ]) {
        final shell = shellTerminalModeFor(TerminalInputModes.of(mode));
        expect(shell.mouse, mode.mouse);
        expect(shell.mouseMotion, mode.mouseMotion);
        expect(shell.bracketedPaste, mode.bracketedPaste);
        expect(shell.focusReporting, mode.focusReporting);
        expect(
          shell.isFullScreen,
          isTrue,
          reason: 'the shell keeps its screen',
        );
      }
    });
  });
}

final class _FakeTerminal implements ShellTerminal {
  final log = <String>[];
  final _output = StringBuffer();
  TerminalInputModes? input;
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
  void enterInput(TerminalInputModes input) {
    log.add('input');
    this.input = input;
  }

  @override
  void write(List<int> bytes) {
    final text = utf8.decode(bytes);
    // Probe queries are the shell's own; app output is what reaches the
    // screen for the app.
    if (!text.startsWith('\x1B[?u')) log.add('output');
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

/// A transport whose incoming stream can fail, as a socket's does.
final class _ErroringTransport implements RemoteFrameTransport {
  final _in = StreamController<RemoteFrame>.broadcast();
  final sent = <RemoteFrame>[];

  void fail(Object error) => _in.addError(error);

  void emit(RemoteFrame frame) => _in.add(frame);

  @override
  Stream<RemoteFrame> get incoming => _in.stream;

  @override
  void send(RemoteFrame frame) => sent.add(frame);

  @override
  bool get isSendBacklogged => false;

  @override
  Future<void> get sendDrained => Future<void>.value();

  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }
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
