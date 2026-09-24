#!/usr/bin/env python3
"""Qualify runApp -> sync prompt -> child -> runApp on a real macOS/Linux PTY.

Uses the same terminal emulator/guardian as check_inline_tui.py; no browser or
fake-driver input. Also verifies the ancestor-held descriptor's blocking bit.
"""
import argparse
import json
import os
from pathlib import Path
import tempfile
import time
from check_inline_tui import Session


def run(dart, executable=None):
    app = Session(dart, fixture='test/fixtures/sequential_native_sessions_fixture.dart',
                  executable=executable)
    try:
        for label in ['INLINE-A', 'FULL-B', 'INLINE-C']:
            app.wait(lambda: f'{label} READY' in app.text(), f'{label} frame')
            app.send('\x1b[200~héllo中\x1b[201~\r'.encode())
            if label == 'INLINE-A':
                app.wait(lambda: 'PLAIN READY' in app.text(), 'ordinary prompt')
                app.send(b'plain\n')
                app.wait(lambda: 'CHILD READY' in app.text(), 'inherited child')
                app.send(b'child\n')
            elif label == 'FULL-B':
                app.wait(lambda: 'HANDOFF READY' in app.text(), 'handoff UI')
                app.send(b'\x0f')
                app.wait(lambda: 'BORROW READY' in app.text(), 'borrowed child')
                deadline = time.monotonic() + 0.2
                while time.monotonic() < deadline:
                    app.pump(0.02)
                assert b'HANDOFF CLOSED' not in app.raw, 'runApp returned before child exit'
                app.send(b'borrow\n')
        app.wait(lambda: 'ASYNC READY' in app.text(), 'Dart async stdin')
        app.send(b'async\n')
        app.wait(lambda: app.child.poll() is not None, 'natural process exit')
        for _ in range(3):
            app.pump(0.05)
        assert app.child.returncode == 0, (app.child.returncode, app.text())
        for marker in [b'SEQUENTIAL PASS', b'PTY-TERMIOS-EXACT', b'PTY-BLOCKING-RESTORED']:
            assert marker in app.raw, (marker, app.text(), bytes(app.raw[-3000:]))
        print('PASS inline -> plain prompt -> child -> full-screen -> inline -> Dart stdin -> natural exit')
    finally:
        app.close()


def showcase(binary, full_screen=False):
    app = Session('unused', rows=30, executable=binary,
                  arguments=['--repeat', *(['--full-screen'] if full_screen else [])])
    def click(label):
        row = app.row(label)
        app.click(row, app.screen.display[row].index(label) + 1)
    try:
        for answer in [b'y\n', b'n\n']:
            app.wait(lambda: 'Include tests' in app.text() and 'Review' in app.text(), 'setup form')
            click('Review')
            app.wait(lambda: 'Generate config' in app.text(), 'setup review')
            app.send(b'\r')
            app.wait(lambda: 'Open setup again?' in app.text(), 'ordinary CLI prompt')
            app.send(answer)
        app.wait(lambda: app.child.poll() is not None, 'showcase exit')
        for _ in range(3):
            app.pump(0.05)
        assert app.child.returncode == 0, app.text()
        assert b'PTY-BLOCKING-RESTORED' in app.raw, app.text()
        print(f'PASS setup --repeat full_screen={full_screen}')
    finally:
        app.close()


def hangup(dart, executable=None, inline=False):
    with tempfile.TemporaryDirectory(prefix='fleury-hangup-') as directory:
        result = Path(directory) / 'result.json'
        # No guardian: terminal loss makes its termios inspection meaningless
        # and killing a session leader can generate an extra unrelated SIGHUP.
        app = Session(dart, fixture='test/fixtures/sequential_native_sessions_fixture.dart',
                      executable=executable, guard=False,
                      arguments=['--hangup-report', str(result), *(['--inline'] if inline else [])])
        try:
            app.wait(lambda: 'HANGUP READY' in app.text(), 'hangup frame')
            os.close(app.master)
            app.master = -1
            assert app.child.wait(timeout=10) == 0, 'hangup did not return naturally'
            assert json.loads(result.read_text()) == {'signal': 'hangup'}, result.read_text()
            print(f'PASS physical terminal disconnect inline={inline}')
        finally:
            app.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--executable')
    parser.add_argument('--showcase', help='compiled setup demo to exercise twice')
    args = parser.parse_args()
    if args.showcase:
        showcase(args.showcase)
        showcase(args.showcase, full_screen=True)
    else:
        run(args.dart, args.executable)
        hangup(args.dart, args.executable)
        hangup(args.dart, args.executable, inline=True)
