"""Runs a command as the foreground job of a minimal job-control shell on a
fresh pseudo-terminal, and continues it every time it stops.

usage: stop_job_pty_harness.py <work-dir> -- <command...>

The command is test/fixtures/stop_job_fixture.dart, which stops its own job
and, each time the stop returns, writes a byte to its file descriptor 3:
<work-dir>/record, opened for appending. While the job is stopped, the shell
counts the bytes there: one more than the stops before it means the fixture
went on running after it asked to stop, before the stop took effect. Writes
<work-dir>/report.json:
{"stops": n, "early": [stop indexes that found their byte], "exit": code};
`failure` names a step that could not complete. Exits 0 whenever it wrote a
report; the Dart test asserts.
"""

import fcntl
import json
import os
import select
import signal
import sys
import termios
import time


def shell(command, record, report_path):
    """The session leader: runs [command] as its foreground job, the way an
    interactive shell does, and continues it after every stop."""
    for sig in (signal.SIGTSTP, signal.SIGTTIN, signal.SIGTTOU):
        signal.signal(sig, signal.SIG_IGN)
    job = os.fork()
    if job == 0:
        try:
            os.setpgid(0, 0)
            os.tcsetpgrp(0, os.getpgrp())
            for sig in (signal.SIGTSTP, signal.SIGTTIN, signal.SIGTTOU):
                signal.signal(sig, signal.SIG_DFL)
            os.dup2(os.open(record, os.O_WRONLY | os.O_APPEND), 3)
            # dup2 onto the same number keeps open()'s close-on-exec.
            os.set_inheritable(3, True)
            os.execvp(command[0], command)
        finally:
            os._exit(127)
    try:
        os.setpgid(job, job)
        os.tcsetpgrp(0, job)
    except OSError:
        pass
    stops = 0
    early = []
    while True:
        _, status = os.waitpid(job, os.WUNTRACED)
        if not os.WIFSTOPPED(status):
            break
        if os.path.getsize(record) > stops:
            early.append(stops)
        stops += 1
        os.killpg(job, signal.SIGCONT)
    with open(report_path, 'w') as f:
        json.dump({'stops': stops, 'early': early,
                   'exit': os.waitstatus_to_exitcode(status)}, f)


def main():
    args = sys.argv[1:]
    if '--' not in args or args.index('--') != 1 or args[-1] == '--':
        print(__doc__, file=sys.stderr)
        return 2
    work_dir, command = args[0], args[2:]
    record = os.path.join(work_dir, 'record')
    report_path = os.path.join(work_dir, 'report.json')
    open(record, 'wb').close()
    master, slave = os.openpty()
    leader = os.fork()
    if leader == 0:
        try:
            os.close(master)
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
            for fd in (0, 1, 2):
                os.dup2(slave, fd)
            if slave > 2:
                os.close(slave)
            shell(command, record, report_path)
        finally:
            os._exit(0)
    os.close(slave)
    output = bytearray()
    deadline = time.monotonic() + 120
    status = None
    # Keep reading the terminal until the shell is gone: on macOS a session
    # leader's exit waits for its terminal's output to drain.
    while time.monotonic() < deadline:
        if select.select([master], [], [], 0.05)[0]:
            try:
                output.extend(os.read(master, 65536))
            except OSError:
                pass
        reaped, status = os.waitpid(leader, os.WNOHANG)
        if reaped:
            break
    else:
        os.killpg(leader, signal.SIGKILL)
        os.waitpid(leader, 0)
        with open(report_path, 'w') as f:
            json.dump({'failure': 'the job did not finish',
                       'output': output[-2000:].decode('latin-1')}, f)
    os.close(master)
    if not os.path.exists(report_path):
        with open(report_path, 'w') as f:
            json.dump({'failure': 'the shell wrote no report',
                       'output': output[-2000:].decode('latin-1')}, f)
    return 0


if __name__ == '__main__':
    sys.exit(main())
