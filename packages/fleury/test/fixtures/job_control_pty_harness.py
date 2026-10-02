"""Suspends a Fleury app running as a job of an interactive shell.

A real `bash -i` owns a pseudo-terminal as its controlling terminal, so job
control is the one a user has: the shell starts the command in a process group
of its own, gives that group the terminal, and gets the terminal back only when
the job stops or ends. The harness types the command, waits for the app's first
frame, presses the key that suspends it, and records whether the shell got its
prompt back and ran a command — the observable meaning of "suspended" — then
brings the job back with `fg` and quits the app with Ctrl+Q.

usage: job_control_pty_harness.py <work-dir> [--supervised] [--suspend-key]
           [--no-shell | --launcher | --orphaned | --login-exec=<shell>]
           -- <command...>

--supervised waits for the hot-reload supervisor to wire the app before
suspending it. --suspend-key drives the fixture's composer
(test/fixtures/job_control_fixture.dart --suspend-key) instead of pressing an
unhandled Ctrl+Z: Ctrl+Z must undo in its focused field and leave the job
running, and Ctrl+T, its suspend key, must suspend. --no-shell runs the command
with no shell at all, the way a terminal emulator, a tmux pane, or `ssh -t host
app` does: the command is the session leader and the PTY's controlling
process, so nothing could continue it if it stopped. --launcher runs it under
a launcher that is no shell but gives it a foreground process group of its own,
as tini does under `docker run --init`. --orphaned has the launcher that gave
it that group exit at once, leaving the command to pid 1. --login-exec=<shell>
has a `login` stand-in run an interactive <shell>, which `exec`s the command:
fish and tcsh keep the process group they made for themselves, so the command
leads a foreground group of its own with no shell above it. In these the harness
presses Ctrl+Z and Ctrl+T and records whether each reached the app and whether
the terminal and the processes were left alone. The app must be that fixture
(or honour its FLEURY_JOB_PID_OUT and FLEURY_JOB_EVENTS_OUT contract).
Writes <work-dir>/report.json (the facts; `failure` names the step that could
not complete) and <work-dir>/pty.bin (every byte the terminal received). Exits
0 whenever a report was written; the Dart test asserts.
"""

import fcntl
import json
import os
import re
import select
import shlex
import shutil
import signal
import struct
import subprocess
import sys
import termios
import time

PROMPT = b'FLEURY-JOB-PROMPT$ '

CTRL_Z = b'\x1a'
CTRL_T = b'\x14'
CTRL_Q = b'\x11'

# Written only when a session leaves the terminal for the shell (or exits):
# mouse reporting off, and the alternate screen left.
RESTORE_MARKERS = (b'\x1b[?1000l', b'\x1b[?1049l')


class StepFailed(Exception):
    pass


class Harness:
    def __init__(self, work_dir, supervised, suspend_key, command):
        self.work_dir = work_dir
        self.supervised = supervised
        self.suspend_key = suspend_key
        self.command = command
        self.pid_file = os.path.join(work_dir, 'app.pid')
        self.events_file = os.path.join(work_dir, 'app-events.log')
        self.bootstrap_log = os.path.join(work_dir, 'bootstrap.log')
        self.output = bytearray()
        self.trace = []
        self.offsets = {}
        self.report = {'command': command, 'trace': self.trace,
                       'offsets': self.offsets}
        self.master = None
        # The process the harness forks as the PTY's session leader: bash, or
        # with --no-shell the command itself.
        self.leader_pid = None
        self.leader_status = None

    def note(self, event):
        self.trace.append(event)

    # -- the terminal and its session leader ----------------------------

    def start_session(self, path, argv, extra_env, leader=None):
        """Forks [argv] as the session leader of a new PTY, with the PTY as its
        controlling terminal. With [leader], the session leader is that
        function instead, run in the forked process with ([argv], env); it
        returns the leader's exit status."""
        master, slave = os.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith('FLEURY_')
            and key not in ('TMUX', 'STY', 'PROMPT_COMMAND', 'ENV', 'BASH_ENV')
        }
        env.update({
            'TERM': 'xterm-256color',
            'FLEURY_JOB_PID_OUT': self.pid_file,
            'FLEURY_JOB_EVENTS_OUT': self.events_file,
            'FLEURY_DEV_BOOTSTRAP_LOG': self.bootstrap_log,
            **extra_env,
        })
        pid = os.fork()
        if pid == 0:
            try:
                os.close(master)
                os.setsid()
                fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
                for fd in (0, 1, 2):
                    os.dup2(slave, fd)
                if slave > 2:
                    os.close(slave)
                os.chdir(self.work_dir)
                if leader is not None:
                    os._exit(leader(argv, env))
                os.execve(path, argv, env)
            finally:
                os._exit(127)
        os.close(slave)
        self.master = master
        self.leader_pid = pid

    def start_shell(self):
        self.start_session('/bin/bash', ['bash', '--norc', '--noprofile', '-i'], {
            'PS1': PROMPT.decode(),
            'BASH_SILENCE_DEPRECATION_WARNING': '1',
            'HISTFILE': '/dev/null',
        })
        self.note('shell started')

    def pump(self, timeout):
        ready, _, _ = select.select([self.master], [], [], timeout)
        if not ready:
            return False
        try:
            chunk = os.read(self.master, 65536)
        except OSError:
            return False
        if not chunk:
            return False
        self.output.extend(chunk)
        return True

    def send(self, data):
        os.write(self.master, data)

    def wait_for(self, predicate, what, timeout):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            self.pump(0.05)
            if self.leader_status is None:
                reaped, status = os.waitpid(self.leader_pid, os.WNOHANG)
                if reaped:
                    self.leader_status = status
        if predicate():
            return
        raise StepFailed(what)

    def settle(self, seconds):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            self.pump(0.05)

    def output_after(self, offset):
        return bytes(self.output[offset:])

    def run_in_shell(self, line):
        self.send(line.encode() + b'\r')

    # -- processes ------------------------------------------------------

    def app_pid(self):
        try:
            with open(self.pid_file) as f:
                text = f.read().strip()
            return int(text) if text else None
        except (OSError, ValueError):
            return None

    def app_events(self):
        try:
            with open(self.events_file) as f:
                return f.read().splitlines()
        except OSError:
            return []

    def field_text(self):
        """The composer's text as its last change left it, or None."""
        fields = [e for e in self.app_events() if e.startswith('field:')]
        return fields[-1][len('field:'):] if fields else None

    def suspend_results(self):
        return [e[len('suspended:'):] for e in self.app_events()
                if e.startswith('suspended:')]

    @staticmethod
    def ps(pid, field):
        result = subprocess.run(['ps', '-o', f'{field}=', '-p', str(pid)],
                                capture_output=True, text=True)
        return result.stdout.strip() or None

    def process_facts(self, pid):
        return {
            'pid': pid,
            'ppid': int(self.ps(pid, 'ppid') or 0),
            'pgid': int(self.ps(pid, 'pgid') or 0),
            'tpgid': int(self.ps(pid, 'tpgid') or 0),
            'stat': self.ps(pid, 'stat'),
        }

    def wait_for_app(self, start):
        self.wait_for(lambda: self.app_pid() is not None, 'app started', 120)
        self.wait_for(lambda: b'JOB-READY' in self.output_after(start),
                      'first frame', 60)
        if self.supervised:
            self.wait_for(
                lambda: os.path.exists(self.bootstrap_log) and
                'child ready' in open(self.bootstrap_log).read(),
                'supervisor wired to the app', 60)
        return self.app_pid()

    # -- the scenario: a job of an interactive shell --------------------

    def run(self):
        self.start_shell()
        self.wait_for(lambda: PROMPT in self.output, 'first prompt', 20)

        start = len(self.output)
        self.run_in_shell(' '.join(shlex.quote(part) for part in self.command))
        app = self.wait_for_app(start)
        facts = self.process_facts(app)
        self.report['app'] = facts
        parent = facts['ppid']
        self.report['parent'] = self.process_facts(parent)
        self.report['shellPid'] = self.leader_pid
        self.note('app running')

        if self.suspend_key:
            # The focused field takes Ctrl+Z: it undoes, and the job runs on.
            self.report['undoBeforeSuspend'] = self.ctrl_z_undoes('x', app)
            suspend = CTRL_T
        else:
            suspend = CTRL_Z

        # The app hands the terminal back and stops.
        start = self.offsets['suspend'] = len(self.output)
        self.send(suspend)
        try:
            self.wait_for(lambda: PROMPT in self.output_after(start),
                          'the shell prompt after the suspend key', 15)
            self.report['promptAfterSuspend'] = True
        except StepFailed:
            self.report['promptAfterSuspend'] = False
            self.report['whileStopped'] = {
                'app': self.ps(app, 'stat'),
                'parent': self.ps(parent, 'stat'),
            }
            raise
        self.report['whileStopped'] = {
            'app': self.ps(app, 'stat'),
            'parent': self.ps(parent, 'stat'),
        }
        self.report['stoppedNotice'] = b'Stopped' in self.output_after(start)
        # A stopped process records nothing: the request has not completed.
        self.report['suspendResultsWhileStopped'] = self.suspend_results()
        self.note('prompt returned')

        # The shell owns the terminal again: a command runs.
        start = len(self.output)
        self.run_in_shell('echo SHELL-ALIVE-$((6*7))')
        self.wait_for(lambda: b'SHELL-ALIVE-42' in self.output_after(start),
                      'a command while the app is stopped', 15)
        self.report['shellRanCommand'] = True

        # fg: the job continues, and the app re-enters and repaints.
        start = self.offsets['fg'] = len(self.output)
        self.run_in_shell('fg')
        self.wait_for(lambda: b'JOB-READY' in self.output_after(start),
                      'the repaint after fg', 30)
        self.report['resumedAfterFg'] = True
        self.report['afterFg'] = {
            'app': self.ps(app, 'stat'),
            'parent': self.ps(parent, 'stat'),
            # A supervisor that took the stop for an exit would have respawned
            # the app, and the new process would have written its own pid.
            'appPid': self.app_pid(),
        }
        self.note('resumed')

        if self.suspend_key:
            self.wait_for(lambda: self.suspend_results(),
                          'the suspend request to complete after fg', 15)
            self.report['suspendResults'] = self.suspend_results()
            # The same field still has focus and still undoes.
            self.report['undoAfterFg'] = self.ctrl_z_undoes('y', app)

        # Ctrl+Q ends the app; the shell reports the job's exit status.
        start = self.offsets['quit'] = len(self.output)
        self.send(CTRL_Q)
        self.wait_for(lambda: PROMPT in self.output_after(start),
                      'the prompt after the app exits', 30)
        start = len(self.output)
        self.run_in_shell('echo JOB-EXIT-$?-END')
        status = re.compile(rb'JOB-EXIT-(\d+)-END')
        self.wait_for(lambda: status.search(self.output_after(start)),
                      'the job exit status', 15)
        self.report['jobExit'] = int(
            status.search(self.output_after(start)).group(1))
        self.run_in_shell('exit')
        self.wait_for(lambda: self.leader_status is not None, 'shell exit', 15)
        self.note('done')

    def ctrl_z_undoes(self, text, app):
        """Types [text] into the composer, presses Ctrl+Z, and records what
        the field and the job did."""
        self.send(text.encode())
        self.wait_for(lambda: self.field_text() == text,
                      f'the field to show {text!r}', 15)
        start = len(self.output)
        self.send(CTRL_Z)
        self.wait_for(lambda: self.field_text() == '',
                      f'Ctrl+Z to undo {text!r}', 15)
        # A suspension would have stopped the job by now and printed a prompt.
        self.settle(0.5)
        return {
            'undone': self.field_text() == '',
            'appState': self.ps(app, 'stat'),
            'prompt': PROMPT in self.output_after(start),
        }

    # -- the scenarios: no job-control shell ----------------------------

    def run_without_shell(self):
        path = self.command[0]
        self.start_session(path, self.command, {})
        self.note('command started as the session leader')
        self.expect_no_suspension(self.wait_for_app(0))

    def run_under_launcher(self):
        """The command runs under a launcher that is no shell (plain_launcher),
        in a process group of its own that owns the terminal."""
        self.start_session(self.command[0], self.command, {},
                           leader=plain_launcher)
        self.note('command started by a plain launcher')
        self.expect_no_suspension(self.wait_for_app(0))

    def run_orphaned(self):
        """The command leads a foreground process group whose creator has
        exited, leaving it to pid 1 (orphaning_launcher)."""
        self.start_session(self.command[0], self.command, {},
                           leader=orphaning_launcher)
        self.note('command orphaned by its launcher')
        self.expect_no_suspension(self.wait_for_app(0))

    def run_exec_under_login(self, shell):
        """A `login` stand-in (login_standin) runs an interactive [shell], and
        the shell `exec`s the command."""
        argv = [shutil.which(shell), *INTERACTIVE_FLAGS[shell]]
        self.start_session(argv[0], argv, {'HISTFILE': '/dev/null'},
                           leader=login_standin)
        self.note(f'{shell} started by login')
        start = len(self.output)
        # The typed line holds RE%sY; only the shell's output holds READY.
        self.send(b"printf 'RE%sY\\n' AD\r")
        self.wait_for(lambda: b'READY' in self.output_after(start),
                      f'{shell} to run a command', 30)
        start = len(self.output)
        self.run_in_shell('exec ' + ' '.join(shlex.quote(part)
                                             for part in self.command))
        self.expect_no_suspension(self.wait_for_app(start))

    def expect_no_suspension(self, app):
        """Nothing could continue a stopped [app]: records its facts, presses
        Ctrl+Z and the fixture's suspend key, and quits it with Ctrl+Q."""
        self.report['app'] = self.process_facts(app)
        self.report['leader'] = self.process_facts(self.leader_pid)
        self.report['leaderPid'] = self.leader_pid
        self.report['supportsSuspend'] = [
            e[len('supportsSuspend:'):] for e in self.app_events()
            if e.startswith('supportsSuspend:')]
        self.note('app running')

        # Nothing could continue a stopped app: Ctrl+Z reaches it as an
        # ordinary key, and its own suspend key's request completes with false.
        self.report['ctrlZ'] = self.press_without_suspending(
            CTRL_Z, 'key:ctrl+z', app)
        self.report['suspendKey'] = self.press_without_suspending(
            CTRL_T, 'suspended:', app)

        # The app still answers: Ctrl+Q ends it, and the session with it.
        start = self.offsets['quit'] = len(self.output)
        self.send(CTRL_Q)
        self.wait_for(lambda: self.leader_status is not None,
                      'the app to exit on Ctrl+Q', 30)
        self.settle(0.2)
        self.report['exit'] = os.waitstatus_to_exitcode(self.leader_status)
        self.report['restoredOnExit'] = all(
            marker in self.output_after(start) for marker in RESTORE_MARKERS)
        self.note('done')

    def press_without_suspending(self, key, expected, app):
        """Presses [key] and waits for an app event starting with [expected];
        records the app's events since the press, the processes' states, and
        whether anything restored the terminal for a shell."""
        before = len(self.app_events())
        start = len(self.output)

        def facts():
            return {
                'events': self.app_events()[before:],
                'appState': self.ps(app, 'stat'),
                'leaderState': self.ps(self.leader_pid, 'stat'),
                'terminalReleased': any(marker in self.output_after(start)
                                        for marker in RESTORE_MARKERS),
            }

        self.send(key)
        try:
            self.wait_for(
                lambda: any(e.startswith(expected)
                            for e in self.app_events()[before:]),
                f'{expected!r} after the key', 15)
        except StepFailed:
            self.report['stuck'] = facts()
            raise
        # A suspension would have released the terminal and stopped by now.
        self.settle(0.5)
        return facts()

    def cleanup(self):
        # A failed step can leave the job stopped: continue its whole group so
        # it can take the kill, then end the session leader.
        app = self.app_pid()
        if app is not None:
            try:
                pgid = os.getpgid(app)
                os.killpg(pgid, signal.SIGCONT)
                os.killpg(pgid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
        if self.leader_pid is not None and self.leader_status is None:
            try:
                os.kill(self.leader_pid, signal.SIGCONT)
                os.kill(self.leader_pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            # Keep reading the terminal while the leader exits: on macOS an
            # exiting process can wait for the terminal's output to drain.
            try:
                self.wait_for(lambda: self.leader_status is not None,
                              'the session leader to exit', 15)
            except StepFailed:
                self.report.setdefault('failure', 'the session leader never exited')
        if self.master is not None:
            os.close(self.master)


# How each shell runs interactively without the user's configuration, for
# run_exec_under_login.
INTERACTIVE_FLAGS = {
    'bash': ['--norc', '--noprofile', '-i'],
    'zsh': ['-f', '-i'],
    'fish': ['--no-config', '-i'],
    'tcsh': ['-f', '-i'],
    'dash': ['-i'],
}


def _status_code(status):
    code = os.waitstatus_to_exitcode(status)
    return code if code >= 0 else 128 - code


def plain_launcher(argv, env):
    """A launcher that is no shell, as tini is under `docker run --init`: it
    starts the command in a process group of its own, gives that group the
    terminal, and waits for it. SIGTSTP keeps its default, which would stop
    the launcher itself, and nothing continues a stopped job."""
    signal.signal(signal.SIGTTOU, signal.SIG_IGN)
    child = os.fork()
    if child == 0:
        try:
            os.setpgid(0, 0)
            os.tcsetpgrp(0, os.getpgrp())
            signal.signal(signal.SIGTTOU, signal.SIG_DFL)
            os.execvpe(argv[0], argv, env)
        finally:
            os._exit(127)
    _, status = os.waitpid(child, 0)
    return _status_code(status)


def login_standin(argv, env):
    """What macOS's `login` does for a terminal tab: runs the user's shell as
    its child and waits for it, with no job control of its own (SIGTSTP keeps
    its default)."""
    child = os.fork()
    if child == 0:
        try:
            os.execvpe(argv[0], argv, env)
        finally:
            os._exit(127)
    _, status = os.waitpid(child, 0)
    return _status_code(status)


def orphaning_launcher(argv, env):
    """A session leader whose child gives the command a foreground process
    group of its own and exits at once, as a shell killed out from under its
    job does. The command is left to pid 1, launchd on macOS, which ignores
    SIGTSTP but continues nothing. The leader stays, as `login` would, until
    the command ends."""
    signal.signal(signal.SIGTTOU, signal.SIG_IGN)
    read_end, write_end = os.pipe()
    creator = os.fork()
    if creator == 0:
        try:
            os.close(read_end)
            job = os.fork()
            if job == 0:
                os.close(write_end)
                os.setpgid(0, 0)
                os.tcsetpgrp(0, os.getpgrp())
                signal.signal(signal.SIGTTOU, signal.SIG_DFL)
                os.execvpe(argv[0], argv, env)
            os.write(write_end, str(job).encode())
        finally:
            os._exit(0)
    os.close(write_end)
    job = int(os.read(read_end, 32) or b'0')
    os.waitpid(creator, 0)
    while job:
        try:
            os.kill(job, 0)
        except ProcessLookupError:
            break
        time.sleep(0.05)
    return 0


def main():
    args = sys.argv[1:]
    if '--' not in args or args.index('--') < 1 or args[-1] == '--':
        print(__doc__, file=sys.stderr)
        return 2
    split = args.index('--')
    work_dir, options, command = args[0], set(args[1:split]), args[split + 1:]
    login_exec = next((option.split('=', 1)[1] for option in options
                       if option.startswith('--login-exec=')), None)
    unknown = {option for option in options
               if not option.startswith('--login-exec=')} - {
        '--supervised', '--suspend-key', '--no-shell', '--launcher', '--orphaned'}
    if unknown or (login_exec and login_exec not in INTERACTIVE_FLAGS):
        print(f'unknown options: {sorted(options)}\n{__doc__}', file=sys.stderr)
        return 2
    harness = Harness(work_dir, '--supervised' in options,
                      '--suspend-key' in options, command)
    try:
        if '--no-shell' in options:
            harness.run_without_shell()
        elif '--launcher' in options:
            harness.run_under_launcher()
        elif '--orphaned' in options:
            harness.run_orphaned()
        elif login_exec:
            harness.run_exec_under_login(login_exec)
        else:
            harness.run()
    except StepFailed as failure:
        harness.report['failure'] = str(failure)
    finally:
        harness.cleanup()
        with open(os.path.join(work_dir, 'pty.bin'), 'wb') as f:
            f.write(harness.output)
        with open(os.path.join(work_dir, 'report.json'), 'w') as f:
            json.dump(harness.report, f, indent=2)
    return 0


if __name__ == '__main__':
    sys.exit(main())
