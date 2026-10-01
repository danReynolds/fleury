# Fleury Pad deployment

**Since September 30, 2026, `fleury-pad-staging` is the public compiler for the
published docs**, invocable anonymously and embeddable only from
`https://danreynolds.github.io`. See [Public docs compiler](#public-docs-compiler-september-30-2026).

The first target was **private Cloud Run staging**. A dedicated project,
`fleury-pad-20260927`, is provisioned in `us-central1` and linked to the approved
billing account. The private `fleury-pad-staging` service uses 1 CPU / 2 GiB,
minimum zero and maximum one. Startup CPU boost temporarily provides a second
CPU; there is no warm minimum. GitHub deployment credentials are not configured;
the release-tag workflow remains disabled. Public availability is a separate
promotion decision. See the hosted trial evidence below.

## One build, one service

The image precompiles the HTTP host to a native executable and contains Dart
3.12.2, the pinned DartPad backend plus its four-file patch, fixed Fleury
dependencies, Monaco, and matching preview assets. The analyzer uses the official
AOT snapshot through the upstream protocol client; DDC remains unchanged.
Source compiles on the service; submitted application code runs only in the
browser. There is no database, session server, package installation per request,
or call to Google's public DartPad API.

A release builds this bundle from one repository commit. Deploy the **verified
image digest**, rather than rebuilding during deployment. `/api/build` records
the build ID, protocol version, upstream revision, SDK, and source revision.
The build ID covers runtime/dependency output, the host/editor protocol, and
the starter source. Setup precompiles the starter into the image with the same
DartPad template and runtime. Exact starter requests return that artifact with
a newly signed checkpoint; custom source and reloads use the compiler as usual.
The artifact is rebuilt on every image build and does not require a cache service.
Startup checks verify that it is available before analyzer initialization finishes.
Absolute generated paths are fixed inside the container; local and container
build IDs need not match. Base images, Dart/npm locks, and upstream source are
pinned; OS packages still resolve from Debian security repositories at build time.
Keep the image digest as the authoritative release artifact.

`release.toml` uses the installed RK schema 2 and explicitly publishes
`fleury-v{version}` and `fleury_web-v{version}` tags. Those tags trigger
[the Pad workflow](../../.github/workflows/fleury-pad.yml). RK pushes a tag before
publishing its package, so this is a source-tag integration, **not proof that
pub.dev publication has finished**. The Pad uses that commit's source directly.
RK still owns package release; GitHub Actions owns container verification and
staging deployment. No new RK target or lifecycle hook is needed.

## Local image qualification

From the repository root:

```sh
docker build --platform linux/amd64 -t fleury-pad:staging \
  -f experiments/fleury_pad/dartpad/Dockerfile .
python3 experiments/fleury_pad/dartpad/container_check.py
python3 experiments/fleury_pad/dartpad/startup_check.py --image fleury-pad:staging
```

The build runs static analysis, checkpoint/import policy checks, real process
watchdog tests, and browser handoff unit tests. The container check starts the
image as UID 10001 with a read-only filesystem, a 512 MiB temporary volume,
1 CPU, 2 GiB memory, no Linux capabilities, and a process limit. It exercises
the actual API, checks graceful SIGTERM shutdown, resumes an accepted checkpoint
in a fresh process, deliberately freezes DDC, verifies deadline termination, and
resumes again after replacement. It then removes its container. The startup
check separately delays the analyzer to verify that editor assets are available
and compilation can queue, then stalls initialization without any API request
to verify that the independent deadline still terminates the service.
The runtime SDK, precompiled host and dependencies remain root-owned in Cloud Run
as well. Local `run.py` continues to run source when no compiled host is present.

These measurements are Docker on the developer's machine, including amd64
emulation where applicable. Measure native Cloud Run cold starts and peak
memory separately before tuning allocation or buying warm instances.

## Local qualification on September 25, 2026

The Linux amd64 image passed nine real API contract tests with the original
2 CPU / 4 GiB allocation. This does not qualify the smaller deployment profile.
Graceful shutdown exited cleanly. An accepted reload checkpoint worked after a
fresh service/worker start. Freezing the actual DDC worker caused service exit
124 after 24.5 seconds; another fresh process continued from the accepted
checkpoint. The image build also passed policy checks, four supervisor tests,
and eleven browser handoff tests. The actual container-hosted browser editor
also ran and hot-reloaded a changed heading while retaining count 1 and a draft,
with no browser console errors. Five mocked deployment tests cover private
access, immutable artifacts, canonical ID-token audiences, failed smoke tests,
and concurrent candidate detection; those are not live Cloud Run evidence.

Observed startup was 15.6–21.5 seconds and warm memory about 1.3 GiB under local
Docker amd64 emulation. These values are **not** Cloud Run performance estimates.

## Smaller allocation qualification on September 26, 2026

The same runtime image (`sha256:a23c6d57310afc96e03616ce90cd6e66f41c38e10d18f65182a2a81a2df45eaf`,
build `395ef1cabf3c468b`) passed the nine actual API tests with **1 CPU / 2 GiB**.
Memory after the API sequence was 1.319 GiB; this is an observation, not a peak
memory guarantee. Graceful shutdown, reload across a fresh process, forced DDC
failure (termination after 24.6 seconds), and reload after replacement all passed.
The temporary test container was removed. Five mocked deployment tests also
passed with assertions for zero minimums, both one-instance maximums,
instance-based billing, and disabled startup CPU boost.

Local amd64-emulated startup took 33.9, 38.6, and 35.8 seconds. Cloud Run's HTTP
timeout is now 60 seconds to leave room for startup; compiler work still has its
25-second process deadline. Native Cloud Run cold starts, actual scale-to-zero,
billing behavior, and overload handling had not been measured at this stage.
See the later hosted trial sections for cloud startup and scale-to-zero results. These checks reused
the existing image because the changes affect deployment settings and the local
resource envelope, not compiler code. The release workflow will build and test a
fresh image from the source it deploys.

## Scale-to-zero latency trial

The initial September 27 hosted trial used the **1 CPU / 2 GiB, minimum zero,
maximum one** profile, with instance-based billing and startup CPU boost off.
The September 28 integration below retains those caps and enables startup boost.
The approved dedicated project is `fleury-pad-20260927` in `us-central1`.
Start with private IAM access and measure this baseline before changing memory,
billing mode, startup CPU boost, or frontend hosting.

Use the bounded probe after deployment:

```sh
python3 experiments/fleury_pad/dartpad/measure_latency.py \
  --project "$FLEURY_PROJECT" --region "$FLEURY_REGION" \
  --label after-deployment > /tmp/fleury-pad-after-deployment.json
```

The probe uses the authenticated user's development ID token by default. Pass
`--invoker-account` for service-account impersonation and a canonical audience.
It checks that the service is private, fetches build metadata as its first HTTP
request, compiles the bundled example, and performs three successive reloads.
Reports separate request round-trip time, server compile time, and response size;
they never include tokens, compiled source, or checkpoint bodies. These are HTTP
measurements from the caller, not browser time-to-interactive measurements.

For an idle trial, close browser tabs/proxies that may send requests and leave the
service untouched. Observe instance count through Cloud Monitoring, rather than
polling `/healthz`, which would keep the service awake. Once the instance count
has reached zero, repeat with `--label after-idle`, then immediately repeat with
`--label warm`. Record the zero-instance observation and correlate the first
request timestamp with the Cloud Run startup logs. The probe deliberately leaves
`coldStartConfirmed: false`; an idle delay or a slow request alone does not prove
a cold start. Retain the deployment revision/build ID with the measurements.

After the API measurements, use the authenticated browser proxy below to check
counter/draft preservation through a reload, error recovery, and restart. Report
native hosted evidence separately from the local Docker/emulation measurements.

## Strict memory trial on September 27, 2026

The earlier Docker runs allowed the engine's default swap allocation. They are
not proof of a strict 2 GiB physical-memory envelope. `container_check.py` now
uses `--memory=2g --memory-swap=2g`, records the final OOM/exit state, and can save
HTTP timings with `--latency-report`. The default test architecture remains
linux/amd64; `--platform linux/arm64` is a separate native control for this Mac.

The initial fresh image passed all nine API tests, but exposed a SIGTERM race:
the supervisor signalled the entire group before the host could send its analyzer
shutdown message. The supervisor now signals the API first, then retains its
bounded final process-group cleanup. A regression test failed on the original
behavior and passed with the fix. Both rebuilt images passed static analysis,
checkpoint/import checks, fourteen Python checks, and eleven browser handoff checks.

With swap disabled, the rebuilt **amd64 image under local emulation** ran the
latency sample successfully but was OOM-killed during subsequent completion tests.
Its sample startup was 41.5 seconds; these timings do not qualify native Cloud Run.
The image ID was
`sha256:e472174db850b4d48f7ad63c9623824552b39c979fd4d11b72454f8cad19971b`.
See [the failed emulated run](dartpad/evidence/2026-09-27-local-amd64-emulated.json).

The **native ARM64 control** passed all nine API checks, graceful shutdown,
checkpoint continuation across replacement, forced worker termination after
24.7 seconds, and subsequent reload recovery, also at **1 CPU / 2 GiB with no
swap**. Peak cgroup memory during the initial API sequence was 1,810,771,968 bytes
(about 1.69 GiB); steady memory afterward was 1.082 GiB. Startup took 19.1, 18.9,
and 17.9 seconds. After readiness, the first sample compile took 886 ms round-trip
and the three reloads took 332, 292, and 264 ms. This is local HTTP evidence, not
browser responsiveness or native amd64/Cloud Run qualification.

The native image was
`sha256:910735c5d95545a3f6c3bb086bbf2696a454e4bfb9dbfb9de7a5b81a548d4e84`,
build `d39c4219f1583aad`. See [the native report](dartpad/evidence/2026-09-27-local-arm64.json).
All temporary test containers were removed. The selected hosted allocation is
unchanged. These local results preceded the hosted trial below; the ARM64 pass
does not erase the emulated run's failure.

## Hosted trial on September 27, 2026

The private service is deployed in `fleury-pad-20260927/us-central1`. Its runtime
identity has no project-wide roles and can read only the dedicated checkpoint
secret. Anonymous `/api/build` requests return 403. No public invoker binding,
paid load balancer, Cloud Armor policy, database, or warm minimum was added.

The first working baseline is revision `fleury-pad-staging-00003-gax`, build
`395ef1cabf3c468b`, registry manifest digest
`sha256:fed94dbc124d35187e4aad27a8e840ad30b996539063e0ba43c065991ec7c4bc`.
This is distinct from Docker's local image/config digest. The deployed source
label is `227e387b-dirty-20260927`; it represents the trial worktree, not a release.

All nine API contract tests passed through Google's authenticated loopback proxy.
Cloud Run reserves some external paths ending in `z`, so the hosted mode asserts
that `/healthz` returns the frontend's 404; internal startup/liveness probes still
reach `/healthz` and pass. HTML/preview security headers are tested normally.
[Reserved URL paths](https://docs.cloud.google.com/run/docs/known-issues#reserved-url-paths).

```sh
FLEURY_PAD_URL=http://127.0.0.1:8080 FLEURY_PAD_CLOUD_RUN_PROXY=1 \
  python3 experiments/fleury_pad/dartpad/test_backend.py
```

In the real browser, a hosted compile mounted the example. Changing its heading
and hot-reloading preserved count 3 and `Keep this draft`; Restart then reset the
count to 0 and cleared the draft. No browser warning/error logs were observed.
The browser compiled in 632 ms, reloaded in 701 ms, and restarted in 661 ms as
reported by the server; these are not complete browser interaction timings.

[The warm HTTP sample](dartpad/evidence/2026-09-27-cloud-warm.json) measured a
739 ms compile and 716–808 ms successive reloads from the developer's machine.
The baseline passed native amd64 API tests under 2 GiB with no logged OOM/runtime
error. Cloud Monitoring's largest sampled mean was about 1.09 GiB at this stage;
minute samples are **not a peak-memory bound**.

[The natural idle trial](dartpad/evidence/2026-09-27-cloud-cold-baseline.json)
confirmed both active and idle instance counts were zero at 18:07 UTC, after the
last request at 17:50:13 UTC. The next reload triggered a new instance and took
48.3 seconds round-trip, including 1.5 seconds of server compile work. The accepted
checkpoint from the prior process still worked. Subsequent reloads took
719–980 ms. This exposed a startup problem, not a need to buy a warm minimum.

The browser request timeout now allows 65 seconds, covering Cloud Run's
60-second request window. This does not increase the compiler's independent
25-second work deadline. The prior 30-second browser timeout could abandon a
valid cold request from an editor left open while the service scaled down.

## Startup optimization

A native ARM64 local startup profile at 1 CPU / 2 GiB spent 11.5 seconds before
entering the host's `main`, then 2.4 seconds initializing the analyzer. Compiling
the HTTP host ahead of time reduced the same local sequence from about 14 seconds
to 2.8 seconds, and all nine API checks still passed. This profile is not Cloud
Run performance evidence.

The Dockerfile now builds `bin/server` with `dart compile exe`. The supervisor
runs that executable in the image and retains source execution for local
development. The host takes the SDK path from `DART_SDK`, because its executable
now lives in the application directory. DDC and the analyzer still use the same
pinned official SDK and upstream worker code; no browser protocol changes are
needed.

The exact optimized AMD64 image passed the full strict **1 CPU / 2 GiB, no swap**
qualification under local emulation, including all nine API checks, graceful
shutdown, checkpoint continuation, deliberate worker failure and recovery.
Startup was 5.4, 4.8 and 5.3 seconds; API-test cgroup peak was 1,604,976,640 bytes
(about 1.49 GiB), and memory afterward was 799 MiB. This resolves the earlier
emulated run's OOM failure for this test sequence, not for every possible input.
See [the optimized local report](dartpad/evidence/2026-09-27-local-amd64-aot.json).

The verified image is deployed as revision `fleury-pad-staging-00006-guy`, build
`8ba98d0bfec4daad`, registry manifest digest
`sha256:ae637c74863e6874f605582c0898472fc5a0135fca23ade74a1135c990395194`.
It passed the hosted compile/reload smoke test before promotion, then all nine
API contract tests again. Native Cloud Run deployment startup to application
readiness fell from 44.5 seconds to 8.8 seconds at the same resource allocation.
Deployment readiness is distinct from an end-to-end cold request.

[The controlled restart report](dartpad/evidence/2026-09-27-cloud-aot-restart.json)
confirmed zero instances at 18:13 UTC after a temporary suspension. Restoring
automatic mode started the optimized server, which became ready in 8.3 seconds
before the next measured request. Its accepted checkpoint survived replacement;
the subsequent reload took 1.5 seconds and warm reloads took 706–879 ms. **That
1.5-second request was prewarmed, not a complete cold request.**

[The later natural-idle test](dartpad/evidence/2026-09-27-cloud-cold-aot.json)
measured the optimized image at 23:04 UTC without changing scaling or warming the
service first. The first `/api/build` request took **8.329 seconds**, followed by
**1.839 seconds** for the first compilation: **10.168 seconds** combined. The
request, automatic instance-start, and application-ready logs share the same
instance ID. Three subsequent reloads took 636–770 ms. This is one confirmed cold
HTTP sample; it excludes editor assets, browser evaluation and preview mounting.

[The cold-start investigation](COLD_START.md) records an isolated local comparison
of Dart's JIT and official AOT analyzer, plus options for reducing startup and
letting the editor open independently. Those options were not deployed at that point; the September 28 integration below
records their implementation and measured result.

Both service and revision caps are verified at one, both minimums at zero,
automatic scaling is restored, and the temporary candidate tag is removed.
[The trial record](dartpad/evidence/2026-09-27-cloud-trial.json) summarizes the
configuration and API evidence. A final browser check on the optimized revision
changed the heading while retaining count 1 and `State survives reload`; the
server reported a 561 ms reload and no browser warning/error logs were observed.
The largest optimized-revision Cloud Monitoring memory sample mean was
0.54 GiB, with no logged OOM/runtime error. This remains a sampled observation,
not a peak-memory guarantee.

## Startup integration on September 28, 2026

The official SDK AOT analyzer replaces the JIT launcher. The HTTP host binds
before starting language services, and a shared readiness barrier holds compiler
requests until initialization completes. An independent process deadline still
bounds initialization after HTTP becomes available. `/healthz` now means the host
can serve assets and accept bounded work; the `ready` log records analyzer
readiness separately from `http_ready`.

The browser bundles its sample source and creates Monaco immediately. Compiler
metadata is fetched by language-service requests and retried after failure;
restoring a draft no longer depends on `/api/build` or `/sample.dart` succeeding.
This separates editor usability from analyzer readiness, but the editor assets
still come from Cloud Run and therefore still wait for infrastructure startup.

The exact image is `sha256:4aa12ac9b9b8c1ba4a8b3bad8518f6b05fca860b33f3adc2676ac965adf6d5ce`,
build `ecd42e145c5b0e2c`. It passed all nine API checks, graceful shutdown, checkpoint
continuation, forced DDC failure/recovery, and the new delayed/stalled analyzer
checks locally at 1 CPU / 2 GiB without swap. The API-sequence cgroup peak was
754,421,760 bytes; this is a workload-specific result, not a bound for all source.

The no-boost revision `fleury-pad-staging-00011-nez` initialized the analyzer in
3.706 seconds. With the same image and temporary startup boost, revision
`fleury-pad-staging-00013-qil` measured 2.593 seconds. These are one deployment
sample per configuration, not complete visitor latency or percentiles. The
boosted revision passed all nine hosted API checks. A browser hot reload changed
the heading while retaining count 6 and `Draft survives startup changes`, with
no warning/error logs; the server reported 585 ms for that reload.

A separate local browser check made compiler discovery return 503. The editor
remained editable, recovered its saved source after a page reload, and compiled
that source when the connection was restored and Run was retried. No page reload
was needed to recover the connection. This used the native local SDK after the
local Docker daemon became unavailable; the image qualification above had
already completed successfully.

The service remains private, with 1 steady CPU / 2 GiB and both service/revision
minimums zero and maximums one. CPU boost is explicitly selected in the release
workflow; GitHub deployment access remains disabled.

[The final natural-idle sample](dartpad/evidence/2026-09-28-cloud-cold-startup-boost.json)
confirmed both instance-count states at zero before sending any request. The
new automatic instance's logs match the first request by instance ID. The first
connection took **2.616 seconds**, followed by **1.314 seconds**
for compilation: **3.931 seconds** combined, versus 10.168 seconds in the
previous confirmed cold sample. Subsequent reloads took 493–578 ms.
This is one HTTP sample, not a percentile or a complete browser interaction time;
editor downloads and preview mounting are excluded.
The 493–578 ms reloads immediately after startup still fall within the CPU boost
window. A [separate steady-state sample](dartpad/evidence/2026-09-28-cloud-steady-warm.json),
more than three minutes later, measured 601–857 ms reloads at one CPU.

See [the startup trial record](dartpad/evidence/2026-09-28-cloud-startup-trial.json),
[local qualification](dartpad/evidence/2026-09-28-local-startup-aot.json), and
[startup fault checks](dartpad/evidence/2026-09-28-startup-faults.json).

## Request and process boundaries

- Only six upstream methods are exposed: compile, reload, analyze, complete,
  format, and documentation. No AI, WebSocket, pub, or arbitrary command routes.
- Source is at most 64 KB and the request body at most 2.1 MB. Offsets are checked.
  Dart's parser checks all import/export URIs, including inactive conditional
  branches. Relative/file/network imports, URI traversal and multi-file parts
  are rejected. Browser Dart libraries and bundled Fleury/web packages remain.
- Reload kernels are wrapped in an HMAC-SHA256 envelope bound to the build and
  a 24-hour expiry. Only authenticated kernels reach DDC. Every replica uses the
  same 32-byte-or-longer key from a pinned Secret Manager version; no sticky
  sessions are needed. The envelope is not encryption or user authentication.
  Key rotation invalidates existing checkpoints and requires app restart.
- At most eight API requests are admitted per instance. An independent Python
  supervisor observes a private control pipe. The HTTP host has 120 seconds to
  open its port. Analyzer initialization then has a separate 25-second deadline,
  even if no API request arrives. Accepted API work has 25 seconds including
  analyzer readiness, queueing and body parsing. A stalled service or compiler
  causes the supervisor to kill the entire process group and exit. Cloud Run
  replaces failed instances. Idle body reads time out after five seconds.
- Logs record method, duration, build, readiness and deadline failures; the host
  does not log source, checkpoint bodies, keys or authentication tokens.
- The editor rejects stale builds. A deployment can require a page refresh;
  drafts remain in browser storage. Preview failures or rejected/expired
  checkpoints offer Restart. Compile errors preserve the last accepted app.

Cloud Run's [HTTP timeout does not terminate application work](https://docs.cloud.google.com/run/docs/configuring/request-timeout).
The watchdog is therefore separate from the 60-second Cloud Run request timeout.
The HTTP timeout allows room for a cold start; accepted compiler work still has
its own 25-second process deadline.
The [container contract](https://docs.cloud.google.com/run/docs/container-contract)
requires binding to `0.0.0.0:$PORT` and allows ten seconds for SIGTERM shutdown.
The host listens only after initialization, exposes `/healthz`, and drains on
shutdown; the supervisor kills remaining children within eight seconds.

## Provision the staging environment

Choose the Fleury Google Cloud project and region explicitly. Do not reuse an
unrelated active CLI project. The deployment script always requires both flags.
Provision these once, with the intended owner's approval:

1. Enable Cloud Run, Artifact Registry, Secret Manager, IAM Credentials, and
   Workload Identity Federation APIs in the Fleury project.
2. Create a Docker Artifact Registry repository in the chosen region.
3. Create a dedicated runtime service account. Give it no project-level data or
   administrative roles. Its only needed grant is access to the single checkpoint
   secret. It does not need storage, pub.dev, or build credentials.
4. Generate at least 32 random bytes and store their **base64 text** in a Secret
   Manager secret. Use a numeric version such as `fleury-pad-checkpoints:1`.
   Never bake this value into an image, source file, build argument or workflow.
5. Configure GitHub Workload Identity Federation for this repository and the
   `fleury-pad-staging` environment. Restrict its subject/repository and allowed
   refs; do not grant deployment credentials to pull requests. The deployer needs
   registry write, Cloud Run deployment/IAM inspection, permission to act as the
   dedicated runtime identity, and permission to invoke the private staging
   service. The script's `--invoker-account` additionally requires permission to
   impersonate that identity to mint an audience-bound ID token (including when
   the workflow impersonates its own deployment account).
6. Set repository variable `FLEURY_PAD_STAGING_ENABLED=true` only when configured.
   Create GitHub environment `fleury-pad-staging`, with these environment variables:
   `FLEURY_PAD_PROJECT`, `FLEURY_PAD_REGION`, `FLEURY_PAD_REPOSITORY`,
   `FLEURY_PAD_RUNTIME_ACCOUNT`, `FLEURY_PAD_DEPLOY_ACCOUNT`,
   `FLEURY_PAD_CHECKPOINT_SECRET`, `FLEURY_PAD_WIF_PROVIDER`.

The workflow always builds/tests on matching pull requests, release tags and
manual dispatch. Cloud authentication happens **after** image qualification, in
a separate job, and only when explicitly enabled. The verified image is carried
between jobs as a one-day artifact, pushed once, then deployed by digest.

## Cost policy

Fleury Pad prioritizes minimal idle cost and limited capacity during traffic
spikes. Deployment uses 1 CPU, 2 GiB, concurrency 8, and automatic scaling from
zero to a configured maximum of one instance. Both service and revision minimums
are explicitly zero and both maximums are one, so an earlier deployment setting
cannot silently leave a warm minimum or larger revision limit. The selected
profile enables startup CPU boost: two CPUs during startup and ten seconds
afterward, then one CPU. It does not add a warm minimum. Excess demand can receive
busy responses instead of a larger configured pool. The deploy helper enables
boost explicitly with `--cpu-boost` and verifies the effective setting.

Instance-based billing (`--no-cpu-throttling`) removes the per-request charge.
An instance is billed for its whole lifetime, including short idle periods before
scale-down; minimum zero does not mean immediate shutdown. With sparse traffic,
most of the month can have no running compiler. Registry storage and any other
provisioned services can still incur idle costs.

This is a compute-capacity policy, **not a hard total-spend ceiling**:

- Cloud Run can temporarily exceed its configured maximum. Tagged revisions
  without a traffic split do not count toward the service maximum; private
  candidate smoke tests can therefore overlap the serving revision. Each
  revision still has its own configured maximum of one. Retire unused candidate
  tags before any public rollout.
- Sustained requests can keep the compiler alive all month. At the published
  us-central1 instance-based rates on September 26, 2026, one 1 CPU / 2 GiB
  instance running for 30 days costs about US$57 in CPU and memory before free
  allowances, discounts, and other charges. This is a usage scenario, not a
  maximum bill. Measure whether the smaller allocation meets hosted latency and
  memory needs before considering more resources.
- Outbound traffic, logging, and artifact storage are separate charges. Before
  anonymous access, qualify traffic and response-size limits, logging volume
  controls, and a compilation suspension procedure. An in-memory request limit
  resets on replacement and is not a monthly budget.
- The monthly target is **CA$20**, matching the approved billing account's CAD
  currency. On September 28, 2026, the project-scoped budget `Fleury Pad monthly
  total - alerts` was created and read back successfully. It includes all
  services in `fleury-pad-20260927`, counts gross costs before credits, and sends
  default billing-contact email alerts at CA$10, CA$16, and CA$20 each calendar
  month. Other projects and existing account-wide budgets are unchanged.
- **Automatic cutoff is configured.** On September 28, 2026, the separate
  `Fleury Pad Cloud Run - monthly cutoff` spend-cap budget was created in the
  Cloud Console and its status verified as **Configured**. It is scoped to
  `fleury-pad-20260927` and Cloud Run only, with a CA$20 calendar-month target
  before savings. The console verified email alerts at CA$10, CA$16, and CA$20
  to billing admins/users and project owners; these recipients and thresholds
  are fixed. Cutoff budget ID: `adc3e651-ee5b-4a4a-9ab6-ae2c6f107369`.
- Manage this preview cutoff through **Billing > Budgets & caps** in the Cloud
  Console. The public v1/v1beta1 Budget APIs and installed CLI expose no cutoff
  field; do not replace the native spend cap with an alerts-only API budget.
  At configuration time, the console showed CA$0.14 against the Cloud Run cap
  and CA$0.15 against the whole-project alert budget. These are delayed reported
  costs, not a final invoice or a current-cost guarantee.
- A native spend cap pauses Cloud Run until manually lifted, but enforcement is
  delayed and any overages are billed. It does not cap Logging, registry storage,
  or other services. Keep the whole-project alert budget to monitor those costs.
  Neither the alerts nor the service-scoped cutoff guarantees a CA$20
  maximum invoice. Email delivery and actual cutoff enforcement have not been
  exercised; the current verification covers saved alerts and the configured cutoff status.

Do not provision a paid load balancer or Cloud Armor as part of this initial
private deployment. Public access remains gated on an accepted cost policy and
abuse controls as well as the security requirements below.

References: [Cloud Run billing](https://docs.cloud.google.com/run/docs/configuring/billing-settings),
[pricing](https://cloud.google.com/run/pricing),
[maximum instances](https://docs.cloud.google.com/run/docs/configuring/max-instances),
and [spend-cap limitations](https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps).

## Suspend and resume the private compiler

With no tagged routes, suspend the service without deleting its image or secret:

```sh
gcloud run services update fleury-pad-staging \
  --project "$FLEURY_PROJECT" --region "$FLEURY_REGION" --scaling=0
```

Restore the full cost profile explicitly:

```sh
gcloud run services update fleury-pad-staging \
  --project "$FLEURY_PROJECT" --region "$FLEURY_REGION" \
  --scaling=auto --min=0 --max=1
```

The trial observed that restoring `--scaling=auto` alone reset the service maximum
to 20. The revision maximum remained one, but the service limit still needed to
be restored. Always verify both effective limits after a scaling-mode change.
The deployment helper specifies both limits and now rejects an unexpected
resource/scaling profile before smoke requests or promotion. Nine mocked
deployment tests include this observed failure mode.

Suspension is a manual operational control, not a dollar-based cutoff. Requests
to revisions kept alive only through tags can bypass service suspension, so
remove unused tags. [Manual scaling](https://docs.cloud.google.com/run/docs/configuring/services/manual-scaling).

## Deploy, verify and roll back

For a verified image already pushed to Artifact Registry:

```sh
python3 experiments/fleury_pad/dartpad/deploy.py \
  --project "$FLEURY_PROJECT" --region "$FLEURY_REGION" \
  --image "$FLEURY_IMAGE_DIGEST" \
  --runtime-account "$FLEURY_RUNTIME_ACCOUNT" \
  --checkpoint-secret fleury-pad-checkpoints:1 \
  --invoker-account "$FLEURY_DEPLOY_ACCOUNT" --cpu-boost --promote
```

The default service is `fleury-pad-staging`. The script refuses an existing public
service and explicitly enables the invoker IAM check. For an existing service,
it deploys a `candidate` revision with no default traffic, verifies compilation
and reload through its authenticated tag URL, then promotes only on success.
For the first deployment there is no previous revision; the service is still
private. Omit `--promote` to inspect an existing service's candidate first.
A failed candidate remains available for diagnosis and does not replace previous
traffic. Successful promotion removes its temporary `candidate` tag; the receipt
contains the serving URL, revision, build and previous traffic assignment. Save
it with release evidence. Absolute executable and supervisor paths are specified
in both the image and deployment command; the first Cloud Run revision failed
before application execution when its entrypoint relied on PATH resolution.

ID tokens use the canonical service URL as their audience even when calling a
revision URL. The service trusts Cloud Run routing/IAM and checks browser POST
origins against the forwarded host. Outside Cloud Run an exact explicit
`FLEURY_PAD_ORIGIN` is required for non-loopback listening. Host/origin checks are
not authentication. Testers need Cloud Run Invoker access. The private deployment
explicitly allows `http://127.0.0.1:8080` as `FLEURY_PAD_PROXY_ORIGIN`, because
Google's proxy preserves browser Origin while rewriting Host. Use:

```sh
gcloud run services proxy fleury-pad-staging \
  --project "$FLEURY_PROJECT" --region "$FLEURY_REGION" --port 8080
```

Open `http://127.0.0.1:8080` (not `localhost`) in the browser. Other origins
remain rejected. Remove this staging-only setting before public rollout,
or configure an authenticated browser gateway for remote testers.

Rollback without rebuilding:

```sh
gcloud run services update-traffic fleury-pad-staging \
  --project "$FLEURY_PROJECT" --region "$FLEURY_REGION" \
  --to-revisions "$PREVIOUS_FLEURY_REVISION=100"
```

[Cloud Run revision traffic](https://docs.cloud.google.com/run/docs/rollouts-rollbacks-traffic-migration)
is the rollback mechanism. Runtime state is local to the browser; a different
compiler build may require refresh/restart even after rollback.

## Before anonymous public access

Staging is useful evidence, not completion of public production readiness:

- Verify Cloud Run cold/warm latency, peak memory, concurrent editors, idle scale
  down, worker failure replacement and checkpoint handoff between replicas.
- Add and test public abuse controls, monitoring/alerting, and a budget policy.
  Per-instance admission and instance limits alone are not per-user rate limits.
  Keep the runtime identity and cloud project isolated from unrelated services.
- The editor lives in the docs site. Serve its executable app frame from the
  compiler site and qualify that separate site/process boundary, including an
  infinite-loop recovery test. Configure `FLEURY_PAD_DOCS_ORIGIN` to permit only
  the docs origin for API requests and frame embedding. The existing opaque
  sandbox protects editor DOM/storage and blocks preview network requests
  other than the loading-data guide's image service, but
  same-site browser CPU hangs can still affect the editor. Do not embed this
  preview on the main documentation origin and assume CPU isolation.
- Review compiler filesystem/network containment and dependency vulnerabilities
  for hostile anonymous traffic. URI restrictions and signed checkpoints reduce
  exposure; they do not make compiler exploits impossible. No outbound network
  deny policy or per-request OS sandbox is claimed by this container.
- Test deployment while an editor is open, expired/key-rotated checkpoints,
  rollback, mobile layout, and supported browsers through the actual hosted UI.

Opening public access, choosing a domain, and configuring GitHub deployment
credentials remain explicit follow-up rollout actions.

## Public docs compiler, September 30, 2026

The docs' editable demos use this service, so it is now public. The verified
image `sha256:d89e66a073c70cd74e58eb2e0a3a78a031ef8d2bfb934235f3fe6bab9a67673b`
(build `8684acc4465f2c79`, protocol 3, source `7ac2cbe7`) serves as revision
`fleury-pad-staging-00015-vuv`, released with:

```sh
python3 experiments/fleury_pad/dartpad/deploy.py \
  --project fleury-pad-20260927 --region us-central1 \
  --image "$FLEURY_IMAGE_DIGEST" \
  --runtime-account fleury-pad-runtime@fleury-pad-20260927.iam.gserviceaccount.com \
  --checkpoint-secret fleury-pad-checkpoints:1 \
  --docs-origin https://danreynolds.github.io --cpu-boost --promote --public
```

`--public` grants `run.invoker` to `allUsers` and drops the loopback proxy
origin; the invoker IAM check stays on. Every other setting is the private
profile: 1 CPU / 2 GiB, minimum zero, maximum one instance, concurrency 8, the
CA$20 Cloud Run spend cap, and the whole-project budget alerts. Release later
images with `--public` too; the release workflow passes it when the
`FLEURY_PAD_PUBLIC` repository variable is `true`. Without it, `deploy.py`
refuses the now-public service instead of making it private. The Pages build
reads the compiler origin from `FLEURY_PAD_COMPILER_URL`
(`https://fleury-pad-staging-vbalblwk3q-uc.a.run.app`).

Verified before and after the release:

- The exact image passed `container_check.py --guides` locally: the eleven API
  tests, all 125 docs projects, graceful shutdown, checkpoint continuation, and
  recovery from a frozen compiler worker. Its cgroup peak was 1.17 GB of 2 GiB.
- Anonymously, `/api/build` reports protocol 3. The docs origin's preflight
  and compiles succeed with its CORS headers; another origin's compile gets 403.
  The frame's CSP limits embedding to the docs origin, and its runtime and font
  are served build-versioned and immutable.
- All 125 docs projects compiled from the docs origin in 136 seconds, one
  instance, sequentially. A hosted-compiled demo ran in the hosted frame.

Still open from the list above: per-user rate limits and abuse controls beyond
per-instance admission, monitoring beyond the budget alerts, and a hang test of
the embedded frame. Demand beyond one instance receives busy responses; the
docs keep working, because every demo stays its prebuilt preview until a reader
runs an edit.

To withdraw public access, remove the binding (published demos then report a
connection error on Run), and unset `FLEURY_PAD_COMPILER_URL` so the next docs
build makes demos read-only:

```sh
gcloud run services remove-iam-policy-binding fleury-pad-staging \
  --project fleury-pad-20260927 --region us-central1 \
  --member=allUsers --role=roles/run.invoker
```

Suspending the service with `--scaling=0` (above) also stops all compilation.
Roll back a release by routing traffic to the previous revision
(`fleury-pad-staging-00013-qil` was the last private one).

## Release from main, October 1, 2026

After the launch fixes merged ([#292](https://github.com/danReynolds/fleury/pull/292)),
the docs' Run buttons needed a compiler built from the same packages as the
prebuilt demos. The image built from `fb2e4154` (build `9cf3f0d7e037c0f1`,
protocol 3, digest
`sha256:66ce5d1c7b49b55d4122a603af485e01470d46c0e469f559e70e6d507991a612`) now
serves as revision `fleury-pad-staging-00017-yoq`, released with the public
command above (`deploy.py … --cpu-boost --promote --public`).

Verified before and after the release:

- `container_check.py --guides` on the exact image: the API tests, graceful
  shutdown, and all 129 docs projects compiled, with a cgroup peak of 1.19 GB of
  2 GiB. `startup_check.py` passed its queued-compilation and stalled-startup
  checks.
- `deploy.py` verified the candidate revision through its tag URL before
  promoting it; the previous serving revision was `fleury-pad-staging-00015-vuv`.
- From the docs origin: `/api/build` reports the new build anonymously, the
  preflight and frame policy are unchanged, another origin's compile gets 403,
  and all 129 projects compiled in 134 seconds.
- On the published site, the home demo restored a saved draft, ran it, hot
  reloaded with its state kept, and reverted. The first reload after the deploy
  took about 10 seconds; later reloads take about a second.

Roll back by routing traffic to `fleury-pad-staging-00015-vuv`.
