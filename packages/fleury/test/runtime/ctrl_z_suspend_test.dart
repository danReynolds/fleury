// Launch audit 3.a: Ctrl+Z is dispatched first and suspends only when nothing
// handled it — the rule Ctrl+C already follows for exit.
//
// Before, the POSIX driver consumed the chord as job control before input
// dispatch, so the undo binding in both default text keymaps (and any app
// binding for Ctrl+Z) could never fire in a native terminal, while the same
// keys worked when served to a browser.
//
// These run the real runApp over a real PosixTerminalDriver whose stdio is
// faked: stdin reports a terminal and a fake termios controller grants native
// raw mode, so Ctrl+Z arrives as the parsed byte it is in production, and
// `selfStopOverride` stands in for the SIGSTOP self-stop. The real-terminal
// proof lives in test/integration/pty_run_app_test.dart.

import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/terminal/posix_driver.dart'
    show PosixTerminalModeController;
import 'package:test/test.dart';

/// A terminal stdin the test types into.
class _TerminalStdin implements Stdin {
  final _controller = StreamController<List<int>>();

  void type(List<int> bytes) => _controller.add(bytes);

  Future<void> close() => _controller.close();

  @override
  bool get hasTerminal => true;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A non-terminal stdout: no screen-mode sequences and no startup probes, so
/// a session starts at once. Frames are accepted and discarded.
class _QuietStdout implements Stdout {
  @override
  bool get hasTerminal => false;

  @override
  bool get supportsAnsiEscapes => false;

  @override
  void write(Object? object) {}

  @override
  Future<void> flush() async {}

  @override
  int get terminalColumns => throw const StdoutException('not a terminal');

  @override
  int get terminalLines => throw const StdoutException('not a terminal');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Native raw mode granted: ISIG is off, so Ctrl+Z reaches Fleury as 0x1a.
class _RawMode implements PosixTerminalModeController {
  @override
  bool enableRawMode() => true;

  @override
  bool restoreMode() => true;
}

/// Signals when the app has built, so input is typed into a mounted tree.
class _Mounted extends StatelessWidget {
  const _Mounted(this.mounted, this.child);

  final Completer<void> mounted;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!mounted.isCompleted) mounted.complete();
    return child;
  }
}

/// One runApp session over a faked POSIX terminal.
final class _Session {
  _Session._(this.driver, this.stdinFake, this.app, this.keyEvents);

  final PosixTerminalDriver driver;
  final _TerminalStdin stdinFake;
  final Future<AppExit> app;

  /// Every [KeyEvent] runApp handed to `onEvent`: all of them, except one
  /// whose unhandled default (exit, suspend) acted instead.
  final List<KeyEvent> keyEvents;

  /// SIGSTOP self-stops the driver attempted.
  int selfStops = 0;

  static Future<_Session> start(
    Widget root, {
    bool suspendOnCtrlZ = true,
    DebugConfig debug = const DebugConfig(),
  }) async {
    final input = _TerminalStdin();
    final keyEvents = <KeyEvent>[];
    late final _Session session;
    final driver = PosixTerminalDriver(
      stdinOverride: input,
      stdoutOverride: _QuietStdout(),
      suspendOnCtrlZ: suspendOnCtrlZ,
      terminalModeController: _RawMode(),
      selfStopOverride: () {
        session.selfStops++;
        // The stop "took": the session stays suspended until `fg`, which a
        // test never sends. Teardown restores it from there.
        return true;
      },
    );
    final mounted = Completer<void>();
    final app = runApp(
      _Mounted(mounted, root),
      driver: driver,
      enableHotReload: false,
      requireInteractiveTerminal: false,
      debug: debug,
      onEvent: (event) {
        if (event is KeyEvent) keyEvents.add(event);
        return null;
      },
    );
    session = _Session._(driver, input, app, keyEvents);
    await mounted.future.timeout(const Duration(seconds: 5));
    await _settle();
    return session;
  }

  Future<void> type(List<int> bytes) async {
    stdinFake.type(bytes);
    await _settle();
  }

  Future<void> close() async {
    exitApp();
    await app.timeout(const Duration(seconds: 5));
    await stdinFake.close();
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

const _ctrlZ = <int>[0x1a];
final _kittyCtrlZ = '\x1b[122;5u'.codeUnits;
const _ctrlT = <int>[0x14];

bool _isCtrlZ(KeyEvent event) =>
    event.code.character == 'z' && event.modifiers.length == 1 && event.hasCtrl;

void main() {
  group('Ctrl+Z is dispatched before job control (launch audit 3.a)', () {
    for (final multiline in [false, true]) {
      final field = multiline ? 'TextArea' : 'TextInput';
      test('a focused $field undoes on Ctrl+Z instead of suspending', () async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final session = await _Session.start(
          multiline
              ? TextArea(controller: controller, autofocus: true)
              : TextInput(
                  controller: controller,
                  autofocus: true,
                  enableBlink: false,
                ),
        );
        try {
          await session.type('x'.codeUnits);
          expect(controller.text, 'x', reason: 'the field has focus');

          await session.type(_ctrlZ);

          expect(controller.text, isEmpty, reason: 'Ctrl+Z undid the typing');
          expect(session.selfStops, 0);
          expect(session.driver.debugSuspended, isFalse);
        } finally {
          await session.close();
        }
      });
    }

    test('focus decides: off the field, Ctrl+Z is job control again', () async {
      // The shape of the inline CI check's fixture (tool/check_inline_tui.py),
      // whose text field is autofocused: the check clicks the button before
      // pressing Ctrl+Z, and pointer focus is what hands the chord back.
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var clicks = 0;
      final session = await _Session.start(
        Column(
          children: [
            TextInput(
              controller: controller,
              autofocus: true,
              enableBlink: false,
            ),
            Button(text: 'Click me', onPressed: () => clicks++),
          ],
        ),
      );
      try {
        await session.type('x'.codeUnits);
        // An SGR press and release on the button's row (one-based 3;2).
        await session.type('\x1b[<0;3;2M\x1b[<0;3;2m'.codeUnits);
        expect(clicks, 1, reason: 'the click landed on the button');

        await session.type(_ctrlZ);

        expect(controller.text, 'x', reason: 'the field no longer has focus');
        expect(session.selfStops, 1);
      } finally {
        await session.close();
      }
    });

    test(
      'an app binding claims Ctrl+Z and the session keeps running',
      () async {
        var undos = 0;
        final session = await _Session.start(
          KeyBindings(
            bindings: [
              KeyBinding(KeySequence.ctrl.z, onTrigger: (_) => undos++),
            ],
            child: const Focus(autofocus: true, child: Text('editor')),
          ),
        );
        try {
          await session.type(_kittyCtrlZ);
          await session.type(_ctrlZ);

          expect(undos, 2, reason: 'both encodings reach the binding');
          expect(session.selfStops, 0);
          expect(session.driver.debugSuspended, isFalse);
        } finally {
          await session.close();
        }
      },
    );

    for (final (name, bytes) in [
      ('the legacy 0x1a byte', _ctrlZ),
      ('a Kitty CSI-u report', _kittyCtrlZ),
    ]) {
      test('an unhandled Ctrl+Z suspends the session ($name)', () async {
        final session = await _Session.start(const Text('nothing focusable'));
        try {
          await session.type(bytes);

          expect(session.selfStops, 1);
          expect(session.driver.debugSuspended, isTrue);
          expect(
            session.keyEvents.where(_isCtrlZ),
            isEmpty,
            reason: 'like an unhandled Ctrl+C, the default acts before onEvent',
          );
        } finally {
          await session.close();
        }
      });
    }

    test('only the exact Ctrl+Z press suspends', () async {
      final session = await _Session.start(const Text('nothing focusable'));
      try {
        // Kitty tells these apart from the job-control press: redo's chord,
        // and the release and auto-repeat of a Ctrl+Z (a held key suspends
        // once, on its press).
        await session.type('\x1b[122;6u'.codeUnits); // Ctrl+Shift+Z
        await session.type('\x1b[122;5:3u'.codeUnits); // Ctrl+Z release
        await session.type('\x1b[122;5:2u'.codeUnits); // Ctrl+Z repeat
        expect(session.selfStops, 0);
        expect(session.driver.debugSuspended, isFalse);

        await session.type(_ctrlZ);
        expect(session.selfStops, 1, reason: 'the session could suspend');
      } finally {
        await session.close();
      }
    });

    test(
      'suspendOnCtrlZ: false keeps an unhandled Ctrl+Z an ordinary key',
      () async {
        final session = await _Session.start(
          const Text('nothing focusable'),
          suspendOnCtrlZ: false,
        );
        try {
          await session.type(_ctrlZ);
          await session.type(_kittyCtrlZ);

          expect(session.selfStops, 0);
          expect(session.driver.debugSuspended, isFalse);
          expect(session.keyEvents.where(_isCtrlZ), hasLength(2));
          expect(session.driver.isActive, isTrue);
        } finally {
          await session.close();
        }
      },
    );

    test('a driver without job control keeps an unhandled Ctrl+Z an ordinary '
        'key (browser, served, and remote sessions)', () async {
      final driver = FakeTerminalDriver();
      final keyEvents = <KeyEvent>[];
      final app = runApp(
        const Text('nothing focusable'),
        driver: driver,
        enableHotReload: false,
        onEvent: (event) {
          if (event is KeyEvent) keyEvents.add(event);
          return null;
        },
      );
      try {
        await _settle();
        driver.enqueue(
          const KeyEvent(KeyCode.char('z'), modifiers: {KeyModifier.ctrl}),
        );
        await _settle();

        expect(keyEvents.where(_isCtrlZ), hasLength(1));
        expect(driver.isActive, isTrue);
      } finally {
        exitApp();
        await app;
        await driver.dispose();
      }
    });
  });

  // A chat composer or a REPL prompt: its text field always has focus and
  // takes every Ctrl+Z for undo, so no press ever reaches job control. The
  // app offers its own suspend key instead (the real-terminal proof is
  // test/integration/job_control_pty_test.dart).
  group("an app's own suspend key (TerminalSession.suspend)", () {
    test('suspends from a binding while the focused field keeps Ctrl+Z for '
        'undo', () async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final requests = <Future<bool>>[];
      final session = await _Session.start(
        ScopeBuilder<TerminalSession>(
          builder: (_, terminal) => KeyBindings(
            bindings: [
              KeyBinding(
                KeySequence.ctrl.t,
                label: 'Suspend',
                enabled: terminal.supportsSuspend,
                onTrigger: (_) => requests.add(terminal.suspend()),
              ),
            ],
            child: TextInput(
              controller: controller,
              autofocus: true,
              enableBlink: false,
            ),
          ),
        ),
      );
      try {
        await session.type('x'.codeUnits);
        await session.type(_ctrlZ);
        expect(controller.text, isEmpty, reason: 'Ctrl+Z undid the typing');
        expect(session.selfStops, 0);

        await session.type(_ctrlT);

        expect(session.selfStops, 1);
        expect(session.driver.debugSuspended, isTrue);
        expect(await requests.single, isTrue);
      } finally {
        await session.close();
      }
    });

    test('with suspendOnCtrlZ: false, an app that takes Ctrl+Z suspends after '
        'its own cleanup', () async {
      // The sensitive-input pattern: no unhandled-press fallback, so the app
      // decides — conceal, then suspend.
      var concealed = false;
      final requests = <Future<bool>>[];
      final session = await _Session.start(
        ScopeBuilder<TerminalSession>(
          builder: (_, terminal) => KeyBindings(
            bindings: [
              KeyBinding(
                KeySequence.ctrl.z,
                onTrigger: (_) {
                  concealed = true;
                  requests.add(terminal.suspend());
                },
              ),
            ],
            child: const Focus(autofocus: true, child: Text('secret')),
          ),
        ),
        suspendOnCtrlZ: false,
      );
      try {
        await session.type(_ctrlZ);

        expect(concealed, isTrue);
        expect(session.selfStops, 1);
        expect(await requests.single, isTrue);
      } finally {
        await session.close();
      }
    });
  });

  group('Ctrl+Z with the debug shell open', () {
    // A focused field holding a typed x, so an undo that reached it shows.
    Future<(_Session, TextEditingController)> start(DebugMode mode) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final session = await _Session.start(
        TextInput(controller: controller, autofocus: true, enableBlink: false),
        debug: DebugConfig(enabled: true, startMode: mode),
      );
      await session.type('x'.codeUnits);
      expect(controller.text, 'x', reason: 'the field has focus');
      return (session, controller);
    }

    test(
      'expanded over the app, it skips the hidden field and suspends',
      () async {
        final (session, controller) = await start(DebugMode.fullscreen);
        try {
          await session.type(_ctrlZ);

          expect(
            controller.text,
            'x',
            reason: 'an undo of a field the user cannot see is no undo at all',
          );
          expect(
            session.selfStops,
            1,
            reason: 'nothing on screen handles the press, so it suspends',
          );
        } finally {
          await session.close();
        }
      },
    );

    test('with its Logs search open, the search takes it', () async {
      final (session, controller) = await start(DebugMode.docked);
      try {
        await session.type('\x1b[24~'.codeUnits); // F12: the Logs tab
        await session.type('/'.codeUnits); // open the search
        await session.type(_ctrlZ);

        expect(controller.text, 'x', reason: 'the app was not being typed in');
        expect(
          session.selfStops,
          0,
          reason: 'a key typed into a text field never suspends',
        );
      } finally {
        await session.close();
      }
    });

    test('docked beside the visible app, the app keeps it', () async {
      final (session, controller) = await start(DebugMode.docked);
      try {
        await session.type(_ctrlZ);

        expect(controller.text, isEmpty, reason: 'the visible field undid');
        expect(session.selfStops, 0);
      } finally {
        await session.close();
      }
    });
  });
}
