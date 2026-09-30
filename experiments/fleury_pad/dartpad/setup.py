"""Prepare a pinned DartPad dependency, Fleury template, and local editor."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from config import ROOT, BUILD, dart_sdk
from prepare import prepare


def run(args, cwd=HERE):
    subprocess.run([str(arg) for arg in args], cwd=cwd, check=True)


def setup():
    sdk = dart_sdk()
    pin = json.loads((HERE / 'UPSTREAM.json').read_text())
    checkout = BUILD / 'dartpad'
    BUILD.mkdir(exist_ok=True)
    if not checkout.exists():
        run(['git', 'init', checkout])
        run(['git', 'remote', 'add', 'origin', pin['repository']], checkout)
        run(['git', 'fetch', '--depth=1', 'origin', pin['revision']], checkout)
        run(['git', 'checkout', '--detach', 'FETCH_HEAD'], checkout)
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=checkout, text=True).strip()
    if actual != pin['revision']:
        raise SystemExit('The generated DartPad checkout has a different revision; inspect it before replacing it.')
    patch = (HERE / 'upstream.patch').read_bytes()
    changes = subprocess.check_output(['git', 'diff', '--binary', 'HEAD'], cwd=checkout)
    if not changes:
        run(['git', 'apply', '--check', HERE / 'upstream.patch'], checkout)
        run(['git', 'apply', HERE / 'upstream.patch'], checkout)
    elif changes != patch:
        raise SystemExit('The generated DartPad checkout has unexpected edits; preserve or remove them before setup.')
    run([sdk / 'bin/dart', 'pub', 'get'] + (['--enforce-lockfile'] if (HERE / 'pubspec.lock').exists() else []))

    project = BUILD / 'project'
    project.mkdir(exist_ok=True)
    repo = ROOT.parents[1]
    fleury_path = os.path.relpath(repo / 'packages/fleury', project)
    web_path = os.path.relpath(repo / 'packages/fleury_web', project)
    widgets_path = os.path.relpath(repo / 'packages/fleury_widgets', project)
    (project / 'pubspec.yaml').write_text(
        f'name: fleury_pad\npublish_to: none\nenvironment:\n  sdk: ^3.12.0\n'
        f'dependencies:\n  fleury:\n    path: {fleury_path}\n  fleury_web:\n    path: {web_path}\n  fleury_widgets:\n    path: {widgets_path}\n  http: ^1.6.0\n  image: ^4.5.4\n  web: ^1.1.1\n'
        f'dependency_overrides:\n  fleury:\n    path: {fleury_path}\n')
    lock = HERE / 'project.pubspec.lock'
    if lock.exists():
        shutil.copy(lock, project / 'pubspec.lock')
    run([sdk / 'bin/dart', 'pub', 'get'] + (['--enforce-lockfile'] if lock.exists() else []), project)
    if not lock.exists():
        shutil.copy(project / 'pubspec.lock', lock)
    (project / 'lib').mkdir(exist_ok=True)
    shutil.copy(ROOT / 'lib/main.dart', project / 'lib/main.dart')
    # The compiler copies this template into each request's temporary directory.
    # Dependency roots must remain absolute; the editable package must be relative.
    config_path = project / '.dart_tool/package_config.json'
    prepare(config_path)
    from urllib.parse import urljoin
    config = json.loads(config_path.read_text())
    for package in config['packages']:
        package['rootUri'] = '../' if package['name'] == 'fleury_pad' else urljoin(config_path.as_uri(), package['rootUri'])
    config_path.write_text(json.dumps(config, indent=2))
    manifest_path = BUILD / 'manifest.json'
    manifest = json.loads(manifest_path.read_text())
    manifest.update(backend='dartpad', upstreamRevision=pin['revision'], protocolVersion=3)
    identity = manifest['buildId'].encode() + pin['revision'].encode() + patch + b'protocol:3'
    for source in [HERE / 'bin/server.dart', HERE / 'lib/request_policy.dart',
                   HERE / 'lib/compiler_backend.dart', HERE / 'lib/precompiled_starter.dart',
                   HERE / 'bin/precompile_starter.dart', ROOT / 'lib/main.dart',
                   HERE / 'web/editor.js', HERE / 'web/source-project.mjs', HERE / 'web/main.js', HERE / 'web/index.html',
                   ROOT / 'frame.js', ROOT / 'preview.mjs']:
        identity += source.read_bytes()
    manifest['buildId'] = hashlib.sha256(identity).hexdigest()[:16]
    manifest_path.write_text(json.dumps(manifest, indent=2))
    run([sdk / 'bin/dart', 'run', 'bin/precompile_starter.dart'])
    run(['npm', 'ci'] if (HERE / 'package-lock.json').exists() else ['npm', 'install'])
    run(['npm', 'run', 'build'])
    print(f'Prepared DartPad {pin["revision"][:8]} with Fleury. Run: python3 {HERE}/run.py')


if __name__ == '__main__':
    setup()
