# Workstream: App Kernel And Command Shell

## Purpose

Turn Fleury's widget primitives into an application framework with screens,
commands, actions, shortcuts, status, lifecycle, and command-palette
integration.

## Current State

- Fleury already has `Navigator`, `KeyBindings`, input dispatch, focus scopes,
  overlays, `KeyHintBar`, `TuiBinding`, debug shell plumbing, and a widget-level
  command palette.
- [RFC 0012: App kernel](../../rfcs/0012-app-kernel.md) defines the Phase 1
  shell contract for `FleuryApp`, screens, command registry, command scopes,
  status, lifecycle, and semantic contributions.
- `CommandId`, `AppCommand`, `CommandRegistry`, `CommandRegistryScope`, and
  `CommandScope` now provide the first structural command layer in core.
- `ScreenId`, `FleuryScreen`, `ScreenController`, `FleuryApp`, and
  `ActiveScreenView` now provide the first app shell and registered-screen
  layer in core.
- `StatusItem`, `StatusController`, `FleuryApp.status`, command-context
  status access, and `AppStatusBar` now provide the first status model and
  renderer in core.
- `AppCommandPalette` now adapts the active command registry into the existing
  widget-level palette, including command IDs, categories, shortcuts, enabled
  state, and active screen command priority.
- Command palette rows now use lazy visible mounting with cached, ranked search
  fields. Stable command IDs are searchable, exact/prefix/contains matches rank
  ahead of fuzzy subsequence matches, and aggregate palette semantics keep the
  full collection count while row semantics stay bounded to visible rows.
- `FleuryTester` can now locate command registries, invoke commands by stable
  ID, and inspect the latest command result.
- `FleuryApp.extensions`, `FleuryAppController.extension<T>()`,
  `FleuryApp.extension<T>(context)`, and command-context
  `appExtension<T>()` now provide the first app-level typed extension registry
  for package/domain integration without adding plugin loading or adapter
  lifecycle to core.
- `FleuryAppExtension` now defines the first static extension contribution
  convention for extension-owned app commands, status items, and theme
  defaults, plus typed data/read-model sources. Host app commands remain
  authoritative on duplicate command IDs, and ambient host theme extensions
  remain ahead of package defaults.
- The proof app package now registers `ProofConsoleExtension` through
  `FleuryApp.extensions` and consumes it from screen builders and command
  enablement/action code while the extension contributes the diagnostics
  command, stream/debug status items, `FleuryWidgetTheme` defaults, and
  `ProofSearchDataSource` for the global search corpus.
- `packages/fleury_git` now proves the same seam from a reusable non-example
  package. It contributes Git commands, status, widget theme defaults, a typed
  repository data source, and a `GitStatusPanel` consumer without adding
  plugin discovery, package loading, lifecycle management, or Git process
  ownership to core.
- The debug Tree tab now surfaces app semantic state, active screen,
  command/status counts, latest command result, and command metadata.
- The proof app can now use structural commands, direct command invocation in
  tests, screen state, status, key hints, debug summaries, and registry-backed
  command palette entries without hand-wiring every screen.
- A proof-app settling pass confirmed app-owned commands invoked from tester
  helpers route through the app registry, and custom semantic proxy elements
  rebuild child subtrees on widget update so status, command, and screen
  semantics do not stale after parent state changes.
- The key-chord launch API now keeps dispatcher-only step inspection internal.
  Public libraries expose stable chord construction/matching, labels,
  key-bindings, and command integration, but no longer export
  `$KeyChordInternal`, `matchesStepAt`, `stepCount`, or `isSequence`.
- The async command v0 contract is now explicit and tested:
  `CommandRegistry.invoke` and `invokeCommand` await `FutureOr` callbacks
  before recording completed or failed results, while shortcut-triggered
  commands dispatch without blocking input and publish their result when the
  async callback settles.
- `CommandRegistry` now owns its disposal lifecycle: disposed registries reject
  new command mutations and invocations, and in-flight async command futures can
  still resolve for their caller without storing or publishing late
  `lastResult` state after the command scope has unmounted.
- `ScreenController`, `StatusController`, and `FleuryAppController` now reject
  post-dispose mutations. `FleuryAppController.dispose` also detaches child
  controller listeners idempotently so screen/status/command changes after app
  teardown cannot publish stale app state.

## Target Capabilities

- `FleuryApp` shell that remains optional for small examples.
- Screen registry and active screen controller.
- Command registry with IDs, labels, descriptions, categories, shortcuts,
  enabled/visible state, semantic actions, and direct invocation.
- Scope-aware command activation for global, screen-local, focused-subtree,
  and modal commands.
- Status model for active screen, active task, diagnostics, and capability
  fallbacks.
- Command palette and key hint bar backed by the same command registry.
- Tester and inspector visibility into active commands, shortcuts, screens,
  and invocation failures.
- Typed app-level extension objects that domain packages can retrieve from
  widgets and commands without coupling core Fleury to provider-specific
  services, ACP, Dune, or plugin installation.
- Static extension-owned commands and status items for integration packages
  that need package-shaped registration without plugin discovery or lifecycle.
- Static extension-owned theme extension defaults that merge under
  `FleuryApp` while preserving host theme override precedence.
- Static extension-owned typed data/read-model sources that widgets, commands,
  and app controllers can retrieve without making Fleury own provider
  lifecycle, fetching, paging, or cache invalidation.

## Milestone Checklist

- [x] AKC.1 Write app kernel RFC.
  - Intent: Define the shell before implementation.
  - Acceptance: RFC covers `FleuryApp`, screens, commands/actions, shortcut
    scopes, command palette, status binding, lifecycle, and proof-app needs.
  - Evidence: [RFC 0012: App kernel](../../rfcs/0012-app-kernel.md).
  - Notes: The shell is additive over existing navigator, key-binding, focus,
    and runtime primitives.

- [x] AKC.2 Implement command registry v0.
  - Intent: Make app commands structural.
  - Acceptance: Commands have stable IDs, metadata, shortcuts,
    enabled/visible state, programmatic invocation, active scope resolution,
    and semantic action contributions.
  - Evidence:
    [command core](../../../packages/fleury/lib/src/app/commands.dart),
    [command tests](../../../packages/fleury/test/app/command_registry_test.dart).
  - Notes: First slice covers stable command IDs, metadata, sync
    enabled/visible predicates, async-capable invocation with completed/
    disabled/notFound/failed results, parent/local registry resolution with
    nearest-scope wins, shortcut emission through existing `KeyBindings`, and
    semantic command nodes. `invokeCommand` now lets already-resolved command
    surfaces invoke the exact command object while preserving policy and result
    recording. Current launch hardening locks the async command v0 rule:
    direct invocations await callback settlement before recording results, and
    shortcut dispatch remains fire-and-forget while still recording the result
    when the callback completes. Command registry disposal now prevents late
    async command completions from mutating disposed registry state while
    preserving the in-flight future result for callers that already invoked the
    command. Screen, status, and app controllers now reject post-dispose
    mutations and app-controller teardown detaches child-controller listeners.

- [x] AKC.3 Implement `FleuryApp` and screen registry v0.
  - Intent: Provide app-scale structure without replacing ordinary widgets.
  - Acceptance: A sample app can declare screens, activate screens, expose
    screen-local commands, and preserve focus/status behavior across screen
    changes.
  - Evidence:
    [app shell](../../../packages/fleury/lib/src/app/app.dart),
    [app shell tests](../../../packages/fleury/test/app/fleury_app_test.dart).
  - Notes: First slice covers stable screen IDs, screen metadata/builders,
    active screen selection, app/screen scopes, `FleuryApp.of`, command-context
    extensions for app/screens, app-level command shortcuts, active screen
    rendering, screen-local command scopes, app/screen semantic state, status
    integration, and latest command-result app semantics. Inactive preserved
    screens have their command scopes disabled. Polished focus preservation is
    deferred until a proof-app scenario requires the exact behavior.

- [x] AKC.4 Wire palette, key hints, status, tester, and inspector.
  - Intent: Make command structure visible and testable.
  - Acceptance: Command palette and key hints query active command scopes;
    status bars bind to app state; tester invokes commands by ID; inspector
    shows active screen, active scopes, command registry, and failures.
  - Evidence:
    [status model](../../../packages/fleury/lib/src/app/status.dart),
    [app shell tests](../../../packages/fleury/test/app/fleury_app_test.dart),
    [tester helper](../../../packages/fleury/lib/src/testing/fleury_tester.dart),
    [debug panel](../../../packages/fleury/lib/src/debug/debug_panel.dart),
    [debug shell tests](../../../packages/fleury/test/debug/debug_shell_test.dart),
    [command palette adapter](../../../packages/fleury_widgets/lib/src/command_palette.dart),
    [command palette tests](../../../packages/fleury_widgets/test/command_palette_test.dart).
  - Notes: Status now has stable items, severities, optional command actions,
    a mutable controller, derived `FleuryApp.status` builder support,
    command-context status access, `AppStatusBar`, and semantic status nodes.
    Registry-backed `AppCommandPalette` now reads app-global commands and
    active screen commands, keeps screen commands ahead of app commands when
    IDs collide, exposes row metadata through semantics, and invokes the exact
    resolved command instance through `CommandRegistry.invokeCommand`. App
    command shortcuts also surface through `KeyHintBar`. Tester helpers now
    expose command registry lookup, command invocation by ID, and latest
    invocation result. The debug Tree tab now shows active screen, command and
    status counts, latest command result, and command metadata from semantics.
    Follow-up proof-app validation fixed app-owned command result routing and
    stale semantic proxy child rebuilds, then passed the full proof app suite.
    SB.8 later forced the palette result list to move from eager rows to lazy
    visible rows; the optimized 1000-command baseline keeps filter p95 at
    1121 us and full-cycle p95 at 6429 us while preserving command-id search,
    visible row semantics, disabled command behavior, and stale-action cleanup.

- [x] AKC.5 Add app-level typed extension registry v0.
  - Intent: Give integration packages and app-owned domains a stable
    app-kernel seam for service/data/workflow objects without making core
    Fleury a plugin runtime.
  - Acceptance: A `FleuryApp` can register typed extension objects; widgets can
    retrieve them from build context; commands can retrieve them from
    `CommandContext`; updates replace the registry without recreating the app
    shell; the exposed list is immutable to callers; opt-in extension objects
    can contribute app-level commands, status items, theme extensions, and
    data sources; app-owned commands and host theme extensions win
    duplicate/default conflicts; a separate package proves the seam through
    real app status, command, theme, data-source, and screen-builder usage.
  - Evidence:
    [app shell](../../../packages/fleury/lib/src/app/app.dart),
    [app shell tests](../../../packages/fleury/test/app/fleury_app_test.dart),
    [proof app integration](../../../packages/fleury_example_console/lib/fleury_example_console.dart),
    [proof app tests](../../../packages/fleury_example_console/test/proof_console_test.dart),
    [fleury_git package](../../../packages/fleury_git/lib/fleury_git.dart),
    [fleury_git tests](../../../packages/fleury_git/test/git_extension_test.dart).
  - Notes: This intentionally mirrors the typed extension ergonomics already
    proven by `ThemeData.extensions`, but at app scope. It does not load
    plugins, manage lifecycles, discover packages, serialize extension values
    into semantics, or introduce ACP/Dune-specific adapters. The optional
    `FleuryAppExtension` contract gives packages a static way to bundle
    commands, status, theme defaults, and data/read-model sources beside their
    typed service object. The proof app validates package-owned extension
    state, an extension-owned diagnostics command, extension-owned status,
    extension-owned `FleuryWidgetTheme` defaults, and extension-owned
    `ProofSearchDataSource` usage in real command/status/theme/data/widget
    paths. The reusable-package slice adds `FleuryGitExtension`,
    `GitRepositoryDataSource`, `GitRepositorySnapshot`, and `GitStatusPanel`,
    proving that package-shaped integrations can contribute commands, status,
    widget-theme defaults, and data/read models without lifecycle/discovery
    machinery. M3.8 is complete for the launch extension story; future
    lifecycle APIs should require concrete package evidence beyond this static
    contribution model.

## Implementation Notes

- Do not create a new routing system. Use screens for app sections and keep
  `Navigator` for modal/route stack behavior.
- Keep `FleuryApp` optional. The exported screen/controller primitives should
  also work when an app hand-builds its shell.
- Command IDs should be stable enough for tests, semantic actions, and later
  adapter packages.
- Command enablement should be synchronous in v0. Async state should update
  ordinary app/worker state and rebuild.
- App-kernel state must contribute to the semantic app graph and debug
  inspector.
- Status is app-kernel state, not just footer text. Keep it queryable,
  actionable, and driven by app/screen/command state.
- App extensions are app-kernel dependency seams, not user-facing semantic
  nodes. Do not serialize arbitrary extension objects into semantics or debug
  capture; expose safe facts through the widgets/services that use them.
- Extension-owned commands and status should stay static app-shell
  contributions. Do not add package discovery, lifecycle hooks, async
  activation, or provider-specific adapters until a reusable package proves
  the need.
- Extension-owned theme entries are defaults, not overrides. Keep ambient host
  `ThemeData.extensions` first so app authors can replace package styling
  without changing extension packages.
- Extension-owned data sources are lookup seams, not providers. Keep fetching,
  subscriptions, paging, caching, disposal, and refresh policy app/package
  owned until a reusable package proves a lifecycle API is necessary.
- The first reusable package proof, `fleury_git`, did not require lifecycle
  hooks. It kept repository discovery, refresh, mutation, and process execution
  app-owned, which supports leaving plugin lifecycle/discovery out of launch.
- Keep keyboard routing on existing `KeyBindings`; app commands should add
  structure over that path, not bypass it.
- Keep dispatcher sequence-walking helpers private. Internal tests may import
  `src/widgets/key_bindings.dart`, but app code should not depend on
  step-by-step chord inspection until a real extension use case proves the
  public contract.
- Worker/process execution belongs to the effects/workflow workstream; app
  commands may start or cancel work but should not own task internals.

## Risks And Open Questions

- The shell could become too heavy if every app is forced through it.
- Command scopes can become confusing if global, screen, focused, and modal
  commands are not resolved predictably.
- Async command behavior is intentionally narrow for launch. Commands may
  return `FutureOr<void>` and have completed/failed results recorded after
  settlement; progress, cancellation, subprocesses, and replay belong to the
  effects/workflow workstream rather than the app kernel.
- Extension lookup could become a service-locator escape hatch if packages put
  too much mutable global behavior behind it. Keep launch guidance focused on
  typed, app-owned integration objects; `fleury_git` proves static package
  contribution, not arbitrary plugin runtime behavior.
- Shortcut internals can leak quickly because extension methods look like
  ordinary methods to app authors. Guard public exports so dispatcher-only
  helpers do not become accidental compatibility promises.

## Acceptance Evidence

- [RFC 0012: App kernel](../../rfcs/0012-app-kernel.md).
- [command core](../../../packages/fleury/lib/src/app/commands.dart).
- [command tests](../../../packages/fleury/test/app/command_registry_test.dart).
- [app shell](../../../packages/fleury/lib/src/app/app.dart).
- [app shell tests](../../../packages/fleury/test/app/fleury_app_test.dart).
- [proof app integration](../../../packages/fleury_example_console/lib/fleury_example_console.dart).
- [proof app tests](../../../packages/fleury_example_console/test/proof_console_test.dart).
- [fleury_git package](../../../packages/fleury_git/lib/fleury_git.dart).
- [fleury_git tests](../../../packages/fleury_git/test/git_extension_test.dart).
- [status model](../../../packages/fleury/lib/src/app/status.dart).
- [tester helper](../../../packages/fleury/lib/src/testing/fleury_tester.dart).
- [debug panel](../../../packages/fleury/lib/src/debug/debug_panel.dart).
- [debug shell tests](../../../packages/fleury/test/debug/debug_shell_test.dart).
- [command palette adapter](../../../packages/fleury_widgets/lib/src/command_palette.dart).
- [command palette tests](../../../packages/fleury_widgets/test/command_palette_test.dart).
- [key chord tests](../../../packages/fleury/test/widgets/key_chord_test.dart).
- [key chord public API boundary tests](../../../packages/fleury/test/widgets/key_chord_public_api_boundary_test.dart).
- [input dispatcher tests](../../../packages/fleury/test/runtime/input_dispatcher_test.dart).
- Proof-app command palette/status integration has first evidence in
  [packages/fleury_example_console](../../../packages/fleury_example_console).
