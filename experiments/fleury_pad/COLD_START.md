# Cold-start investigation — September 27, 2026

Update September 28: the AOT analyzer, early HTTP/editor availability, and startup
CPU boost are implemented and deployed privately. See [the implementation and
validation record](DEPLOYMENT.md#startup-integration-on-september-28-2026). The
sections below preserve the original research and baseline measurements.

The current private Pad is too slow for a first visit after scaling to zero.
We have a confirmed cold HTTP measurement and a promising local optimization;
we do not yet have a cloud measurement of that next optimization. No runtime or
cloud configuration was changed during this investigation.

## Measured current behavior

The deployed AOT HTTP host still starts the JIT analyzer and waits for its
initialization before binding the HTTP port. This blocks the editor, metadata,
and compilation endpoints together. The browser then waits for `/api/build`
and `/sample.dart` before creating Monaco.

After several hours without test traffic, the unchanged revision
`fleury-pad-staging-00006-guy` produced:

| Operation | HTTP round trip |
| --- | ---: |
| First connection (`/api/build`) | 8.329 s |
| First compilation | 1.839 s |
| First connection + compilation | 10.168 s |
| Three subsequent reloads | 0.636–0.770 s |

The first request, automatic new-instance start, and application-ready logs
share one instance ID. Application readiness followed the new-instance log by
6.927 seconds; the successful HTTP startup probe was logged about 1.169 seconds
after readiness. These timestamps do not isolate how much time was infrastructure
versus application initialization. The probe is currently on a two-second interval.

This is one cold sample, not a latency percentile. The two HTTP requests exclude
editor downloads, JavaScript evaluation, user thinking time and preview mounting.
See [the measured report](dartpad/evidence/2026-09-27-cloud-cold-aot.json).

## First recommendation: official precompiled Dart workers

The pinned SDK includes `analysis_server_aot.dart.snapshot` and
`dartdevc_aot.dart.snapshot`. The analyzer integration currently selects
`analysis_server.dart.snapshot`, and the DDC worker selects
`dartdevc.dart.snapshot`. Dart's own tools use the AOT analyzer; this is an
upstream SDK option, not a new compiler dependency.

An isolated local comparison at **1 CPU / 2 GiB, swap disabled** ran the exact
analyzer initialization handshake used by the host against the Fleury project,
then requested diagnostics. Each worker received a new HOME/cache directory.
The order was JIT, AOT, AOT, JIT, JIT, AOT to reduce ordering bias.

| Analyzer | Ready, three runs | Median |
| --- | --- | ---: |
| Current JIT snapshot | 4.252, 3.883, 3.939 s | 3.939 s |
| Official AOT snapshot | 1.559, 1.520, 1.508 s | 1.520 s |

That is a **61% lower median analyzer initialization time** locally. All runs
returned zero diagnostics for the sample. This used Linux AMD64 emulation on
Apple Silicon, so it predicts neither absolute Cloud Run times nor a percentage
improvement for the complete service. The DDC AOT worker has not been benchmarked
or qualified for compile/reload here.

The existing `analysis_server_lib` client hardcodes the `dart` executable, so
changing only the snapshot path is insufficient: the SDK rejects that invocation
and requires `dartaotruntime`. A small adapter change must preserve its protocol,
exit handling and shutdown. Qualify completion, hover, format, diagnostics,
compilation, reload checkpoints and worker deadlines before deploying it.

Evidence: [results](dartpad/evidence/2026-09-27-analyzer-startup.json) and
[probe](dartpad/evidence/2026-09-27-analyzer-startup-probe.py).
Reproduce from this directory with the recorded local image available:

```sh
docker run --rm --platform=linux/amd64 --network=none \
  --cpus=1 --memory=2g --memory-swap=2g --read-only \
  --tmpfs /tmp:rw,size=536870912 --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --mount "type=bind,src=$PWD/dartpad/evidence/2026-09-27-analyzer-startup-probe.py,dst=/tmp/probe.py,readonly" \
  --entrypoint=/usr/bin/python3 fleury-pad:cloud-aot-trial /tmp/probe.py
```

Sources: [Dart 3.9 changelog](https://dart.dev/changelog#3-9),
[pinned Dart CLI analyzer launcher](https://github.com/dart-lang/sdk/blob/3.12.2/pkg/dartdev/lib/src/analysis_server.dart).

## Other options, in order

1. **Startup CPU boost:** temporarily gives this one-CPU service two CPUs during
   startup and for ten seconds afterward. It preserves scale-to-zero and adds
   no warm minimum. At the current us-central1 instance-based rate, an additional
   CPU for twenty seconds is $0.00036 per start, or $0.36 per thousand starts,
   before free tier. This is an illustrative incremental compute charge, not a
   total bill or fixed startup duration. Benchmark the improvement independently;
   it will not necessarily halve startup. The deployment verifier currently
   requires boost off and would need an intentional update.
2. **Let the editor load independently:** first remove browser initialization's
   dependency on a live compiler. A static frontend on existing hosting can show
   the editor and saved draft while compiler startup overlaps reading/editing.
   Binding the current host before analyzer initialization is a smaller change,
   but still waits for Cloud Run's container startup. Either approach needs
   explicit backend readiness and failure handling. It improves responsiveness;
   a custom compile still waits if the backend is not ready. A precompiled sample
   is an additional option, with build matching and reload-checkpoint handoff to
   design rather than silently claiming hot reload works immediately.
3. **Benchmark first-generation Cloud Run:** Google recommends it for infrequent,
   cold-start-sensitive traffic. Pricing is the same. Our second-generation
   runtime offers full Linux compatibility and stronger sustained CPU performance;
   validate compiler child processes, termination and watchdog recovery before
   switching. It is a candidate, not an established improvement for this workload.

Sources: [startup CPU boost](https://docs.cloud.google.com/run/docs/configuring/services/cpu#startup-boost),
[Cloud Run pricing](https://cloud.google.com/run/pricing),
[execution environments](https://docs.cloud.google.com/run/docs/configuring/execution-environments).

Keep the 2 GiB allocation and min-zero/max-one policy for these comparisons.
Do not buy a warm minimum or add periodic keep-alive requests as the first fix.
Compare real natural-idle cold requests after each cloud change, with startup
logs and the exact revision, rather than treating deployment readiness as visitor
latency. Measure browser interactivity separately once the frontend can open
without the compiler.
