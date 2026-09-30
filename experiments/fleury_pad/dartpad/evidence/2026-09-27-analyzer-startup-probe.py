import json, os, pathlib, queue, shutil, subprocess, threading, time

sdk = '/usr/lib/dart'
project = '/app/experiments/fleury_pad/.build/project'
results = []
for mode in ('jit', 'aot', 'aot', 'jit', 'jit', 'aot'):
    cache = pathlib.Path('/tmp/analyzer-probe-home')
    shutil.rmtree(cache, ignore_errors=True)
    cache.mkdir()
    args = [f'{sdk}/bin/' + ('dart' if mode == 'jit' else 'dartaotruntime'),
            f'{sdk}/bin/snapshots/analysis_server' + ('' if mode == 'jit' else '_aot') + '.dart.snapshot',
            '--sdk', sdk, '--client-id=DartPad']
    messages = queue.Queue()
    err = open('/tmp/analyzer-probe-stderr', 'w+')
    start = time.perf_counter()
    p = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=err,
                         text=True, env={**os.environ, 'HOME': str(cache)})
    def reader(proc):
        for line in proc.stdout:
            try: messages.put(json.loads(line))
            except ValueError: pass
        messages.put({'processClosed': True})
    threading.Thread(target=reader, args=(p,), daemon=True).start()
    def until(predicate):
        deadline = time.monotonic() + 45
        while True:
            msg = messages.get(timeout=max(0.01, deadline-time.monotonic()))
            if msg.get('processClosed'): raise RuntimeError('Analyzer exited before response')
            if predicate(msg): return msg
    def call(id, method, params=None):
        p.stdin.write(json.dumps({'id': id, 'method': method, **({'params':params} if params else {})})+'\n')
        p.stdin.flush()
        msg = until(lambda m: m.get('id') == id)
        if 'error' in msg: raise RuntimeError(msg)
        return msg.get('result')
    try:
        until(lambda m: m.get('event') == 'server.connected')
        connected = time.perf_counter()
        call('1', 'server.setSubscriptions', {'subscriptions':['STATUS']})
        call('2', 'analysis.setAnalysisRoots', {'included':[project], 'excluded':[]})
        ready = time.perf_counter()
        result = call('3', 'analysis.getErrors', {'file':project+'/lib/main.dart'})
        analyzed = time.perf_counter()
        row = {'mode':mode, 'connectedMs':round((connected-start)*1000,1),
               'hostEquivalentReadyMs':round((ready-start)*1000,1),
               'firstAnalysisMs':round((analyzed-start)*1000,1),
               'diagnostics':len(result['errors'])}
        print(json.dumps(row), flush=True)
        results.append(row)
        call('4', 'server.shutdown')
        p.wait(timeout=5)
    finally:
        if p.poll() is None: p.kill(); p.wait(timeout=5)
        err.close()
print(json.dumps({'samples':results, 'cpu':1, 'memoryGiB':2, 'platform':'linux/amd64 emulated on Apple Silicon',
 'scope':'Analyzer worker only; excludes Cloud Run infrastructure, HTTP host, DDC and browser.',
 'sdk':'3.12.2', 'image':'fleury-pad:cloud-aot-trial',
 'cache':'New analyzer HOME for each run; kernel file cache is not flushed.'}))
