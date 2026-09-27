import 'dart:io';

import 'package:test/test.dart';

void main() {
  for (final inline in [false, true]) {
    test(
      'native output survives backpressure (inline=$inline)',
      () async {
        final result = await Process.run('python3', [
          '-c',
          r'''
import fcntl, os, pty, select, struct, subprocess, sys, termios, time
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 30, 132, 0, 0))
before = termios.tcgetattr(slave)
blocking = os.get_blocking(slave)
child = subprocess.Popen(sys.argv[1:], stdin=slave, stdout=slave, stderr=subprocess.PIPE,
                         env={**os.environ, 'TERM': 'xterm-256color', 'FLEURY_SYNC_OUTPUT': '0'})
output = bytearray()
deadline = time.monotonic() + 20
delayed = False
try:
    while time.monotonic() < deadline:
        if select.select([master], [], [], .05)[0]:
            chunk = os.read(master, 65536)
            output.extend(chunk)
            if b'\x1b[6n' in chunk:
                os.write(master, b'\x1b[1;1R')
            if b'\x1b[c' in chunk:
                os.write(master, b'\x1b[?1;2c')
            if b'FRAME-START' in output and not delayed:
                delayed = True
                time.sleep(.2)  # force a full output queue
        elif child.poll() is not None:
            break
    assert child.poll() == 0, (child.poll(), child.stderr.read() if child.poll() is not None else b'timeout')
    payload = bytes(output).split(b'FRAME-START')[1].split(b'FRAME-END')[0]
    assert payload == b'x' * (128 * 1024), ('truncated output', len(payload))
    assert b'OUTPUT-RESTORED' in output
    after = termios.tcgetattr(slave)
    if sys.platform == 'darwin':
        # PENDIN is kernel-owned pending retype state, not an application mode.
        before[3] &= ~termios.PENDIN
        after[3] &= ~termios.PENDIN
    assert after == before, 'termios changed'
    assert os.get_blocking(slave) == blocking, 'input flags changed'
finally:
    if child.poll() is None:
        child.kill()
    child.wait()
    os.close(master)
    os.close(slave)
''',
          Platform.resolvedExecutable,
          '--packages=.dart_tool/package_config.json',
          'test/fixtures/terminal_output_backpressure_fixture.dart',
          if (inline) '--inline',
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      },
      skip: Platform.isWindows,
      tags: ['pty'],
    );
  }
}
