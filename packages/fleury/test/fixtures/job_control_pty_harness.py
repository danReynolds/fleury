"""Presses Ctrl+Z at a Fleury app running as a job of an interactive shell.

A real `bash -i` owns a pseudo-terminal as its controlling terminal, so job
control is the one a user has: the shell starts the command in a process group
of its own, gives that group the terminal, and gets the terminal back only when
the job stops or ends. The harness types the command, waits for the app's first
frame, presses Ctrl+Z, and records whether the shell got its prompt back and
ran a command — the observable meaning of "suspended" — then brings the job
back with `fg` and quits the app with Ctrl+Q.

usage: job_control_pty_harness.py <work-dir> <wait-for-supervisor> <command...>

<wait-for-supervisor> is `supervised` to wait for the hot-reload supervisor to
wire the app before pressing Ctrl+Z, anything else not to. The app must be
test/fixtures/job_control_fixture.dart (or honour its FLEURY_JOB_PID_OUT
contract). Writes <work-dir>/report.json (the facts; `failure` names the step
that could not complete) and <work-dir>/pty.bin (every byte the terminal
received). Exits 0 whenever a report was written; the Dart test asserts.
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


class StepFailed(Exception):
    pass


class Harness:
    def __init__(self, work_dir, supervised, command):
        self.work_dir = work_dir
        self.supervised = supervised
        self.command = command
        self.pid_file = os.path.join(work_dir, 'app.pid')
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

        # The user's Ctrl+Z: the app hands the terminal back and stops.
        start = len(self.output)
        self.send(b'\x1a')
        try:
            self.wait_for(lambda: PROMPT in self.output_after(start),
                          'the shell prompt after Ctrl+Z', 15)
            self.report['promptAfterCtrlZ'] = True
        except StepFailed:
            self.report['promptAfterCtrlZ'] = False
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

        # Ctrl+Q ends the app; the shell reports the job's exit status.
        start = len(self.output)
        self.send(b'\x11')
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
    if len(sys.argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    work_dir = sys.argv[1]
    harness = Harness(work_dir, sys.argv[2] == 'supervised', sys.argv[3:])
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
