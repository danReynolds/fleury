// Framework-agnostic PTY capture for the TUI profiling harness — all-Dart.
//
// Runs ANY command under a real pseudo-terminal (so a TUI thinks it's attached
// to a terminal and renders normally), capturing every output byte plus
// per-read timestamps. Pure Dart + dart:ffi (openpty + posix_spawnp + a
// non-blocking read loop); no third-party PTY dep, no Flutter, no Python.
// POSIX only (macOS / Linux). `fork()` in the VM is unsafe, so we use
// posix_spawnp, which forks+execs in one syscall.
//
//   dart run capture_pty.dart --out cap --timeout 5 --ui-mode strict-ui \
//     --frame-count 6 -- <command> [args...]
//
// Writes <out>.bin (raw wire bytes) + <out>.json (reads/timing) for analyze.dart.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ---- libc / libutil bindings ----------------------------------------------

final DynamicLibrary _libc = DynamicLibrary.process();
// On Linux openpty lives in libutil; on macOS it's in libSystem (process()).
final DynamicLibrary _util =
    Platform.isLinux ? DynamicLibrary.open('libutil.so.1') : _libc;

final _openpty = _util.lookupFunction<
    Int32 Function(Pointer<Int32>, Pointer<Int32>, Pointer<Void>, Pointer<Void>,
        Pointer<Uint16>),
    int Function(Pointer<Int32>, Pointer<Int32>, Pointer<Void>, Pointer<Void>,
        Pointer<Uint16>)>('openpty');

final _spawnp = _libc.lookupFunction<
    Int32 Function(Pointer<Int32>, Pointer<Utf8>, Pointer<Void>, Pointer<Void>,
        Pointer<Pointer<Utf8>>, Pointer<Pointer<Utf8>>),
    int Function(Pointer<Int32>, Pointer<Utf8>, Pointer<Void>, Pointer<Void>,
        Pointer<Pointer<Utf8>>, Pointer<Pointer<Utf8>>)>('posix_spawnp');

final _faInit = _libc.lookupFunction<Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('posix_spawn_file_actions_init');
final _faDup2 = _libc.lookupFunction<
    Int32 Function(Pointer<Void>, Int32, Int32),
    int Function(Pointer<Void>, int, int)>('posix_spawn_file_actions_adddup2');
final _faClose = _libc.lookupFunction<Int32 Function(Pointer<Void>, Int32),
    int Function(Pointer<Void>, int)>('posix_spawn_file_actions_addclose');

final _read = _libc.lookupFunction<
    IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
    int Function(int, Pointer<Uint8>, int)>('read');
final _close =
    _libc.lookupFunction<Int32 Function(Int32), int Function(int)>('close');
final _fcntl = _libc.lookupFunction<Int32 Function(Int32, Int32, Int32),
    int Function(int, int, int)>('fcntl');
final _kill =
    _libc.lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'kill');
final _waitpid = _libc.lookupFunction<
    Int32 Function(Int32, Pointer<Int32>, Int32),
    int Function(int, Pointer<Int32>, int)>('waitpid');
final _getrusage = _libc.lookupFunction<Int32 Function(Int32, Pointer<Uint8>),
    int Function(int, Pointer<Uint8>)>('getrusage');

const _rusageChildren = -1;

/// Peak RSS (bytes) and total CPU time (ms) of all reaped children, read out of
/// `struct rusage` by byte offset. Layout (64-bit): ru_utime{tv_sec@0, tv_usec},
/// ru_stime{tv_sec@16, tv_usec}, ru_maxrss@32. tv_usec is 32-bit on macOS,
/// 64-bit on Linux; ru_maxrss is bytes on macOS, kilobytes on Linux.
({int rssBytes, double cpuMs}) _childUsage(Pointer<Uint8> buf) {
  if (_getrusage(_rusageChildren, buf) != 0) return (rssBytes: 0, cpuMs: 0);
  final i64 = buf.cast<Int64>();
  final i32 = buf.cast<Int32>();
  int usec(int byteOffset) =>
      Platform.isMacOS ? i32[byteOffset ~/ 4] : i64[byteOffset ~/ 8];
  final utimeMs = i64[0] * 1000 + usec(8) / 1000.0;
  final stimeMs = i64[2] * 1000 + usec(24) / 1000.0;
  final maxrss = i64[4];
  return (
    rssBytes: Platform.isMacOS ? maxrss : maxrss * 1024,
    cpuMs: utimeMs + stimeMs,
  );
}

// Platform constants.
const _fSetfl = 4;
const _fGetfl = 3;
final int _oNonblock = Platform.isMacOS ? 0x0004 : 0x800;
const _wnohang = 1;
const _sigterm = 15;

void _fail(String m) {
  stderr.writeln('capture_pty: $m');
  exit(1);
}

({int? exitCode, int? signal}) _decodeWaitStatus(int status) {
  final signal = status & 0x7f;
  if (signal == 0) return (exitCode: (status >> 8) & 0xff, signal: null);
  if (signal == 0x7f) return (exitCode: null, signal: null);
  return (exitCode: null, signal: signal);
}

void main(List<String> args) {
  var out = 'capture';
  var timeout = 10.0;
  var cols = 100, rows = 30;
  int? logicalFrameCount;
  String? uiMode;
  final cmd = <String>[];
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--out') {
      out = args[++i];
    } else if (a == '--timeout') {
      timeout = double.parse(args[++i]);
    } else if (a == '--cols') {
      cols = int.parse(args[++i]);
    } else if (a == '--rows') {
      rows = int.parse(args[++i]);
    } else if (a == '--ui-mode') {
      uiMode = args[++i];
      if (uiMode != 'strict-ui' && uiMode != 'full-ui') {
        _fail('--ui-mode must be strict-ui or full-ui');
      }
    } else if (a == '--frame-count') {
      logicalFrameCount = int.parse(args[++i]);
      if (logicalFrameCount <= 0) {
        _fail('--frame-count must be a positive integer');
      }
    } else if (a == '--') {
      cmd.addAll(args.sublist(i + 1));
      break;
    } else {
      cmd.add(a);
    }
  }
  if (cmd.isEmpty) _fail('no command (use: --out X -- cmd args)');

  final arena = Arena();
  try {
    // openpty(&master, &slave, null, null, &winsize)
    final master = arena<Int32>();
    final slave = arena<Int32>();
    final win = arena<Uint16>(4);
    win[0] = rows;
    win[1] = cols;
    win[2] = 0;
    win[3] = 0;
    if (_openpty(master, slave, nullptr, nullptr, win) != 0) {
      _fail('openpty failed');
    }
    final masterFd = master.value, slaveFd = slave.value;

    // file actions: child dup2 slave -> 0/1/2, close master + slave.
    // posix_spawn_file_actions_t is opaque; over-allocate generously for both
    // macOS (pointer-sized) and Linux (~80-byte struct).
    final fa = arena<Uint8>(256).cast<Void>();
    _faInit(fa);
    _faDup2(fa, slaveFd, 0);
    _faDup2(fa, slaveFd, 1);
    _faDup2(fa, slaveFd, 2);
    _faClose(fa, slaveFd);
    _faClose(fa, masterFd);

    // argv (null-terminated).
    final argv = arena<Pointer<Utf8>>(cmd.length + 1);
    for (var i = 0; i < cmd.length; i++) {
      argv[i] = cmd[i].toNativeUtf8(allocator: arena);
    }
    argv[cmd.length] = nullptr;

    // envp = current env + TERM/COLUMNS/LINES (null-terminated).
    final env = <String, String>{
      ...Platform.environment,
      'TERM': Platform.environment['TERM'] ?? 'xterm-256color',
      'COLUMNS': '$cols',
      'LINES': '$rows',
    };
    final entries = env.entries.toList();
    final envp = arena<Pointer<Utf8>>(entries.length + 1);
    for (var i = 0; i < entries.length; i++) {
      envp[i] = '${entries[i].key}=${entries[i].value}'
          .toNativeUtf8(allocator: arena);
    }
    envp[entries.length] = nullptr;

    final pidPtr = arena<Int32>();
    final rc = _spawnp(pidPtr, cmd.first.toNativeUtf8(allocator: arena), fa,
        nullptr, argv, envp);
    if (rc != 0) _fail('posix_spawnp failed (rc=$rc) for "${cmd.first}"');
    final pid = pidPtr.value;

    _close(slaveFd); // parent doesn't use the slave end.
    // Non-blocking master so we can enforce a timeout + timestamp reads.
    final flags = _fcntl(masterFd, _fGetfl, 0);
    _fcntl(masterFd, _fSetfl, flags | _oNonblock);

    final buf = arena<Uint8>(65536);
    final status = arena<Int32>();
    final raw = BytesBuilder();
    final reads = <List<num>>[];
    double? ttfb;
    final sw = Stopwatch()..start();
    var childExited = false;
    var timedOut = false;
    int? childStatus;

    while (true) {
      final elapsedMs = sw.elapsedMicroseconds / 1000.0;
      if (elapsedMs > timeout * 1000) {
        timedOut = true;
        _kill(pid, _sigterm);
        break;
      }
      final n = _read(masterFd, buf, 65536);
      if (n > 0) {
        final now = sw.elapsedMicroseconds / 1000.0;
        ttfb ??= now;
        raw.add(buf.asTypedList(n));
        reads.add([double.parse(now.toStringAsFixed(3)), n]);
        continue; // drain fast
      }
      if (n == 0) break; // EOF — all slave fds closed
      // n < 0: no data right now (EAGAIN) or the pty closed.
      if (childExited) break;
      if (_waitpid(pid, status, _wnohang) == pid) {
        childStatus = status.value;
        childExited = true; // one more drain pass, then EOF/-1 ends it
      }
      sleep(const Duration(milliseconds: 2));
    }
    _close(masterFd);
    if (childStatus == null && _waitpid(pid, status, 0) == pid) {
      childStatus = status.value;
    }
    final decoded = childStatus == null
        ? (exitCode: null, signal: null)
        : _decodeWaitStatus(childStatus);
    final usage = _childUsage(arena<Uint8>(256));

    final bytes = raw.toBytes();
    final durationMs = sw.elapsedMicroseconds / 1000;
    File('$out.bin').writeAsBytesSync(bytes);
    File('$out.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'cmd': cmd,
      'totalBytes': bytes.length,
      'durationMs': double.parse(durationMs.toStringAsFixed(3)),
      'ttfbMs': ttfb,
      'maxRssBytes': usage.rssBytes,
      'cpuMs': double.parse(usage.cpuMs.toStringAsFixed(3)),
      'timedOut': timedOut,
      if (decoded.exitCode != null) 'exitCode': decoded.exitCode,
      if (decoded.signal != null) 'signal': decoded.signal,
      if (uiMode != null) 'uiMode': uiMode,
      if (logicalFrameCount != null) 'logicalFrameCount': logicalFrameCount,
      'reads': reads,
    }));
    stdout.writeln(
        'captured ${bytes.length} bytes in ${reads.length} reads -> $out.bin');
    if (!timedOut && decoded.exitCode != null && decoded.exitCode != 0) {
      _fail('child exited with code ${decoded.exitCode} for "${cmd.first}"');
    }
    if (!timedOut && decoded.signal != null) {
      _fail('child exited from signal ${decoded.signal} for "${cmd.first}"');
    }
  } finally {
    arena.releaseAll();
  }
}
