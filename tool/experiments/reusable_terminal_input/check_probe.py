#!/usr/bin/env python3
"""Bounded PTY checks for the standalone input ownership experiment."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import termios
import time

ROOT = Path(__file__).resolve().parents[3]


def run(command, *, file_stream=False):
    master, slave = os.openpty()
    original = termios.tcgetattr(slave)
    original_flags = fcntl.fcntl(slave, fcntl.F_GETFL)
    output = bytearray()
    sent = set()
    steps = {'FIRST READY': b'a', 'PLAIN READY': b'plain\n',
             'CHILD READY': b'child\n', 'BETWEEN READY': b'between\n',
             'SECOND READY': b'b', 'ASYNC READY': b'async\n'}
    child = subprocess.Popen(command, cwd=ROOT, stdin=slave, stdout=slave,
                             stderr=slave, start_new_session=True)
    deadline = time.monotonic() + 15
    cancellation_at = None
    try:
        while time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], 0.05)
            if ready:
                output.extend(os.read(master, 65536))
            text = output.decode(errors='replace')
            if file_stream:
                if 'CANCELLING' in text and cancellation_at is None:
                    cancellation_at = time.monotonic()
                if cancellation_at and time.monotonic() - cancellation_at > 2:
                    if child.poll() is None:
                        return {'result': 'BLOCKED_CANCEL', 'waitSeconds': 2}
            else:
                for marker, payload in steps.items():
                    if marker in text and marker not in sent:
                        os.write(master, payload)
                        sent.add(marker)
            if child.poll() is not None:
                assert child.returncode == 0, text
                assert termios.tcgetattr(slave) == original, 'termios changed'
                assert (fcntl.fcntl(slave, fcntl.F_GETFL) & os.O_NONBLOCK) == (
                    original_flags & os.O_NONBLOCK), 'blocking mode changed'
                if file_stream:
                    return {'result': 'CANCELLED'}
                assert len(sent) == len(steps), text
                lines = [line for line in text.splitlines() if line.startswith('{')]
                assert lines, text
                return json.loads(lines[-1])
        raise AssertionError('probe timed out: ' + output.decode(errors='replace'))
    finally:
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
        os.close(master)
        os.close(slave)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--executable')
    parser.add_argument('--package-config', default=str(
        ROOT / 'packages/fleury/.dart_tool/package_config.json'))
    parser.add_argument('--file-stream', action='store_true')
    parser.add_argument('--pause-handoff', action='store_true')
    parser.add_argument('--reopen-tty', action='store_true')
    args = parser.parse_args()
    command = [args.executable] if args.executable else [
        args.dart, '--packages=' + args.package_config,
        str(Path(__file__).with_name('input_probe.dart'))]
    if args.file_stream:
        command.append('--file-stream')
    if args.pause_handoff:
        command.append('--pause-handoff')
    if args.reopen_tty:
        command.append('--reopen-tty')
    print(json.dumps(run(command, file_stream=args.file_stream)))
