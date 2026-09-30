"""Exercise HTTP availability, queued compilation, and a stalled analyzer startup.

The SDK launcher is delayed only in disposable local containers. No production
configuration or test-only runtime switches are needed.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile
import time
from urllib.request import Request, urlopen


def run(image):
    records = {}
    with tempfile.TemporaryDirectory(prefix='fleury-pad-startup-') as directory:
        root = Path(directory)
        temporary = subprocess.check_output(['docker', 'create', '--platform=linux/amd64', image], text=True).strip()
        try:
            subprocess.run(['docker', 'cp', temporary + ':/usr/lib/dart/bin/dartaotruntime', str(root / 'runtime')], check=True)
        finally:
            subprocess.run(['docker', 'rm', temporary], check=True, stdout=subprocess.DEVNULL)
        shim = root / 'launcher'
        shim.write_text('#!/bin/sh\nsleep 5\nexec /opt/probe/runtime "$@"\n')
        shim.chmod(0o755)
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        base = f'http://127.0.0.1:{port}'
        env = {**os.environ, 'FLEURY_CHECKPOINT_KEY': base64.b64encode(secrets.token_bytes(32)).decode()}
        container = subprocess.check_output([
            'docker', 'run', '-d', '--platform=linux/amd64', '--read-only',
            '--cpus=1', '--memory=2g', '--memory-swap=2g', '--pids-limit=128',
            '--cap-drop=ALL', '--security-opt=no-new-privileges',
            '--tmpfs', '/tmp:rw,nosuid,size=536870912,mode=1777',
            '-v', f'{shim}:/usr/lib/dart/bin/dartaotruntime:ro',
            '-v', f'{root / "runtime"}:/opt/probe/runtime:ro',
            '-p', f'127.0.0.1:{port}:8080', '-e', 'K_SERVICE=startup-test',
            '-e', 'FLEURY_CHECKPOINT_KEY', image,
        ], env=env, text=True).strip()
        def state():
            return json.loads(subprocess.check_output(['docker', 'inspect', container], text=True))[0]['State']
        def assets():
            started = time.monotonic()
            while True:
                try:
                    with urlopen(base, timeout=1) as response:
                        assert b'Fleury Pad' in response.read()
                    break
                except OSError:
                    if time.monotonic() - started > 10 or not state()['Running']:
                        raise RuntimeError('HTTP assets waited for the delayed analyzer')
                    time.sleep(.1)
            logs = subprocess.check_output(['docker', 'logs', container], text=True)
            # Test the actual ordering, not a production latency threshold.
            events = [json.loads(line)['event'] for line in logs.splitlines() if line.startswith('{')]
            assert 'http_ready' in events and 'ready' not in events, events
            with urlopen(base + '/editor/main.js', timeout=5) as response:
                assert len(response.read()) > 1000
            return round((time.monotonic() - started) * 1000, 1)
        try:
            records['editorAvailableBeforeAnalyzerMs'] = assets()
            build = json.load(urlopen(base + '/api/build', timeout=5))
            starter = (Path(__file__).resolve().parent.parent / 'lib/main.dart').read_text()
            request = Request(base + '/api/v3/compileNewDDC', headers={
                'Content-Type': 'application/json', 'X-Fleury-Build': build['buildId'],
            }, data=json.dumps({'source': starter}).encode())
            with urlopen(request, timeout=5) as response:
                assert response.headers.get('x-fleury-precompiled') == 'starter'
                assert json.load(response).get('deltaDill')
            logs = subprocess.check_output(['docker', 'logs', container], text=True)
            events = [json.loads(line)['event'] for line in logs.splitlines() if line.startswith('{')]
            assert 'ready' not in events, events
            records['starterAvailableBeforeAnalyzer'] = True
            request = Request(base + '/api/v3/compileNewDDC', headers={
                'Content-Type': 'application/json', 'X-Fleury-Build': build['buildId'],
            }, data=json.dumps({'source': "import 'package:fleury/fleury_core.dart'; Widget buildApp() => const Text('Queued during startup');"}).encode())
            with urlopen(request, timeout=30) as response:
                result = json.load(response)
                assert result.get('deltaDill') and 'Queued during startup' in result['result']
            records['queuedCompilationPassed'] = True
            subprocess.run(['docker', 'stop', '--time', '10', container], check=True, stdout=subprocess.DEVNULL)
            assert state()['ExitCode'] == 0
            # Same mounted inode, intentionally never reaching analyzer startup.
            shim.write_text('#!/bin/sh\nsleep 120\nexec /opt/probe/runtime "$@"\n')
            subprocess.run(['docker', 'start', container], check=True, stdout=subprocess.DEVNULL)
            started = time.monotonic()
            # No API work: initialization itself must retain a process deadline.
            while state()['Running'] and time.monotonic() - started < 35:
                time.sleep(.25)
            stopped = state()
            assert not stopped['Running'] and stopped['ExitCode'] == 124 and not stopped['OOMKilled'], stopped
            records['stalledInitializationKilledMs'] = round((time.monotonic() - started) * 1000, 1)
            records['passed'] = True
            records['note'] = 'Fault injection; these are not normal startup latency measurements.'
            print(json.dumps(records, indent=2))
        finally:
            subprocess.run(['docker', 'logs', '--tail', '12', container], check=False)
            subprocess.run(['docker', 'rm', '-f', container], check=False, stdout=subprocess.DEVNULL)
    return records


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', required=True)
    parser.add_argument('--report')
    args = parser.parse_args()
    result = run(args.image)
    if args.report:
        Path(args.report).write_text(json.dumps(result, indent=2) + '\n')
