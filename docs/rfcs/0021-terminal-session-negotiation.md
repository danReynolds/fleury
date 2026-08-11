# RFC 0021: Terminal Session Negotiation

**Status:** Implemented

**Date:** 2026-08-11
**Supersedes:** the terminal-negotiation portions of RFC 0013; preserves RFC
0019 width policy and RFC 0020 keyboard semantics

## 1. Summary

Fleury will treat terminal setup as one bounded transaction owned by
`TerminalDriver`.

`TerminalDriver.enter()` will return one immutable session profile containing
the semantic surface and keyboard behavior that `runApp` may use, plus the
concrete presentation path. Native
drivers will route every input byte through one parser. That parser will emit
either application input or a typed terminal response; probes will no longer
divert arbitrary stdin into a second buffer.

The design deliberately does not introduce a second public session owner, a
generic capability registry, a protocol plugin system, background capability
discovery, or a general terminal-state reconciler.

## 2. Why

The existing implementation has strong individual safeguards:

- one framework-facing `TerminalDriver` I/O boundary;
- bounded startup probes with Device Attributes sentinels;
- transactional Kitty keyboard fallback;
- conservative glyph-width and image fallbacks;
- idempotent restore, suspend, and subprocess handoff paths;
- semantic `SurfaceCapabilities` and `KeyboardCapabilities`;
- passive, active, and delivery evidence in terminal diagnostics.

The remaining weakness is composition. During a probe the POSIX driver diverts
all stdin bytes away from `InputParser`, collects them in a driver-owned byte
buffer, searches the buffer for reply terminators, and heuristically replays a
tail as application input. `TerminalCapabilities` and `TerminalFeature` also
mix semantic behavior, concrete protocols, requested modes, transport context,
and detection policy.

That creates four structural risks:

1. A terminal reply and a user key have competing byte owners.
2. A late reply can be decoded as input or a real key can be discarded as a
   reply.
3. `runApp` must know which driver getters become meaningful only after
   `enter()`.
4. Widgets and diagnostics can accidentally treat a protocol claim as a
   delivered product capability.

## 3. First-principle invariants

1. Every input byte has exactly one parser.
2. Every complete parsed unit becomes exactly one application event or one
   terminal response.
3. Terminal responses never enter application dispatch.
4. Application input arriving during negotiation is delivered normally and is
   bounded only by `runApp`'s existing startup event buffer.
5. Exactly one object owns terminal mutation and restoration:
   `TerminalDriver`.
6. Cleanup derives from state Fleury attempted to activate, not from requested
   state or inferred support.
7. Public capabilities use semantic vocabulary. Protocol names remain in the
   presentation plan and diagnostics.
8. Unsupported and inconclusive evidence select safe fallbacks.
9. Terminal identity can suppress a known-unsafe probe, but cannot positively
   grant a capability.
10. Presentation facts are frozen when `enter()` completes. A capability may
    later demote only when runtime behavior can contradict negotiation and the
    domain defines a repair path; keyboard lifecycle is the initial case.
11. OS transport evidence and named-emulator compatibility evidence are
    separate claims.
12. Equal context, replies, policy, and overrides produce equal decisions and
    diagnostic explanations.

## 4. Ownership

`TerminalDriver` remains the public lifecycle and I/O boundary. Fleury will not
add a `TerminalSession` above it: `runApp` already performs that orchestration,
and a second owner would make write, event, and cleanup authority ambiguous.

Native drivers may share internal helpers:

- `InputParser`: the sole byte-framing and input-decoding state machine;
- `TerminalQueryRunner`: one logical query exchange at a time;
- domain resolution functions for keyboard, images, width, color, and links;
- a typed active-state record for restoration.

POSIX and Windows drivers retain platform ownership of termios/console modes,
signals, and resize delivery. `RemoteTerminalDriver` retains its structured
handshake; it returns the same session-profile shape without pretending that a
WebSocket peer speaks ANSI probes.

## 5. Entered-session profile

The long-term driver contract is:

```dart
abstract interface class TerminalDriver {
  Stream<TuiEvent> get events;
  Future<TerminalSessionProfile> enter(TerminalMode request);
  Future<void> restore();
  void write(String data);
}
```

`TerminalSessionProfile` is immutable and valid until `restore()`:

```dart
final class TerminalSessionProfile {
  final SurfaceCapabilities surface;
  final KeyboardCapabilities keyboard;
  final TerminalPresentation presentation;
}
```

`TerminalPresentation` is a sealed choice:

- ANSI presentation: synchronized-output decision and concrete image
  transport;
- structured presentation: the negotiated `RemoteSurfaceSink`.

The profile replaces post-`enter()` temporal reads of terminal capabilities,
keyboard capabilities, and `surfaceSink`. Output-flow control and subprocess
handoff remain optional driver behaviors because they are live behavior, not
entered-session facts.

## 6. Parser output

The parser has two explicit sinks:

```dart
void feed(
  List<int> bytes,
  TuiEventSink input, {
  TerminalResponseSink? responseSink,
});
```

The driver forwards input to its public event stream and passes
`TerminalResponse` directly to the active query runner. A wrapper sealed item
was rejected during implementation: the two typed sinks express the ownership
boundary without allocating an object around every ordinary key or text event.
There is no public response event and no internal response event bus.

The parser frames CSI, OSC, DCS, and APC strings across arbitrary read
boundaries with explicit size limits. Unambiguous response forms are never
decoded as keys. Cursor Position Reports are ambiguous with legacy modified
F3, so the parser classifies them as responses only while a width/cursor query
or its bounded late-reply tombstone is active.

Bracketed paste remains an input-owned framing mode: control-looking bytes in a
paste body are paste content until the bracketed-paste terminator.

## 7. Query runner

`TerminalQueryRunner` implements the existing probe transport boundary for
runtime negotiation, allowing runtime and `fleury diagnose` to keep sharing
the same request constants and response codecs.

Rules:

- At most one logical exchange is active.
- An exchange may contain several related requests followed by one Device
  Attributes sentinel.
- Replies are accumulated from typed parser responses, never arbitrary stdin.
- A matching sentinel completes the exchange immediately.
- A sentinel without an optional response means unsupported.
- No sentinel before the deadline means inconclusive/timeout.
- After timeout, exact response forms remain quarantined for a bounded grace;
  further startup probes do not overlap that quarantine.
- Transport write/flush time is inside the same deadline as response time; a
  blocked output path cannot pin startup indefinitely.
- On quarantine expiry, a response-shaped partial frame is discarded. A bare
  Escape has no response-specific evidence and is released as application
  input once the bounded ambiguity window ends.
- If the terminal cannot complete the sentinel contract, remaining optional
  probes may be skipped rather than multiplying timeouts.
- A total startup budget bounds the sequence in addition to per-query budgets.

## 8. Active terminal state

Terminal state is finite and typed. `ActiveTerminalState` records the requested
mode, the effective mode after policy/fallback, raw-input ownership, output-mode
ownership, and modifyOtherKeys ownership. `TerminalMode` carries the selected
screen, cursor, paste, focus, mouse, and keyboard settings; platform-native
termios/console snapshots remain in their platform controllers.

Restoration is derived from this record in protocol-safe reverse order. A
small number of deliberate safety resets may remain unconditional when foreign
code can mutate the same state during a handoff; those exceptions must be
named, documented, and tested.

The RFC does not add live mode reconciliation. If an application-facing need
for dynamic pointer or screen-mode transitions appears, the typed active state
can gain `transitionTo()` without changing parser, negotiation, or public
capability architecture.

## 9. Capability domains

Fleury already has the correct public domains:

- `SurfaceCapabilities`: color, glyphs, images, links, pointer precision, and
  text presentation;
- `KeyboardCapabilities`: held state, repeat distinction, positions, and
  printable key events;
- clipboard operation reports: attempted mechanism and actual fallback;
- resolved text policy: operational geometry with provenance beside it.

These are canonical. The current terminal-specific capability snapshot will be
removed from widget/runtime truth. Concrete ANSI mechanisms live in the ANSI
presentation plan and diagnostics.

`TerminalFeature` will not drive negotiation. Protocol entries, transport
context, and implementation details will be removed or deprecated. The common
`CapabilityResolution` result vocabulary may remain for semantics and
diagnostics where useful, but domain owners perform resolution.

Widgets do not feed a pre-mount requirement graph into the driver. The driver
selects the safest available session mechanisms from requested mode, policy,
context, and evidence; widgets consume the resulting semantic capabilities and
their own domain fallbacks.

## 10. Evidence and quirks

There is no global evidence store or numeric confidence score. Each domain
resolver returns its operational value together with categorical evidence:

- confirmed;
- unsupported;
- inconclusive;
- forced by override;
- degraded to fallback;
- blocked by policy;
- contradicted by observed behavior.

Evidence records its source: override, environment, terminfo, query response,
remote declaration, or runtime observation.

If Fleury needs a known-terminal quirk table, quirks must be negative and
narrow: query suppressed, matching context/version, observed failure, source,
and revalidation boundary. This change does not add a quirk table merely to
create an extension point. A future quirk cannot grant positive support.

## 11. Legacy keyboard input

The parser combines:

- grammar-based decoding for CSI-u, modifyOtherKeys, parameterized CSI/SS3
  keys, mouse, and terminal responses;
- a fixed-sequence table/trie for exceptional legacy terminal key strings.

`InputParser` accepts additional validated `LegacyKeySequence` data alongside
Fleury's built-in table. A future POSIX terminfo adapter can produce that data
without introducing a provider hierarchy. Terminfo is not mandatory and does
not control modern protocol capability; an adapter ships only if fixture
comparison demonstrates material coverage beyond the built-in grammar/table.

The activation preference is semantic:

1. full key lifecycle;
2. key disambiguation;
3. modifyOtherKeys compatibility;
4. legacy input.

The parser may understand every encoding, but the driver activates one selected
enhancement path.

## 12. Verification

Deterministic scripted terminal profiles respond to exact writes and can
fragment, delay, omit, corrupt, or interleave replies with application input.
Profiles assert writes, events, negotiation, fallbacks, active state,
restoration, and diagnostics.

Required cases include full, partial, unsupported, timeout, malformed, late,
every-byte split, interleaved input, CPR/F3 collision, mux-stripped response,
write failure, restore during negotiation, suspend/handoff, and runtime
keyboard contradiction.

Evidence layers remain distinct:

1. parser/resolver unit, property, and fuzz tests;
2. scripted profiles and golden transaction traces;
3. POSIX PTY and Windows ConPTY/native-console CI;
4. real-terminal matrix and keytrace receipts for named-emulator claims.

ConPTY proves Windows transport behavior, not Windows Terminal or another GUI
emulator.

## 13. Non-goals

- protocol plugin SDK;
- generic capability registry or planner hierarchy;
- global evidence database;
- numeric confidence scores;
- background probing or general capability reactivity;
- dynamic mode reconciler before dynamic modes exist;
- terminal emulator implementation;
- arbitrary terminal-path topology graph;
- positive feature detection from terminal brand;
- mandatory terminfo dependency.

## 14. Migration order

1. Characterize existing bytes, input, negotiation, and cleanup.
2. Add typed parser responses and the single-flight query runner.
3. Replace requested-mode cleanup with typed active state.
4. Return the immutable session profile from every driver and simplify
   `runApp`.
5. Make surface/keyboard/service capabilities canonical and narrow the mixed
   terminal feature vocabulary.
6. Add the legacy sequence provider and modifyOtherKeys fallback.
7. Add synchronized-output detection, in-band resize, pixel mouse, and further
   protocols only through the proven path.

Steps 1–6 are implemented by this RFC. Step 7 remains ordinary future protocol
work, not architecture required to validate this design.
