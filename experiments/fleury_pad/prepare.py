"""Build browser assets using only the installed, pinned Dart SDK."""
import hashlib
import json
from pathlib import Path
import subprocess
import time
from urllib.parse import urljoin

from config import BUILD, ROOT, SDK_VERSION, dart_sdk


def prepare(package_config=None):
    sdk = dart_sdk()
    repo = ROOT.parents[1]
    package_config = package_config or repo / 'website/examples/.dart_tool/package_config.json'
    if not package_config.exists():
        raise SystemExit('First run dart pub get in website/examples, then run this script again.')
    BUILD.mkdir(exist_ok=True)
    config = json.loads(package_config.read_text())
    for package in config['packages']:
        package['rootUri'] = urljoin(package_config.as_uri(), package['rootUri'])
    config['packages'] = [package for package in config['packages'] if package['name'] != 'fleury_pad']
    config['packages'].append({'name': 'fleury_pad', 'rootUri': ROOT.as_uri() + '/',
                               'packageUri': 'lib/', 'languageVersion': '3.10'})
    (BUILD / 'package_config.json').write_text(json.dumps(config, indent=2))
    (BUILD / 'deps.dart').write_text("import 'package:fleury/fleury_core.dart' as fleury;\n"
                                    "import 'package:fleury_web/fleury_web.dart' as host;\n"
                                    "import 'package:web/web.dart' as web;\n"
                                    "import 'package:fleury/themes.dart';\n"
                                    "import 'package:http/http.dart';\n"
                                    "import 'package:image/image.dart';\n")
    compiler = [str(sdk / 'bin/dart'), str(sdk / 'bin/snapshots/dartdevc.dart.snapshot')]
    start = time.perf_counter()
    print('Building the browser runtime from the official SDK…', flush=True)
    subprocess.run(compiler + ['--modules=ddc', '--canary', '--multi-root-scheme=org-dartlang-sdk',
                              '-o', str(BUILD / 'sdk.js'), str(sdk / 'lib/_internal/ddc_platform.dill')], check=True)
    print('Precompiling Fleury and its dependencies…', flush=True)
    subprocess.run(compiler + ['--modules=ddc', '--canary', '--enable-asserts',
                              f'--packages={BUILD}/package_config.json', '-o', str(BUILD / 'deps.js'),
                              str(BUILD / 'deps.dart')], check=True)
    fingerprint = hashlib.sha256()
    for name in ['sdk.js', 'deps.js', 'deps.dill', 'package_config.json']:
        fingerprint.update((BUILD / name).read_bytes())
    fingerprint.update((ROOT / 'lib/bootstrap.dart').read_bytes())
    manifest = {'sdkVersion': SDK_VERSION, 'buildId': fingerprint.hexdigest()[:16]}
    (BUILD / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    print(f'Prepared browser assets in {time.perf_counter() - start:.1f}s.')


if __name__ == '__main__':
    prepare()
