"""Container PID 1: bound startup/work and kill the entire process group on exit.

The dedicated control pipe is not stdout and never contains submitted source.
Cloud Run's HTTP timeout alone does not stop compiler work.
"""
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time


def supervise(command, *, startup_seconds=120, request_seconds=25, stop_seconds=8):
    read_fd, write_fd = os.pipe()
    env = {**os.environ, 'FLEURY_WATCHDOG_FD': str(write_fd)}
    child = subprocess.Popen(command, env=env, pass_fds=(write_fd,), start_new_session=True)
    os.close(write_fd)
    selector = selectors.DefaultSelector()
    selector.register(read_fd, selectors.EVENT_READ)
    started = time.monotonic()
    ready = False
    active = {}
    pending = b''
    stopping = None
    code = 1

    def kill_group(sig):
        try:
            os.killpg(child.pid, sig)
        except ProcessLookupError:
            pass

    def stop(signum, _frame):
        nonlocal stopping
        if stopping is None:
            stopping = time.monotonic()
            # Let the API drain requests and shut down its workers first.
            # Signalling the group here races analyzer shutdown against a dead
            # pipe. The deadline/finally still kill every remaining descendant.
            try:
                child.send_signal(signal.SIGTERM)
            except ProcessLookupError:
                pass

    previous = {sig: signal.signal(sig, stop) for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        while child.poll() is None:
            now = time.monotonic()
            overdue = any(now - stamp >= request_seconds for stamp in active.values())
            if overdue or (not ready and now - started >= startup_seconds):
                print(json.dumps({'severity': 'ERROR', 'event': 'compiler_deadline',
                                  'phase': 'request' if ready else 'startup'}), flush=True)
                code = 124
                break
            if stopping is not None and now - stopping >= stop_seconds:
                code = 0
                break
            for _, _ in selector.select(0.1):
                chunk = os.read(read_fd, 4096)
                if not chunk:
                    selector.unregister(read_fd)
                    continue
                pending += chunk
                while b'\n' in pending:
                    line, pending = pending.split(b'\n', 1)
                    fields = line.decode('ascii').split()
                    if fields == ['ready']:
                        ready = True
                    elif len(fields) == 2 and fields[0] == 'start':
                        active[fields[1]] = time.monotonic()
                    elif len(fields) == 2 and fields[0] == 'end':
                        active.pop(fields[1], None)
                    else:
                        raise RuntimeError('Invalid watchdog control message')
        else:
            code = child.returncode
    finally:
        # Covers worker crashes, graceful service exit, timeout, and SIGTERM.
        kill_group(signal.SIGKILL)
        child.wait()
        selector.close()
        os.close(read_fd)
        for sig, handler in previous.items():
            signal.signal(sig, handler)
    return code


if __name__ == '__main__':
    here = Path(__file__).resolve().parent
    os.chdir(here)
    sdk = os.environ.get('DART_SDK', '/usr/lib/dart')
    executable = here / 'bin/server'
    # Images precompile the HTTP host. Local development keeps source execution.
    command = [str(executable)] if executable.is_file() else [
        f'{sdk}/bin/dart', '--disable-dart-dev',
        '--packages=.dart_tool/package_config.json', 'bin/server.dart']
    sys.exit(supervise(command))
