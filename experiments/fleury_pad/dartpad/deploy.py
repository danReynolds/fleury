"""Deploy an already verified image to Cloud Run.

Requires an explicit project, pre-provisioned registry/runtime identity/secret,
and deployer credentials. By default the service is private staging and this
never grants public access. `--public` is the deliberate exception: the docs
compiler, invocable anonymously from the docs origin only.
"""
import argparse
import json
import re
import subprocess
from urllib.request import Request, urlopen


def command(args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def identity_token(url, invoker_account=None):
    # User credentials support gcloud's development ID token. Service account
    # impersonation requires the canonical service URL as its audience.
    args = ['gcloud', 'auth', 'print-identity-token']
    if invoker_account:
        args += ['--audiences', url, '--impersonate-service-account', invoker_account]
    return command(args)


def verify_profile(service, *, cpu_boost=False):
    service_annotations = service['metadata'].get('annotations', {})
    template = service['spec']['template']
    revision_annotations = template['metadata'].get('annotations', {})
    limits = template['spec']['containers'][0]['resources']['limits']
    expected = [
        service_annotations.get('run.googleapis.com/scalingMode') == 'automatic',
        service_annotations.get('run.googleapis.com/maxScale') == '1',
        service_annotations.get('run.googleapis.com/minScale', '0') == '0',
        revision_annotations.get('autoscaling.knative.dev/maxScale') == '1',
        revision_annotations.get('autoscaling.knative.dev/minScale', '0') == '0',
        revision_annotations.get('run.googleapis.com/cpu-throttling') == 'false',
        revision_annotations.get('run.googleapis.com/startup-cpu-boost') == str(cpu_boost).lower(),
        limits.get('cpu') in ('1', '1000m'), limits.get('memory') == '2Gi',
    ]
    if not all(expected):
        raise RuntimeError('Effective Cloud Run resource/scaling profile differs from the approved zero-to-one 1 CPU / 2 GiB profile; refusing smoke or promotion.')


def deploy(args):
    docs_origin = getattr(args, 'docs_origin', None)
    public = getattr(args, 'public', False)
    if docs_origin and not re.fullmatch(r'https://[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?(?::[0-9]{1,5})?', docs_origin):
        raise ValueError('Use an exact HTTPS docs origin without a path or credentials.')
    if public and not docs_origin:
        raise ValueError('A public Pad serves the docs; pass --docs-origin.')
    if not re.fullmatch(r'[a-z][a-z0-9-]{4,28}[a-z0-9]', args.project):
        raise ValueError('Expected an explicit Google Cloud project ID.')
    if not re.fullmatch(r'[a-z]+-[a-z]+[0-9]+', args.region):
        raise ValueError('Expected a Cloud Run region.')
    if not re.fullmatch(r'[a-z][a-z0-9-]{0,40}', args.service):
        raise ValueError('Invalid service name.')
    if not re.fullmatch(r'[a-z][a-z0-9_-]*:[0-9]+', args.checkpoint_secret):
        raise ValueError('Use a named secret with an immutable numeric version: name:1.')
    if not args.runtime_account.endswith(f'@{args.project}.iam.gserviceaccount.com'):
        raise ValueError('Use a dedicated runtime service account in the target project.')
    prefix = f'{args.region}-docker.pkg.dev/{args.project}/'
    if not args.image.startswith(prefix) or not re.search(r'@sha256:[a-f0-9]{64}$', args.image):
        raise ValueError('Deploy an immutable Artifact Registry image digest from this project.')
    common = ['--project', args.project, '--region', args.region, '--quiet']
    # Refuse to alter an existing public service under a staging command.
    listing = json.loads(command(['gcloud', 'run', 'services', 'list', *common, '--format=json']))
    exists = any(item['metadata']['name'] == args.service for item in listing)
    previous = None
    if exists:
        policy = json.loads(command(['gcloud', 'run', 'services', 'get-iam-policy', args.service, *common, '--format=json']))
        if not public and any(member in {'allUsers', 'allAuthenticatedUsers'} for binding in policy.get('bindings', []) for member in binding.get('members', [])):
            raise ValueError('Refusing a public service; choose a private staging service, or release it with --public.')
        previous = json.loads(command(['gcloud', 'run', 'services', 'describe', args.service, *common, '--format=json']))
        if previous['metadata'].get('annotations', {}).get('run.googleapis.com/invoker-iam-disabled') == 'true':
            raise ValueError('Staging requires the Cloud Run invoker IAM check.')
    subprocess.run([
        'gcloud', 'run', 'deploy', args.service, *common, '--image', args.image,
        '--service-account', args.runtime_account,
        # A public release grants run.invoker to allUsers; the service still
        # checks browser origins, and the frame's CSP limits who may embed it.
        '--allow-unauthenticated' if public else '--no-allow-unauthenticated', '--invoker-iam-check',
        # Absolute paths also repair services created with older image entrypoints.
        '--command=/usr/bin/python3', '--args=/app/experiments/fleury_pad/dartpad/supervise.py',
        '--execution-environment=gen2', '--cpu=1', '--memory=2Gi',
        # Instance-based billing avoids per-request fees; idle services may scale
        # to zero. Reset both service and revision settings on every release.
        '--no-cpu-throttling', '--cpu-boost' if args.cpu_boost else '--no-cpu-boost', '--scaling=auto',
        '--concurrency=8', '--min=0', '--min-instances=0',
        '--max=1', '--max-instances=1', '--timeout=60s',
        '--port=8080', '--tag=candidate', *(['--no-traffic'] if exists else []),
        # The loopback proxy origin is for testers of a private service only.
        '--set-env-vars=FLEURY_PAD_BIND=0.0.0.0' +
        ('' if public else ',FLEURY_PAD_PROXY_ORIGIN=http://127.0.0.1:8080') +
        (f',FLEURY_PAD_DOCS_ORIGIN={docs_origin}' if docs_origin else ''),
        f'--set-secrets=FLEURY_CHECKPOINT_KEY={args.checkpoint_secret}',
        '--startup-probe=httpGet.path=/healthz,initialDelaySeconds=0,timeoutSeconds=2,periodSeconds=2,failureThreshold=60',
        '--liveness-probe=httpGet.path=/healthz,timeoutSeconds=2,periodSeconds=10,failureThreshold=3',
    ], check=True)
    service = json.loads(command(['gcloud', 'run', 'services', 'describe', args.service, *common, '--format=json']))
    verify_profile(service, cpu_boost=args.cpu_boost)
    traffic = service['status']['traffic']
    candidate = next(entry for entry in traffic if entry.get('tag') == 'candidate')
    if candidate['revisionName'] != service['status']['latestReadyRevisionName']:
        raise RuntimeError('Candidate changed concurrently; refusing promotion.')
    url = candidate['url']
    # ID token audience is the canonical service URL, even when invoking a tag.
    token = identity_token(service['status']['url'], args.invoker_account)

    def request(route, payload=None, build=None):
        headers = {'Authorization': f'Bearer {token}'}
        if payload is not None:
            headers.update({'Content-Type': 'application/json', 'X-Fleury-Build': build})
        req = Request(url + route, data=None if payload is None else json.dumps(payload).encode(), headers=headers)
        with urlopen(req, timeout=65) as response:
            return json.load(response)

    build = request('/api/build')
    source = "import 'package:fleury/fleury_core.dart'; Widget buildApp() => const Text('Staging smoke');"
    initial = request('/api/v3/compileNewDDC', {'source': source}, build['buildId'])
    reload = request('/api/v3/compileNewDDCReload', {'source': source.replace('Staging smoke', 'Reload smoke'), 'deltaDill': initial['deltaDill']}, build['buildId'])
    if 'Reload smoke' not in reload['result']:
        raise RuntimeError('Candidate failed the hosted reload smoke test; previous traffic unchanged.')
    revision = candidate['revisionName']
    if args.promote:
        subprocess.run(['gcloud', 'run', 'services', 'update-traffic', args.service, *common, f'--to-revisions={revision}=100', '--remove-tags=candidate'], check=True)
    print(json.dumps({'url': service['status']['url'] if args.promote else url,
                      'candidateUrl': None if args.promote else url, 'revision': revision, 'build': build,
                      'promoted': args.promote, 'previousTraffic': previous.get('status', {}).get('traffic', []) if previous else []}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['project', 'region', 'image', 'runtime-account', 'checkpoint-secret']:
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--docs-origin', help='Exact HTTPS docs origin permitted for the embedded Pad')
    parser.add_argument('--service', default='fleury-pad-staging')
    parser.add_argument('--invoker-account', help='Service account the deployer may impersonate for the smoke test')
    parser.add_argument('--cpu-boost', action='store_true', help='Temporarily use 2 CPUs during startup; steady CPU and scaling caps stay unchanged')
    parser.add_argument('--promote', action='store_true', help='Route traffic to the candidate after its smoke test passes')
    parser.add_argument('--public', action='store_true', help='Serve the docs: allow anonymous invocation and drop the staging proxy origin (requires --docs-origin)')
    deploy(parser.parse_args())
