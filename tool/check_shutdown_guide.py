#!/usr/bin/env python3
"""Exercise the guide's compiled commands on a real POSIX PTY.

Compile website/examples/doc_snippets/shutdown/{signals,finish_work}.dart,
then pass them with --default-executable and --finish-executable.
Signal delivery, exit status, and terminal restoration are native behavior;
the UI is inspected through the same emulator as the inline lifecycle checks.
"""
import argparse
import os
import re
import signal

from check_inline_tui import Session


def check(binary, cause, finishing):
    app = Session('unused', rows=20, executable=binary)
    expected = {'finish': 0, 'ctrl-c': 130, 'SIGINT': 130,
                'SIGTERM': 143, 'SIGHUP': 129}[cause]
    try:
        app.wait(lambda: '[ Finish ]' in app.text(), 'interactive task')
        pid = int(re.search(rb'PID (\d+)', app.raw)[1])
        if cause == 'finish':
            app.send(b'\r')
        elif cause == 'ctrl-c':
            app.send(b'\x03')
        else:
            os.kill(pid, getattr(signal, cause))
        if finishing:
            app.wait(lambda: 'Finishing current item' in app.text(), 'visible cleanup')
            assert app.child.poll() is None, 'UI ended before its work finished'
            if cause == 'ctrl-c':
                # Repeated raw key input reuses the same app-owned work;
                # it is not the POSIX driver's repeated-signal force path.
                app.send(b'\x03')
        app.finish(expected, summary=False)
        raw = bytes(app.raw)
        summary = f'Resources closed. Exit code: {expected}'.encode()
        assert raw.count(summary) == 1, (cause, app.text())
        assert raw.index(b'\x1b[?7h') < raw.index(summary), 'output before restoration'
        assert b'PTY-TERMIOS-EXACT' in raw, 'terminal settings changed'
        if not finishing:
            assert b'Finishing current item' not in raw, 'default exit unexpectedly waited'
        print(f'PASS finish_work={finishing} cause={cause} exit={expected}', flush=True)
    finally:
        app.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--default-executable', required=True)
    parser.add_argument('--finish-executable', required=True)
    args = parser.parse_args()
    for finishing, binary in [(False, args.default_executable), (True, args.finish_executable)]:
        for cause in ['finish', 'ctrl-c', 'SIGINT', 'SIGTERM', 'SIGHUP']:
            check(binary, cause, finishing)
