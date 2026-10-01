"""Suspends a Fleury app running as a job of an interactive shell.

A real `bash -i` owns a pseudo-terminal as its controlling terminal, so job
control is the one a user has: the shell starts the command in a process group
of its own, gives that group the terminal, and gets the terminal back only when
the job stops or ends. The harness types the command, waits for the app's first
frame, presses the key that suspends it, and records whether the shell got its
prompt back and ran a command — the observable meaning of "suspended" — then
brings the job back with `fg` and quits the app with Ctrl+Q.

usage: job_control_pty_harness.py <work-dir> [--supervised] [--suspend-key]
           -- <command...>

--supervised waits for the hot-reload supervisor to wire the app before
suspending it. --suspend-key drives the fixture's composer
(test/fixtures/job_control_fixture.dart --suspend-key) instead of pressing an
unhandled Ctrl+Z: Ctrl+Z must undo in its focused field and leave the job
running, and Ctrl+T, its suspend key, must suspend. The app must be that
fixture (or honour its FLEURY_JOB_PID_OUT and FLEURY_JOB_EVENTS_OUT contract).
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
        self.report = {'command': command, 'trace': self.trace}
        self.master = None
        self.shell_pid = None
        self.shell_status = None

    def note(self, event):
        self.trace.append(event)

    # -- the terminal and its shell -------------------------------------

    def start_shell(self):
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
            'PS1': PROMPT.decode(),
            'BASH_SILENCE_DEPRECATION_WARNING': '1',
            'HISTFILE': '/dev/null',
            'FLEURY_JOB_PID_OUT': self.pid_file,
            'FLEURY_JOB_EVENTS_OUT': self.events_file,
            'FLEURY_DEV_BOOTSTRAP_LOG': self.bootstrap_log,
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
                os.execve('/bin/bash', ['bash', '--norc', '--noprofile', '-i'], env)
            finally:
                os._exit(127)
        os.close(slave)
        self.master = master
        self.shell_pid = pid
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
            if self.shell_status is None:
                reaped, status = os.waitpid(self.shell_pid, os.WNOHANG)
                if reaped:
                    self.shell_status = status
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

    # -- the scenario ---------------------------------------------------

    def run(self):
        self.start_shell()
        self.wait_for(lambda: PROMPT in self.output, 'first prompt', 20)

        start = len(self.output)
        self.run_in_shell(' '.join(shlex.quote(part) for part in self.command))
        self.wait_for(lambda: self.app_pid() is not None, 'app started', 120)
        app = self.app_pid()
        self.wait_for(lambda: b'JOB-READY' in self.output_after(start),
                      'first frame', 60)
        if self.supervised:
            self.wait_for(
                lambda: os.path.exists(self.bootstrap_log) and
                'child ready' in open(self.bootstrap_log).read(),
                'supervisor wired to the app', 60)
        facts = self.process_facts(app)
        self.report['app'] = facts
        parent = facts['ppid']
        self.report['parent'] = self.process_facts(parent)
        self.report['shellPid'] = self.shell_pid
        self.note('app running')

        if self.suspend_key:
            # The focused field takes Ctrl+Z: it undoes, and the job runs on.
            self.report['undoBeforeSuspend'] = self.ctrl_z_undoes('x', app)
            suspend = CTRL_T
        else:
            suspend = CTRL_Z

        # The app hands the terminal back and stops.
        start = len(self.output)
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
        start = len(self.output)
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
        start = len(self.output)
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
        self.wait_for(lambda: self.shell_status is not None, 'shell exit', 15)
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

    def cleanup(self):
        # A failed step can leave the job stopped: continue its whole group so
        # it can take the kill, then end the shell.
        app = self.app_pid()
        if app is not None:
            try:
                pgid = os.getpgid(app)
                os.killpg(pgid, signal.SIGCONT)
                os.killpg(pgid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
        if self.shell_pid is not None and self.shell_status is None:
            try:
                os.kill(self.shell_pid, signal.SIGKILL)
                os.waitpid(self.shell_pid, 0)
            except ChildProcessError:
                pass
            except ProcessLookupError:
                pass
        if self.master is not None:
            os.close(self.master)


def main():
    args = sys.argv[1:]
    if '--' not in args or args.index('--') < 1 or args[-1] == '--':
        print(__doc__, file=sys.stderr)
        return 2
    split = args.index('--')
    work_dir, options, command = args[0], set(args[1:split]), args[split + 1:]
    unknown = options - {'--supervised', '--suspend-key'}
    if unknown:
        print(f'unknown options: {sorted(unknown)}\n{__doc__}', file=sys.stderr)
        return 2
    harness = Harness(work_dir, '--supervised' in options,
                      '--suspend-key' in options, command)
    try:
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
