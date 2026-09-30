"""Contract tests against a loopback service or an authenticated Cloud Run proxy."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen
import unittest

ROOT = Path(__file__).resolve().parent.parent
BASE = os.environ.get('FLEURY_PAD_URL', 'http://127.0.0.1:4346').rstrip('/')
CLOUD_RUN_PROXY = os.environ.get('FLEURY_PAD_CLOUD_RUN_PROXY') == '1'
if urlparse(BASE).hostname != '127.0.0.1':
    raise SystemExit('These tests only send source to a loopback service.')


class DartPadBackendTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = json.load(urlopen(BASE + '/api/build', timeout=10))
        pin = json.loads((ROOT / 'dartpad/UPSTREAM.json').read_text())
        assert cls.build['backend'] == 'dartpad'
        assert cls.build['upstreamRevision'] == pin['revision']
        cls.source = (ROOT / 'lib/main.dart').read_text()

    def call(self, method, payload, headers=None, *, include_headers=False):
        body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        request = Request(BASE + '/api/v3/' + method, data=body, headers={
            'Content-Type': 'application/json', 'X-Fleury-Build': self.build['buildId'], 'Origin': BASE,
            **(headers or {}),
        })
        try:
            response = urlopen(request, timeout=60)
        except HTTPError as error:
            response = error
        with response:
            text = response.read().decode()
            result = (response.status, json.loads(text) if text.startswith('{') else text)
            return (*result, response.headers) if include_headers else result

    def test_precompiled_starter_and_custom_source_fallback(self):
        status, initial, headers = self.call('compileNewDDC', {'source': self.source}, include_headers=True)
        self.assertEqual(status, 200)
        self.assertEqual(headers.get('x-fleury-precompiled'), 'starter')
        self.assertEqual(headers.get('cache-control'), 'no-store')
        self.assertIsNone(headers.get('x-compile-ms'))
        self.assertTrue(initial['deltaDill'].startswith('v1.' + self.build['buildId'] + '.'))
        changed = self.source.replace('Hello, Fleury Pad!', 'Edited starter')
        status, reload, headers = self.call('compileNewDDCReload', {'source': changed, 'deltaDill': initial['deltaDill']}, include_headers=True)
        self.assertEqual(status, 200)
        self.assertIn('Edited starter', reload['result'])
        self.assertIsNone(headers.get('x-fleury-precompiled'))
        status, custom, headers = self.call('compileNewDDC', {'source': changed}, include_headers=True)
        self.assertEqual(status, 200)
        self.assertIn('Edited starter', custom['result'])
        self.assertIsNone(headers.get('x-fleury-precompiled'))
        self.assertIsNotNone(headers.get('x-compile-ms'))

    def test_project_reload_analysis_and_isolation(self):
        files = {
            'main.dart': "import 'package:fleury/fleury_core.dart'; import 'view.dart'; Widget buildApp() => const Counter();",
            'view.dart': "import 'package:fleury/fleury_core.dart'; class Counter extends StatelessWidget { const Counter(); Widget build(BuildContext context) => const Text('project label'); }",
        }
        payload = {'source': files['main.dart'], 'files': files}
        status, initial = self.call('compileNewDDC', payload)
        self.assertEqual(status, 200, initial)
        self.assertIn('package:fleury_pad/view.dart', initial['result'])
        files['view.dart'] = files['view.dart'].replace('project label', 'edited project label')
        status, changed = self.call('compileNewDDCReload', {**payload, 'deltaDill': initial['deltaDill']})
        self.assertEqual(status, 200, changed)
        self.assertIn('edited project label', changed['result'])
        # A second project's overlay must not leak into the next request.
        good = files['view.dart']
        files['view.dart'] = good.replace("const Text('edited project label')", 'missingGuideLabel')
        status, analysis = self.call('analyze', payload)
        self.assertEqual(status, 200, analysis)
        issue = next(issue for issue in analysis['issues'] if issue['kind'] == 'error')
        self.assertEqual(issue['file'], 'view.dart')
        self.assertEqual(issue['location']['charStart'], files['view.dart'].index('missingGuideLabel'))
        status, failed = self.call('compileNewDDCReload', {**payload, 'deltaDill': changed['deltaDill']})
        self.assertNotEqual(status, 200)
        files['view.dart'] = good
        status, clean = self.call('analyze', payload)
        self.assertEqual(status, 200, clean)
        self.assertFalse(any(issue['kind'] == 'error' for issue in clean['issues']))
        status, recovered = self.call('compileNewDDCReload', {**payload, 'deltaDill': changed['deltaDill']})
        self.assertEqual(status, 200, recovered)
        status, hover = self.call('document', {**payload, 'activeFile': 'view.dart', 'offset': good.index('StatelessWidget') + 2})
        self.assertEqual(status, 200, hover)
        self.assertIn('StatelessWidget', hover.get('elementDescription', ''))
        files['view.dart'] = good.replace('Text(', 'Tex(')
        status, completion = self.call('complete', {**payload, 'activeFile': 'view.dart', 'offset': files['view.dart'].index('Tex(') + 3})
        self.assertEqual(status, 200, completion)
        self.assertTrue(any(item['completion'] == 'Text' for item in completion['suggestions']), completion)
        status, single = self.call('analyze', {'source': self.source})
        self.assertEqual(status, 200, single)
        self.assertFalse(any(issue['kind'] == 'error' for issue in single['issues']))

    def test_compile_reload_reject_and_recover(self):
        status, initial = self.call('compileNewDDC', {'source': self.source})
        self.assertEqual(status, 200)
        self.assertIn('package:fleury_pad/bootstrap.dart', initial['result'])
        self.assertTrue(initial['deltaDill'])
        changed = self.source.replace('Hello, Fleury Pad!', 'Hello, DartPad!')
        status, reload = self.call('compileNewDDCReload', {'source': changed, 'deltaDill': initial['deltaDill']})
        self.assertEqual(status, 200)
        self.assertIn('Hello, DartPad!', reload['result'])
        self.assertNotIn('dartDevEmbedder.defineLibrary("package:fleury_pad/bootstrap.dart"', reload['result'])
        invalid = changed.replace("'Count: $_count'", 'missingLabel')
        status, rejected = self.call('compileNewDDCReload', {'source': invalid, 'deltaDill': reload['deltaDill']})
        self.assertNotEqual(status, 200)
        self.assertIn('missingLabel', rejected)
        self.assertNotIn('deltaDill', rejected)
        status, recovered = self.call('compileNewDDCReload', {'source': changed.replace('Count:', 'Clicks:'), 'deltaDill': reload['deltaDill']})
        self.assertEqual(status, 200)
        self.assertIn('Clicks:', recovered['result'])
        status, fresh = self.call('compileNewDDC', {'source': changed})
        self.assertEqual(status, 200)
        self.assertIn('dartDevEmbedder.defineLibrary("package:fleury_pad/bootstrap.dart"', fresh['result'])

    def test_analysis_reports_real_locations_and_clears(self):
        status, clean = self.call('analyze', {'source': self.source})
        self.assertEqual((status, clean['issues']), (200, []))
        source = self.source.replace("'Count: $_count'", 'missingLabel')
        status, result = self.call('analyze', {'source': source})
        self.assertEqual(status, 200)
        issue = next(issue for issue in result['issues'] if issue['code'] == 'undefined_identifier')
        start = issue['location']['charStart']
        self.assertEqual(source[start:start + issue['location']['charLength']], 'missingLabel')
        self.assertEqual(self.call('analyze', {'source': self.source})[1]['issues'], [])

    def test_fleury_completions_imports_and_documentation(self):
        source = "import 'package:fleury/fleury_core.dart';\nWidget buildApp() => Tex"
        status, result = self.call('complete', {'source': source, 'offset': len(source)})
        self.assertEqual(status, 200)
        names = {item['completion'] for item in result['suggestions']}
        self.assertIn('Text', names)
        self.assertIn('TextArea', names)
        self.assertEqual(source[result['replacementOffset']:], 'Tex')
        imports = "import 'package:fleury/';"
        status, result = self.call('complete', {'source': imports, 'offset': imports.index("/';") + 1})
        self.assertEqual(status, 200)
        self.assertTrue(any('fleury_core.dart' in item['completion'] for item in result['suggestions']))
        status, result = self.call('document', {'source': self.source, 'offset': self.source.index('StatefulWidget') + 2})
        self.assertEqual(status, 200)
        self.assertIn('StatefulWidget', result['elementDescription'])
        self.assertIn('retained', result['dartdoc'])

    def test_format_uses_dart_formatter(self):
        source = "import 'package:fleury/fleury_core.dart';Widget buildApp()=>const Text('hello');"
        status, result = self.call('format', {'source': source, 'offset': len(source)})
        self.assertEqual(status, 200)
        self.assertIn("\n\nWidget buildApp() => const Text('hello');\n", result['source'])
        self.assertIsInstance(result['offset'], int)

    def test_interleaved_requests_do_not_share_source(self):
        def analyze(name):
            source = self.source.replace("'Count: $_count'", name)
            return name, self.call('analyze', {'source': source})
        with ThreadPoolExecutor(max_workers=3) as executor:
            results = list(executor.map(analyze, ['missingAlpha', 'missingBeta', 'missingGamma']))
        for name, (status, result) in results:
            self.assertEqual(status, 200)
            messages = ' '.join(issue['message'] for issue in result['issues'])
            self.assertIn(name, messages)
            for other, _ in results:
                if other != name:
                    self.assertNotIn(other, messages)

    def test_browser_assets_accept_compression(self):
        import gzip
        for asset in ['editor/main.js', 'editor/main.css', 'editor/editor.worker.js', 'sdk.js', 'deps.js']:
            request = Request(BASE + '/' + asset, headers={'Accept-Encoding': 'gzip'})
            with urlopen(request, timeout=20) as response:
                self.assertEqual(response.status, 200)
                self.assertEqual(response.headers.get('Content-Encoding'), 'gzip')
                self.assertGreater(len(gzip.decompress(response.read())), 1000)

    def test_checkpoint_authentication_and_source_boundaries(self):
        status, initial = self.call('compileNewDDC', {'source': self.source})
        self.assertEqual(status, 200)
        token = initial['deltaDill']
        self.assertTrue(token.startswith('v1.'))
        parts = token.split('.')
        parts[3] = 'AA=='
        for invalid in ['.'.join(parts), 'AA==', 1, None]:
            self.assertEqual(self.call('compileNewDDCReload', {'source': self.source, 'deltaDill': invalid})[0], 400)
        self.assertEqual(self.call('compileNewDDC', {'source': self.source, 'deltaDill': 1})[0], 400)
        for directive in ["import 'file:///etc/passwd';", "export '../secret.dart';",
                          "part 'other.dart';", "import 'dart:core' if (dart.library.io) 'file:///etc/passwd';",
                          "import 'package:fleury/%2e%2e/secret.dart';"]:
            for method in ['analyze', 'compileNewDDC', 'format']:
                self.assertEqual(self.call(method, {'source': directive + self.source})[0], 400)
        self.assertEqual(self.call('document', {'source': self.source, 'offset': -1})[0], 400)
        self.assertEqual(self.call('complete', {'source': self.source})[0], 400)
        self.assertEqual(self.call('compileNewDDCReload', {'source': self.source, 'deltaDill': token})[0], 200)

    def test_health_and_security_headers(self):
        # Cloud Run's frontend reserves /healthz; its internal startup/liveness
        # probes reach the container directly. Verify that boundary explicitly.
        # https://docs.cloud.google.com/run/docs/known-issues#reserved-url-paths
        if CLOUD_RUN_PROXY:
            with self.assertRaises(HTTPError) as blocked:
                urlopen(BASE + '/healthz', timeout=10)
            self.assertEqual(blocked.exception.code, 404)
            blocked.exception.close()
        assets = ['', 'frame.html'] if CLOUD_RUN_PROXY else ['', 'healthz', 'frame.html']
        for asset in assets:
            with urlopen(BASE + '/' + asset, timeout=10) as response:
                self.assertEqual(response.headers['X-Content-Type-Options'], 'nosniff')
                if asset == 'frame.html':
                    self.assertIn("connect-src https://picsum.photos https://fastly.picsum.photos;",
                                  response.headers['Content-Security-Policy'])
                    self.assertIn("img-src data: blob:;", response.headers['Content-Security-Policy'])
                elif asset == '':
                    self.assertIn("frame-ancestors 'none'", response.headers['Content-Security-Policy'])

    def test_local_host_guards(self):
        self.assertEqual(self.call('compileNewDDC', {'source': self.source}, {'X-Fleury-Build': 'wrong'})[0], 409)
        self.assertEqual(self.call('compileNewDDC', {'source': self.source}, {'Origin': 'https://example.com'})[0], 403)
        self.assertEqual(self.call('compileNewDDC', {'source': 'x' * 64001})[0], 400)
        self.assertEqual(self.call('compileNewDDC', b'x' * 2100001)[0], 413)
        self.assertEqual(self.call('compileNewDDC', b'{')[0], 400)
        self.assertEqual(self.call('compileNewDDCReload', {'source': self.source, 'deltaDill': 'not base64!'})[0], 400)
        self.assertEqual(self.call('generateCode', {'source': self.source})[0], 404)
        self.assertEqual(self.call('compileNewDDC', {'source': self.source})[0], 200)


if __name__ == '__main__':
    unittest.main(verbosity=2)
