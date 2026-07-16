import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:fleury/fleury.dart';

typedef _WriteC = IntPtr Function(Int32 fd, Pointer<Uint8> buf, IntPtr count);
typedef _WriteDart = int Function(int fd, Pointer<Uint8> buf, int count);
final _write = DynamicLibrary.process().lookupFunction<_WriteC, _WriteDart>(
  'write',
);

/// A raw POSIX write(1, ...) — exactly what a native/FFI library does,
/// invisible to Dart zones and IOOverrides. Only the fd-level capture can
/// keep this off the screen.
void _nativeWrite(String s) {
  final bytes = s.codeUnits;
  final buf = malloc<Uint8>(bytes.length);
  buf.asTypedList(bytes.length).setAll(0, bytes);
  var off = 0;
  while (off < bytes.length) {
    final w = _write(1, buf + off, bytes.length - off);
    if (w <= 0) break;
    off += w;
  }
  malloc.free(buf);
}

/// The canonical consumer shape under app-owned shutdown: runApp resolves
/// with WHY the app ended (after the terminal is restored), and the caller
/// owns the process exit code — 128+n for signals, 0 otherwise.
Never _exitWith(AppExit appExit) => exit(switch (appExit.signal) {
  AppSignal.interrupt => 130,
  AppSignal.terminate => 143,
  null => 0,
});

Future<void> main(List<String> args) async {
  final hookArg = args.where((a) => a.startsWith('--stray-hook=')).firstOrNull;
  if (hookArg != null) {
    final hookFile = File(hookArg.substring('--stray-hook='.length));
    Timer(const Duration(milliseconds: 300), () {
      print('HOOKED-PRINT');
      _nativeWrite('HOOKED-NATIVE\n');
    });
    _exitWith(await runApp(
      const _PtySmokeApp(label: 'PTY-HOOK-MODE'),
      enableHotReload: false,
      onStrayOutput: (line) => hookFile.writeAsStringSync(
        '${line.source.name}:${line.text}\n',
        mode: FileMode.append,
      ),
      onEvent: (event) => event is ResizeEvent ? const ExitRequested() : null,
    ));
  }
  if (args.contains('--stray-output')) {
    Timer(const Duration(milliseconds: 300), () {
      // Both classes of stray writer: Dart print (zone-visible) and a raw
      // native descriptor write (zone-INvisible).
      print('STRAY-PRINT-MARKER');
      _nativeWrite('STRAY-NATIVE-MARKER\n');
      // Hostile terminal payload (OSC title set) — replay must be sanitized.
      print('STRAY-HOSTILE \x1B]0;pwned\x07END');
    });
    _exitWith(await runApp(
      const _PtySmokeApp(label: 'PTY-STRAY-MODE'),
      enableHotReload: false,
      // Exit cleanly on the harness's SIGWINCH — input-byte exits need a
      // controlling terminal (job control) that sandboxes/CI lack, but
      // SIGWINCH delivery works everywhere the resize smoke test does.
      onEvent: (event) => event is ResizeEvent ? const ExitRequested() : null,
    ));
  }
  if (args.contains('--layout-crash')) {
    _exitWith(await runApp(const _BoomWidget(), enableHotReload: false));
  }
  if (args.contains('--handoff')) {
    final driver = createNativeTerminalDriver();
    _exitWith(
      await runApp(
        _PtyHandoffApp(driver),
        driver: driver,
        enableHotReload: false,
      ),
    );
  }
  _exitWith(await runApp(const _PtySmokeApp(), enableHotReload: false));
}

class _PtyHandoffApp extends StatefulWidget {
  const _PtyHandoffApp(this.driver);

  final TerminalDriver driver;

  @override
  State<_PtyHandoffApp> createState() => _PtyHandoffAppState();
}

class _PtyHandoffAppState extends State<_PtyHandoffApp> {
  var _scheduled = false;

  @override
  Widget build(BuildContext context) {
    if (!_scheduled) {
      _scheduled = true;
      // Prove handoff only after the first frame has mounted and reached the
      // presenter. A fixed startup timer can fire during bounded terminal
      // capability probes, while the driver is still inactive.
      TuiBinding.of(context).addPostFrameCallback((_) {
        unawaited(_runHandoff());
      });
    }
    return const _PtySmokeApp(label: 'PTY-HANDOFF-MODE');
  }

  Future<void> _runHandoff() async {
    await withTerminalHandoff(widget.driver, () {
      File('/dev/stdout').writeAsStringSync('PTY-HANDOFF-OPERATION\n');
    });
    // The handoff future resolves only after Fleury has re-entered its raw and
    // alternate-screen modes. End from that proof point instead of racing a
    // separately timed Ctrl+C against the child-terminal window.
    if (!requestExit()) {
      throw StateError('PTY handoff completed without an active app.');
    }
  }
}

class _PtySmokeApp extends StatelessWidget {
  const _PtySmokeApp({this.label = 'PTY-FIRST-FRAME'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Column(
      children: [Text(label), Text('SIZE ${size.cols}x${size.rows}')],
    );
  }
}

class _BoomWidget extends LeafRenderObjectWidget {
  const _BoomWidget();

  @override
  RenderObject createRenderObject(BuildContext context) => _BoomRender();
}

class _BoomRender extends RenderObject {
  @override
  CellSize performLayout(CellConstraints constraints) {
    throw StateError('layout-boom');
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {}
}
