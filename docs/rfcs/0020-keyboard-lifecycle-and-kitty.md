# RFC 0020: Keyboard Lifecycle, the Kitty Protocol, and the Key-Input DX

**Status:** FROZEN 2026-08-05, then amended the same day by §26.1 — the
default tier flipped to lifecycle, the one post-freeze design change.
Implemented across P1–P7; §24's showcase validation gate passed with no
API-surface change (see §26).
**Dates:** drafted 2026-07-29; revised 2026-07-30 (peer review); finalized
2026-08-03 after five persona-review rounds, a naming poll, and a four-lens
assumption-challenge review (implementation-vs-code, adversarial semantics,
platform reality, forward compatibility); implemented and frozen 2026-08-05.
§25 records every decision; §26 records what building it changed.
**Amends:** RFC 0008's input dispatch pipeline; RFC 0018's `KeyEvent` model,
repeat behavior (§21.1), handler signature, and constructor set (`.any`,
`.event`, `Focus.onKey` removed — §21). RFC 0018's sequence semantics are
completed, not changed, by §14.4. RFC 0018 requires a short amendment note
pointing here.

The design has **two parts**:

- **Part I (§5–§11): the input pipeline and protocol work** — complete Kitty
  CSI-u support with transactional negotiation, a normalized batch model, a
  session regularizer with per-press records, frame-latched sampling state, web
  as the first lifecycle backend, and remote parity.
- **Part II (§12–§19): the public DX** — two widgets, one entry family, one
  handle, five types; everything else deleted or deferred with recorded
  triggers.

Primary references: [Kitty keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)
(verbatim-verified against the RST source and kitty's `key_encoding.c`),
Flutter `HardwareKeyboard`/`KeyboardListener`, Bevy `ButtonInput`, Godot
`InputEvent`/`Input`, Bubble Tea v2 (+ issue #1383), crossterm, Textual, Flame,
notcurses, leafwing-input-manager, the W3C UI Events `code` spec.

---

## 1. Summary

Fleury has two different keyboard jobs. **Commands:** find the deepest active
`KeyBinding`, invoke it, stop when it consumes. **Continuous and lifecycle
input:** know what is physically held and when it changed. These must not share
one dispatch contract, and the second is a *state* question, not a callback
question.

The complete public surface:

```text
WIDGETS     KeyBindings(bindings:, modal:)      · KeyDetector(onKey:)
ENTRIES     KeyBinding(gesture, aliases:, includeRepeats:, label:, onTrigger:)
            KeyBinding.hold(key, onHoldStart:, onHoldEnd:, label:)
HANDLE      Keyboard.of(context)
              .capabilities   .snapshot (isHeld / wasPressed / wasReleased)
              .nextKey(context)   .layout.labelFor(selector)
TYPES       KeyCode · KeyPosition · KeySelector · KeyEvent (.consume/.matches)
            KeyBindingEvent (.bubble)
RESERVED    KeyboardListener (observation lane, framework-internal)
```

The documentation rule that organizes everything: **`KeyBindings` matches
gestures; `Keyboard` reads keys.** React to a press → a binding. Need "is it
held right now" in a tick → the snapshot. Wait for one key → `nextKey`.
Widget-internal conditional key handling → the detector floor.

On terminals, `runApp` requests full lifecycle (flags 1|2|4|8|16) by default
and *queries what stuck*, committing transactionally — only when text entry
provably survives — and falling back to the safe tier (1|2) otherwise, or
inside a multiplexer (§26.1; this reverses decision 12). Unsupported terminals stay
fully usable; capabilities report what was **confirmed, never what was
requested**, and applications branch to different control schemes rather than
degraded ones. The browser backend has full lifecycle unconditionally and is
implemented first.

## 2. Current state (verified 2026-07-30, line refs from this tree)

- `TerminalMode.kittyKeyboard` is a bool pushing only flag 1
  (`terminal/terminal_sequences.dart:19`); the pop is `:42`. Push/pop already
  bracket inside the alt screen — correct by ordering, unprotected by tests.
- The parser decodes CSI-u event types (`terminal/input_parser.dart:597`) but
  the dispatcher drops every `up` (`runtime/input_dispatcher.dart:222`).
  Printables are lowered to `TextInputEvent` with the key identity discarded
  (`input_parser.dart:569-583`) — "text beats bindings" is enforced by event
  *shape* today, not by ordering.
- The web input source listens to `keydown`/composition/input only
  (`fleury_web/lib/src/input/dom_input_source.dart:70-74`); it already maps
  `repeat` and guards `isComposing`.
- `Focus.onKey` (`widgets/focus.dart:154, :1072`, dispatch `:938-949`) is the
  low-level consuming hook. In-repo usage is **~30 non-test sites across four
  packages** (fleury: list_view :852, scroll_view :288, text_input :1561,
  text_area :767; fleury_widgets: controls ×2, select ×3, menu ×2, tabs, tree,
  data_table, table, tree_table, date_picker, file_browser, file_picker,
  range_slider, stepper, color_picker, json_view, form, line_chart; storybook
  catalog; fleury_web main; hot_reload_demo) plus `NeonAsteroids`. None reads
  event type or depends on releases (verified).
- The bindings that actually rely on auto-repeat are **arrow/Tab focus
  traversal** (`widgets/focus_traversal.dart:72-125`, installed on every route
  by `navigator.dart:819`) and **Shift+arrow selection extension**
  (`widgets/selection/selection_area.dart:575-598`, default-on at `runApp`) —
  not the list/table widgets, which use `Focus.onKey`.
- `NeonAsteroids` fakes held keys with a 170 ms repeat-renewed latch
  (`samples/lib/src/neon_asteroids.dart:160`) — physics coupled to the OS
  key-repeat rate.
- One process serves exactly one surface (`remote/spawn.dart` closes the
  listener after the first connection; `run_app.dart:1614`). Focus traversal is
  Tab-based; arrows never collide with it.
- Every driver event already schedules a frame, and input drains before build
  (`run_app.dart:685`, `frame_scheduler.dart:73-122`); the frame-start hook for
  the snapshot latch exists (`tui_runtime.dart:148-149`).

## 3. Goals and non-goals

**Goals.** Correct simultaneous/held input on capable surfaces; `KeyBindings`
stays the concise command API and the sole ownership authority; continuous
input costs zero rebuilds; complete CSI-u grammar from a generated table;
logical, positional, modifier, phase, and text information preserved without
double delivery; capabilities as semantic guarantees confirmed by negotiation;
truthful degradation with *different* (not worse) control schemes; recovery
from lost releases wherever the platform makes loss detectable, honesty where
it does not; behavioral compatibility except the deliberate changes in §21.

**Non-goals.** Release-fired commands; making `KeyBindings` a capture/bubble
event system; guaranteeing releases on legacy input; treating positions as
scan codes; replacing text/IME/paste paths; a process-global keyboard
singleton; a public observation widget (reserved: §23); precise event timing or
multi-press-per-frame (recorded triggers: §23).

---

# PART I — PIPELINE AND PROTOCOL

## 4. Protocol facts that bind the design

Kitty's CSI-u report: `CSI code:alternates ; modifiers:event-type ; text u`.
Progressive flags: 1 disambiguate · 2 event types · 4 alternate keys ·
8 all-keys-as-escapes · 16 associated text. Facts load-bearing here, each
verified against the spec text or kitty's encoder:

- **Flag 2 without flag 8:** printable *presses and repeats* remain plain text;
  printable **releases are escape-coded** (`key_encoding.c` short-circuits only
  PRESS/REPEAT for text keys). Only Enter, Tab, Backspace are release-exempt
  ("so that the user can still type reset at a shell prompt"). Consequences:
  typing traffic roughly doubles at tier 1|2; release reports arrive for
  arbitrary codepoints **and legacy finals** (`CSI 1;1:3 A`); an app that
  spawns a tty-sharing child while flags are pushed leaks release escapes into
  it (§8.5).
- **Flag 8 without 16 deletes text entry** ("text will not be sent"); flag 16
  re-supplies it as codepoints. Hence transactional negotiation (§8.3).
- **Flag 4 is permissive**: the terminal "**can** send" shifted/base-layout
  alternates. The base layout key is "the key corresponding to the physical key
  in the standard PC-101 key layout" (the Cyrillic Ctrl+С → `ctrl+c` example is
  the spec's own); its *purpose* is cross-layout shortcut matching. Nothing
  obliges any given event to carry it → positions are optional **per event**
  even when the flag is confirmed.
- **Key number 0** denotes text with no key identity. The normal form must
  represent text-only input (§5).
- **Flag stacks are per screen buffer** (spec-mandated) — push/query/pop must
  all happen on the same screen. Modifier encoding is `1 + bitmask`; lock
  modifiers are suppressed for text keys unless flag 8. Functional keys live in
  PUA 57344–63743; lone modifier keys (57441+) are reported only under flag 8.
- **Lifecycle reality check:** flag 2 alone cannot express held printables;
  legacy auto-repeat repeats only the most recent key, so simultaneous
  opposite-direction input is *impossible* there, not merely worse — which is
  why degradation means a different control scheme (§20 demo).

## 5. The batch model

```dart
final class InputBatch {
  final KeyEvent? key;            // at least one payload present
  final String? committedText;
  final Duration timeStamp;       // monotonic receipt time
  final int sequence;             // per-source ordering
}
```

Terminal CSI-u typically yields one correlated batch; the DOM yields key-only
(`keydown`/`keyup`) and text-only (`input`) batches in source order; kitty key
0 yields text-only. Timestamps and sequence numbers exist from day one so the
deferred features that need them (§23) require no wire change; batch-level
timing is likely the *permanent* answer (no terminal protocol carries per-event
time). `KeyEvent.==` never includes timing.

```dart
final class KeyEvent extends TuiEvent {
  final KeyCode code;             // logical: what the cap says
  final KeyPosition? position;    // physical: where the key sits; per-event nullable
  final Set<KeyModifier> modifiers;
  final KeyEventType type;        // down | repeat | up
  final bool synthesized;         // framework-generated phase (provenance)
  void consume();                 // §17.2 liveness contract
  bool matches(KeySelector s);    // §13.3 identity-only matching
}
```

## 6. The pipeline

```text
source (terminal CSI-u │ DOM │ remote wire │ test driver)
  └─ 1 normalize        → InputBatch
     └─ 2 SESSION REGULARIZER   press records · phase repair · edge accumulation
        └─ 3 OBSERVATION        internal observers + hold registrations (projected)
           └─ 4 CAPTURE GATE    pending nextKey (routed-lane suppression only)
              └─ 5 KEY WALK     deepest-first: KeyDetector nodes + KeyBindings
                 │              scopes · sequence engine · modal frontier ·
                 │              per-event repeat policy · consume ⇒ suppress text
                 └─ 6 TEXT      claimant (if not suppressed)
                    └─ 7 CHARACTER-BINDING FALLBACK (text-driven, scopes only)
```

**Stage order is normative.** The assumption-challenge review found the two
contradictions this ordering fixes: text delivered before the key walk made
`consume()`-suppresses-text unimplementable, and a capture gate ahead of
observation starved hold pairing. Rules:

1. **Session regularizer** (stage 2) is the canonical physical record. It
   repairs duplicate-down (demoted to repeat), repeat-without-down (synthesized
   down, command-eligible — suppressing it would drop a real keystroke), and
   unmatched up (delivered for observability, records untouched). It
   synthesizes releases **only on authority loss**: application/window blur
   where detectable, suspend, disconnect, terminal-mode restoration, protocol
   downgrade, session replacement. Focus transitions never touch session state.
   Repair is **capability-gated**: sources without release reporting (legacy
   terminals, the default test profile) are never "repaired" — a fresh down on
   a release-less source is a fresh press, not a duplicate.
2. **Observation** (stage 3) sees every phase through per-registration scope
   projectors: an observer entering scope mid-press sees no phantom up; leaving
   scope while a key it saw is held receives exactly one synthesized up;
   phases for downs it never saw are suppressed. Projector-synthesized events
   are queued and dispatched after the current batch, never re-entrantly.
   **`KeyBinding.hold` registrations live in this lane** — that is how holds
   legally receive releases while `up` never enters the command lane.
3. **Capture gate** (stage 4): a pending `nextKey` examines user-originated key
   events; on completion it suppresses the batch's routed lanes (walk, text,
   fallback) and reports the key as handled upstream (so e.g. the Ctrl+C exit
   guard in `run_app` sees "handled"). Non-completing batches pass through
   untouched — observation and session are **never** starved by a pending
   capture. Recovery-synthesized events never complete a capture (a blur must
   not "choose" Ctrl for a rebind row). On surfaces where printables arrive as
   text only, a pending capture derives its result from the committed grapheme
   (logical identity, no position) — the documented exception that keeps
   rebinding alive on legacy terminals. Replayed events (§14.4) route through
   the gate like fresh ones.
4. **Key walk** (stage 5): deepest-first over the active focus chain, visiting
   `KeyDetector` markers and `KeyBindings` scopes strictly by depth. `up` and
   recovery-synthesized events never enter. A `consume()` anywhere in the walk
   marks the batch's committed text suppressed.
5. **Text** (stage 6) delivers to the claimant only if not suppressed;
   **character-binding fallback** (stage 7) is **text-driven** (so character
   gestures work on legacy terminals, where no printable KeyEvent exists),
   walks binding scopes only (not detectors), respects modality, and each
   binding is eligible in exactly one stage per batch.
6. **Determinism:** chain order is node depth; within one bindings list,
   declaration order (debug-warn when a positional and a logical entry both
   match the same physical key); globals in registration order; when nothing
   holds focus, root-ambient `KeyBindings` scopes participate (today's
   behavior, which root-level app bindings rely on) while `KeyDetector`s are
   focus-within only. A routing snapshot (chain, claimants, observer set) is
   captured per batch before any callback; session state, projector activity,
   and `nextKey` lifetime read live state.

**Synthesis taxonomy** (one flag, five origins — normative table):

| origin | session records | observers | snapshot edges | command lane | completes nextKey |
|---|---|---|---|---|---|
| repair-down (repeat w/o down) | ✓ | ✓ | ✓ | **✓** | ✗ |
| recovery release (authority loss) | ✓ clears | ✓ | ✓ | n/a (up) | ✗ |
| observer-local scope-exit up | ✗ | that observer | ✗ | ✗ | ✗ |
| web Meta-regime release (§10) | ✓ | ✓ | ✓ | n/a | ✗ |
| text-derived capture event | ✗ | ✗ | ✗ | ✗ | **✓** |

## 7. Frame-latched sampling

At frame start, after input drains, the runtime atomically publishes an
immutable `KeyboardSnapshot`: pressed sets plus every identity that went down
and every one that went up since the previous latch. Edges are non-consuming;
both may be true in one frame; down→up→down in one frame yields both edges
*and* `isHeld` true; repeats affect nothing; edges expire whether or not read;
paused consumers get no backlog; `sessionGeneration` invalidates everything. A
key transition always schedules a frame (verified as existing behavior), so
edges cannot outlive their frame in an idle app. The snapshot's readable window
is the whole frame span — tickers included; only `build()` asserts.

## 8. Kitty implementation

### 8.1 Modes and tiers

```dart
enum KeyboardProtocolMode { legacy, disambiguated, lifecycle }
TerminalMode(keyboardProtocol: KeyboardProtocolMode.lifecycle)  // default (§26.1)
```

| mode | request | notes |
|---|---|---|
| `legacy` | nothing | debugging / strict environments |
| `disambiguated` | flags **1\|2** | the safe fallback tier (and the multiplexer cap, §26.1); text presses/repeats unchanged; chords, arrows, F-keys gain event types where honored |
| `lifecycle` | flags 1\|2\|4\|8\|16 | the default (§26.1); transactional (§8.3) |

The **default tier also queries** (§8.2): the 2026 ecosystem is not universal
(VTE, Konsole, Terminal.app, default WezTerm, tmux, screen, mosh, Windows
Terminal stable lack event types), so repeat suppression is recorded as a
capability, never assumed. ~~`lifecycle` remaining opt-in is a closed decision:
flag 8 makes Fleury reconstruct all committed text; a future RFC may revisit
only with evidence of general-app benefit.~~ **AMENDED 2026-08-05 (§26.1): lifecycle is the default.** The revisit bar this paragraph set was met by the showcase gate itself — the browser surface already ran every app with full lifecycle semantics, so the terminal opt-in made the two surfaces behave differently for a reason apps could not see.

### 8.2 Negotiation is answer-driven and never blocks

Query = `CSI ? u` bracketed by primary DA (`CSI c`) — the spec's own
recommended detection; every real emulator answers DA1, so detection is
RTT-independent. Fully async: the app runs at the conservative tier from frame
one; a confirmation is a capability *upgrade* that may never arrive (pipes, CI,
VT-disabled consoles); nothing awaits it. Platform is never special-cased —
Windows Terminal 1.25+ confirms like any terminal; conhost answers DA1 and
fails the bracket. tmux answers for itself (it consumes the query) → correctly
unconfirmed; mosh likewise; SSH is transparent. The CSI-u *grammar* is decoded
unconditionally regardless of tier — tmux with `extended-keys` emits CSI-u
without being asked. The runtime and the diagnostic probe share one parser
(the probe already sends this exact bracket, `terminal_probe.dart:513`).

### 8.3 Lifecycle commit/rollback

Push 1|2|4|8|16 → query on the **same screen buffer** → **commit only if 2, 8
and 16 are all active** (4 optional, enables positions) → otherwise pop and
re-establish `disambiguated` before application input begins. A terminal
honoring 8 but not 16 has, at that moment, no text input — "conservative
capability reporting" cannot fix a terminal already in a text-destroying mode;
only rollback can.

### 8.4 Screen-buffer ordering and restoration

Enter: `?1049h` … push. Exit: pop … `?1049l`. This ordering is load-bearing
(per-buffer stacks; Bubble Tea #1383 is the failure), gets a comment at both
sites and a regression test. Pops always carry an explicit count (`CSI < 1 u`
— bare `CSI [ u` collides with ANSISYSRC on Windows consoles). SIGTSTP pops
before suspend; SIGCONT re-pushes and repaints. Restoration covers every
**observable** exit; SIGKILL/OOM cannot run cleanup — the docs say so and
document `reset`, rather than claiming impossibility. A chaos-exit test list
(kill -9, VM abort, Ctrl+Z/fg, SSH drop, tmux kill-pane) records actual
terminal state per terminal.

### 8.5 Spawn bracket and legacy hygiene

Flags are popped around any child process sharing the tty (`$EDITOR`,
subshells) and re-pushed after — at tier 1|2 every printable *release* is an
escape report (§4) and must not leak into children. Raw mode clears IXON
(Ctrl+S is a Save key, not XOFF). Release reports are dropped for all keys and
all finals. Esc-disambiguation timers stay armed unless event-types were
*confirmed* (the push is blind until the answer arrives).

### 8.6 Focus reporting and the hold watchdog

Blur-synthesized releases on terminals require DECSET 1004, which is
unqueryable, default-unforwarded by tmux (`focus-events`), and absent on
Terminal.app/mosh/screen/conhost. Policy: enable 1004 opportunistically at both
tiers and treat `CSI I/O` as authority where it flows. "App blur" is
kitty-tier opportunism, not a guarantee; the docs say which.

**The repeat-silence watchdog specified here was never implemented**, and this
section previously described it as though it had been. Two code comments
repeated the claim. What follows is the reasoning, kept because the idea keeps
suggesting itself.

The proposal: OS auto-repeat stops the instant focus leaves, so silence from a
held key implies the hold is over. Two uses, with opposite economics:

1. **As a substitute for phase reporting** — emulating held state on a
   terminal that never sends releases. *Rejected.* macOS waits ~500 ms before
   the first auto-repeat, so within that window there is no signal to
   distinguish a tap from a hold. A watchdog conservative enough not to end a
   real hold would report a tapped key as held for over half a second, which
   is unusable for exactly the controls that want held state. Phase-less
   surfaces demote to press-only instead (§6.4), and apps pair every sampled
   control with a press-driven binding.
2. **As a backstop for a hold wedged by focus loss**, on a surface that DOES
   report phases and where 1004 never arrived. *Still valid, still unbuilt.*
   Here the maths inverts: the watchdog can only ever END a hold that would
   otherwise last forever, so a wrong guess costs one re-press while the
   absence costs a permanently stuck key. Its two holes remain — users with
   auto-repeat disabled, and lone modifiers, which never repeat.

Until (2) exists, a key held across a focus change on a 1004-less terminal
stays held until the next press of that key. `KeyboardSession`'s duplicate-down
repair then clears it, so the wedge is bounded by the next keystroke rather
than by the session.

### 8.7 Parser completeness

Generated from **one checked-in specification table** (also the source of
`KeyCode`, `KeyPosition`, the DOM `code` map, and documentation): the full PUA
functional table, lone-modifier keys (57441+ — new vocabulary, new codec
coverage, excluded from chord matching so `.ctrl.x` never fires on Ctrl's own
down), alternate keys, event phases, associated text, key 0, omitted-field
defaults, keypad/sided/extended distinctions, lock-bit normalization
(mode-dependent per §4), malformed/overlong rejection without wedging, exact
phase retention end-to-end. Unknown well-formed functional codes are
diagnosable, never misparsed as text.

## 9. Layout labels

`Keyboard.layout.labelFor(KeySelector) → String?` with precedence **learned >
`getLayoutMap` > static table > null**; callers render null honestly ("key at
QWERTY-W"). Sources: static per-OS tables (fr-AZERTY, de-QWERTZ, tr-Q, Dvorak
to start); incremental learning from flag-4 alternates (one key per first
press, escape-coded events only — a slow-fill cache, *never* the first-paint
story; recency wins on contradiction, since layout switches are unsignaled);
`navigator.keyboard.getLayoutMap` (Chromium-only, secure context, the other
engines have rejected it). The hint bar consumes this for positional gestures —
the framework's own discoverability UI must never tell an AZERTY user to press
"W" for the key capped "Z".

## 10. Web backend (first lifecycle backend)

The DOM source adds `keyup`, `KeyboardEvent.code` → `KeyPosition`
(`'Unidentified'` → null), and blur/`visibilitychange` recovery; `repeat` and
`isComposing` handling already exist. Keydown never inserts text — browser
input events stay authoritative for IME/dead keys; keydown/`input` remain
separate batches with the pairing rule: a consumed printable suppresses the
next `input` batch whose insertion matches it within the same task; no match →
no suppression. **macOS Meta regime:** AppKit swallows keyup for non-modifier
keys while Cmd is held (verified cross-engine), so keys under Meta get
press-only semantics — synthesized release immediately after the down — plus a
sweep on Meta-up and blur; hold durations under Meta are documented as
undefined. Reserved chords (Cmd+W…) are unbindable and documented. Web ships
before terminal negotiation: it needs no flags and proves the regularizer,
snapshot, holds, and the Asteroids rewrite against a releases-producing surface
with zero protocol risk — and the flagship samples import
`fleury_widgets_web.dart` anyway.

## 11. Remote parity

The wire event adds optional `position`, `synthesized`, batch `timeStamp` and
`sequence` (trailing-extension pattern; the codec has the additive precedent);
the handshake adds the capability set. Old peers decode absent fields to
press-only defaults; new peers trust declared capabilities, never protocol
version. Wire cost accepted and gated: flag 8 inflates the *input* stream
~13×; typing at tier 1|2 roughly doubles it (releases).

---

# PART II — THE PUBLIC DX

## 12. Surface and decision rule

§1's table is the entire public surface. The decision tree an author needs:

- run code when the user presses something → `KeyBinding` in a `KeyBindings`
- …and while it auto-repeats → `includeRepeats: true`
- …for the duration of a press → `KeyBinding.hold`
- read what's held inside a ticker → `Keyboard.of(context).snapshot`
- wait for exactly one key → `await Keyboard.nextKey(context)`
- dialog that must not leak keys → `KeyBindings(modal: true)`
- widget-internal conditional handling / bridges → `KeyDetector`

**Constructor rule:** parameters shape a binding's match and callback
(`aliases`, `includeRepeats`); named constructors change its dispatch nature
(`.hold`). Nothing else earns a constructor.

## 13. Identity

### 13.1 Two types, one line

> **`KeyCode` is what the cap says. `KeyPosition` is where the key sits.**

`KeyCode.w` = the key that types W (AZERTY: top-middle). `KeyPosition.w` = the
key at W's QWERTY spot (AZERTY: the Z cap) — QWERTY is the *naming grid* for
positions (as in DOM `code`, USB HID, kitty's base layout), the way "the C key"
names a piano key. Litmus: **would you say the key's name out loud when
explaining the controls?** "Press P to pause" → `KeyCode`. "Left hand on the
movement cluster", "tap the number row" → `KeyPosition` (AZERTY digits are
*shifted*; positional digit-select is the difference between playable and
not). Position is legitimate for letters and the digit row used as spatial
controls — nothing else; `KeyPosition.q` for "quit" produces the truthful hint
"Quit · A" on AZERTY, which is the failure. Position members parallel code
members (`KeyPosition.w`, not `keyW`). ANSI/ISO/JIS edge keys map fuzzily; the
shared letter/digit block — the caged use — maps cleanly.

### 13.2 `KeySelector`

The sealed-in-spirit union both enums implement. **Closed to exhaustive
switching** (the `KeySequence` trick: user switches always need a default) so
future selector kinds — the InputMap RFC's growth axis — are additive. The
persistence ids specified here (kind-prefixed: `pos:w`, `code:sp`, because
they land in user config files) are the InputMap RFC's to implement: the
`.id`/`parse` pair originally shipped with P1b, but an id grammar with no
serializer consuming it is exactly the shipped-no-caller defect class this
project keeps re-learning, so the 2026-08-09 review pass deleted the
implementation and this spec remains the grammar's home. Users will name the
type roughly twice per app (a settings map annotation, a parse call) and
never construct it.

### 13.3 Matching rules

- `KeyEvent.matches(selector)`: **identity-only** (modifiers ignored — the
  chord-suppression behavior is deliberate and documented), with the one-way
  degradation rule applied **per press**: a position matches its spot when the
  press carried one, else its US-twin letter; a `KeyCode` never upgrades. When
  a flag-4 terminal omits the base field, position derives from the primary
  codepoint only when that codepoint is itself a US-layout key — never guessed.
- Bindings match logical `code`; the kitty base-layout code is the **non-Latin
  fallback** (Ctrl+С matches `.ctrl.c` — the protocol's stated purpose; without
  this every letter chord is dead on Cyrillic/Greek/Hebrew layouts).
- Shifted symbols match the *produced* character Shift-agnostically (AZERTY `.`
  is Shift+;). AltGr-produced text is **never** a Ctrl+Alt chord (Windows
  AltGr≙Ctrl+Alt would otherwise false-fire on every German bracket). No
  locale case-folding (Turkish İ).
- Positional gesture steps are legal (`KeyBinding(KeyPosition.w, …)` — the
  legacy tap-toggle scheme is spatial); sequence steps carry `KeySelector`.
- Debug nudges: sampling a *letter* `KeyCode` for held state hints once toward
  `KeyPosition`; sampled queries without `supportsHeldState` assert once,
  naming the capability branch.

## 14. `KeyBindings` and `KeyBinding`

### 14.1 The entry

```dart
KeyBinding(.ctrl.s, onTrigger: (e) => save(), label: 'Save')
KeyBinding(.j, aliases: [.down], includeRepeats: true, label: 'Next',
    onTrigger: (e) => next())
KeyBinding(.escape, onTrigger: (e) { if (!close()) e.bubble(); })
```

Handlers always receive the `KeyBindingEvent` (tear-offs declare the
parameter). Match ⇒ consumed; `e.bubble()` opts out — conditional capture is
idiomatic. `aliases` makes the primary/alternate asymmetry explicit (the hint
bar shows the primary; the term "alternate" stays reserved for kitty flag 4).
Deepest active binding wins; labels feed the hint bar and which-key.

### 14.2 Repeat policy

`includeRepeats: false` is the default: one invocation per physical press,
evaluated **per event** on `KeyEventType` — a tagged repeat on a default
binding is skipped; an untagged down fires. This is honest per key class: at
tier 1|2 chords/arrows/F-keys carry tags where confirmed; plain printables
degrade to today's behavior (best-effort, capability-recorded). Movement opts
in. Flutter's `includeRepeats` defaults *true* — the inversion is deliberate
(held Ctrl+S must not re-save) and documented as a landmine note.

### 14.3 `modal:`

`KeyBindings(modal: true)` stops the **unmatched remainder** at this scope —
blocks ancestor scopes and suppresses globals, extending the focus system's
existing modality (Navigator modal routes set it implicitly; routed dialogs
write nothing). Per-key passthrough is a binding **at the modal scope** that
matches and bubbles. Transit rule (adversarially reviewed): an unconsumed
event crosses a modal boundary only if a binding *at that boundary's scope*
matches and bubbles; deeper bubbles propagate up to the boundary and stop
unless relayed. Implementation note: the current chain walk pre-truncates at
the modal frontier — bubble-through requires boundary-annotated traversal (new
machinery, scoped in P4) — and the hint bar cannot advertise ancestor bindings
reachable only via passthrough (it renders reachability truth).

### 14.4 Sequences (0018 completed)

Steps advance on `down` and consume; a non-advancing key clears pending and
dispatches normally — the swallowed prefix is **not** replayed (a deliberate
divergence from today's replay-on-cancel, flagged for 0018's amendment note).
Repeats never advance or reset. Aliases are evaluated uniformly. Pending state
clears on scope exit and on a documented timeout; detector-consumed keys never
reach the engine and leave pending intact. **Esc cancellation is a
non-competing side effect**: any Esc, however consumed, clears all pending
sequences; the Esc itself is consumed by the cancellation only when no binding
matched it. `KeyBindings.pendingOf` (existing) and `cancelPending()` (new) are
public.

### 14.5 `KeyBinding.hold`

```dart
KeyBinding.hold(.space, onHoldStart: (e) => peek(), onHoldEnd: (e) => unpeek(),
    label: 'Peek')
```

Push-to-talk, not long-press: **start fires on the down, immediately** — on a
keyboard every press *is* a hold of some duration; there is no tap/hold fork to
disambiguate and no threshold (a delay-triggered variant is deliberately not
provided). End is **paired to the same binding** — physical or synthesized —
because holds register in the observation lane (§6): pairing survives
command-lane consumption and modality; modal-open is scope exit (synthesized
end); on modal-close a still-held key does not restart the hold (its down was
never seen by the re-entered scope). Exactly one end per start, always. A plain
binding and a hold on the same key at one node both fire (start before
trigger). Repeats are meaningless to holds. Inert without `supportsHeldState` —
never silently a toggle; branch on capabilities.

## 15. `Keyboard`

```dart
final keyboard = Keyboard.of(context);   // stable per runApp; capability/session
                                         // dependencies only — never key events
```

**Capabilities** (semantic, confirmed-only, legal and reactive in `build()`):
`supportsHeldState` (kitty 2∧8; web true; legacy false), `distinguishesRepeats`
(event types confirmed; printables only with `reportsPrintableKeys`),
`supportsPositions` (2∧8∧4; per-event optional), `reportsPrintableKeys`
(flag 8; the floor's tier requirement, §17.4). Driver replacement clears state,
bumps `sessionGeneration`, updates capabilities on the same handle — caching
the handle is safe.

**Snapshot** (§7): `isHeld`/`wasPressed`/`wasReleased(KeySelector)`, `pressed`,
`positionsPressed`. Reads assert in `build()`; legal anywhere else in the
frame. **All queries are empty/false without `supportsHeldState`** — an
accumulating set with no releases is a lying set; press-only input remains
fully available through bindings. Sampling is session truth: routing (captures,
consumption) never hides physical state — a rebind overlay pauses the game via
focus, not via input lies.

**`nextKey(context)`** → `Future<KeyEvent?>`: scope-tied by signature (unmount
completes null — a framework guarantee, `showDialog`-style, never
mounted-check discipline); exclusive over routed lanes while pending (§6 stage
4) including the batch's text; bypasses the sequence engine; single awaiter
(second concurrent call debug-throws); **modifier-composing** — completes on a
non-modifier down, or on a lone modifier's release (so Shift+X captures as a
chord and sprint-on-Shift stays bindable where modifier events exist);
recovery-synthesized events never complete it; on legacy tiers printables
complete it via the text-derived exception (§6). Debug-shell hotkeys are
consumed upstream of the dispatcher and are never capturable (documented).

## 16. Propagation model

| construct | granularity | default | override |
|---|---|---|---|
| `KeyDetector` | per event | propagate | `e.consume()` |
| `KeyBinding` | per match | consume | `e.bubble()` |
| `KeyBindings(modal:)` | per scope | consume the unmatched | a binding that bubbles |
| `Keyboard.nextKey` | per interaction | consume everything routed | — |

One idiom (methods on the event) for runtime decisions; static declarations
for static ones. The asymmetric defaults are principled: a binding *declared* a
match (consumption is the semantics; bubble opts out); a detector *peeks*
(observation is the base state; consume opts in). **Reserved for the future:**
the lane order is `[capture (reserved) → pending sequence → focus chain →
globals]` — the capture slot is unimplemented but named, so a future InputMap
that must own keys against deeper third-party widgets has a home that does not
re-litigate this model (§23).

## 17. `KeyDetector` — the floor

```dart
KeyDetector(
  onKey: (KeyEvent e) {
    if (e.code == KeyCode.arrowDown && _canScroll(1)) { _scrollBy(1); e.consume(); }
    // not consumed → falls through, no ceremony
  },
  child: Focus(child: view),      // focusability composed explicitly
)
```

### 17.1 Contract

Replaces `Focus.onKey` entirely (Focus does focus — the parameter is removed,
~30 sites migrate, §21.2). Active while focus is within its subtree; **not**
ambient when nothing is focused (unlike root binding scopes). Implemented as a
non-focusable, non-traversable marker node in the chain — the same pattern
`KeyBindings` uses; invisible to traversal, click-to-focus, and autofocus.
Receives `down`/`repeat` only — the release fence (`input_dispatcher.dart:222`)
is the stuck-key theorem: a consumable release wedges an ancestor's state.
Propagate-by-default inverts the old blanket-`handled` failure from
silent-and-distant (ancestor starves) to loud-and-local (your key does double
duty while you test).

### 17.2 `consume()` liveness

Valid only during the live synchronous dispatch of that event to an entitled
consumer. Entitlement is **dispatch-context-scoped** (an ambient dispatch-frame
stack), never instance-keyed — const canonicalization makes every plain
ArrowLeft the identical object, and the replay machinery re-dispatches
instances; replayed events re-enter liveness. Out of context: debug-throw
(observation lane, stored events, after an `await`); release-mode no-op. This
keeps the future listener's contract clean: same event type, entitlement by
context.

### 17.3 Suppression idiom

The blessed replacement for the deleted claim/claimAll (§25): a subtree that
samples keys consumes them against ancestors with one derived line —

```dart
KeyDetector(
  onKey: (e) { if (e.modifiers.isEmpty && _controls.any(e.matches)) e.consume(); },
  child: playfield,
)
```

— derived from the same list the ticker samples (no drift), with the
`modifiers.isEmpty` guard as the chord-safe documented form (omit it knowingly
to own chords over your keys). Failure direction: forgetting the line means an
ancestor palette opens mid-game — loud, local, caught in first playtest.

### 17.4 The floor's keyspace is tier-dependent

Legacy printables arrive as text only — no `KeyEvent` exists for the detector
to see. Character *gestures* still work everywhere (stage 7 is text-driven);
raw-key floors that need every printable as a key (a PTY-forwarding pane)
require `reportsPrintableKeys` and must branch on it. This is documented, not
papered over.

## 18. Worked examples (normative demos)

Nine scenarios exercise the full surface; the first seven never mention the
floor. (1) **fuzzy picker** — aliases+repeats movement, `/` focuses the filter,
per-alias claiming lets arrows navigate while j/k type, Esc dual role via
bubble. (2) **dashboard** — root palette + per-pane Ctrl+R shadowing, hold-
Space log peek. (3) **confirm dialog** — `modal: true`, y/n/Esc, explicit
Ctrl+Q passthrough. (4) **splash** — `nextKey` in initState, null-safe by
contract. (5) **modal editor** — bindings-list-swap modes, `.d.d`/`.g.g`/
leader, `nextKey` as `getchar()` for marks (`_marks[k.code]`). (6) **arcade
game** — positional controls sampled in a fixed-step tick (`wasPressed`
survives sub-frame taps), suppression idiom, capability-branched tap-toggle
legacy scheme on a positional binding, `FocusDetector`+`TickerMode(enabled:)`
pause.
(7) **rebind screen** — `nextKey`, spatial-vs-mnemonic rows choosing
`k.position ?? k.code` vs `k.code`, `.id` persistence, `labelFor` truth.
(8) **reusable scroll pane** — detector conditional consumption, boundary
fall-through. (9) **embedded terminal pane** — detector consume-everything
with one prefix key, gated on `reportsPrintableKeys`. The compile-checked home of this surface is
`website/examples/doc_snippets/keyboard_tour.dart` (analyzed on every CI run,
and mirrored by the Focus & keyboard guide); the scenarios themselves are
exercised by `packages/samples` — (5) by `editor`, (6) by `neon_asteroids`,
and the repeat/hold pair by `ansi_sprite_studio` — which is the DX acceptance
fixture §24 P7 gates on.

## 19. Performance

Input volume is human-scale (~100 events/s worst case held-keys); the risks are
shape-induced and each has a structural answer: **rebuild amplification** —
sampling produces zero rebuilds (the handle never notifies on key events; an
API that cannot notify cannot storm); **latency** — input drains before build
(verified existing); **zero-cost when unused** — empty observer/detector lanes
are null checks, snapshot publish allocates nothing when unchanged; **wire** —
§11's accepted costs. Gates per CLAUDE.md: dispatcher/framework changes →
`alloc-gate` + `paint-gate`; wire/codec → `serve-wire-live` +
`serve-semantics-gate`; web client imports → `bundle-size`; selection-adjacent
→ `selection-gate`; plus a new input-path allocation measurement (P6). The
input pipeline is currently uncovered by any gate — that ends here.

## 20. API delta at a glance

| | |
|---|---|
| **unchanged** | `KeyBindings` scoping/precedence, the gesture DSL, sequences (semantics completed §14.4), hint bar/which-key, text-claims-printables, focus-change detection and `TickerMode` (renamed to `FocusDetector` / plain `enabled:` during implementation — behaviour unchanged), IME/paste paths |
| **new** | `KeyDetector`, `Keyboard` handle (capabilities/snapshot/`nextKey`/`layout`), `KeyBinding.hold`, `aliases:`/`includeRepeats:`/`modal:`, `KeyPosition`, `KeySelector`, `KeyEvent.consume/.matches/.position/.synthesized`, `InputBatch`, `cancelPending`, lone-modifier vocabulary, `KeyboardProtocolMode`, capability set, layout labels |
| **removed** | `Focus.onKey` (→ `KeyDetector`), `KeyBinding.any` (→ `aliases:`), `KeyBinding.event` (→ handlers always take the event), `TerminalMode.kittyKeyboard` bool (→ mode enum) |
| **changed** | bindings no longer fire on auto-repeat by default (§21.1); handler signature takes the event |
| **never existed** (rejected in design, §25) | `owns:`/`claims:` field, `KeyBinding.claim/.claimAll/.capture/.repeatable`, `KeyCapture` widget, `KeySelector` factories with `logicalFallback`, propagate-flag listener, scope-behavior enum |

## 21. Behavior changes and migration

### 21.1 Repeat default flip (0018 amendment)

Held `P` toggles pause once; held `Ctrl+S` saves once. The sweep marks the
*actual* repeat-reliant binding sites `includeRepeats: true` **in the same
change**: `focus_traversal.dart` arrow/Tab bindings, `selection_area.dart`
Shift+arrow extension, `samples/editor` movement — *not* the list/table
widgets, which migrate to `KeyDetector` and receive repeats naturally. This
lands with the 1|2 default tier, so the miss would be user-visible on day one;
the corrected list is a review outcome, treated as normative.

### 21.2 `Focus.onKey` removal

All ~30 sites (§2) migrate to `KeyDetector` atomically across the four
packages; none depends on releases (verified); the `ignored`/`handled` edge
convention maps 1:1 onto propagate/consume. Widgets whose nodes were
ambient-active with no focus (RadioGroup) are re-examined individually since
detectors are focus-within only. Text editing is untouched — the text keymap
is its own path.

## 22. Testing

**Driver (P2, new):** `tester.sendBatch(...)` with a fake monotonic clock;
`tester.keyboardCapabilities` faking (legacy/kitty/web profiles);
`holdKey`/`releaseKey`; `press` rerouted through the batch path; async pumping
for `nextKey`. The harness presents the **legacy profile by default** — the 79
existing test files emit downs with no ups and must keep meaning what they
meant (the capability-gated regularizer guarantees it).

**Acceptance matrix** (beyond 0018's suites staying green): protocol — PUA
round-trips, alternate/phase/text parsing, fragmentation, malformed bounds,
key-0 text-only (no KeyEvent, no records, no observers); pipeline — the
stage-order interlock (consume suppresses text; character fallback is
text-driven; one eligible stage per binding), capture-gate placement (held-key
release completes holds while a capture pends), synthesis-taxonomy table
enforced row by row, routing snapshot vs live state, replay-through-gate;
frames — sub-frame tap, edge combinations, frame coherence, paused-consumer,
sessionGeneration; identity — AZERTY ownership (positional sample + suppression
+ ancestor `.z` silent), per-event position fallback, non-Latin chord fallback,
AltGr never-Ctrl+Alt, Turkish İ; capabilities — reactivity rebuilds the
branch, transactional rollback preserves text entry, legacy honesty asserts,
confirmed-not-requested; terminal — escape-ordering regression, explicit-count
pop, spawn bracket, SIGTSTP/SIGCONT, chaos-exit records; web —
Meta-regime, keydown/input pairing, blur sweep; holds — pairing under
consumption/modality/capture, both-fire order, inert-on-legacy; sequences —
§14.4 lifecycle incl. Esc side-effect and detector-consumed-key pending
survival; hint bar — reachability truth (no shadowed/bubble-through
advertising). Real surfaces: the §8 matrix run via the probe harness and the
keyboard inspector across kitty/Ghostty/WezTerm/iTerm2/Alacritty/WT, xterm-ish
legacy, tmux (both configs), mosh, web — acceptance is truthful degradation:
no stuck keys where confirmed, press-only honesty where not, text never
doubled or lost, no release ever fires a command.

## 23. Deferred, with recorded triggers

- **`KeyboardListener`** (public observation): edge timing, multi-press-per-
  frame, chord visualizers. The internal lane, timestamps, and the
  context-scoped consume() contract make promotion additive.
- **InputMap/ActionMap RFC**: `KeySelector` + labels are its substrate; legacy
  fallback triggers (tap-toggle driving the same actions) absorb capability
  branching; the reserved capture lane (§16) is its ownership story; grows
  selector kinds (why §13.2 is switch-closed).
- **Count prefixes**: `KeyBindingEvent` grows `count` without signature
  breaks; `match.events` invariant is stated as "one event per gesture step" to
  leave room; per-scope opt-in (the editor sample teaches app-owned digits
  today).
- **`TextInputReceiver`** (custom editors) — text-editing RFC territory; also
  the eventual answer if the floor ever needs a text lane beyond §17.4.
- **Semantics/a11y exposure** of bindings + pending state, riding
  `resolveActiveKeyBindings` + the pending notifier over the serve semantics
  channel.
- **`FocusTickerMode`** convenience; **event timestamps** (batch-level timing
  is likely permanent; any event field would be `==`-excluded).

## 24. Delivery

- **P1 — model, vocabularies, parser** (Part I): the generated spec table
  (`KeyCode`/`KeyPosition`/PUA/DOM maps + lone modifiers), `KeySelector` +
  id grammar, `KeyEvent` extensions, `InputBatch`, full grammar + fixtures +
  fuzz, additive codec fields.
- **P2 — regularizer, lanes, snapshot** (Part I): session records +
  capability-gated repair, projector, dispatch-frame stack for `consume()`,
  frame latch + scheduler wake, capability plumbing, **test driver**,
  zero-lane fast paths asserted allocation-free.
- **P3 — web lifecycle** (Part I): keyup/code/blur, Meta regime, batch
  pairing. First releases-producing backend.
- **P4 — the DX** (Part II): `Keyboard` handle + snapshot + `nextKey`,
  `KeyDetector` + liveness, `hold`, `aliases`/`includeRepeats`/`modal` (incl.
  boundary-annotated traversal), sequence-lifecycle completion + Esc rule,
  `Focus.onKey` removal + ~30 migrations + repeat sweep (§21), **NeonAsteroids
  rewritten** (latch deleted, positional controls, suppression idiom, legacy
  scheme, focus pause).
- **P5 — kitty negotiation** (Part I): transactional negotiation + query
  (default tier since amended to lifecycle by §26.1),
  transactional lifecycle, ordering tests, spawn bracket, SIGTSTP/CONT, 1004,
  chaos-exit suite. (The §8.6 watchdog was listed here and never built — see
  that section for why one of its two uses is rejected outright and the other
  is still open.)
- **P6 — parity + tooling**: remote round-trip, keyboard inspector (internal
  lane), layout tables + learning + `labelFor`, input-path gate, probe-generated
  support matrix.
- **P7 — showcase validation gate (exit criteria for this RFC).** Rewrite the
  remaining showcases on the final DX — `ansi_sprite_studio` (repeatable
  cursor + paint), `samples/editor` (modal patterns, sequences, `nextKey`
  marks), `file_manager`, `dashboard`/`debug_playground` passes — alongside the
  P4 Asteroids rewrite, then review them against one explicit question: **do
  they read better, or do remaining quality issues justify further key-DX
  adjustment?** Findings feed amendments; the RFC freezes only when this gate
  answers "no further adjustment justified."

## 25. Decisions ledger

1. Two lanes (commands / observation) fanned from one canonical session
   stream; session regularization vs per-observer projection are two layers —
   a focus transition never mutates session records.
2. Continuous input is sampled: frame-latched, zero rebuilds; edges
   (`wasPressed`/`wasReleased`) exist because fixed-step simulations lose
   sub-frame taps to boolean sets.
3. Capability reads reactive and build-legal; sampled reads build-asserted;
   handle stable per `runApp`; sampled queries all-empty without
   `supportsHeldState`.
4. Logical and positional identity are separate types; `KeySelector` unifies
   at data boundaries only; one-way per-press degradation; selectors
   switch-closed with kind-prefixed ids.
5. Capabilities are semantic guarantees projected from **confirmed** flags;
   lifecycle negotiation is transactional (2∧8∧16 or rollback); the default
   tier is 1|2 *with* the query; detection is DA1-bracketed, async,
   never-blocking, platform-agnostic.
6. Repeat: bindings fire once per press by default, per-event evaluation;
   `includeRepeats` opts in (0018 amendment; corrected sweep list is
   normative).
7. Handlers always take the event; propagation is methods-on-events with
   principled asymmetric defaults (binding consumes / detector propagates);
   `consume()` liveness is dispatch-context-scoped.
8. Ownership: per-key claims deleted in favor of the detector suppression
   idiom + `matches()` (chord-guarded form blessed); scope modality is
   `modal:` on the widget (claimAll deleted); the capture lane is reserved for
   the InputMap future.
9. Interactive capture is `nextKey(context)` — scope-tied, exclusive over
   routed lanes only, sequence-bypassing, synthesized-never-completes,
   text-derived on legacy. (Widget and list-entry capture shapes rejected
   after persona review; the async shape won on the mid-flow race and
   structural-lifetime grounds once scope-tying removed the dangling-await
   class.)
10. `KeyBinding.hold` is push-to-talk (zero-latency, observer-lane paired,
    both-fire coexistence); no long-press threshold exists.
11. The floor is `KeyDetector` (propagate-by-default), replacing `Focus.onKey`;
    the release fence stands everywhere; the floor's keyspace is
    tier-dependent and `reportsPrintableKeys` says so.
12. ~~`lifecycle` stays opt-in permanently absent a future RFC with general-app
    evidence~~ — **AMENDED 2026-08-05 (§26.1).** `lifecycle` is the DEFAULT:
    negotiation is transactional, so asking for it cannot leave a session unable
    to type, and the opt-in predated that machinery. The automatic upgrade holds
    back only inside a multiplexer, where a raw query is not a reliable
    statement about the host terminal; restoration honesty is "every observable exit" plus documented
    `reset`; blur on terminals is opportunistic-1004 ALONE — the watchdog that
    was to back it up was never built (§8.6) — so it is not a guarantee;
    macOS-web Meta keys are press-only.
13. Rejected along the way (each with its round recorded in the session
    notes): phase predicates on bindings; releases via the focus hook; a
    public observation widget as the games API; focus-scoped sampling; a
    keyboard singleton; one identity type (or flags/verbs instead of types);
    Flame's set-in-callback hybrid; notcurses' `unknown` phase; flag-2-only
    lifecycle; commit-whatever-came-back; `owns:`/`claims:` fields;
    `KeyBinding.claim/.claimAll/.capture`; a `KeyCapture` widget; return-value
    propagation control; a propagate-option listener; `absorbs:` (AbsorbPointer
    direction inversion); scope-behavior enums (translucent = per-binding
    bubble); `alternates:` naming (kitty term collision); focus-aware base
    tickers.

## 26. P7 — what building it changed

The gate's question was: **do the showcases read better, or do remaining
quality issues justify further key-DX adjustment?**

**Answer: no further adjustment justified.** Every defect the phases surfaced
was the implementation failing to do what this document already specified —
not the specification being wrong. No public name changed after P4, and one
§25 decision was reopened: decision 12, reversed by §26.1 after the gate.

That distinction is the finding. The API surface survived seven phases of
contact with real apps unchanged; the one reversal was a *policy* default,
and the gate producing it is exactly the signal this paragraph exists to
watch for — recorded in §26.1 rather than smoothed over.

### What the showcases proved

- **`neon_asteroids`** (sampled + positional). The tick reads as one immutable
  snapshot and three boolean queries; `wasPressed` is what keeps a sub-frame
  tap from being swallowed. It ORs a positional and a logical alternative by
  hand (`isHeld(_leftKey) || isHeld(KeyCode.arrowLeft)`) where a binding would
  have used `aliases:`. Considered and **left alone**: the same expression
  already mixes in pointer state, so no keyboard-only combinator would have
  collapsed it, and the `||` is the clearest thing on the line.
- **`samples/editor`** (modal + sequences + capture). The modal flip stayed a
  `TextInputClaimant` decision rather than anything key-DX — NORMAL declines
  text, so a printable routes as a command. Marks (`m<letter>`) are the case a
  declared sequence structurally cannot express, and are what `nextKey` is for.
- **`ansi_sprite_studio`** (repeat + hold). `includeRepeats: true` on the
  cursor keys is the repeat-reliant class the default policy exists to exclude
  everywhere else. Space became hold-to-draw where the surface reports
  releases, and stayed tap-to-paint where it does not — the §7.6 capability
  branch, in an app that is not a game.
- **`file_manager`, `dashboard`, `debug_playground`** (passes). Between them
  they need one binding, none, and none: focus traversal and widget-internal
  handling cover the rest. Worth recording — the key-DX surface is not
  something every Fleury app has to touch.

### Defects the gate caught

1. **`nextKey` ignored text-borne printables.** The capture gate was consulted
   on the key and batch paths, not the text path — so on every terminal that
   reports printables only as bytes, it ignored exactly the keys it waits for
   and let them fire ordinary bindings instead. Decision 9 already said
   "text-derived on legacy". Root cause: **`nextKey` had no test at all**, a
   public API shipped unexercised. Now has a contract file per lane.
2. **A learned layout label never reached the screen** — the dispatcher's
   zero-cost fast path skipped session ingest on release-less surfaces, but
   position and release reporting are independent capabilities; and nothing
   republished when a cap became known.
3. **Positional and logical labels disagreed on casing** (`[q] Quit
   [W] Thrust`).
4. **The diagnostic measured the wrong thing** — `CSI ? u` reports flags
   currently in force, and a terminal at a prompt has pushed nothing, so
   `diagnose --probe` answered 0 for every emulator. It now pushes, reads
   back, and pops.
5. **Three allocation defects on the input path**, found by the gate built to
   look for them (§19): a logically-constant step rebuilt per call, a value
   type not interned, and a batched printable walking the binding chain twice.
   485 → 208 B/key.

### Amendments folded in during implementation

- `KeyboardCapabilities.fromKittyFlags` is the single definition of the §5.7
  projection, shared by the local driver, the `fleury shell` relay, and the
  diagnostic.
- §9's layout labels resolve through `KeyboardLayout`, which learns from flag-4
  reports and falls back to bundled tables; `Keyboard.of(context)` is reactive
  to learning as well as to capabilities.
- §11's peer declaration is `keyboard=<bits>` on INIT, carrying semantic
  guarantees rather than Kitty flags so a browser peer can declare lifecycle
  support it has no flags for.
- `InputBatch` is the correlated shape on terminals; the browser surface
  keeps the split keydown/input pair, which the dispatcher normalizes. Both
  are supported deliberately — a bare event is a one-payload batch.

### 26.1 Amendment — `lifecycle` is the default (2026-08-05)

Decision 12 made the full tier opt-in. Dogfooding overturned it, on a question
the RFC never asked: *should a dashboard and a game both work out of the box?*

They should, and two facts say the opt-in was vestigial:

- **The two-surface promise already broke here.** On the browser surface
  releases are free — `KeyboardCapabilities.full`, no negotiation, no flag. The
  same app on a terminal had to opt in, for a reason that is an implementation
  detail of one surface. Fleury's own pitch says that does not happen.
- **The risk the opt-in guarded is now handled.** Decision 12 was taken before
  P5's transactional negotiation existed: a terminal honouring flag 8 without 16
  is rolled back to the safe tier and re-probed *before the app sees a
  keystroke*. Conservatism that predates its own mitigation is just cost.

Peers split exactly along the library/framework line — crossterm hands you
`PushKeyboardEnhancementFlags` to call yourself, Bubble Tea v2 has
`WithKeyboardEnhancements()`, Textual parses the protocol but never enables it;
while Bevy, Godot, and Flame never ask, because their platform always delivers
releases. Fleury is a framework, and the comparison that binds is Flutter,
which never asks.

**What stays cautious:** inside a multiplexer the automatic upgrade stops at
the safe tier. A raw query there is not a reliable statement about the host
terminal — tmux may answer for itself, forward to a host that answers
differently, or accept the flags and fail to translate the enhanced input back
— and this is the one tier where being wrong costs the user their ability to
type. `FLEURY_KEYBOARD=lifecycle` still forces it for a deployment that knows
better, and the same variable caps it for one that misbehaves.
