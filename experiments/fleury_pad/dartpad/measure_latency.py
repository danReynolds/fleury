"""Measure private Fleury Pad HTTP latency without changing scaling or polling.

Run after deployment, or after leaving the service untouched long enough to
scale down. Correlate timestamps with Cloud Run startup logs/instance metrics
before calling a sample cold; an idle interval alone does not prove shutdown.
Reports contain timing/build metadata, never credentials, code or checkpoints.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import time
from urllib.parse import urlparse
from urllib.request import Request, urlopen

from deploy import command, identity_token


def measure(base, token=None, rounds=3, label='unspecified'):
    parsed = urlparse(base)
    if (parsed.scheme, parsed.hostname) != ('http', '127.0.0.1') and not (
            parsed.scheme == 'https' and (parsed.hostname or '').endswith('.run.app')):
        raise ValueError('Use HTTP loopback or the HTTPS Cloud Run service URL.')
    if parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ('', '/'):
        raise ValueError('Expected an origin without credentials, query or path.')
    if not 1 <= rounds <= 5:
        raise ValueError('Use one to five warm reloads.')
    base = base.rstrip('/')
    records = []
    started = datetime.now(timezone.utc).isoformat()

    def request(name, route, payload=None, build=None):
        headers = {'Accept-Encoding': 'identity'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        if payload is not None:
            headers.update({'Content-Type': 'application/json', 'X-Fleury-Build': build})
        req = Request(base + route, data=None if payload is None else json.dumps(payload).encode(), headers=headers)
        begin = time.perf_counter()
        with urlopen(req, timeout=65) as response:
            body = response.read()
            elapsed = (time.perf_counter() - begin) * 1000
            server_ms = response.headers.get('x-compile-ms')
            precompiled = response.headers.get('x-fleury-precompiled') == 'starter'
        records.append({'operation': name, 'roundTripMs': round(elapsed, 1),
                        'serverElapsedMs': int(server_ms) if server_ms else None,
                        'responseBytes': len(body), 'precompiledStarter': precompiled})
        return json.loads(body)

    # This is deliberately the first data-plane request; no readiness polling
    # or health request can accidentally warm the service before measurement.
    build = request('initialConnection', '/api/build')
    source = (Path(__file__).resolve().parent.parent / 'lib/main.dart').read_text()
    marker = 'Hello, Fleury Pad!'
    if marker not in source:
        raise ValueError('The benchmark sample heading changed; update its marker.')
    initial = request('firstCompile', '/api/v3/compileNewDDC', {'source': source}, build['buildId'])
    if not initial.get('deltaDill') or 'package:fleury_pad/bootstrap.dart' not in initial.get('result', ''):
        raise RuntimeError('Initial compilation failed its output checks.')
    checkpoint = initial['deltaDill']
    for index in range(rounds):
        heading = f'Latency sample {index + 1}'
        result = request(f'reload{index + 1}', '/api/v3/compileNewDDCReload',
                         {'source': source.replace(marker, heading), 'deltaDill': checkpoint}, build['buildId'])
        if heading not in result.get('result', '') or not result.get('deltaDill'):
            raise RuntimeError('Reload failed its output checks.')
        checkpoint = result['deltaDill']
    return {'startedAt': started, 'finishedAt': datetime.now(timezone.utc).isoformat(),
            'url': base, 'label': label, 'build': build, 'httpOnly': True,
            'coldStartConfirmed': False, 'samples': records,
            'firstConnectionThroughCompileMs': round(sum(item['roundTripMs'] for item in records[:2]), 1)}


def target(args):
    if args.local_url:
        if urlparse(args.local_url).hostname != '127.0.0.1':
            raise ValueError('--local-url must use 127.0.0.1.')
        return args.local_url, None, None
    if not args.project or not args.region:
        raise ValueError('Cloud measurements require an explicit --project and --region.')
    if not re.fullmatch(r'[a-z][a-z0-9-]{4,28}[a-z0-9]', args.project):
        raise ValueError('Invalid project ID.')
    common = ['--project', args.project, '--region', args.region, '--format=json']
    service = json.loads(command(['gcloud', 'run', 'services', 'describe', args.service, *common]))
    policy = json.loads(command(['gcloud', 'run', 'services', 'get-iam-policy', args.service, *common]))
    if any(member in {'allUsers', 'allAuthenticatedUsers'} for binding in policy.get('bindings', []) for member in binding.get('members', [])):
        raise ValueError('This trial measures a private service only.')
    if service['metadata'].get('annotations', {}).get('run.googleapis.com/invoker-iam-disabled') == 'true':
        raise ValueError('The private trial requires the invoker IAM check.')
    url = service['status']['url']
    metadata = {'project': args.project, 'region': args.region, 'service': args.service,
                'revision': service['status']['latestReadyRevisionName'],
                'serviceAnnotations': service['metadata'].get('annotations', {}),
                'revisionAnnotations': service['spec']['template']['metadata'].get('annotations', {}),
                'resources': service['spec']['template']['spec']['containers'][0]['resources']}
    return url, identity_token(url, args.invoker_account), metadata


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project')
    parser.add_argument('--region')
    parser.add_argument('--service', default='fleury-pad-staging')
    parser.add_argument('--invoker-account')
    parser.add_argument('--local-url', help='HTTP loopback for local qualification only')
    parser.add_argument('--label', default='unspecified', help='Context, not proof that a request was cold')
    parser.add_argument('--rounds', type=int, choices=range(1, 6), default=3)
    args = parser.parse_args()
    url, token, metadata = target(args)
    report = measure(url, token, args.rounds, args.label)
    if metadata:
        report['deployment'] = metadata
    print(json.dumps(report, indent=2))
