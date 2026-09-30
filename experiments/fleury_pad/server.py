"""Loopback-only hosted-compilation proof. The browser executes the app."""
import base64
import json
import os
import gzip
import hashlib
from pathlib import Path
import re
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from config import ROOT, BUILD, dart_sdk

SDK = dart_sdk()
if not (BUILD / 'manifest.json').exists():
    raise SystemExit('Run prepare.py before starting the compiler preview.')
MANIFEST = json.loads((BUILD / 'manifest.json').read_text())
PORT = int(os.environ.get('PORT', '4345'))
ORIGIN = f'http://127.0.0.1:{PORT}'
LOCK = threading.Lock()
ASSETS = {
    '/': (ROOT / 'index.html', 'text/html'),
    '/pad.js': (ROOT / 'pad.js', 'text/javascript'),
    '/frame.html': (ROOT / 'frame.html', 'text/html'),
    '/preview.mjs': (ROOT / 'preview.mjs', 'text/javascript'),
    '/frame.js': (ROOT / 'frame.js', 'text/javascript'),
    '/loader.js': (SDK / 'lib/dev_compiler/ddc/ddc_module_loader.js', 'text/javascript'),
    '/sdk.js': (BUILD / 'sdk.js', 'text/javascript'),
    '/deps.js': (BUILD / 'deps.js', 'text/javascript'),
    '/sample.dart': (ROOT / 'lib/main.dart', 'text/plain'),
}


def compile_source(source, previous=None):
    # Research service: fixed packages, one editable file, bounded compiler work.
    if not isinstance(source, str) or len(source.encode()) > 64_000:
        raise ValueError('Source must be a string of at most 64 KB.')
    if previous is not None and (not isinstance(previous, str) or len(previous) > 2_000_000):
        raise ValueError('Invalid reload checkpoint.')
    with tempfile.TemporaryDirectory(prefix='fleury-pad-') as directory:
        job = Path(directory)
        (job / 'lib').mkdir()
        (job / 'lib/main.dart').write_text(source)
        (job / 'lib/bootstrap.dart').write_text((ROOT / 'lib/bootstrap.dart').read_text())
        config = json.loads((BUILD / 'package_config.json').read_text())
        next(p for p in config['packages'] if p['name'] == 'fleury_pad')['rootUri'] = job.as_uri() + '/'
        (job / 'package_config.json').write_text(json.dumps(config))
        command = [str(SDK / 'bin/dart'), str(SDK / 'bin/snapshots/dartdevc.dart.snapshot'),
                   '--modules=ddc', '--canary', '--no-summarize', '--enable-asserts',
                   f'--packages={job}/package_config.json', '-s', str(BUILD / 'deps.dill'),
                   f'--reload-delta-kernel={job}/next.dill', '-o', str(job / 'app.js')]
        if previous:
            (job / 'previous.dill').write_bytes(base64.b64decode(previous, validate=True))
            command += [f'--reload-last-accepted-kernel={job}/previous.dill', 'package:fleury_pad/main.dart']
        else:
            command += ['package:fleury_pad/bootstrap.dart']
        start = time.perf_counter()
        result = subprocess.run(command, capture_output=True, text=True, timeout=20)
        elapsed = round((time.perf_counter() - start) * 1000)
        if result.returncode:
            return {'ok': False, 'diagnostics': (result.stdout + result.stderr).replace(str(job) + '/lib/', ''), 'compileMs': elapsed}
        javascript = (job / 'app.js').read_text()
        return {'ok': True, 'javascript': javascript,
                'checkpoint': base64.b64encode((job / 'next.dill').read_bytes()).decode(),
                'libraries': re.findall(r'dartDevEmbedder.defineLibrary\("([^"]+)"', javascript),
                'compileMs': elapsed, 'javascriptBytes': len(javascript.encode()),
                'checkpointBytes': (job / 'next.dill').stat().st_size}


class Handler(BaseHTTPRequestHandler):
    def respond(self, status, data, content_type='application/json', cacheable=False):
        if not isinstance(data, bytes):
            data = json.dumps(data).encode()
        etag = '"' + hashlib.sha256(data).hexdigest()[:24] + '"'
        if cacheable and self.headers.get('If-None-Match') == etag:
            self.send_response(304)
            self.send_header('ETag', etag)
            self.end_headers()
            return
        compressed = len(data) > 1024 and 'gzip' in self.headers.get('Accept-Encoding', '')
        if compressed:
            data = gzip.compress(data)
        self.send_response(status)
        self.send_header('Vary', 'Accept-Encoding')
        if compressed:
            self.send_header('Content-Encoding', 'gzip')
        if cacheable:
            self.send_header('ETag', etag)
        self.send_header('Content-Type', content_type + '; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Cache-Control', 'no-cache' if cacheable else 'no-store')
        if self.path.split('?')[0] == '/frame.html':
            self.send_header('Content-Security-Policy', "default-src 'none'; script-src 'self' 'unsafe-inline' 'unsafe-eval' blob:; style-src 'unsafe-inline'; img-src data:; connect-src 'none'")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.headers.get('Host') != f'127.0.0.1:{PORT}':
            return self.respond(403, {'error': 'Loopback host only.'})
        if self.path == '/api/build':
            return self.respond(200, MANIFEST)
        asset = ASSETS.get(self.path.split('?')[0])
        if not asset:
            return self.respond(404, {'error': 'Not found'})
        path, content_type = asset
        self.respond(200, path.read_bytes(), content_type, cacheable=self.path.split('?')[0] in ('/loader.js', '/sdk.js', '/deps.js'))

    def do_POST(self):
        if self.path != '/api/compile':
            return self.respond(404, {'error': 'Not found'})
        if self.headers.get('Host') != f'127.0.0.1:{PORT}' or self.headers.get('Origin') != ORIGIN or self.headers.get_content_type() != 'application/json':
            return self.respond(403, {'error': 'Same-origin JSON requests only.'})
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 2_100_000:
                return self.respond(413, {'error': 'Request too large.'})
            request = json.loads(self.rfile.read(length))
            if request.get('buildId') != MANIFEST['buildId']:
                return self.respond(409, {'error': 'Compiler build changed. Refresh the page and run again.'})
            if not LOCK.acquire(blocking=False):
                return self.respond(429, {'error': 'Compiler busy. Try again.'})
            try:
                result = compile_source(request.get('source'), request.get('checkpoint'))
            finally:
                LOCK.release()
            self.respond(200, result)
        except (ValueError, TypeError, AttributeError) as error:
            self.respond(400, {'error': str(error)})
        except subprocess.TimeoutExpired:
            self.respond(408, {'error': 'Compilation exceeded 20 seconds.'})


if __name__ == '__main__':
    print(f'Fleury Pad compilation proof: {ORIGIN}', flush=True)
    ThreadingHTTPServer(('127.0.0.1', PORT), Handler).serve_forever()
