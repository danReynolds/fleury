import 'dart:io';
import 'package:test/test.dart';

void main() {
  test(
    'native restoration survives a closed stdin descriptor',
    () async {
      final result = await Process.run('python3', [
        '-c',
        r'''
import os, pty, select, sys, termios
gate_read, gate_write = os.pipe()
pid, master = pty.fork()
if pid == 0:
    os.close(gate_write)
    os.read(gate_read, 1)
    os.close(gate_read)
    os.execv(sys.argv[1], sys.argv[1:])
os.close(gate_read)
original = termios.tcgetattr(master)
os.write(gate_write, b'x')
os.close(gate_write)
output = bytearray()
try:
    while b'restored' not in output:
        ready, _, _ = select.select([master], [], [], 20)
        assert ready, 'child timed out'
        output.extend(os.read(master, 1024))
    restored = termios.tcgetattr(master)
    # Darwin marks pending input for retyping on return to canonical mode.
    # PENDIN is kernel-managed transient state, not an application mode.
    if sys.platform == 'darwin':
        original[3] &= ~termios.PENDIN
        restored[3] &= ~termios.PENDIN
    assert restored == original, 'termios snapshot not restored'
    _, status = os.waitpid(pid, 0)
    assert os.waitstatus_to_exitcode(status) == 0
finally:
    os.close(master)
''',
        Platform.resolvedExecutable,
        '--packages=.dart_tool/package_config.json',
        'test/fixtures/termios_restore_fixture.dart',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    skip: Platform.isWindows,
    tags: ['pty'],
  );
}
