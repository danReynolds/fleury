"""Drives probe.dart: counts how often the thread that called
killpg(own group, SIGSTOP) wrote its next byte before the stop was reported.

usage: race.py <dart> <iterations> <main|isolate> <none|toggle>
"""
import fcntl
import os
import signal
import subprocess
import sys

dart, iterations, where, fix = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
here = os.path.dirname(os.path.abspath(__file__))
read_fd, write_fd = os.pipe()
child = subprocess.Popen(
    [dart, os.path.join(here, 'probe.dart'), str(iterations), where, fix],
    stdout=write_fd, preexec_fn=lambda: os.setpgid(0, 0))
os.close(write_fd)
fcntl.fcntl(read_fd, fcntl.F_SETFL, fcntl.fcntl(read_fd, fcntl.F_GETFL) | os.O_NONBLOCK)
stream = bytearray()


def drain():
    while True:
        try:
            chunk = os.read(read_fd, 65536)
        except BlockingIOError:
            return
        if not chunk:
            return
        stream.extend(chunk)


stops = raced = synchronous = odd = 0
while True:
    pid, status = os.waitpid(child.pid, os.WUNTRACED)
    if os.WIFSTOPPED(status):
        drain()
        b, a = stream.count(b'B'), stream.count(b'A')
        stops += 1
        if a == b:
            raced += 1
        elif b == a + 1:
            synchronous += 1
        else:
            odd += 1
        os.killpg(child.pid, signal.SIGCONT)
        continue
    break
drain()
child.returncode = os.waitstatus_to_exitcode(status)
print(f'{where:8} fix={fix:6} stops={stops} raced={raced} '
      f'synchronous={synchronous} odd={odd} exit={child.returncode} '
      f'complete={stream.endswith(b"E")}')
