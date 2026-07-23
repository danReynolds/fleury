# RFC 0018: The Key Binding Surface

**Status:** Accepted — design converged in maintainer review 2026-07-20; implementation pending
**Date:** 2026-07-20
**Supersedes:** the authoring surface of RFC 0008 (`KeyChord`, `KeyBinding` constructors, `KeyEvent` shape). The dispatch architecture of RFC 0008 §7 (precedence, modal scopes, text-input claim order, central `InputDispatcher`) carries forward unchanged.
**Prerequisite:** Dart ≥ 3.10 (dot shorthands — already required by the current tree).

## 1. Summary

One rule generates the whole model:

> A `KeyCode` is one logical key. A `KeySequence` is one or more
> keypresses, possibly modified. Every `KeyCode` is a valid one-step
> `KeySequence`; nothing else is a `KeyCode`.

This RFC makes `KeyCode` a value type (characters and special keys in
one vocabulary) and the one-step subtype of `KeySequence`, gives
`KeyEvent` a single required `code` (deleting the nullable
`keyCode`/`char` pair), renames `KeyChord` to `KeySequence` (the
current type is documented as "a sequence of steps" — the name is
wrong), and rebuilds the `KeyBinding` constructors around a no-argument
`onTrigger` common case. It also fixes a real matching bug (Super+S
currently fires a bare `.s` binding), adds runtime introspection for
which-key UIs, and adds a string grammar (`parse` ↔ `hintLabel`) for
user-remappable keymaps.

Pre-launch policy applies: **no deprecations, no aliases, no shims** —
every rename is a clean break, landed with its call-site sweep in the
same PR.

The entire call-site surface in this RFC was validated against a
compiling prototype (Dart 3.10 dot shorthands, statics + chain
extensions — the same mechanics the current `KeyChord` already uses).
The compile-error messages quoted in §11 are verbatim analyzer output.

## 2. Goals and non-goals

### Goals

- **The common binding is noise-free.** `KeyBinding(.ctrl.s, onTrigger:
  save, label: 'Save')` — no `(_) =>`. The current handler shape forces
  `onEvent: (_) =>` at 156 call sites in this repo.
- **One expression everywhere.** The same `.ctrl.x.ctrl.s` that binds a
  shortcut constructs test input, keys an action map, and round-trips
  through the string grammar.
- **Invalid states are unrepresentable.** A `KeyEvent` always has
  exactly one code. An incomplete modifier expression (`.ctrl`) is a
  compile error. A multi-step sequence cannot pose as a single code.
- **Strict, complete modifier matching.** Super and Meta join Ctrl,
  Alt, Shift as first-class, strictly-compared modifiers everywhere.
- **Introspection is a primitive.** Hint bars, help overlays, palettes,
  which-key popups, and prefix indicators all read from two accessors;
  none walks the focus tree itself.
- **Keymaps are plain data.** Modal apps swap binding lists; user
  remapping parses strings; conflict detection is map lookups and
  `isPrefixOf`.

### Non-goals

- Flutter's `Shortcuts`/`Intents`/`Actions` indirection. Callback-at-
  the-binding is the right altitude for TUI-scale apps; an action-map
  layer composes on top via `Map<KeySequence, VoidCallback>`.
- A public step type. Steps stay private; sequences are opaque values
  with equality, `stepCount`, and `isPrefixOf`.
- String-based *bind sites* (`bind('ctrl+s', …)`). Strings are for
  config files and capture UIs (§9); call sites stay typed.
- Digit statics (`.digit1`). Digits and punctuation use `.char('1')`.
- A `repeats:` flag on bindings. Legacy terminals cannot distinguish
  auto-repeat from fresh presses, so the flag would silently behave
  differently per terminal. Kitty-only repeat sensitivity is available
  via `KeyBinding.event` + `event.raw.type` (§7).
- Vim-grade operator/count/textobject grammar as a framework primitive
  (unchanged from RFC 0008). The `samples/editor` showcase (§13)
  demonstrates how far plain bindings + app state go.

## 3. The model

### 3.1 Type hierarchy

```dart
final class KeySequence { ... }                    // 1+ steps, each = code + modifiers
final class KeyCode extends KeySequence { ... }    // one unmodified logical key
final class PendingKeySequence { ... }             // incomplete expression (.ctrl) — NOT a KeySequence
final class _Chord extends KeySequence { ... }     // private: modified single step
final class _Steps extends KeySequence { ... }     // private: multi-step sequence
```

`KeySequence` is `final`, not `sealed`: the non-`KeyCode` subtypes are
private, and `sealed` would invite exhaustive switches that users
cannot satisfy. `is KeyCode` checks still work.

`KeyCode` unifies printable characters and special keys:

```dart
KeyCode.a  KeyCode.escape  KeyCode.f5  KeyCode.char('?')  KeyCode.char('é')
```

`KeyCode.char` accepts **exactly one grapheme cluster** (asserted) and
normalizes to NFC. Named statics cover `a`–`z`, `space`, `enter`,
`tab`, `backspace`, `escape`, `delete`, `insert`, arrows
(`up`/`down`/`left`/`right`), `home`/`end`, `pageUp`/`pageDown`,
`f1`–`f12`. The `shiftTab` static is dropped — spell it `.shift.tab`.

### 3.2 The pending grid

Naming rule, stated once: **`Pending-` means not yet complete.** It
applies to both nouns:

| | Sequence (the value) | Match (the process) |
|---|---|---|
| **Complete** | `KeySequence` — bindable | `KeySequenceMatch` — a binding fired (§7) |
| **Pending** | `PendingKeySequence` — still being *written* | `PendingKeySequenceMatch` — still being *typed* (§8) |

The two pending types are incomplete in opposite directions and cannot
share a type: `PendingKeySequence` is a half-built *step* (dangling
modifiers — never a valid runtime state), while a
`PendingKeySequenceMatch` holds only *complete* steps (its `prefix` is
a valid `KeySequence`) and what is unfinished is the dispatcher's
decision. The same value `.ctrl.x` is a complete `KeySequence` when
written and part of a pending *match* when typed.

`PendingKeySequence` stays exported: its name is the vocabulary of the
compile error (§11), and the chain extensions that return it must be
public for `.ctrl.s` to resolve. Users never *name* it.

### 3.3 The chain DSL

Unchanged mechanics from the current tree (statics on the class, chain
getters via extensions), retargeted at the new types:

```dart
.enter                     // KeyCode — one-step KeySequence
.ctrl.s                    // modified step
.ctrl.shift.p              // stacked modifiers (order-agnostic)
.superKey.k                // super/meta are first-class (§5)
.g.g                       // two-step sequence
.ctrl.x.ctrl.s             // emacs-style multi-step
.space.f                   // leader style
.alt.char('${i + 1}')      // dynamic atoms
.shift.code(someKeyCode)   // escape hatch for a KeyCode held in a variable
```

Renames: `.key(KeyCode)` → `.code(KeyCode)`. Modifiers fold into the
*next* atom; an expression ending in a modifier has type
`PendingKeySequence` and is unusable where a `KeySequence` is expected.

`KeySequence` forwards the atom statics to `KeyCode` (canonical home)
so dot shorthands resolve in both `KeyCode` and `KeySequence` contexts.

## 4. Events

```dart
final class KeyEvent extends TuiEvent {
  const KeyEvent(this.code, {this.modifiers = const {}, this.type = KeyEventType.down});
  final KeyCode code;                 // required — the nullable keyCode/char pair is deleted
  final Set<KeyModifier> modifiers;   // {shift, ctrl, alt, superKey, meta}
  final KeyEventType type;            // down | repeat | up
  KeySequence toSequence();           // code + modifiers as a one-step sequence (capture UIs)
}
```

`TextInputEvent`, `TextCompositionEvent`, and `PasteEvent` are
unchanged. Committed text is not a keypress: IME composition,
multi-grapheme bursts, and paste never masquerade as `KeyEvent`s, and
the parser's routing (printables → text, chords/specials → key events)
is unchanged. This matches the Kitty protocol's own separation and
Crossterm/Bubble Tea v2 practice.

**Wire impact:** the remote codec currently encodes `KeyCode` by enum
index (`remote_codec.dart`). The value type requires a discriminated
encoding (kind + payload: special-index or UTF-8 char). Both codec ends
move in the same PR; `serve-wire-live`, `serve-semantics-gate`, and
`bundle-size` gates apply.

## 5. Matching semantics

Nine rules, normative:

1. **Char atoms match the produced character; shift folds into it.**
   `.char('?')` fires on `?` from any layout — never "Shift+Slash".
   `.shift.g`, `.char('G')`, and any equivalent spelling are one value:
   equal, same hash. (This is `CharacterActivator` semantics and
   generalizes the current matcher's ASCII canonicalisation.)
2. **Special-key atoms match all five modifiers strictly**, shift
   included.
3. **Super and Meta are strict everywhere** — model, matcher, DSL,
   labels, shadowing. This fixes the current bug where the matcher
   compares only Ctrl/Alt/Shift, so ⌘S (reported as `superKey` by both
   the Kitty path and the DOM input source) fires a bare `.s` binding.
4. **Caps Lock / Num Lock never enter the model** — dropped at the
   parser.
5. **Bindings fire on `down` and `repeat`, never `up`.** The matcher
   rejects releases so enabling Kitty event-type reporting later cannot
   double-fire bindings.
6. **Sequences keep RFC 0008 dispatch:** vim-style precedence (a direct
   `.d` waits while `.d.d` is live), per-dispatcher `sequenceTimeout`
   (default 500 ms), cancel/timeout replays held events with text-origin
   steps owed to the focused text claimant first. **`sequenceTimeout` is
   `timeoutlen`, not a self-destruct:** it only commits an *ambiguous*
   prefix — one where a shorter binding also completes (`g` vs `gg`) or a
   held printable is owed to a focused field. A *pure* prefix (nothing
   completes on the held keys — operator-pending `.d`, a `Space` leader)
   commits nothing, so it does **not** time out: it stays pending until the
   next key or Esc, so a which-key popup rests on it while the user reads it
   (matching which-key.nvim / emacs). The dispatcher decides by *trying* the
   commit on expiry and holding open only when the replay lands nowhere — no
   prediction, and the pending notifier never blips so the popup doesn't
   flicker.
7. **Shadowing is honest, two ways.** Bare printables are claimed by a
   focused editable before bindings (unchanged). New: on terminals that
   cannot report super/meta, bindings requiring them are inert **and**
   hidden from hint surfaces — capability shadowing, driven by the
   terminal probe, same predicate family as text shadowing. (The text-
   shadowing predicate is extended so super/meta chords are not
   text-shadowed — they arrive as key events, not text.)
8. **Sequences are values.** Structural, canonicalised equality and
   hashing; safe as `Map<KeySequence, _>` keys; `stepCount` and
   `isPrefixOf` exposed for tooling (§9).
9. **`KeyCode.char` is one grapheme, NFC-normalized** (asserted).

## 6. Bindings

```dart
final class KeyBinding {
  KeyBinding(KeySequence sequence, {
    required VoidCallback onTrigger,
    String? label, bool enabled = true, bool hideFromHintBar = false,
  });

  KeyBinding.event(KeySequence sequence, {
    required void Function(KeyBindingEvent) onEvent,
    String? label, bool enabled = true, bool hideFromHintBar = false,
  });

  KeyBinding.any(List<KeySequence> sequences, {
    VoidCallback? onTrigger,                       // exactly one of
    void Function(KeyBindingEvent)? onEvent,       // these two (asserted)
    String? label, bool enabled = true, bool hideFromHintBar = false,
  });

  List<KeySequence> get sequences;
  String get displayLabel;
}
```

- **`onTrigger` is the default.** Most handlers ignore their event;
  reaching for `KeyBinding.event` is itself a review signal ("this
  handler cares about propagation or the raw event").
- **`KeyBinding.any`** replaces `KeyBinding.list`: several spellings,
  one action, one hint-bar entry. The first sequence is canonical for
  display, falling back to the first *deliverable* alias (so
  `KeyBinding.any([.superKey.k, .ctrl.k], …)` shows ⌘K under
  serve/kitty and Ctrl+K on a legacy terminal — this is the
  cross-surface accelerator story; no `cmdOrCtrl` concept exists).
- Discoverability rules are unchanged from the current tree: a binding
  with `label == null` fires but is not shown; `hideFromHintBar` hides
  a labeled binding from the bar (help surfaces may still show it);
  `enabled: false` disables matching and display.

## 7. The handler event

```dart
class KeyBindingEvent {
  KeySequenceMatch get match;      // what fired
  KeyEvent get raw;                // sugar for match.events.last
  void bubble();                   // propagate instead of consuming
  // forwarding getters: code, modifiers, hasCtrl/hasAlt/hasShift, type
}

final class KeySequenceMatch {
  KeySequence get sequence;        // which alias/sequence matched
  List<KeyEvent> get events;       // every consumed event; length == sequence.stepCount
}
```

Consumed-by-default stays the rule; `bubble()` is the single escape
hatch and must be called synchronously (unchanged). `KeySequenceMatch`
fixes two existing gaps: multi-step handlers currently see only the
final raw event, and `KeyBinding.any` handlers cannot tell which alias
fired. Events synthesized from text input appear as their synthesized
`KeyEvent`s.

Kitty-only repeat sensitivity, when genuinely needed:

```dart
KeyBinding.event(.ctrl.q, onEvent: (event) {
  if (event.raw.type == KeyEventType.repeat) return;
  confirmQuit();
});
```

## 8. Introspection

Two context accessors on `KeyBindings`, deliberately separate because
they answer different questions at different timescales — merging them
would put hint bars on the keystroke-frequency invalidation path:

| | `activeOf(context)` | `pendingOf(context)` |
|---|---|---|
| Answers | "What could the user press here?" | "What is the user halfway through typing?" |
| Returns | `List<ActiveKeyBinding>` | `PendingKeySequenceMatch?` (null almost always) |
| Changes when | Focus moves, bindings/enabled change, modal opens, text claims | A prefix is pressed, advanced, completed, canceled, or times out |
| Powers | Hint bar, help overlay, palette, devtools keymap search | Which-key popup, tmux-style prefix indicator |

Both register a rebuild dependency (`of(context)` idiom); widgets that
never call them pay nothing. "Active bindings" matches ecosystem usage
(Textual's `Screen.active_bindings` feeding its Footer; Emacs' active
keymaps). `resolveActiveKeyBindings(manager)` remains the underlying
resolution API; `ActiveKeyBinding.chordLabel` renames to
`sequenceLabel`.

```dart
final class PendingKeySequenceMatch {
  KeySequence get prefix;                    // complete steps typed so far — a real KeySequence
  List<KeyCompletion> get completions;       // ways the match can complete
}
final class KeyCompletion {
  String get next;                           // remaining-step label ('f', 'Ctrl+S')
  KeyBinding get binding;
}
```

`prefix` being a real `KeySequence` enables `match.prefix.hintLabel`
for display and checks like `match?.prefix == KeySequence.space` to
pick a which-key layout per leader. `pendingOf` exists because it
cannot be derived: the dispatcher *swallows* the leader keypress while
holding a sequence (RFC 0008 precedence), so no widget ever observes
it. Completions include only bindings that can still fire; the hint-bar
rule applies (unlabeled completions fire but do not render).

**Stock widget:** `WhichKey(child: app)` renders the standard popup
with a show-delay (~150–200 ms) so fast sequences (`dd` in ~80 ms)
don't flash it. The delay lives in the widget, not the dispatcher.
`pendingOf` remains the primitive for custom UIs — a VS Code-style
status message is `'(${match.prefix.hintLabel}) was pressed…'`.

## 9. The string grammar

```dart
static KeySequence parse(String source);       // throws FormatException
static KeySequence? tryParse(String source);
String get hintLabel;                          // canonical display form
```

Grammar: steps separated by spaces; within a step, modifiers joined to
the atom with `+` (`ctrl`, `alt`, `shift`, `super`, `meta`,
case-insensitive, any order); atoms are the static names (`enter`,
`escape`, `f1`, `up`, …) or a literal character. Examples:
`ctrl+s` · `ctrl+x ctrl+s` · `g g` · `super+k` · `?`.

`parse(x.hintLabel) == x` for every sequence (round-trip is tested).
This is the entire user-remapping story: keymaps load from config
(`tryParse(config['save'] ?? '') ?? .ctrl.s`), capture UIs display
`event.toSequence().hintLabel`, and conflict detection is a
`Map<KeySequence, String>` plus `isPrefixOf` for prefix-overlap
warnings. `hintLabel` stays ASCII-canonical; display surfaces may
prettify (⌘ vs `Super+` is a presentation hook, platform-dependent —
left to the hint bar, not the grammar).

## 10. Testing

The app tester speaks the DSL and synthesizes **what a real terminal
sends**:

```dart
await tester.press(.ctrl.x.ctrl.s);   // KeyEvents for chords/specials
await tester.press(.d.d);             // two TextInputEvents — bare printables are text
await tester.type('hello');           // raw text path
```

This closes a known blind spot: hand-built synthetic `KeyEvent`s in
tests exercise a routing path real terminals don't use for printables,
masking text-claim bugs. `press` on a bare-printable step emits the
`TextInputEvent` the parser would.

## 11. Compile-time guardrails

Verbatim analyzer output from the prototype:

```dart
KeyEvent(.g.g);
// error: The argument type 'KeySequence' can't be assigned to the
//        parameter type 'KeyCode'.

KeyBinding(.ctrl, onTrigger: save);
KeyBinding(.ctrl.shift, onTrigger: save);
// error: The argument type 'PendingKeySequence' can't be assigned to
//        the parameter type 'KeySequence'.

KeyEvent(.ctrl);
// error: The static getter 'ctrl' isn't defined for the context type 'KeyCode'.
```

Sequences can't pose as events; incomplete modifier expressions can't
bind; modifiers don't resolve where a code is expected. The
`PendingKeySequence` name appearing in the second error is deliberate
pedagogy — another reason the type stays exported.

## 12. Delivery

Originally planned as four PRs; **PR 1 shipped standalone (#157) and PRs
2–3 plus the value-level parts of PR 4 landed together** as the combined
break (no deprecation shims at any step, per the pre-launch policy):

1. **Events + parsers + wire** (#157). `KeyCode` value type, required
   `KeyEvent.code`, `SpecialKey` rename, terminal + DOM parsers,
   dispatcher text→key synthesis, remote codec re-encoding (kind
   discriminant). Gates: `serve-wire-live`, `serve-semantics-gate`,
   `bundle-size`.
2. **`KeySequence` + matcher.** `KeyChord` → `KeySequence` with
   `KeyCode extends KeySequence`, five-modifier strict matching (the
   §5.3 super/meta bug fix), `up` rejection (at the dispatcher entry),
   produced-character folding, text-shadow predicate excludes super/meta.
3. **`KeyBinding` constructors + sweep.** `onTrigger` / `.event` /
   `.any`, `KeySequenceMatch` (which alias fired + consumed events), then
   the mechanical pass across every package, tests, and docs snippets.
4. **Strings + value APIs** (this PR): `parse` / `tryParse` ↔
   `hintLabel` round-trip, `isPrefixOf`, `KeyEvent.toSequence`.

**Deferred to a follow-up PR** (new reactive runtime plumbing, best
reviewed on its own): the `KeyBindings.activeOf` / `pendingOf` context
accessors, `PendingKeySequenceMatch`, the `WhichKey` widget, and
`tester.press` / `type`. None blocks the core redesign — they are
additive discovery/ergonomics surfaces. `resolveActiveKeyBindings`
(the resolution logic behind `activeOf`) already ships and powers the
hint bar. The `samples/editor` proving ground (§13) also lands with
that follow-up, since its which-key demo depends on `pendingOf`.

Not on the hot paint path, so paint/alloc gates are unaffected; `check`
plus the serve gates above cover it.

### 12.1 Implementation errata

Three refinements discovered while implementing, noted so the code and
this RFC agree:

- **`sealed`, not `final`, for `KeySequence`.** §3.1 preferred `final`
  to avoid exhaustive-switch friction. In practice the two subtypes
  (`KeyCode`; the private `_ModifiedSequence`) must share one library
  with the supertype for the extension to work, and the non-`KeyCode`
  subtype is private — so external code can never write an exhaustive
  switch anyway (it always needs a default). `sealed` is then the
  cleaner tool: it gives the abstract step interface the two subtypes
  implement. No user-visible difference.
- **`KeyCode.char` asserts one grapheme; it does not NFC-normalize.**
  §3.1 called for NFC normalization, but Dart has no built-in
  normalizer and a `const` constructor can't run one. The constructor
  asserts non-empty and documents the single-grapheme expectation;
  callers passing pre-composed characters (the parsers do) are
  unaffected.
- **`hintLabel` renders a modified letter uppercase (`Ctrl+S`) for
  readability; `parse` treats that uppercase as styling, not Shift,**
  when a non-Shift modifier is present. Shift on a letter is otherwise
  carried by case (`Shift+G` ↔ upper `G`). This keeps `parse(hintLabel)
  == x` while matching the conventional `Ctrl+S` display.

## 13. Proving ground: `samples/editor`

A vim-flavored modal editor beside `dashboard` / `files` / `agent` —
explicitly *vim-flavored, not vim emulation* (curated subset: `hjkl`,
`i`/`Esc`, `dd`, `gg`/`G`, `x`, `o`, `:`, a small operator set). It
exists to prove the risky parts in one app: the mode/claimant flip
(printables as commands vs text), sequence replay (`d` then `j` must
not eat the `j`), counts as ordinary bindings mutating app state
(`3dd` needs no framework feature), the which-key popup on a leader,
and — via a runtime-switchable emacs personality (`.ctrl.x.ctrl.s`,
`.ctrl.k`) — that an entire keymap is swappable data. It doubles as
the integration-level acceptance test for §5's routing rules and as a
guide demo on both surfaces (terminal + `fleury serve`).

## 14. Call-site gallery (all verified compiling)

```dart
KeyBindings(
  bindings: [
    KeyBinding.any([.j, .down], onTrigger: state.next, label: 'Next'),
    KeyBinding(.enter,     onTrigger: state.open,        label: 'Open'),
    KeyBinding(.char('/'), onTrigger: state.startSearch, label: 'Search'),
    KeyBinding(.ctrl.shift.p, onTrigger: state.palette,  label: 'Commands'),
    KeyBinding(.g.g,       onTrigger: state.scrollToTop, label: 'Top'),
    KeyBinding(.space.f,   onTrigger: state.findFile,    label: 'Find file'),
    KeyBinding.event(.escape, onEvent: (event) {
      if (!state.dismissTopmost()) event.bubble();
    }),
    for (var i = 0; i < tabs.length; i++)
      KeyBinding(.alt.char('${i + 1}'),
          onTrigger: () => state.selectTab(i), label: 'Tab ${i + 1}'),
  ],
  child: app,
)

const event = KeyEvent(.c, modifiers: {.ctrl});          // const works
final actions = <KeySequence, VoidCallback>{ .ctrl.s: save, .g.g: top };
final custom = KeySequence.tryParse(config['save'] ?? '') ?? .ctrl.s;
```
