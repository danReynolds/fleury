#!/usr/bin/env python3
"""Run Fleury's inline fixture on a real POSIX PTY with a terminal emulator.

pip install -r tool/inline-pty-requirements.txt
python tool/check_inline_tui.py --dart /path/to/dart

Checks native termios/input/lifecycle plus the rendered screen and scrollback.
The emulator supplies real cursor reports; canned CPR replies cannot validate
inline placement. This is automated PTY evidence, not a physical terminal UI.
"""
import argparse
import codecs
import fcntl
import os
from pathlib import Path
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time

import pyte

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "packages/fleury"


class Session:
    def __init__(self, dart, *, cols=80, rows=18, supervised=False,
                 fixture="test/fixtures/inline_terminal_fixture.dart", executable=None, arguments=(),
                 guard=True):
        self.master, self.slave = os.openpty()
        self.original_modes = termios.tcgetattr(self.slave)
        self.raw = bytearray()
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")
        self.keyboard_tail = ''
        self.hold_replies = False
        self.held_replies = []
        self.set_size(cols, rows)
        owner = self

        class Screen(pyte.HistoryScreen):
            def write_process_input(self, data):
                if owner.hold_replies:
                    owner.held_replies.append(data.encode())
                else:
                    owner.send(data.encode())

        self.screen = Screen(cols, rows, history=2000)
        self.stream = pyte.Stream(self.screen)

        def child_terminal():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)

        command = ([executable] if executable else
                   [dart, "--packages=.dart_tool/package_config.json", fixture])
        command.extend(arguments)
        if supervised:
            command.append("--supervised")
        self.child = subprocess.Popen(
            ([sys.executable, str(Path(__file__).resolve()), '--guard', *command]
             if guard else command),
            cwd=PACKAGE, stdin=self.slave, stdout=self.slave,
            stderr=self.slave, preexec_fn=child_terminal,
            env={**os.environ, "TERM": "xterm-256color", "FLEURY_SYNC_OUTPUT": "0"},
        )

    def set_size(self, cols, rows):
        fcntl.ioctl(self.master, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    def resize(self, cols, rows):
        # Commit old-size output before changing the emulator's geometry.
        while select.select([self.master], [], [], 0)[0]:
            self.pump(0)
        # pyte clips from the top but does not shift its saved cursor with
        # those lines. Keep the cursor attached to the retained content.
        y = max(0, self.screen.cursor.y - max(0, self.screen.lines - rows))
        self.screen.resize(lines=rows, columns=cols)
        self.screen.cursor.y = min(y, rows - 1)
        self.screen.cursor.x = min(self.screen.cursor.x, cols - 1)
        self.set_size(cols, rows)
        os.killpg(self.child.pid, signal.SIGWINCH)

    def send(self, data):
        os.write(self.master, data)

    def pump(self, timeout=0.1):
        ready, _, _ = select.select([self.master], [], [], timeout)
        if ready:
            chunk = os.read(self.master, 65536)
            self.raw.extend(chunk)
            text = self.keyboard_tail + self.decoder.decode(chunk)
            # pyte predates the Kitty keyboard stack and prints a '<1u'
            # suffix instead of ignoring the unknown CSI. Model an ordinary
            # legacy terminal: ignore stack operations and decline '?u'.
            tail = re.search(r'\x1b(?:\[(?:[<>?][0-9;]*)?)?$', text)
            self.keyboard_tail = tail[0] if tail else ''
            if tail:
                text = text[:tail.start()]
            self.stream.feed(re.sub(r'\x1b\[[<>?][0-9;]*u', '', text))

    def wait(self, predicate, label, timeout=20):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            self.pump()
            if predicate():
                return
            if self.child.poll() is not None:
                break
        raise AssertionError(f"{label}\n{self.text()}\n{bytes(self.raw[-1500:])!r}")

    def text(self):
        return "\n".join(self.screen.display)

    def row(self, text):
        return next(i for i, line in enumerate(self.screen.display) if text in line)

    def app_pid(self):
        match = re.search(r"INLINE-READY (\d+)", self.text())
        return int(match[1]) if match else None

    def click(self, row, col=2):
        self.send(f"\x1b[<0;{col+1};{row+1}M\x1b[<0;{col+1};{row+1}m".encode())

    def finish(self, expected=0, *, summary=True):
        self.wait(lambda: self.child.poll() is not None, "process exit")
        for _ in range(3):
            self.pump(0.05)
        assert self.child.returncode == expected, (self.child.returncode, self.text())
        assert b"\x1b[2J" not in self.raw, "cleared the whole main screen"
        assert b"1049" not in self.raw, "switched alternate-screen state"
        assert not re.search(rb"\x1b\[\d*S", self.raw), "scrolled the entire terminal"
        assert b"\x1b[?7h" in self.raw, "autowrap was not restored"
        assert b"\x1b[?1006l" in self.raw, "mouse capture was not released"
        assert b"\x1b[?25h" in self.raw, "cursor was not restored"
        assert b"PTY-MODES-RESTORED" in self.raw, "left the terminal raw"
        assert b"PTY-BLOCKING-RESTORED" in self.raw, "left shared input nonblocking"
        if summary:
            assert "INLINE-DONE" in self.text(), self.text()
            assert "INLINE-READY" not in self.text(), "live region survived cleanup"

    def close(self):
        try:
            os.killpg(self.child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        self.child.wait(timeout=5)
        os.close(self.slave)
        if self.master >= 0:
            os.close(self.master)


def interactions(dart, cols, rows):
    app = Session(dart, cols=cols, rows=rows)
    try:
        app.wait(lambda: "INLINE-READY" in app.text(), "initial inline frame")
        history = "\n".join("".join(line[i].data for i in range(cols))
                            for line in app.screen.history.top) + app.text()
        for n in range(10):
            assert f"SHELL-KEEP-{n}" in history, f"lost shell line {n}"
        app.send(b"hello")
        app.wait(lambda: "value=hello" in app.text(), "text input")
        app.click(app.row("Click me"))
        app.wait(lambda: "clicks=1" in app.text(), "offset mouse click")
        app.send(b"\x07")
        app.wait(lambda: f"{cols}x{min(12, rows)}" in app.text(), "grow region")
        app.send(b"\x13")
        app.wait(lambda: f"{cols}x6" in app.text(), "shrink region")
        app.send(b"\x0f")
        app.wait(lambda: "AFTER-HANDOFF" in app.text(), "subprocess return")
        assert "CHILD-OUTPUT" in app.text(), app.text()
        app.resize(cols - 10, rows)
        app.wait(lambda: f"{cols-10}x6" in app.text(), "narrow resize")
        app.resize(cols, rows - 3)
        app.wait(lambda: f"{cols}x6" in app.text(), "height resize")
        assert "value=hello" in app.text() and "clicks=1" in app.text(), app.text()
        app.send(b"\x11")
        app.finish()
        print(f"PASS inline interactions {cols}x{rows}")
    finally:
        app.close()


def lifecycle(dart, supervised=False, crash=False, abrupt=False):
    app = Session(dart, supervised=supervised)
    try:
        app.wait(lambda: app.app_pid() is not None, "initial lifecycle frame")
        if supervised:
            initial = app.app_pid()
            # The supervisor attaches after the first frame; let its command
            # channel finish negotiating before asking for a restart.
            for _ in range(10):
                app.pump(0.1)
            if crash or abrupt:
                if abrupt:
                    app.send(b'\x05')
                else:
                    os.kill(initial, signal.SIGKILL)
                app.finish(7 if abrupt else 137, summary=False)
                assert "INLINE-READY" not in app.text(), "crashed child region survived"
            else:
                app.send(b"\x12")
                app.wait(lambda: app.app_pid() not in (None, initial), "development restart")
                app.send(b"\x11")
                app.finish()
        else:
            pid = app.app_pid()
            app.send(b"\x1a")
            end = time.monotonic() + 5
            stopped = False
            while time.monotonic() < end:
                app.pump()
                status = subprocess.run(['ps', '-o', 'stat=', '-p', str(pid)],
                                        capture_output=True, text=True).stdout
                if 'T' in status:
                    stopped = True
                    break
            assert stopped, "Ctrl+Z did not suspend"
            assert "INLINE-READY" not in app.text(), "suspend left the live region"
            os.kill(pid, signal.SIGCONT)
            app.wait(lambda: "INLINE-READY" in app.text(), "resume frame")
            app.send(b"\x03")
            app.finish(130)  # Raw Ctrl+C preserves the same outcome as SIGINT.
        print(f"PASS inline lifecycle supervised={supervised} crash={crash} abrupt={abrupt}")
    finally:
        app.close()


def signals(dart):
    for sent, expected in [(signal.SIGINT, 130), (signal.SIGTERM, 143)]:
        app = Session(dart)
        try:
            app.wait(lambda: app.app_pid() is not None, 'ready for signal')
            os.kill(app.app_pid(), sent)
            app.finish(expected)
            print(f'PASS inline cleanup {sent.name}')
        finally:
            app.close()


def resize_exit(dart, *, executable=None):
    """Exit while the resize query is pending, not after a convenient redraw."""
    for cols, rows in [(70, 18), (90, 24)]:
        app = Session(dart, executable=executable)
        try:
            app.wait(lambda: app.app_pid() is not None, 'ready for resize/exit')
            app.hold_replies = True
            start = len(app.raw)
            app.resize(cols, rows)
            app.wait(lambda: b'\x1b[6n' in app.raw[start:], 'pending resize cursor query')
            app.send(b'\x11')
            # Give shutdown the pending query; it cannot finish until we reply.
            until = time.monotonic() + .15
            while time.monotonic() < until:
                app.pump(.02)
            app.hold_replies = False
            for reply in app.held_replies:
                app.send(reply)
            app.held_replies.clear()
            app.finish()
            history = '\n'.join(''.join(cell.data for cell in line.values())
                                for line in app.screen.history.top) + app.text()
            for n in range(10):
                assert f'SHELL-KEEP-{n}' in history, f'lost shell line {n}'
            print(f'PASS exit during pending resize {cols}x{rows}')
        finally:
            app.close()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == '--guard':
        # Keep the controlling session alive long enough to inspect real
        # termios after Dart exits (macOS revokes the slave when its session
        # leader dies). The guardian performs no terminal-mode restoration.
        original = termios.tcgetattr(0)
        original_flags = fcntl.fcntl(0, fcntl.F_GETFL)
        code = subprocess.call(sys.argv[2:])
        final = termios.tcgetattr(0)
        if final == original:
            os.write(1, b'\r\nPTY-TERMIOS-EXACT\r\n')
        if fcntl.fcntl(0, fcntl.F_GETFL) & os.O_NONBLOCK == original_flags & os.O_NONBLOCK:
            os.write(1, b'\r\nPTY-BLOCKING-RESTORED\r\n')
        flags = final[3]
        restored = flags & termios.ICANON and flags & termios.ECHO
        os.write(1, b'\r\nPTY-MODES-RESTORED\r\n' if restored else b'\r\nPTY-MODES-RAW\r\n')
        sys.exit(code if code >= 0 else 128 - code)
    parser = argparse.ArgumentParser()
    parser.add_argument("--dart", default="dart")
    parser.add_argument("--skip-supervisor", action="store_true")
    args = parser.parse_args()
    interactions(args.dart, 80, 18)
    interactions(args.dart, 40, 12)
    lifecycle(args.dart)
    signals(args.dart)
    resize_exit(args.dart)
    if not args.skip_supervisor:
        lifecycle(args.dart, supervised=True)
        lifecycle(args.dart, supervised=True, crash=True)
        lifecycle(args.dart, supervised=True, abrupt=True)
