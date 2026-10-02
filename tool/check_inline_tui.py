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
        self.supervised = supervised
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
        self.guarded = guard
        self.child = subprocess.Popen(
            ([sys.executable, str(Path(__file__).resolve()), '--guard', *command]
             if guard else command),
            cwd=PACKAGE, stdin=self.slave, stdout=self.slave,
            stderr=self.slave, preexec_fn=child_terminal,
            env={**os.environ, "TERM": "xterm-256color", "FLEURY_SYNC_OUTPUT": "0"},
        )

    def set_size(self, cols, rows):
        fcntl.ioctl(self.master, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    def job_groups(self):
        """The process groups running the app. The guard runs its command as
        a job led by the command (run_as_foreground_job), so each child of the
        guard leads one; unguarded, the command is the session leader."""
        if not self.guarded:
            return [self.child.pid]
        children = subprocess.run(['pgrep', '-P', str(self.child.pid)],
                                  capture_output=True, text=True).stdout
        return [int(pid) for pid in children.split()]

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
        for group in self.job_groups():
            os.killpg(group, signal.SIGWINCH)

    def send(self, data):
        os.write(self.master, data)

    def pump(self, timeout=0.1, *, max_bytes=65536):
        ready, _, _ = select.select([self.master], [], [], timeout)
        if ready:
            chunk = os.read(self.master, max_bytes)
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

    def wait(self, predicate, label, timeout=None):
        # A supervised start pays the VM service and a JIT cold start on top of
        # the app's own, which a loaded CI runner can stretch past 20 s.
        if timeout is None:
            timeout = 60 if self.supervised else 20
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
        # The mode sequence, not the bare digits: the app prints its pid, and a
        # pid containing "1049" is not an alternate-screen switch.
        assert not re.search(
            rb"\x1b\[\?[\d;]*1049[\d;]*[hl]", self.raw
        ), "switched alternate-screen state"
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
        # A failed suspend assertion can leave Dart stopped. Resume the app's
        # job, which the guard runs in a process group of its own, then the
        # guard's, so teardown can reap them on macOS as well.
        for group in dict.fromkeys([*self.job_groups(), self.child.pid]):
            try:
                os.killpg(group, signal.SIGCONT)
                os.killpg(group, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
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
        # Answer the narrow resize's cursor query 1.5 s late, as a congested
        # SSH link or a busy terminal does. A fixed one-second deadline ended
        # the app here whenever a loaded runner delayed the emulator's reply;
        # the region must wait for the report, then settle on the new width.
        app.hold_replies = True
        start = len(app.raw)
        app.resize(cols - 10, rows)
        app.wait(lambda: b"\x1b[6n" in app.raw[start:], "narrow resize cursor query")
        until = time.monotonic() + 1.5
        while time.monotonic() < until:
            app.pump(0.05)
        app.hold_replies = False
        for reply in app.held_replies:
            app.send(reply)
        app.held_replies.clear()
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
            # The guard stands where an interactive shell would: it runs the
            # app as a job and keeps running while the job is stopped.
            suspend_and_resume(app, [pid])
            app.send(b"\x03")
            app.finish(130)  # Raw Ctrl+C preserves the same outcome as SIGINT.
        print(f"PASS inline lifecycle supervised={supervised} crash={crash} abrupt={abrupt}")
    finally:
        app.close()


def supervised_suspend(dart):
    """Ctrl+Z under the hot-reload supervisor stops the whole job.

    The supervisor is the app's parent and shares its process group. Stopping
    the app alone left the supervisor running in the foreground, so a shell
    never got its prompt back.
    """
    app = Session(dart, supervised=True)
    try:
        app.wait(lambda: app.app_pid() is not None, "initial supervised frame")
        pid = app.app_pid()
        supervisor = int(subprocess.run(['ps', '-o', 'ppid=', '-p', str(pid)],
                                        capture_output=True, text=True).stdout)
        # The supervisor attaches after the first frame; let it finish before
        # the job stops, as the restart case does.
        for _ in range(10):
            app.pump(0.1)
        suspend_and_resume(app, [pid, supervisor])
        assert app.app_pid() == pid, "the supervisor replaced the stopped app"
        app.send(b"\x11")
        app.finish()
        print("PASS inline supervised suspend")
    finally:
        app.close()


def session_processes(app):
    """The processes in the PTY's session, with their groups, the terminal's
    foreground group, and their states."""
    sid = os.getsid(app.child.pid)
    rows = subprocess.run(['ps', '-eo', 'pid,ppid,pgid,sid,tpgid,stat,args'],
                          capture_output=True, text=True).stdout.splitlines()
    return "\n".join(rows[:1] + [row for row in rows[1:]
                                  if row.split()[3] == str(sid)])


def kernel_view(pids):
    """Linux: each process's signal state and the syscall each of its threads
    is stopped in, to tell the driver's own stop from a terminal stop."""
    lines = []
    for pid in pids:
        try:
            status = Path(f"/proc/{pid}/status").read_text().splitlines()
            keep = [l for l in status
                    if l.split(":")[0] in ("State", "SigPnd", "ShdPnd", "SigBlk", "SigIgn", "SigCgt")]
            lines.append(f"{pid}: " + " | ".join(keep))
            for task in sorted(Path(f"/proc/{pid}/task").iterdir()):
                comm = (task / "comm").read_text().strip()
                call = (task / "syscall").read_text().split()[:3]
                lines.append(f"  {task.name} {comm}: syscall {call}")
        except OSError as error:
            lines.append(f"{pid}: {error}")
    return "\n".join(lines)


def termios_diff(expected, actual):
    """Names each termios field that differs, with the bits that changed."""
    names = ["iflag", "oflag", "cflag", "lflag", "ispeed", "ospeed"]
    changes = [
        f"{name} {want:#x} -> {got:#x} (bits {want ^ got:#x})"
        for name, want, got in zip(names, expected, actual)
        if want != got
    ]
    changes += [
        f"cc[{i}] {want!r} -> {got!r}"
        for i, (want, got) in enumerate(zip(expected[6], actual[6]))
        if want != got
    ]
    return "; ".join(changes)


def suspend_and_resume(app, job):
    """Presses Ctrl+Z, checks that every process in [job] stopped and that
    the terminal is the shell's again, then continues the job as `fg` does.
    Fleury suspends only a job a job-control shell started; the guard runs
    the app as one (see run_as_foreground_job)."""
    # Ctrl+Z reaches the app first, and the autofocused field would take it as
    # undo. Focus the button, which leaves the chord unhandled, so it becomes
    # the terminal's job control.
    app.click(app.row("Click me"))
    app.wait(lambda: "clicks=1" in app.text(), "focus the button")
    app.send(b"\x1a")
    end = time.monotonic() + 5
    states = []
    while time.monotonic() < end:
        # Deliberately fragment reads: stopping is not evidence that the
        # emulator has consumed every preceding terminal write.
        app.pump(max_bytes=8)
        states = [subprocess.run(['ps', '-o', 'stat=', '-p', str(pid)],
                                 capture_output=True, text=True).stdout.strip()
                  for pid in job]
        if all('T' in state for state in states):
            break
    assert all('T' in state for state in states), \
        f"Ctrl+Z did not suspend the job: {dict(zip(job, states))}"
    # The stopped app has flushed its cleanup output, but that output may
    # still be queued on the PTY. Drain it before inspecting the screen; no
    # sleep or relaxed screen assertion is needed.
    while select.select([app.master], [], [], 0)[0]:
        app.pump(0, max_bytes=8)
    assert "INLINE-READY" not in app.text(), "suspend left the live region"
    restored_modes = termios.tcgetattr(app.slave)
    expected_modes = app.original_modes.copy()
    # macOS may set PENDIN when canonical input resumes. It describes pending
    # input retyping, not a mode configured by the app.
    pending_input = getattr(termios, "PENDIN", 0)
    restored_modes[3] &= ~pending_input
    expected_modes[3] &= ~pending_input
    assert restored_modes == expected_modes, (
        f"suspend left terminal modes changed: "
        f"{termios_diff(expected_modes, restored_modes)}\n"
        f"processes:\n{session_processes(app)}\n"
        f"kernel view:\n{kernel_view(job)}\n"
        f"output tail: {bytes(app.raw[-600:])!r}")
    # fg continues the job's whole process group, not only the app.
    os.killpg(os.getpgid(job[0]), signal.SIGCONT)
    app.wait(lambda: "INLINE-READY" in app.text(), "resume frame")


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


def run_as_foreground_job(command):
    """Runs [command] the way an interactive shell runs a job, and returns its
    exit code: in a process group of its own that owns the terminal's
    foreground. Fleury suspends on Ctrl+Z only for such a job. The session
    leader's own group, where a command started with no shell runs, has
    nothing above it to continue a stopped app."""
    # A background group's tcsetpgrp raises SIGTTOU; shells ignore it.
    signal.signal(signal.SIGTTOU, signal.SIG_IGN)

    def become_foreground_job():
        os.setpgid(0, 0)
        os.tcsetpgrp(0, os.getpgrp())
        signal.signal(signal.SIGTTOU, signal.SIG_DFL)

    job = subprocess.Popen(command, preexec_fn=become_foreground_job)
    code = job.wait()
    os.tcsetpgrp(0, os.getpgrp())
    return code


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == '--guard':
        # Keep the controlling session alive long enough to inspect real
        # termios after Dart exits (macOS revokes the slave when its session
        # leader dies). The guardian performs no terminal-mode restoration.
        original = termios.tcgetattr(0)
        original_flags = fcntl.fcntl(0, fcntl.F_GETFL)
        code = run_as_foreground_job(sys.argv[2:])
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
        supervised_suspend(args.dart)
        lifecycle(args.dart, supervised=True)
        lifecycle(args.dart, supervised=True, crash=True)
        lifecycle(args.dart, supervised=True, abrupt=True)
