# Fleury Pad

Fleury runs against a self-hosted copy of **DartPad's actual backend**,
with a small Monaco editor and Fleury browser preview. Source is compiled by
the official Dart development compiler; hot reload preserves the live widget
tree. No requests go to Google's public DartPad service.

The browser integration runs locally and on private Cloud Run staging in the
dedicated `fleury-pad-20260927` project. The trial uses 1 CPU / 2 GiB, scaling from
zero to one instance. Hosted API tests and browser reload/restart checks pass.
The editor opens while Dart tools initialize; the official AOT analyzer and
temporary startup CPU boost reduce startup work. Cost controls and public
readiness remain separate concerns.
The release-tag workflow is prepared but GitHub deployment access is not enabled.
See [deployment and trial evidence](DEPLOYMENT.md). The latest confirmed cold HTTP
sample took 2.62 seconds for the first response and 3.93 seconds through the
first compilation, versus 10.17 seconds combined previously. These are single
samples, excluding editor downloads and browser rendering.
The docs now have a dedicated Fleury Pad page at `/fleury/pad/`, linked from the
homepage, Start here navigation, and hot-reload guide. That page is the full Pad
workspace. Every docs demo that shows its code also uses Pad's editor and
compiler: the guides, concepts, Coming from Flutter, the home page, and the
widget reference.

## Docs integration

`/fleury/pad/` is the primary editor, inside the docs navigation. It uses the
same Monaco controller, API protocol, and sandbox handoff as the standalone
host, with a full-height code/app workspace, stateful hot reload, formatting,
source download, local drafts, site themes, and Code/App tabs on narrow screens.
The editor bundle loads on the Pad page and as demos approach the viewport.
Demo code is editable immediately, with no edit button. Previews remain
prebuilt, so reading a page makes no compiler requests; the first Run compiles
the reader's edit and replaces the prebuilt preview with a frame that matches
it: the docs theme, the FleuryMono font, and the example's exact grid. The
frame's runtime is named by build and cached by the browser, so later runs
download only the compiled edit. Revert returns to the prebuilt example.

For local development, start the authenticated Cloud Run proxy described in
[DEPLOYMENT.md](DEPLOYMENT.md), then from `website/` run:

```sh
npm ci
FLEURY_PAD_PROXY_TARGET=http://127.0.0.1:8080 npx astro dev --host 127.0.0.1 --port 4334
```

A local compiler (`dartpad/run.py`, below) works the same way:
`FLEURY_PAD_PROXY_TARGET=http://127.0.0.1:4346`. Open `/fleury/pad/` and run
the example, or edit any docs demo and press Run. The dev-only middleware forwards an
allowlist of API routes through that loopback proxy. It checks browser origins
before forwarding, and keeps authentication out of browser code. The sandbox
loads the runtime matching the hosted compiler build.

For published docs, configure `PUBLIC_FLEURY_PAD_COMPILER_URL` with the HTTPS
compiler origin. The Pages workflow reads it from the `FLEURY_PAD_COMPILER_URL`
repository variable. On the compiler, set `FLEURY_PAD_DOCS_ORIGIN` to the exact
HTTPS docs origin (for the current site, `https://danreynolds.github.io`). The
compiler permits that origin's API requests and frame embedding; no wildcard
CORS or browser credentials are used. `deploy.py --docs-origin` preserves this
setting on releases; the staging workflow defaults it to the current docs site
and accepts the `FLEURY_PAD_DOCS_ORIGIN` repository variable. User code stays in an opaque sandbox on
the compiler site. Its CSP blocks network access except to the image service
the loading-data guide fetches from (`picsum.photos`).

These settings do not grant anonymous Cloud Run access. The currently deployed
service is still private; the updated origin policy needs deployment alongside
the docs before public access is enabled. Missing compiler configuration leaves
the editor usable and reports a connection error when using language tools.

## Editable demo projects

Demos expose whole files, `#docregion`s, or declarations backed by complete
runnable Dart projects. Edits replace those regions in their original files;
imports and private declarations keep their normal Dart library boundaries.
Protocol version 3 adds bounded multi-file requests to the existing scheduler,
compiler, and language services. Single-file Pad requests still work unchanged.

The catalogue currently contains 125 projects: 59 guide, concept, and home
page demos, and 66 widget reference demos derived from the registry. Source
ranges are generated from the same canonical Dart examples used by the
prebuilt previews. See [the authoring guide](../../website/examples/GUIDE_PADS.md)
for adding or changing a demo. CI compiles every catalogue entry against the
deployable image. This integration is verified locally, where every project
compiles and runs in the docs; the hosted compiler must be redeployed from this
source (protocol 3, the docs font, and the frame's grid sizing) before published
editors can use it.

## Run locally

Install Dart **3.12.2**, Python 3, Node.js, npm, and Git. A matching Flutter
installation's Dart SDK works too; this build uses no Flutter engine or widgets.
From this repository root:

```sh
export DART_SDK=/absolute/path/to/dart-sdk
python3 experiments/fleury_pad/dartpad/setup.py
python3 experiments/fleury_pad/dartpad/run.py
```

Open <http://127.0.0.1:4346>. Set `PORT` to select another loopback port. Setup
fetches the exact upstream revision, applies the saved patch, resolves locked
packages, builds matching runtime/dependency bundles, precompiles the starter,
and bundles Monaco. Exact starter runs reuse this build artifact through the
normal compilation endpoint, with a newly signed reload checkpoint per request.
Edited source still goes through DartPad. The starter can be served before
language services finish initializing; it does not eliminate container cold starts.
Generated files stay in ignored `.build/` and `node_modules/` directories.

Run the example, increment the counter, and enter a draft. Edit the heading or
button callback and press **Hot reload**. **Restart** runs the current code from
the beginning. Ctrl/Cmd+Enter runs initially and reloads a running app.
Ctrl+Space offers Fleury completions; Format uses DartPad's formatter. Editor
source is saved locally in the browser. The example entry point is
`Widget buildApp()`; the host owns browser mounting and reassembly.

Rerun setup and restart the service after changing the SDK, Fleury, bootstrap, or starter source.
Setup refuses unexpected edits in its generated upstream checkout instead of
resetting them. A build ID rejects checkpoints from another prepared build. Reload checkpoints
are authenticated; local startup generates an ephemeral key, so restarting the
local service requires restarting the preview app.

In another terminal:

```sh
python3 experiments/fleury_pad/dartpad/test_backend.py
# For a different port:
FLEURY_PAD_URL=http://127.0.0.1:4347 python3 experiments/fleury_pad/dartpad/test_backend.py
```

## What is reused and what we own

The upstream revision is recorded in [UPSTREAM.json](dartpad/UPSTREAM.json):
`70a62b1ebcf9d2b906ec564254bde02a543be895`. It supports our pinned Dart 3.12.2 SDK;
upstream main had already moved its SDK constraint to 3.13 during this evaluation.

[upstream.patch](dartpad/upstream.patch) adapts the upstream backend. It supplies
a prepared Fleury project, custom bootstrap, dependency summaries, supported
package names, a standalone SDK, and the SDK's AOT analyzer launcher. The analyzer
still uses the upstream protocol client; DartPad's compiler worker, scheduler,
and single-file API handlers remain in place. Our project adapter uses those
same workers with per-file compiler inputs and analyzer overlays. Its BSD license is retained in [LICENSE.dartpad](dartpad/LICENSE.dartpad).

Our [local host](dartpad/bin/server.dart) selects those hooks, serves assets, and
exposes only compilation, reload, analysis, completion, formatting, and symbol
documentation. DartPad's persistent DDC worker performs compilation. Requests
use temporary projects and the last accepted kernel checkpoint; no database or
per-visitor server process is needed. Packages are resolved at setup time.

Our [editor](dartpad/web/main.js) uses Monaco for code editing and the upstream
HTTP protocol for language services. The [preview](frame.js) applies DDC updates
and asks the [Fleury bootstrap](lib/bootstrap.dart) to call the public
`MountedApp.reassemble()` method. The browser host and terminal host share
`TuiRuntime.reassembleApplication()`, including animation and ticker resets. Submitted app code runs in a sandboxed browser iframe, not on the compiler
host. A failed compilation leaves the app and accepted checkpoint unchanged.

We are reusing the backend, not adopting DartPad's Flutter editor UI. The remaining
ownership is the Fleury preview, editor integration, fixed build preparation,
and the small upstream patch. The backend still brings optional AI/Redis-related
transitive dependencies even though those routes are not exposed. Its internal
`src` APIs and DDC protocol are not stable embedding contracts, so upgrades need
an explicit pin update and these integration checks. This is a good starting
point for avoiding a second compiler service implementation, not zero maintenance.

## Verified locally on September 24, 2026

Seven saved backend integration tests pass: compilation/reload/error recovery,
source diagnostics, Fleury completions/imports/documentation, formatting,
interleaved analysis requests, compressed browser assets, and local request
limits/build checks. `dart analyze bin` passes. The complete setup script also
succeeds when rerun against the saved checkout and locks.

Verified through the actual browser editor and local DartPad service:

- Ran the example and created counter value 3 plus a draft.
- Changed the heading, increment callback to add 2, and initializer to 10.
  Hot reload retained count 3 and the draft; clicking then produced count 5.
- Introduced an undefined identifier. Reload showed compiler diagnostics while
  the previous app stayed interactive and advanced to count 7.
- Fixed the source and reloaded from the last accepted checkpoint. Count 7 and
  the draft survived. Restart then produced count 10 and an empty draft.
- Displayed and accepted Fleury-specific editor completions, including TextArea,
  and applied Dart formatting through the editor.
- Triggered a build-time runtime error, saw Fleury render its error widget,
  then edited the source and ran the working example again.

Warm example compilation/reloads observed in this browser run were about
**130–175 ms**, measured inside the local service. These are macOS ARM64 results,
not cloud latency, cold-start figures, or a browser compatibility claim.

## Integrated reload lifecycle, September 25, 2026

The Pad no longer finds the build owner through a GlobalKey. Its browser mount
handle owns reassembly and completes only after the visual frame and deferred
accessibility update. Disposed/remote mounts and failed presentation reject the
operation. Terminal reload delegates to the same runtime lifecycle, so the
animation scheduler is reset in one place after the tree rebuild.

Both experimental editors share [preview.mjs](preview.mjs). Each update has an
operation ID; duplicate readiness messages, stale acknowledgements, messages
from replaced frames, and overlapping applications cannot commit a new checkpoint.
Only executable code and library names cross into the preview. The editor keeps
source/checkpoints outside it and commits the next checkpoint after the matching
successful acknowledgement. Compilation errors preserve the running app; an
application/reassembly failure invalidates reload and leaves Restart available.
Actual Dart hook errors remain readable across the JavaScript promise boundary.

API requests have a 30-second client wait limit; preview application has a
15-second acknowledgement limit. These recover ordinary missing responses, not
CPU-bound browser hangs. The subsequent container work adds independent server
process deadlines; public browser isolation remains a launch gate.

Validation for this integration:

- 33 core/runtime/animation/hot-reload-controller tests and 43 browser-host tests
  pass, including disposal and failed presentation during reload.
- 11 JavaScript handoff tests cover stale/duplicate responses, replaced frames,
  timeouts, runtime failures, and waiting for the framework reload future.
- Seven real DartPad backend contract tests pass against the rebuilt assets.
- Changed Dart files pass static analysis. The existing real-PTY native
  save-to-reload/hot-restart regression passes after resolving the profiling
  harness dependencies.
- In the actual Pad, an in-flight 120-second animation settled at its target on
  reload while the counter and draft survived. Repeated reloads invoked the
  state hook exactly once each. A rejected compile preserved the accepted app
  and checkpoint; fixing it continued from count 7 and the existing draft.
- A throwing `State.reassemble` produced `Bad state: reload hook failed`, disabled
  further reloads, and left Restart usable. Restart created fresh app state.

Run the handoff regressions with:

```sh
node --test experiments/fleury_pad/test_preview.mjs
```

## Hosting decision

The local adaptation supports proceeding with DartPad backend reuse. For a first
hosted version, keep one fixed SDK/Fleury build, stateless API calls, and matching
runtime assets packaged with the service. Deployment uses Cloud Run with zero
minimum instances, a configured maximum of one, 1 CPU / 2 GiB, and instance-based
billing. The priority is minimal idle cost and limited compute capacity under
load; this is not a hard total-spend cap. The deployment guide records remaining
traffic/logging exposure, the configured CA$20 Cloud Run cutoff, and whole-project alerts. The
[playground comparison](COMPARISON.md) records the wider research and tradeoffs.

The [deployment guide](DEPLOYMENT.md) describes the implemented image, signed
checkpoints, import policy, hard process deadlines, container tests and private
staging workflow. The release configuration now uses RK schema 2 with explicit
Fleury/Fleury Web tags; tag workflows verify one image and deploy that exact digest
only after staging is enabled. The private cloud trial is provisioned; GitHub
deployment credentials and automatic release deployment remain unconfigured.

Public access still needs hosted capacity/failure evidence, abuse controls,
monitoring, and preview-site/hang qualification. These remain launch gates;
passing local container tests does not establish public readiness.

## Earlier compiler-only proof

The original `prepare.py`, `server.py`, and `test_compiler.py` remain as the
standalone official-SDK experiment, using port 4345 and a textarea editor. The
DartPad setup above is the current evaluation path; run its setup again if
switching back from that older proof because both share generated `.build/` assets.
