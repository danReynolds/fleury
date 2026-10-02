// Stop-race probe: does killpg(own group, SIGSTOP) stop the calling thread
// before it returns? Writes 'B' before the stop and 'A' right after the call
// returns (raw write(2) on fd 1). The parent (race.py) waits for the stop and
// checks whether 'A' arrived before the stop was reported.
//
// usage: dart probe.dart <iterations> <main|isolate> <none|toggle>
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

final _libc = DynamicLibrary.process();
final _getpgrp = _libc.lookupFunction<Int32 Function(), int Function()>(
  'getpgrp',
);
final _killpg = _libc
    .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
      'killpg',
    );
final _write = _libc
    .lookupFunction<
      IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
      int Function(int, Pointer<Uint8>, int)
    >('write');
final _malloc = _libc
    .lookupFunction<Pointer<Uint8> Function(IntPtr), Pointer<Uint8> Function(int)>(
      'malloc',
    );
final _sigemptyset = _libc
    .lookupFunction<Int32 Function(Pointer<Uint8>), int Function(Pointer<Uint8>)>(
      'sigemptyset',
    );
final _sigaddset = _libc
    .lookupFunction<
      Int32 Function(Pointer<Uint8>, Int32),
      int Function(Pointer<Uint8>, int)
    >('sigaddset');
final _pthreadSigmask = _libc
    .lookupFunction<
      Int32 Function(Int32, Pointer<Uint8>, Pointer<Uint8>),
      int Function(int, Pointer<Uint8>, Pointer<Uint8>)
    >('pthread_sigmask');

final int _sigstop = Platform.isMacOS ? 17 : 19;
final int _sigusr2 = Platform.isMacOS ? 31 : 12;
// SIG_BLOCK / SIG_SETMASK: Linux 0 / 2, Darwin 1 / 3.
final int _sigBlock = Platform.isMacOS ? 1 : 0;
final int _sigSetmask = Platform.isMacOS ? 3 : 2;

void _byte(int b) {
  final p = _malloc(1);
  p.value = b;
  _write(1, p, 1);
}

String _thread() {
  if (!Platform.isLinux) return 'n/a';
  final link = Link('/proc/thread-self').targetSync();
  final tasks = [
    for (final task in Directory('/proc/self/task').listSync())
      '${task.uri.pathSegments.where((s) => s.isNotEmpty).last}:'
          '${File('${task.path}/comm').readAsStringSync().trim()}:'
          '${File('${task.path}/syscall').readAsStringSync().split(' ').first}',
  ];
  return '$pid:$link tasks=$tasks';
}

void _toggleMask() {
  final set = _malloc(256);
  final old = _malloc(256);
  _sigemptyset(set);
  _sigaddset(set, _sigusr2);
  _pthreadSigmask(_sigBlock, set, old);
  _pthreadSigmask(_sigSetmask, old, nullptr);
}

void _run(List<Object> args) {
  final iterations = args[0] as int;
  final fix = args[1] as String;
  stderr.writeln('probe thread ${_thread()} pid=$pid');
  for (var i = 0; i < iterations; i++) {
    _byte(0x42); // B
    _killpg(_getpgrp(), _sigstop);
    if (fix == 'toggle') _toggleMask();
    _byte(0x41); // A
    // Busy for a moment so the next 'B' doesn't race the parent's read.
    final until = DateTime.now().add(const Duration(milliseconds: 2));
    while (DateTime.now().isBefore(until)) {}
  }
  _byte(0x45); // E
}

Future<void> main(List<String> args) async {
  final iterations = int.parse(args[0]);
  final where = args[1];
  final fix = args[2];
  stderr.writeln('main thread ${_thread()}');
  if (where == 'main') {
    _run([iterations, fix]);
  } else {
    final done = ReceivePort();
    await Isolate.spawn(_run, [iterations, fix], onExit: done.sendPort);
    await done.first;
  }
  exit(0);
}
