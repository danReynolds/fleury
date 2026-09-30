"""Compile the canonical guide catalogue against a loopback Pad compiler.

Regenerate first with npm run guides:projects. This is an explicit qualification
check, not something a visitor or normal page build sends to a hosted service.
"""
import json
import os
from pathlib import Path
import time
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

BASE = os.environ.get('FLEURY_PAD_URL', 'http://127.0.0.1:4346').rstrip('/')
if urlparse(BASE).hostname != '127.0.0.1':
    raise SystemExit('Use a loopback compiler or an authenticated local proxy.')
website = Path(__file__).resolve().parents[1]
projects = json.loads((website / 'src/guide_projects.json').read_text())
build = json.load(urlopen(BASE + '/api/build', timeout=15))
if build.get('protocolVersion', 0) < 3:
    raise SystemExit('Guide projects require compiler protocol 3 or later.')
failures = []
for name, project in projects.items():
    request = Request(BASE + '/api/v3/compileNewDDC',
                      data=json.dumps({'source': project['files']['main.dart'], 'files': project['files']}).encode(),
                      headers={'Content-Type': 'application/json', 'Origin': BASE, 'X-Fleury-Build': build['buildId']})
    start = time.monotonic()
    try:
        with urlopen(request, timeout=60) as response:
            result = json.load(response)
            if not result.get('result') or not result.get('deltaDill'):
                raise ValueError('Compiler returned no executable/checkpoint')
        print(f'{name}: compiled ({(time.monotonic()-start)*1000:.0f} ms)', flush=True)
    except (HTTPError, ValueError) as error:
        failures.append(name)
        print(f'{name}: {error.read().decode() if isinstance(error, HTTPError) else error}', flush=True)
if failures:
    raise SystemExit(f'Failed projects: {", ".join(failures)}')
print(f'Compiled all {len(projects)} guide projects with build {build["buildId"]}.')
