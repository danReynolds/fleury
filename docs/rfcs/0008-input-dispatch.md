# RFC 0008: Input Dispatch for fleury

**Status:** Revised (incorporates peer review)
**Date:** 2026-05-17
**Supersedes:** the input subsystem framing in RFC 0007 §6.5
**Decision point for:** P1 implementation order

## 1. Summary

Input dispatch is the one part of the framework where copying Flutter
verbatim is the wrong move. Flutter's `Focus` / `Shortcuts` / `Actions` /
`Intent` stack was designed for mouse-first desktop apps; fleury's
audience is keyboard-first TUIs where every interaction is a key. Mature
TUI libraries (Textual, Bubble Tea + Bubbles, tview, urwid, Cursive)
have converged on a smaller, more declarative primitive than Flutter's
four-widget ceremony.

**Recommendation:** ship a single declarative `KeyBindings` widget as
the primary path, layered over `Focus` / `FocusScope` for tree-scoped
routing. Each binding carries a description; a built-in `KeyHintBar`
widget reads the active bindings from the focus chain and renders them
automatically. Bindings accept multiple chord aliases (so `j` and `↓`
are one binding, not two). A central `InputDispatcher` owns
pending-sequence state for 2-step leader chords (`Space q` style).
Modal scopes claim the focus chain via `FocusScope(modal: true)`.
Text input widgets consume insertable characters before ancestor
`KeyBindings` see them.

The resulting "press `j` to move down" widget is one wrapper with one
binding. A vim emulator someone might want to build is still possible
as a layer on top, but is not the primitive.

## 2. Goals and non-goals

### Goals

- **One canonical path** that handles 95% of TUI input cases cleanly:
  single keys, modifiers, chord-style shortcuts, descriptions for help.
- **Per-widget capture via the focus tree**, with unhandled keys
  bubbling up.
- **Modal claim** via `FocusScope(modal: true)` so a dialog can swallow
  Esc/Enter without parents seeing them.
- **Text input precedence**: focused text-input widgets consume
  insertable characters before ancestor bindings can claim them.
- **Discoverability is free** — wherever you declare a binding with a
  description, `KeyHintBar` can read it.
- **Multi-key chord sequences** for leader-style 2-step bindings
  (`Space q` to quit). Sequence state lives in a central dispatcher,
  not in each `KeyBindings` widget.
- **Key aliases first-class**: `j` and `↓` are one binding with two
  matching chords.
- **Familiar enough to a Flutter developer to read** without a guide;
  the names are recognizable (`KeyBindings`, `Focus`, `FocusScope`).

### Non-goals

- Vim-grade multi-key tries with operator-pending, count prefixes,
  textobjects. A consumer building an editor can layer that on top
  using `Focus` directly.
- Modes as a first-class framework concept. They're widget state.
- Mouse parity in this slice. Mouse input dispatch is its own design
  question (hit-testing against the laid-out rect tree) and lives in
  a separate RFC.
- Flutter source compatibility for `Shortcuts`/`Actions`/`Intent`.
  Those classes can ship later as an *optional* layer over
  `KeyBindings` for power users; they are not the primary path.

## 3. User stories

The API must handle each of these in 5–10 lines of widget code, and
each must work compositionally (any combination of them).

1. **Single key triggers a callback.** "Press `j` to scroll down."
2. **Modifier chord.** "Press `Ctrl+S` to save." `Alt+X` to open menu.
3. **Alias.** "`j` and `↓` both scroll down" as a single binding.
4. **Per-widget capture with bubble-up.** A list widget eats arrow
   keys when focused; if it doesn't have a binding for `q`, `q`
   reaches the app-level binding.
5. **Modal claim.** A confirmation dialog opens, claims `Enter`/`Esc`,
   and arrow-key bindings on the list behind it are inactive until
   the dialog dismisses.
6. **Leader-key 2-step sequence.** "Press `Space p` to open the
   command palette." After Space, the framework waits briefly for
   the continuation; if none arrives, Space is delivered as a normal
   key.
7. **Help/discoverability.** A status-bar widget renders all
   currently-active bindings with their descriptions, automatically,
   with no manual registry.
8. **Text input precedence.** A composer that has focus consumes
   `Space`, `q`, and every other insertable character as literal
   text — ancestor `KeyBindings` do not see them. Modifier chords
   like `Ctrl+S` still reach ancestors.
9. **Dynamic bindings.** A widget's bindings change based on
   selection state. The `KeyBindings` widget is rebuildable like any
   other widget.

A non-goal: "Press `5 j` to move down 5." That's vim-style count
prefix and would force a state machine into the parser. Out of scope.

## 4. Survey of TUI library input patterns

The libraries actually shipping heavy-keyboard TUIs today have
converged. Listed by what's worth borrowing:

### 4.1 Textual (Python)

```python
class MyApp(App):
    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("ctrl+s", "save", "Save"),
        Binding("space", "toggle", "Toggle"),
    ]
```

**Borrow:** declarative bindings as a list; description is part of the
binding; built-in `Footer` reads them.
**Skip:** `action_*` string-reflection method discovery (brittle in a
typed language); Screen stack as the only modal mechanism.

### 4.2 Bubble Tea + Bubbles (Go)

```go
keys.Up = key.NewBinding(
    key.WithKeys("k", "up"),
    key.WithHelp("↑/k", "up"),
)
```

**Borrow:** multiple keys per binding (`k` AND `up`); short and long
help strings for the hint bar.
**Skip:** central `Update` function; stringly-typed key descriptors.

### 4.3 tview (Go)

```go
primitive.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
    if event.Key() == tcell.KeyEsc { return nil } // consumed
    return event // pass through
})
```

**Borrow:** "return decides consume vs pass" semantics → `KeyEventResult.handled`
vs `KeyEventResult.ignored`. Per-widget and global capture as two
distinct primitives.
**Skip:** big switch in user code per widget.

### 4.4 urwid (Python)

```python
def keypress(self, size, key):
    if key == 'k': return self.move_up()
    return super().keypress(size, key)  # bubble up
```

**Borrow:** explicit return-to-bubble gesture.
**Skip:** method override style.

### 4.5 Cursive (Rust)

```rust
view.add_global_callback('q', |s| s.quit());
view.on_event(Event::Key(Key::Up), |s| { /* ... */ });
```

**Borrow:** global vs per-view callbacks as distinct primitives.

### 4.6 Ink (Node, React)

```js
useInput((input, key) => {
  if (input === 'q') process.exit();
});
```

**Borrow:** structured `key` object (already our `KeyEvent`).
**Skip:** every-consumer-sees-everything subscription with manual
`isFocused` filtering.

### 4.7 Gemini CLI's KeypressContext (production TUI input)

The Gemini CLI's `KeypressContext` is a notable real-world reference:
escape buffering with timeouts, bracketed-paste state machine,
Kitty/CSI-u key mappings, SGR mouse parsing, priority-based subscribers
where modal dialogs claim keys without being a tree ancestor. The
takeaway for us: **a serious input dispatcher needs a central
state machine**. Local-per-widget state breaks the moment focus moves
mid-sequence.

## 5. Synthesis

The cross-library consensus is small:

1. **Declarative bindings list** with descriptions (Textual, Bubbles).
2. **Each binding carries human-readable text** that a help widget
   can read.
3. **Focus-tree-scoped, with bubble-up** (tview, urwid, Cursive).
4. **Modal claim via scope** (Textual screens, urwid modals).
5. **Multiple chords per binding** (Bubbles).
6. **Central dispatcher** for sequence/timeout/priority handling
   (Gemini CLI).

Frameworks we explicitly reject as the primary model:
- Pure subscription / lifted state (Ink, Bubble Tea).
- Method-override per widget (urwid).
- Big switch in user code per widget (tview as primary).
- Flutter's 4-widget Shortcuts/Actions/Intent stack as the primary
  path.

That leaves a small primary primitive (`KeyBindings`), small scoping
primitives we already have (`Focus`, `FocusScope`), a small
discoverability widget (`KeyHintBar`), and a central `InputDispatcher`
inside the runtime.

## 6. API design

### 6.1 The primary widget

```dart
KeyBindings(
  bindings: [
    KeyBinding.action(
      keys: const [KeyChord.char('j'), KeyChord.key(KeyCode.arrowDown)],
      onTrigger: _moveDown,
      hint: 'j/↓',
      description: 'Move down',
    ),
    KeyBinding.action(
      keys: const [KeyChord.char('k'), KeyChord.key(KeyCode.arrowUp)],
      onTrigger: _moveUp,
      hint: 'k/↑',
      description: 'Move up',
    ),
    KeyBinding.action(
      keys: [KeyChord.ctrl('s')],
      onTrigger: _save,
      description: 'Save',
    ),
  ],
  child: ...,
)
```

`KeyBindings` is a `StatefulWidget`. It creates a non-focusable
`Focus` node internally (`canRequestFocus: false`, `skipTraversal:
true`) and contributes its bindings to the active focus chain. It
is the canonical authoring pattern; `Focus.onKey` is the escape
hatch for advanced cases.

### 6.2 `KeyBinding`

```dart
typedef KeyBindingHandler = KeyEventResult Function(KeyEvent event);

final class KeyBinding {
  const KeyBinding({
    required this.keys,
    required this.onKey,
    this.description,
    this.hint,
    this.enabled = true,
    this.hideFromHint = false,
  });

  /// Convenience: a sync void callback that always returns handled.
  /// Use this for the common case.
  factory KeyBinding.action({
    required List<KeyChord> keys,
    required void Function() onTrigger,
    String? description,
    String? hint,
    bool enabled = true,
    bool hideFromHint = false,
  }) = ...;

  final List<KeyChord> keys;
  final KeyBindingHandler onKey;

  /// Long description for help screens. Required for the binding to
  /// appear in `KeyHintBar`.
  final String? description;

  /// Short display string for hint bars (e.g. `'j/↓'`). If null,
  /// derived from the first chord (e.g. `'j'`).
  final String? hint;

  /// When false, the binding doesn't match and doesn't appear in
  /// hints. Useful for "delete (only when something is selected)".
  final bool enabled;

  /// When true, the binding still fires but is hidden from
  /// `KeyHintBar`. Useful for Ctrl+C that everyone knows.
  final bool hideFromHint;
}
```

The handler signature is **synchronous**. Bindings that need async
work (`saveFile()` returns a `Future`) fire-and-forget inside the
callback; the dispatch decision must be sync because the input
dispatcher can't block waiting for I/O. Bindings that want to
conditionally decline return `KeyEventResult.ignored` from the
non-`.action` constructor:

```dart
KeyBinding(
  keys: [KeyChord.char('d')],
  description: 'Delete selected',
  onKey: (event) {
    if (selection == null) return KeyEventResult.ignored;
    _delete();
    return KeyEventResult.handled;
  },
)
```

### 6.3 `KeyChord`

```dart
sealed class KeyChord {
  /// A printable character with no modifiers, no shift implication.
  /// `KeyChord.char('q')` matches lowercase q.
  /// `KeyChord.char('Q')` matches uppercase Q (i.e. shift-q).
  const factory KeyChord.char(String char) = _CharChord;

  /// Convenience: Ctrl+<letter>. Case-insensitive on the letter.
  const factory KeyChord.ctrl(String char) = _CtrlChord;

  /// Convenience: Alt+<letter>. Case-insensitive on the letter.
  const factory KeyChord.alt(String char) = _AltChord;

  /// A special key (arrows, function keys, escape).
  const factory KeyChord.key(KeyCode key, {
    bool ctrl, bool alt, bool shift,
  }) = _SpecialChord;

  /// Sequence of exactly two chords: `Space` then `q`. Longer
  /// sequences require dropping down to `Focus.onKey` directly.
  const factory KeyChord.sequence(KeyChord first, KeyChord then) = _Sequence;

  bool matches(KeyEvent event);
}
```

#### Normalization rules

The `InputParser` produces typed `KeyEvent` objects (defined in
`lib/src/terminal/events.dart`); `KeyChord` operates against those,
never against raw escape bytes. Specific rules:

- `KeyChord.char(c)` matches `KeyEvent` where:
  - `event.char == c`
  - `event.modifiers` contains neither `ctrl` nor `alt`
  - Shift presence is **implicit in the character**. `'q'` matches
    lowercase q; `'Q'` matches uppercase Q. We do not separately
    expose `shift: true` because terminals don't reliably report
    shift for printable letters — the case of the character is the
    signal.
- `KeyChord.ctrl(c)` matches when `event.char.toLowerCase() == c.toLowerCase()`
  and `event.modifiers` contains `ctrl`. The case of `c` is normalized
  away — `KeyChord.ctrl('S')` and `KeyChord.ctrl('s')` are the same.
- `KeyChord.alt(c)` is the same shape as `KeyChord.ctrl` but for the
  `alt` modifier. Terminals deliver Alt+x as either ESC-prefix `\x1B
  x` or via the keyboard protocol; the parser normalizes both to a
  `KeyEvent` with `alt` set.
- `KeyChord.key(KeyCode, {ctrl, alt, shift})` matches by `keyCode`.
  Modifiers must match exactly. Use this for arrows, function keys,
  Tab, Escape, etc.
- `KeyChord.sequence(a, b)` matches when `a` matches the first event
  AND `b` matches the next event within the sequence timeout
  (configurable; default 500ms). Sequences of length > 2 are not
  supported as `KeyChord` values — they need a custom state machine.

### 6.4 `KeyHintBar`

```dart
class KeyHintBar extends StatelessWidget {
  const KeyHintBar({super.key, this.maxBindings = 8});
  final int maxBindings;

  @override
  Widget build(BuildContext context) {
    final bindings = ActiveKeyBindings.of(context);
    return Text(_format(bindings.take(maxBindings)));
  }
}
```

`KeyHintBar` walks the active focus chain (via an
`InheritedNotifier`-style hook so it rebuilds when bindings change),
collects bindings from every `KeyBindings` ancestor, dedups by chord,
and renders each as `<hint> <description>` along the available
horizontal space.

Filtering rules:
1. Bindings with `description == null` are hidden.
2. Bindings with `hideFromHint: true` are hidden.
3. Bindings with `enabled: false` are hidden.
4. When two bindings have overlapping chords, the deeper one (closer
   to the focused widget) wins for display.
5. Global bindings (registered at `runTui`) appear last, after focus-
   chain bindings.
6. A modal `FocusScope` hides bindings behind it from the hint bar.

`KeyHintBar` is the **P1 deliverable**. An overlay variant
(`KeyHintOverlay` — full-screen which-key style popup) is deferred to
P2 or later, on demand.

### 6.5 Modal scope

```dart
FocusScope(
  modal: true,
  child: ConfirmDialog(...),
)
```

A normal `FocusScope` groups focus traversal but does not block
bubble-up — events still reach ancestor `KeyBindings`. `modal: true`
turns the scope into a *trap*: events do not reach `KeyBindings`
ancestors above the scope.

Global bindings (registered with `runTui`'s `globalBindings`
parameter) **still fire** when a modal scope is active, unless the
modal scope sets `suppressGlobals: true`. Default is to leave globals
active so `Ctrl+C` always works.

### 6.6 Global bindings

```dart
runTui(
  () => const MyApp(),
  globalBindings: [
    KeyBinding.action(
      keys: [KeyChord.ctrl('c')],
      onTrigger: () => TuiApp.exit(),
      description: 'Quit',
      hideFromHint: true,
    ),
  ],
);
```

Global bindings are checked after the focus chain. They fire only
when no focused binding consumed the event. They appear in
`KeyHintBar` last (after dedup against focus-chain bindings) unless
hidden.

### 6.7 Text input precedence

A focused text-input widget (the future `TextInput` / `Composer` /
`EditableText` — landing with the Dune chat slice) consumes
**insertable characters** before any ancestor `KeyBindings` sees
them. Specifically:

- Printable ASCII (`0x20`–`0x7E`) and any multi-byte Unicode delivered
  as `TextInputEvent` go to the focused text input first.
- Modifier chords (`Ctrl+X`, `Alt+X`) bypass the text input and reach
  ancestor `KeyBindings`. The text input only claims unmodified
  printable characters.
- Special keys (`Escape`, `Tab`, `Enter`, arrows) follow the normal
  focus-chain rules — the text input can opt in to handling them
  (composer claims `Enter` to send) or let them bubble.

Implementation: the text input widget registers a
`TextInputClaimant` marker on its focus node. The dispatcher's
focus-chain walk checks for one before consuming insertable
characters via the normal binding path. There is no special widget
on the consumer side — `TextInput` itself implements the claim.

This is the rule that prevents Dune chat from quitting every time
the user types `q` into the composer.

## 7. Dispatch precedence

When the runtime receives a `KeyEvent` from the driver, the
`InputDispatcher` runs this algorithm:

```
1. PENDING SEQUENCE
   If a sequence is pending in the dispatcher:
     a. If this event completes a known sequence binding, fire it.
        Clear pending state. Return handled.
     b. Otherwise, cancel the pending state. Redispatch the original
        first event as a normal event (step 2), then dispatch the
        current event as a normal event (step 2).

2. SEQUENCE TIMEOUT (cleanup path, runs from the timer)
   If a pending sequence times out (default 500ms with no follow-up),
   cancel the pending state. Redispatch the original first event as
   a normal event (step 3).

3. FOCUS-CHAIN DISPATCH
   Walk from the focused node upward, stopping at the first modal
   FocusScope boundary:
     a. If a TextInputClaimant is in the chain AND this event is
        an insertable character, deliver to it. Return handled.
     b. For each KeyBindings in the chain (deepest first), check
        bindings:
          - If a direct binding's `keys` contains a chord that
            matches the event, call `onKey(event)`. If the result
            is handled, return handled.
          - If a sequence binding's first chord matches the event,
            start pending sequence state. Return handled.
     c. If a binding is disabled (`enabled: false`), skip it.

4. GLOBAL BINDINGS
   Check `runTui`'s globalBindings. Same match logic as step 3b.
   Modal scope's `suppressGlobals` (if true) skips this step.

5. IGNORED
   No handler claimed the event. Return ignored.
```

Key precedence properties:

- **Deeper-direct beats ancestor-sequence**: if a focused widget
  binds `' '` directly and an ancestor binds `' p'` as a sequence,
  the focused widget's direct binding wins. (Step 3b processes the
  deeper node first.)
- **Text input beats leader sequences**: if a composer is focused
  and the user types `' '`, the space inserts into the composer; an
  ancestor's `' p'` sequence does not start. (Step 3a runs before
  3b.)
- **Modal isolation**: events do not cross a `modal: true`
  `FocusScope` upward. Globals still run unless suppressed.
- **Sequence redispatch**: if a leader times out, the original key
  is delivered as a normal event, not lost.

## 8. Implementation sketch

### 8.1 `InputDispatcher`

```dart
class InputDispatcher {
  InputDispatcher({this.sequenceTimeout = const Duration(milliseconds: 500)});
  final Duration sequenceTimeout;

  _PendingSequence? _pending;
  Timer? _timeoutTimer;
  final FocusManager focusManager;
  List<KeyBinding> globalBindings = const [];

  KeyEventResult dispatch(KeyEvent event) {
    // 1. Pending-sequence handling
    if (_pending != null) {
      final binding = _pending!.tryComplete(event);
      if (binding != null) {
        _clearPending();
        return binding.onKey(event);
      }
      // Cancel and redispatch.
      final firstEvent = _pending!.firstEvent;
      _clearPending();
      _dispatchPlain(firstEvent);
      return _dispatchPlain(event);
    }
    return _dispatchPlain(event);
  }

  KeyEventResult _dispatchPlain(KeyEvent event) {
    // 2. Focus chain (with TextInput precedence and modal boundary).
    // 3. Globals.
    // 4. Ignored.
    ...
  }

  void _clearPending() {
    _pending = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }
}
```

`InputDispatcher` is owned by `runTui`. It subscribes to the
driver's `events` stream and dispatches each `KeyEvent`. The
`FocusManager` exposes the current focus chain (a list of
`FocusNode`s from focused to root, with binding sources attached).

### 8.2 `KeyBindings` is a thin Focus wrapper

```dart
class _KeyBindingsState extends State<KeyBindings> {
  late final FocusNode _node;

  @override
  void initState() {
    super.initState();
    _node = FocusNode(
      canRequestFocus: false,
      skipTraversal: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _BindingsHost(
      node: _node,
      bindings: widget.bindings,
      child: Focus(focusNode: _node, child: widget.child),
    );
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }
}
```

`_BindingsHost` is an `InheritedWidget`-style marker that lets
`ActiveKeyBindings.of(context)` collect bindings from every
`KeyBindings` on the focus chain. The dispatcher reads them via the
focus tree, not via a separate registry.

**Note:** `KeyBindings` does not own pending-sequence state. Sequence
matching is a function of the bindings (which sequences start with
this chord?) but the *state* of "we're waiting on the second key"
lives in `InputDispatcher`.

### 8.3 `KeyHintBar` reads through the focus chain

```dart
class _KeyHintBarState extends State<KeyHintBar> {
  @override
  Widget build(BuildContext context) {
    final bindings = ActiveKeyBindings.of(context);
    // Dedup, filter, format.
    final visible = _filter(bindings);
    return Text(_format(visible.take(widget.maxBindings)));
  }
}
```

Reads from the same focus chain the dispatcher uses, so a binding
that fires is the same binding that appears in the hint bar.

## 9. P1 acceptance tests

Lifted verbatim from the peer-review feedback because the list is
the implementation contract:

1. Focused child binding handles a key before parent binding.
2. If child ignores a key, parent binding handles it.
3. Normal `FocusScope` does not block parent bindings.
4. Modal `FocusScope` blocks parent bindings behind it.
5. Global binding fires after focus chain ignores a key.
6. Focus-chain binding can override global binding.
7. `KeyHintBar` shows currently active focused bindings.
8. `KeyHintBar` deduplicates with nearest binding winning.
9. Bindings with `description: null` do not appear in `KeyHintBar`.
10. Bindings with `hideFromHint: true` do not appear in `KeyHintBar`.
11. Dynamic binding rebuild updates `KeyHintBar`.
12. Alias binding matches both `j` and `arrowDown`.
13. Sequence `Space q` fires when `q` follows `Space`.
14. Sequence timeout redispatches `Space` as a normal key.
15. Direct focused `Space` binding beats ancestor `Space q`
    sequence.
16. Text input handles insertable `Space` before ancestor leader
    sequence.
17. `Ctrl`/`Alt` modifier chords match normalized `KeyEvent`.
18. Modal dialog can claim Esc/Enter without list bindings behind
    it firing.
19. Global `Ctrl+C` still works unless a modal explicitly suppresses
    globals.
20. Disabled bindings do not fire and do not show in hints.

Each test is a unit test that mounts a tree, fires events through a
`FakeTerminalDriver`, and asserts on the resulting handler calls
and `KeyHintBar` contents. None require a real PTY.

## 10. Open questions

1. **Sequence timeout duration.** Default 500ms is the cross-library
   median (vim is 1000ms, most modern TUIs are 250-500ms). Should
   be configurable per `runTui` call.
2. **Should `runTui` allow per-app overrides to the dispatch
   precedence?** Probably not at v1; revisit if a real consumer
   needs it.
3. **Mouse**. Where do mouse hit-tests live? Probably a separate
   `OnTap` / `MouseRegion` widget tree, but the design isn't here.
   Sibling RFC 0009 will cover it.

## 11. Counter app in the post-P1 idiom

```dart
import 'package:fleury/fleury.dart';

Future<void> main() => runTui(
      () => const Counter(),
      globalBindings: [
        KeyBinding.action(
          keys: [KeyChord.ctrl('c')],
          onTrigger: () => TuiApp.exit(),
          description: 'Quit',
          hideFromHint: true,
        ),
      ],
    );

class Counter extends StatefulWidget {
  const Counter({super.key});
  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding.action(
          keys: const [KeyChord.char('+'), KeyChord.char('=')],
          onTrigger: () => setState(() => count += 1),
          hint: '+/=',
          description: 'Increment',
        ),
        KeyBinding.action(
          keys: const [KeyChord.char('-')],
          onTrigger: () => setState(() => count -= 1),
          description: 'Decrement',
        ),
        KeyBinding.action(
          keys: const [KeyChord.char('0')],
          onTrigger: () => setState(() => count = 0),
          description: 'Reset',
        ),
        KeyBinding.action(
          keys: const [KeyChord.char('q')],
          onTrigger: () => TuiApp.of(context).exit(),
          description: 'Quit',
        ),
      ],
      child: Focus(
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: Column(children: [
            Text('Counter: $count', style: const CellStyle(bold: true)),
            const KeyHintBar(),
          ]),
        ),
      ),
    );
  }
}
```

## 12. References

1. **Textual `BINDINGS` and `Footer`** —
   https://textual.textualize.io/guide/input/#bindings
2. **Bubble Tea + Bubbles `key.Binding` and `help`** —
   https://github.com/charmbracelet/bubbles/tree/master/key
3. **tview `SetInputCapture`** —
   https://github.com/rivo/tview/wiki
4. **urwid `keypress`** —
   https://urwid.org/manual/widgets.html
5. **Cursive `on_event` / `add_global_callback`** —
   https://docs.rs/cursive/latest/cursive/
6. **Ink `useInput`** —
   https://github.com/vadimdemedes/ink#useinput
7. **Gemini CLI `KeypressContext`** —
   https://github.com/google-gemini/gemini-cli/blob/main/packages/cli/src/ui/contexts/KeypressContext.tsx
8. **Helix keymap (TOML tree)** —
   https://docs.helix-editor.com/keymap.html
9. **Flutter `Focus` / `Shortcuts` / `Actions`** —
   https://api.flutter.dev/flutter/widgets/Shortcuts-class.html

## 13. Recommendation summary

Implement P1 with:
- `KeyBindings` as the primary input authoring API
- `KeyBinding` carrying multiple chord aliases and a description
- `KeyChord` with `.char`, `.ctrl`, `.alt`, `.key`, `.sequence`
  constructors and explicit normalization rules
- `Focus` / `FocusScope` (with `modal: true`) for routing and
  modal scope (lifted from Flutter)
- `KeyHintBar` for built-in discoverability
- A central `InputDispatcher` owning pending-sequence state, timeout
  redispatch, focus-chain walking, and global-binding fallback
- Text-input precedence claimed via a `TextInputClaimant` marker on
  focus nodes (implemented by the future `TextInput` widget)

Skip Flutter's `Shortcuts` / `Actions` / `Intent` ceremony for the
primary path. If later demand surfaces, ship them as an optional
layer over `KeyBindings`.

This gives fleury the input model that the heavy-keyboard TUI
audience has converged on across Python, Go, Rust, and JS — not the
mouse-centric model Flutter built for desktop apps.
