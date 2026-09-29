#!/usr/bin/env python3
"""Native sink backpressure with aliased PTY input/output descriptors.

A slow output consumer must not truncate frames when the input lease sets the
shared O_NONBLOCK bit. This does not promise interruptible synchronous writes.
"""
import argparse
import fcntl
import os
from pathlib import Path
import select
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def run(dart):
    master, slave = os.openpty()
    original = fcntl.fcntl(slave, fcntl.F_GETFL)
    child = subprocess.Popen([
        dart, '--packages=packages/fleury/.dart_tool/package_config.json',
        'packages/fleury/test/fixtures/posix_input_resources_fixture.dart', '--backpressure',
    ], cwd=ROOT, stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
    data = bytearray()
    paused = False
    deadline = time.monotonic() + 15
    try:
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.05)[0]:
                data.extend(os.read(master, 65536))
            if not paused and b'PRESSURE READY' in data:
                paused = True
                time.sleep(0.3)
                assert child.poll() is None, 'writer did not encounter backpressure'
            if child.poll() is not None:
                while select.select([master], [], [], 0)[0]:
                    chunk = os.read(master, 65536)
                    # A revoked macOS PTY stays readable at EOF; it will not
                    # become unready just because the child has exited.
                    if not chunk:
                        break
                    data.extend(chunk)
                assert child.returncode == 0, bytes(data[-1000:])
                assert paused and b'BACKPRESSURE PASS' in data, bytes(data[-1000:])
                assert data.count(b'X') == 32 * 65536, 'truncated synchronous output'
                assert fcntl.fcntl(slave, fcntl.F_GETFL) & os.O_NONBLOCK == original & os.O_NONBLOCK, 'shared blocking mode changed'
                print('PASS 2MiB native output across PTY backpressure; ancestor flags restored')
                return
        raise AssertionError('native output remained blocked after consumer resumed')
    finally:
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
        os.close(master)
        os.close(slave)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--dart', default='dart')
    run(parser.parse_args().dart)
