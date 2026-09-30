# Fleury Pad: playground architecture comparison

Research date: September 24, 2026. This is a design recommendation based on
primary documentation, current public source, and the existing local Fleury
prototype. It is not a cloud deployment, load test, or security qualification.

The core choice holds up: use the official Dart development compiler on a
server and run Fleury in the browser. The surrounding first release can be
smaller than the earlier hosting proposal.

## Local implementation result

The subsequent [DartPad integration](README.md) uses the real upstream backend,
not just its design. A compatible pinned revision needs a 44-line addition and
four-line removal across three files to provide the Fleury template, bootstrap,
summaries, and standalone SDK. Compilation, reload, analysis, completion,
formatting, and documentation work through its existing handlers. Real browser
reloads preserve app state and recover after a rejected edit.

That evidence favors retaining the backend dependency and small explicit patch
for the next stage. A separate compiler-service reimplementation is unnecessary
for this evaluation. Internal API upgrades and unused transitive dependencies
remain maintenance costs; the local proof is not public-hosting qualification.

## Established playground patterns

| Playground | Observed approach | Implication for Fleury |
| --- | --- | --- |
| [DartPad](https://github.com/dart-lang/dart-pad/blob/main/pkgs/dart_services/README.md) | Stateless Dart API for compilation, analysis, completion, and formatting; pinned supported dependencies and prepared artifacts. | Closest reference for the language, compiler, and editor services. |
| [Kotlin Playground](https://github.com/JetBrains/kotlin-playground) | Editor sends code to a configurable compiler server; a custom server can include a library's own dependencies. Its JavaScript mode executes compiled code in a browser iframe. | Hosted compilation plus library-specific dependencies is an established pattern. |
| [TypeScript Playground](https://www.typescriptlang.org/dev/sandbox/) | Monaco and the TypeScript language service run in browser workers. | Client compilation is attractive when the existing compiler already supports that environment. |
| [Svelte Playground](https://github.com/sveltejs/svelte.dev/blob/main/packages/repl/src/lib/workers/compiler/index.ts) | Browser worker loads the requested Svelte compiler and compiles source; a separate worker bundles the preview. | Browser compilation follows the compiler's existing distribution model. |
| [Rust Playground](https://github.com/rust-lang/rust-playground#architecture) | Server backend uses containers for compilers and tools, with compilation/execution resource limits and prepared crates. | Fixed dependencies help, but running submitted native programs adds responsibilities Fleury can avoid. |
| [Go Playground](https://github.com/golang/playground/blob/master/sandbox.go) | Backend builds submitted source and invokes a separate sandbox execution path. | Useful operational reference; Fleury's browser renderer avoids hosting its application runtime. |

These are architectural comparisons, not claims that the playgrounds have
identical isolation, hot reload, dependency policies, or production topology.
The Go comparison uses current source, not its older Native Client blog post.
Kotlin's browser execution is visible in its
[JS executor](https://github.com/JetBrains/kotlin-playground/blob/master/src/js-executor/index.js).

## What DartPad specifically confirms

Its [compiler implementation](https://github.com/dart-lang/dart-pad/blob/main/pkgs/dart_services/lib/src/compiling.dart)
uses the SDK's DDC persistent-worker interface with one worker. Each compilation
gets a temporary project. Initial compilation includes a bootstrap; reload
compiles the editable main library and accepts the previous encoded kernel
checkpoint. Successful compilation returns JavaScript and a new checkpoint.

Its [browser integration](https://github.com/dart-lang/dart-pad/blob/main/pkgs/dartpad_ui/web/frame.js)
applies the update with `dartDevEmbedder.hotReload`, then invokes Flutter's
reassembly extension. Fleury's analogous extra responsibility is reassembling
its existing widget tree. Our local proof has demonstrated that part.

A long-lived compiler worker is shared infrastructure within an instance. It
does not require an application process or reserved server session per visitor.
The browser's running app and last accepted compilation checkpoint are enough
for our current reload protocol. Failed compilation must leave both intact;
failed application of an update must offer a clear restart.

DDC's generated representation is deliberately not a stable application ABI.
Keep the SDK, dependency summaries, browser runtime, bootstrap, and Fleury
versions together. That compatibility contract is a real requirement, even
with a simpler deployment. See the
[DDC support contract](https://github.com/dart-lang/sdk/blob/main/pkg/dev_compiler/README.md).

## Recommended smaller first release

1. **One supported compiler build.** Initially expose one Fleury/SDK combination.
   Preserve source and offer a restart when a deployment makes an old build
   unavailable. Keep the previous deployment for rollback. Seamless continuity
   across deployments and a historical version selector can come later. This
   deliberately trades cross-deployment runtime state for less version routing.
2. **One stateless HTTP service.** Compile, analyze, complete, and format against
   a prepared project. Use a single DDC worker and analysis process per instance
   as the starting point, with serialized/bounded work and measured capacity.
   No database, per-user VM, sticky sessions, WebSocket requirement, or separate
   queue service is needed for this design.
3. **Fixed dependencies and one source file.** Resolve the supported Fleury
   packages at build time. Avoid arbitrary pubspecs and per-request `pub get`.
   DartPad likewise limits imports to its
   [supported packages](https://dart.dev/tools/dartpad).
4. **One prepared deployment bundle.** The compiler image can initially also
   serve its matching runtime assets and preview shell with explicit build IDs.
   Keep execution isolated from the documentation/editor origin. Separate CDN
   or object-storage publishing is an optimization to add when measurements
   justify it, rather than a second release transaction on day one.
5. **Selective DartPad reuse.** Build a small Dart service using its compiler
   worker pattern and the SDK analysis server. Keep any adapted upstream code
   identifiable and pinned. The complete service is not a drop-in dependency:
   it has Flutter-specific templates, optional Redis/AI/WebSocket features, and
   its current [manifest](https://github.com/dart-lang/dart-pad/blob/main/pkgs/dart_services/pubspec.yaml)
   requires Dart 3.13, while our proof is pinned to 3.12.2. A compatible upstream
   revision or an explicitly tested SDK upgrade must be selected.
6. **A release workflow first.** Tie the container build/deploy/smoke test to the
   exact release produced by RK. A generic Cloud Run target can follow after
   that transaction is proven. There is precedent for release-triggered Pad
   deployments in the [Go Playground](https://go.googlesource.com/playground/+/refs/heads/master/README.md).

## Costs that cannot simply be removed

A public compiler processes untrusted source and binary checkpoints even when
it does not execute submitted app code. Request/filesystem boundaries, strict
resource limits, rate limits, checkpoint validation or authentication, and
worker cleanup still need implementation and validation. Shared warm workers
must not leak one request into another. Browser isolation and recovery from
runtime errors or hangs remain part of the preview contract.

Statelessness does not imply trusting checkpoints. A bounded authenticated
checkpoint envelope is one possible way to preserve stateless requests;
choosing and validating that mechanism remains implementation work. A build
ID alone provides compatibility checking, not authenticity.

The local prototype has not measured hosted cold starts, worker memory,
concurrency, or broader browser compatibility. Reusing DartPad's pattern does
not establish those properties for Fleury.

## Alternatives and the decision boundary

A service wrapping `dart compile js` and restarting the preview on every Run
would have fewer reload-specific moving parts. It would give up the actual
state-preserving hot reload that motivated this Pad. Maintaining both that
compiler path and DDC would add more surface than selecting DDC alone.

Client-only compilation would remove server operation, but adopting or owning
a browser port of Dart's compiler adds a different maintenance dependency.
TypeScript and Svelte's browser workers demonstrate the value of a compiler
already designed to run there; they do not remove Dart's toolchain tradeoff.

Hosting native Fleury applications with streamed terminal sessions would add
server execution and session lifecycle management. The existing browser host
makes that unnecessary for this scope.

Using DartPad's public service is not an immediate substitute: Fleury must be
available in its supported dependency set and the host/bootstrap integration
must work. Upstream inclusion could reduce ownership later, but is not a
prerequisite we control.

The recommended implementation is therefore a small DartPad-style compiler
service, fixed dependencies, and a browser preview, with real hot reload and a
single supported deployment build.
