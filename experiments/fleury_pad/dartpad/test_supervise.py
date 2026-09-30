import os
from pathlib import Path
import sys
import tempfile
import unittest

from supervise import supervise


class SupervisorTest(unittest.TestCase):
    def run_child(self, code):
        return supervise([sys.executable, '-c', code], startup_seconds=.3, request_seconds=.3, stop_seconds=.2)

    def test_normal_exit(self):
        self.assertEqual(self.run_child('pass'), 0)

    def test_startup_deadline(self):
        self.assertEqual(self.run_child('import time; time.sleep(10)'), 124)

    def test_request_deadline_kills_descendants(self):
        with tempfile.TemporaryDirectory() as directory:
            pid_file = Path(directory) / 'pid'
            code = f'''
import os, subprocess, sys, time
child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(10)'])
open({str(pid_file)!r}, 'w').write(str(child.pid))
os.write(int(os.environ['FLEURY_WATCHDOG_FD']), b'ready\\nstart 1\\n')
time.sleep(10)
'''
            self.assertEqual(self.run_child(code), 124)
            pid = int(pid_file.read_text())
            # A killed descendant can briefly remain a zombie until init reaps it.
            status = subprocess_status(pid)
            self.assertTrue(status is None or status.startswith('Z'), status)

    def test_service_can_drain_workers_before_process_group_cleanup(self):
        # Model an API that sends a final shutdown message to its worker. If the
        # supervisor sends SIGTERM to the entire group first, that worker exits
        # prematurely and the API sees the same broken pipe as the analyzer.
        worker = "import sys; print('ready', flush=True); sys.stdin.readline()"
        code = f'''
import os, signal, subprocess, sys, time
worker = subprocess.Popen([sys.executable, '-c', {worker!r}], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
assert worker.stdout.readline() == b'ready\\n'
def stop(signum, frame):
    time.sleep(.05)
    if worker.poll() is not None:
        sys.exit(23)
    worker.stdin.write(b'shutdown\\n')
    worker.stdin.flush()
    worker.wait(timeout=1)
    sys.exit(0)
signal.signal(signal.SIGTERM, stop)
os.write(int(os.environ['FLEURY_WATCHDOG_FD']), b'ready\\n')
os.kill(os.getppid(), signal.SIGTERM)
while True:
    time.sleep(.1)
'''
        self.assertEqual(supervise([sys.executable, '-c', code],
                                  startup_seconds=3, request_seconds=3, stop_seconds=2), 0)

    def test_completed_work_clears_deadline(self):
        events = b"ready\nstart 1\nend 1\n"
        code = f"import os, time; os.write(int(os.environ['FLEURY_WATCHDOG_FD']), {events!r}); time.sleep(.4)"
        self.assertEqual(self.run_child(code), 0)


def subprocess_status(pid):
    if sys.platform.startswith('linux'):
        try:
            return Path(f'/proc/{pid}/stat').read_text().split(') ', 1)[1].split()[0]
        except FileNotFoundError:
            return None
    import subprocess
    result = subprocess.run(['ps', '-o', 'stat=', '-p', str(pid)], capture_output=True, text=True)
    return result.stdout.strip() or None


if __name__ == '__main__':
    unittest.main()
