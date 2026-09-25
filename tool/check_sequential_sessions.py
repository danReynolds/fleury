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


def slow_cleanup(dart, executable=None):
    with tempfile.TemporaryDirectory(prefix='fleury-slow-cleanup-') as directory:
        report = Path(directory) / 'result.json'
        app = Session(dart, fixture='test/fixtures/sequential_native_sessions_fixture.dart',
                      executable=executable, arguments=['--slow-cleanup-report', str(report)])
        try:
            app.wait(lambda: 'SLOW HANDOFF READY' in app.text(), 'slow handoff UI')
            app.send(b'\x0f')
            app.wait(lambda: 'SLOW CHILD READY' in app.text(), 'slow child')
            # The child remains blocked until runApp reports its deadline and
            # a new invocation proves admission is still held.
            app.wait(report.exists, 'bounded cleanup error report', timeout=8)
            first = json.loads(report.read_text())
            assert 'terminal restore' in first['first'], first
            assert first['blocked'] is True, first
            assert 'handoff' not in first, first
            assert b'fleury: error during teardown' not in app.raw, 'diagnostics corrupted child UI'
            app.send(b'finish\n')
            app.wait(lambda: 'RECOVERED READY' in app.text(), 'recovered session')
            before = bytes(app.raw)
            assert before.count(b'CAPTURE BEFORE SLOW CHILD') == 1, before[-4000:]
            assert before.index(b'CAPTURE BEFORE SLOW CHILD') < before.index(b'RECOVERED READY'), before[-4000:]
            assert b'fleury: error during teardown' in before, 'cleanup failure was not reported'
            assert before.rindex(b'fleury: error during teardown') < before.index(b'RECOVERED READY'), before[-4000:]
            diagnostic_count = before.count(b'fleury: error during teardown')
            app.send(b'\r')
            app.wait(lambda: app.child.poll() is not None, 'slow cleanup process exit')
            for _ in range(3):
                app.pump(0.05)
            assert app.child.returncode == 0, app.text()
            result = json.loads(report.read_text())
            assert result['handoff'] == result['second'] == 'completed', result
            assert b'capture is stopped' not in app.raw, app.text()
            assert bytes(app.raw).count(b'CAPTURE BEFORE SLOW CHILD') == 1, app.text()
            assert bytes(app.raw).count(b'fleury: error during teardown') == diagnostic_count, 'late diagnostics entered next UI'
            assert b'PTY-TERMIOS-EXACT' in app.raw and b'PTY-BLOCKING-RESTORED' in app.raw, app.text()
            print('PASS delayed handoff cleanup retains capture and replays before next session')
        finally:
            app.close()


def throwing_hook(dart, executable=None):
    with tempfile.TemporaryDirectory(prefix='fleury-throwing-hook-') as directory:
        report = Path(directory) / 'result.json'
        app = Session(dart, fixture='test/fixtures/sequential_native_sessions_fixture.dart',
                      executable=executable, arguments=['--throwing-hook-report', str(report)])
        try:
            app.wait(lambda: 'HOOK READY' in app.text(), 'hook UI')
            app.send(b'\r')
            app.wait(lambda: 'stray hook failed' in app.text(), 'reported hook failure')
            assert app.child.poll() is None, 'hook failure killed the native process'
            assert b'HOOK FAILURE TRIGGER' not in app.raw, 'failed line corrupted live UI'
            app.send(b'\x03')
            app.wait(lambda: app.child.poll() is not None, 'hook cleanup')
            for _ in range(3):
                app.pump(0.05)
            assert app.child.returncode == 0, app.text()
            assert json.loads(report.read_text()) == {'signal': 'interrupt', 'calls': 2}, report.read_text()
            raw = bytes(app.raw)
            assert b'HOOKED BEFORE FAILURE' not in raw, 'already handled output replayed'
            assert raw.count(b'HOOK FAILURE TRIGGER') == 1, app.text()
            assert raw.index(b'\x1b[?1049l') < raw.index(b'HOOK FAILURE TRIGGER'), app.text()
            assert b'PTY-TERMIOS-EXACT' in raw and b'PTY-BLOCKING-RESTORED' in raw, app.text()
            print('PASS throwing output hook is reported, fenced, and restores the native terminal')
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
        slow_cleanup(args.dart, args.executable)
        throwing_hook(args.dart, args.executable)
        hangup(args.dart, args.executable)
        hangup(args.dart, args.executable, inline=True)
