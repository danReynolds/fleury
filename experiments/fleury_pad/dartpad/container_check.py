"""Qualify the exact deployable image on loopback with bounded resources."""
import argparse
import base64
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from measure_latency import measure

HERE = Path(__file__).resolve().parent


def run(image, port=0, latency_report=None, platform='linux/amd64', guides=False):
    if not port:
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
    base = f'http://127.0.0.1:{port}'
    # This ephemeral test key is never saved, printed, or used in deployment.
    env = {**os.environ, 'FLEURY_CHECKPOINT_KEY': base64.b64encode(secrets.token_bytes(32)).decode()}
    container = subprocess.check_output([
        'docker', 'run', '-d', '--platform', platform, '--read-only',
        '--memory=2g', '--memory-swap=2g', '--cpus=1', '--pids-limit=128', '--cap-drop=ALL',
        '--security-opt=no-new-privileges', '--tmpfs', '/tmp:rw,nosuid,size=536870912,mode=1777',
        # Simulate Cloud Run's host handling plus an explicit loopback proxy origin.
        # This tests HTTP headers, not Google IAM authentication.
        '-p', f'127.0.0.1:{port}:8080', '-e', 'K_SERVICE=container-test',
        '-e', f'FLEURY_PAD_PROXY_ORIGIN={base}',
        '-e', 'FLEURY_CHECKPOINT_KEY', image,
    ], env=env, text=True).strip()
    def state():
        return json.loads(subprocess.check_output(['docker', 'inspect', container], text=True))[0]['State']

    def ready():
        started = time.monotonic()
        while True:
            try:
                with urlopen(base + '/healthz', timeout=2) as response:
                    if response.status == 200:
                        elapsed = time.monotonic() - started
                        print(f'Container ready in {elapsed:.1f}s', flush=True)
                        return elapsed
            except OSError:
                pass
            if not state()['Running'] or time.monotonic() - started > 120:
                raise RuntimeError('Container did not become ready within 120 seconds.')
            time.sleep(.5)

    def compile(method, source, checkpoint=None):
        build = json.load(urlopen(base + '/api/build', timeout=5))
        payload = {'source': source}
        if checkpoint:
            payload['deltaDill'] = checkpoint
        req = Request(base + '/api/v3/' + method, data=json.dumps(payload).encode(), headers={
            'Content-Type': 'application/json', 'X-Fleury-Build': build['buildId'], 'Origin': base})
        return json.load(urlopen(req, timeout=35))

    report = None
    peak_bytes = None
    image_id = json.loads(subprocess.check_output(['docker', 'inspect', container], text=True))[0]['Image']
    try:
        startup = ready()
        if latency_report:
            report = measure(base, label='local-after-readiness')
            report.update(environment=f'Local Docker {platform}; not Cloud Run',
                          qualificationPassed=False, imageId=image_id,
                          startupReadinessMs=round(startup * 1000, 1),
                          allocation={'cpus': 1, 'memoryGiB': 2, 'swapEnabled': False})
            Path(latency_report).write_text(json.dumps(report, indent=2) + '\n')
            print(f'Local latency report saved to {latency_report}', flush=True)
        subprocess.run([sys.executable, str(HERE / 'test_backend.py')],
                       env={**os.environ, 'FLEURY_PAD_URL': base}, check=True)
        if guides:
            subprocess.run([sys.executable, str(HERE.parents[2] / 'website/scripts/check-guide-projects.py')],
                           env={**os.environ, 'FLEURY_PAD_URL': base}, check=True)
        subprocess.run(['docker', 'stats', '--no-stream', '--format', '{{.MemUsage}}', container], check=True)
        peak = subprocess.run(['docker', 'exec', container, 'cat', '/sys/fs/cgroup/memory.peak'],
                              capture_output=True, text=True)
        if peak.returncode == 0:
            peak_bytes = int(peak.stdout.strip())
            print(f'Container cgroup peak bytes: {peak_bytes}', flush=True)

        source = "import 'package:fleury/fleury_core.dart'; Widget buildApp() => const Text('Instance one');"
        accepted = compile('compileNewDDC', source)
        subprocess.run(['docker', 'stop', '--time', '10', container], check=True, stdout=subprocess.DEVNULL)
        stopped = state()
        if stopped['OOMKilled'] or stopped['ExitCode'] != 0:
            raise RuntimeError(f'Unclean shutdown: {stopped}')
        print('Container API and graceful shutdown passed.', flush=True)
        subprocess.run(['docker', 'start', container], check=True, stdout=subprocess.DEVNULL)
        ready()
        # No writable state survives this restart; the same key and build suffice.
        resumed = compile('compileNewDDCReload', source.replace('one', 'two'), accepted['deltaDill'])
        assert 'Instance two' in resumed['result']
        print('Accepted checkpoint continued in a fresh compiler process.', flush=True)
        freeze = """
import os, signal
from pathlib import Path
count = 0
for entry in Path('/proc').glob('[0-9]*'):
    try:
        args = (entry / 'cmdline').read_bytes().split(bytes([0]))
        if b'--persistent_worker' in args and any(arg.endswith(b'/dartdevc.dart.snapshot') for arg in args):
            os.kill(int(entry.name), signal.SIGSTOP)
            count += 1
    except (FileNotFoundError, ProcessLookupError):
        pass
assert count == 1, count
"""
        subprocess.run(['docker', 'exec', container, 'python3', '-c', freeze], check=True)
        started = time.monotonic()
        try:
            compile('compileNewDDC', source)
            raise AssertionError('Frozen compiler unexpectedly succeeded.')
        except (HTTPError, URLError, ConnectionError, TimeoutError):
            pass
        while state()['Running'] and time.monotonic() - started < 30:
            time.sleep(.1)
        stopped = state()
        if stopped['Running'] or stopped['ExitCode'] != 124 or stopped['OOMKilled']:
            raise RuntimeError(f'Compiler deadline did not terminate the container: {stopped}')
        print(f'Frozen DDC worker terminated with its service after {time.monotonic() - started:.1f}s.', flush=True)
        subprocess.run(['docker', 'start', container], check=True, stdout=subprocess.DEVNULL)
        ready()
        recovered = compile('compileNewDDCReload', source.replace('one', 'recovered'), resumed['deltaDill'])
        assert 'Instance recovered' in recovered['result']
        print('Reload recovered after worker failure and replacement.', flush=True)
        if report:
            report.update(qualificationPassed=True, peakMemoryBytesDuringApiTests=peak_bytes)
            Path(latency_report).write_text(json.dumps(report, indent=2) + '\n')
    finally:
        current = state()
        print('Container final state: ' + json.dumps({key: current[key] for key in
              ('Running', 'OOMKilled', 'ExitCode')}), flush=True)
        subprocess.run(['docker', 'logs', '--tail', '30', container], check=False)
        subprocess.run(['docker', 'rm', '-f', container], check=False, stdout=subprocess.DEVNULL)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', default='fleury-pad:staging')
    parser.add_argument('--port', type=int, default=0)
    parser.add_argument('--latency-report', help='Save local HTTP timings separately from hosted evidence')
    parser.add_argument('--platform', choices=['linux/amd64', 'linux/arm64'], default='linux/amd64')
    parser.add_argument('--guides', action='store_true', help='Also compile the generated guide catalogue')
    args = parser.parse_args()
    run(args.image, args.port, args.latency_report, args.platform, args.guides)
