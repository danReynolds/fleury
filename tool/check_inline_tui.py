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

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "packages/fleury"
# What Session.fg sends the guard (run_as_foreground_job) for `fg`.
GUARD_FG = signal.SIGUSR1


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
        # Only the harness emulates a terminal; the guard process imports
        # this module without the emulator.
        import pyte
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

    def foreground_group(self):
        """The terminal's foreground process group, as ps reports it. Only a
        process in the PTY's session may ask the terminal itself."""
        out = subprocess.run(['ps', '-o', 'tpgid=', '-p', str(self.child.pid)],
                             capture_output=True, text=True).stdout.strip()
        return int(out) if out else None

    def fg(self):
        """`fg`: asks the guard to give its stopped job the terminal again and
        continue it (see run_as_foreground_job). The guard leads the PTY's
        session; this process is outside it and cannot give the terminal to
        anyone."""
        os.kill(self.child.pid, GUARD_FG)

    def resize(self, cols, rows):
        # Commit old-size output before changing the emulator's geometry.
        while self.pump(0):
            pass
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
        """Feeds what the terminal receives within [timeout] to the emulator.
        Returns whether anything arrived: false at end of file, which a macOS
        PTY reads at once from the moment its session leader exits."""
        ready, _, _ = select.select([self.master], [], [], timeout)
        if not ready:
            return False
        chunk = os.read(self.master, max_bytes)
        if not chunk:
            return False
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
        return True

    def wait(self, predicate, label, timeout=None):
        # A supervised start pays the VM service and a JIT cold start on top of
        # the app's own, which a loaded CI runner can stretch past 20 s.
        if timeout is None:
            timeout = 60 if self.supervised else 20
        start = time.monotonic()
        while True:
            self.pump()
            # Read the guard's exit before the predicate, so a predicate on
            # that exit, or on what the guard wrote last, sees everything up
            # to it. Checked after the predicate, an exit landing between the
            # two failed the wait as a timeout: a session leader's exit
            # revokes a macOS terminal, the PTY then reads end of file at
            # once, and this loop spun through the exit until one did.
            exited = self.child.poll() is not None
            if exited:
                # Nothing more arrives once the guard is gone; take the rest.
                while self.pump(0):
                    pass
            if predicate():
                return
            if exited or time.monotonic() - start >= timeout:
                break
        raise AssertionError(
            f"{label} (gave up after {time.monotonic() - start:.1f} s "
            f"of {timeout} s)\n{self.text()}\n{bytes(self.raw[-1500:])!r}\n"
            f"guard exit status: {self.child.poll()}\n"
            f"processes:\n{session_processes(self)}")

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
        # A failed assertion can leave the app's job stopped, with the guard
        # holding the terminal while it waits for `fg`. SIGKILL ends a stopped
        # process as well, so end the job's process group (the guard notices,
        # as a shell notices a stopped job killed from elsewhere), then the
        # guard's own, without continuing anything into a terminal it no
        # longer owns.
        for group in dict.fromkeys([*self.job_groups(), self.child.pid]):
            try:
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
    """The processes on the PTY or descended from its session leader, with
    their groups, the terminal's foreground group, their states, and what
    each is waiting in (WCHAN). macOS's ps has no session id, so this goes by
    terminal and ancestry."""
    try:
        tty = os.ttyname(app.slave).removeprefix('/dev/')
    except OSError:
        tty = None
    rows = subprocess.run(['ps', '-A', '-o', 'pid,ppid,pgid,tpgid,stat,wchan,tty,command'],
                          capture_output=True, text=True).stdout.splitlines()
    parents = {}
    for row in rows[1:]:
        fields = row.split()
        parents[fields[0]] = fields[1]
    tree = {str(app.child.pid)}
    for _ in range(8):
        tree |= {pid for pid, parent in parents.items() if parent in tree}
    return "\n".join(rows[:1] + [row for row in rows[1:]
                                  if row.split()[0] in tree or row.split()[6] == tty])


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
    the terminal is the shell's again, with exactly the modes it had before
    the app started, then has the guard `fg` the job. Fleury suspends only a
    job a job-control shell started; the guard runs the app as one (see
    run_as_foreground_job)."""
    # Ctrl+Z reaches the app first, and the autofocused field would take it as
    # undo. Focus the button, which leaves the chord unhandled, so it becomes
    # the terminal's job control.
    app.click(app.row("Click me"))
    app.wait(lambda: "clicks=1" in app.text(), "focus the button")
    start = len(app.raw)
    app.send(b"\x1a")
    end = time.monotonic() + 5
    states = []
    foreground = None
    while time.monotonic() < end:
        # Deliberately fragment reads: stopping is not evidence that the
        # emulator has consumed every preceding terminal write.
        app.pump(max_bytes=8)
        states = [subprocess.run(['ps', '-o', 'stat=', '-p', str(pid)],
                                 capture_output=True, text=True).stdout.strip()
                  for pid in job]
        foreground = app.foreground_group()
        if all('T' in state for state in states) and foreground == app.child.pid:
            break
    assert all('T' in state for state in states), \
        f"Ctrl+Z did not suspend the job: {dict(zip(job, states))}"
    # The guard, like a shell, took the terminal back when the job stopped.
    assert foreground == app.child.pid, (
        f"the guard did not get the terminal back: foreground group "
        f"{foreground}\nprocesses:\n{session_processes(app)}")
    # The stopped app has flushed its cleanup output, but that output may
    # still be queued on the PTY. Drain it before inspecting the screen; no
    # sleep or relaxed screen assertion is needed.
    while app.pump(0, max_bytes=8):
        pass
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
    # Nor did it write anything after restoring them: the exit sequences show
    # the cursor, and every enter sequence hides it again.
    suspended = bytes(app.raw[start:])
    shown = suspended.rfind(b"\x1b[?25h")
    assert shown >= 0 and b"\x1b[?25l" not in suspended[shown:], (
        f"the app re-entered its modes before it stopped: "
        f"{suspended[max(0, shown - 200):]!r}\n"
        f"processes:\n{session_processes(app)}\n"
        f"kernel view:\n{kernel_view(job)}")
    # fg gives the job the terminal again and continues its whole process
    # group, not only the app.
    group = os.getpgid(job[0])
    app.fg()
    app.wait(lambda: "INLINE-READY" in app.text(), "resume frame")
    assert app.foreground_group() == group, "fg did not give the job the terminal"


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
    """Runs [command] as an interactive job-control shell runs a job, and
    returns its exit code (negative for a signal, as Popen reports one).

    It does what `bash -i` does with a job:
    - it ignores SIGTSTP, SIGTTIN and SIGTTOU, so job control never stops it
      and it can take the terminal back from the background;
    - it starts the job in a process group of its own and gives that group
      the terminal's foreground;
    - it waits with WUNTRACED, and when the job stops it takes the terminal
      back (tcsetpgrp to its own group). Unlike a shell, it leaves the
      terminal's modes as the job left them, so the harness inspects exactly
      what the app left;
    - on `fg` (GUARD_FG from the harness, which is outside this session and
      cannot give the job the terminal itself; see Session.fg) it gives the
      job the terminal again and continues its whole process group;
    - when the job ends, it takes the terminal back.

    Fleury suspends on Ctrl+Z only for a job a job-control shell started: the
    job's own process group, in the terminal's foreground, made by a process
    that ignores or catches SIGTSTP, as every interactive shell does. That is
    why this guard has to ignore it: a launcher that leaves SIGTSTP at its
    default is no shell, and Fleury no longer suspends under one. The session
    leader's own group, where a command started with no shell runs, has
    nothing above it to continue a stopped app."""
    terminal = 0
    shell_group = os.getpgrp()
    job_control = (signal.SIGTSTP, signal.SIGTTIN, signal.SIGTTOU)
    for sig in job_control:
        signal.signal(sig, signal.SIG_IGN)
    fg_requested = False

    def request_fg(signum, frame):
        nonlocal fg_requested
        fg_requested = True

    signal.signal(GUARD_FG, request_fg)
    job = os.fork()
    if job == 0:
        try:
            os.setpgid(0, 0)
            os.tcsetpgrp(terminal, os.getpgrp())
            # Ignored signals stay ignored across exec; the job gets the
            # defaults, as a shell's jobs do.
            for sig in (*job_control, GUARD_FG):
                signal.signal(sig, signal.SIG_DFL)
            os.execvp(command[0], command)
        except BaseException as error:
            os.write(2, f'guard: cannot run {command[0]}: {error}\r\n'.encode())
        finally:
            os._exit(127)
    # As a shell does, from both sides, so the job leads its own foreground
    # group before either process goes on, whichever runs first.
    try:
        os.setpgid(job, job)
        os.tcsetpgrp(terminal, job)
    except OSError:
        pass  # The job has already exec'd (EACCES) or exited.
    while True:
        _, status = os.waitpid(job, os.WUNTRACED)
        if not os.WIFSTOPPED(status):
            break
        # The job stopped: the shell gets its terminal back, its modes
        # untouched.
        os.tcsetpgrp(terminal, shell_group)
        ended = False
        while not fg_requested:
            # A stopped job can still be killed from elsewhere.
            done, status = os.waitpid(job, os.WNOHANG)
            if done:
                ended = True
                break
            time.sleep(0.01)
        if ended:
            break
        fg_requested = False
        os.tcsetpgrp(terminal, job)
        os.killpg(job, signal.SIGCONT)
    os.tcsetpgrp(terminal, shell_group)
    return os.waitstatus_to_exitcode(status)


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
