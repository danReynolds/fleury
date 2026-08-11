# RFC 0022: Terminal Protocol Baseline v1

**Status:** Implemented baseline; protocol ledger contains open work

**Date:** 2026-08-11
**Next review:** 2026-11-11
**Builds on:** RFC 0021 terminal session negotiation

## 1. Purpose

This is the admission rule and living ledger for terminal protocol claims in
Fleury. It prevents a protocol from becoming a public capability merely
because Fleury knows its escape sequence, recognizes a terminal brand, or
received a syntactically valid probe reply.

The baseline is deliberately not a plugin system, global evidence database,
or terminal-emulator catalog. Domain owners continue to make small local
decisions through the session profile, active terminal state, and operation
reports defined by RFC 0021.

## 2. Capability truth

Every capability decision exposed to widgets, diagnostics, semantics, or
tests must preserve these facts:

- **support:** `supported`, `unsupported`, or `unknown` for the relevant
  terminal, surface, or transport;
- **enablement:** `enabled`, `disabled`, `unknown`, or `notApplicable` for the
  current Fleury session;
- **delivery:** `delivered`, `failed`, `unverified`, or `notApplicable` for the
  behavior the user requested;
- **policy:** whether policy blocked use independently of technical support;
- **fallback:** the behavior retained when the primary path is not verified;
- **provenance:** the active probe, applied state, operation result, surface
  profile, environment, override, policy, or fallback that supplied the fact.

`CapabilityTruth` and `CapabilityResolution` are the common vocabulary for
operation reports and inspectors. They are not a global registry. A domain
owner supplies truth at the boundary where it was observed; the resolver does
not reconstruct it from `TerminalCapabilities` or terminal identity.

`notApplicable` is explicit rather than implied. A static rendering feature
may have support evidence without an enablement or delivery step. Conversely,
an OSC 52 write can be enabled and emitted while delivery remains unverified.

## 3. Evidence rules

1. Terminal identity and environment may select a conservative fallback or
   suppress a known-unsafe probe. They do not prove delivery.
2. A positive protocol query proves only the fact queried. It does not prove
   that later output rendered or reached the user.
3. Emitting bytes proves enablement or an attempt, not delivery.
4. An operation acknowledgement may prove delivery for that operation.
5. A behavioral receipt records what the user saw or the terminal reported
   after the complete action; it is required for named-terminal claims.
6. Policy state is recorded even when support is unknown.
7. Unknown and unverified are first-class outcomes, never aliases for false or
   available.
8. Fallbacks and cleanup are part of the protocol contract, not incidental
   implementation details.

## 4. Admission checklist

No capability enters Fleury's public compatibility matrix without all of:

- a domain owner;
- an exact support/enablement negotiation strategy;
- a conservative fallback;
- cleanup semantics for every state Fleury attempts to activate;
- automated byte-level parser and transaction tests;
- a named-terminal behavioral receipt for every named-terminal claim.

OS transport CI and real-terminal receipts are separate evidence. POSIX PTY
tests do not prove Terminal.app, Kitty, or tmux behavior. Windows ConPTY tests
do not prove Windows Terminal rendering. Missing evidence is unexecuted, not
passed.

## 5. Protocol ledger

### P0

| Area | Owner | Negotiation and truth | Fallback and cleanup | Required evidence | State |
| --- | --- | --- | --- | --- | --- |
| Capability truth | Domain boundary plus `CapabilityResolution` | Observed facts are supplied explicitly; no static availability inference | Domain fallback is named in the resolution | Resolver tests plus operation-report tests | Implemented |
| Compatibility evidence | Terminal conformance harness | Exercise delivered behavior through a real terminal session | Claim remains unverified; harness must always restore its modes | Receipts for Terminal.app, iTerm2, Kitty, Ghostty, Alacritty, WezTerm, Windows Terminal, tmux, Zellij, and SSH | Open |
| Legacy keyboard | Input parser and POSIX driver | Kitty protocol is queried; terminfo may add validated legacy sequences | Legacy parser; modifyOtherKeys is parsed but never enabled; pop attempted Kitty state | Parser fixtures, transaction traces, then terminfo fixture comparison | Parse-only policy implemented; terminfo open |
| Windows transport | Windows driver | Native console/ConPTY behavior is detected by the driver, not inferred from macOS | Legacy keyboard and conservative surface profile; restore console modes | Windows CI first, then Windows Terminal receipt | Open |

### P1

| Area | Owner | Negotiation and truth | Fallback and cleanup | Required evidence | State |
| --- | --- | --- | --- | --- | --- |
| Cell pixel geometry | ANSI session profile | Query CSI `14 t` and `16 t`; refresh after resize | Unknown geometry disables pixel-derived sizing; no terminal mode to clean up | Codec, fragmented-reply, resize, and real-terminal receipts | Open |
| Dark/light changes | Theme domain | Negotiate DEC 2031/996; use OSC 10/11 only as fallback evidence | Keep configured theme; undo subscriptions during restore | Parser, lifecycle, fallback, and terminal receipts | Open |
| Synchronized output | ANSI presentation | Query DEC mode 2026 with DECRQM before treating support as known | Plain frame output; always close a started synchronized frame | Query/timeout/partial-support traces and terminal receipts | Open |
| Pixel mouse | Pointer domain | Negotiate xterm mode 1016 when sub-cell coordinates are requested | SGR 1006 cell mouse; disable every enabled mouse mode on exit | Parser, resize, cleanup, and canvas receipts | Open |
| Multiplexer graphics | Image presentation | Confirm terminal graphics and configured mux passthrough separately | Half-block cells; delete image placements and end passthrough cleanly | tmux and Zellij configuration/lifecycle receipts | Open |

### P2

| Area | Owner | Negotiation and truth | Fallback and cleanup | Required evidence | State |
| --- | --- | --- | --- | --- | --- |
| Styled underlines | Text presentation | Use terminfo `Su` plus protocol fixtures for SGR `4:x`, `58`, and `59` | Single underline/current foreground; reset underline color/style | Encoder goldens and terminal receipts | Open |

## 6. Watch and defer

Watch Kitty OSC 66 text sizing, but retain Fleury's draw-and-measure width
foundation until it provides a demonstrably better cross-terminal result.

Defer Kitty drag-and-drop, MIME clipboard events, file transfer, multiple
cursors, and OSC 133 shell integration until a concrete product mode needs
them. Native screen-reader support remains user research, not a protocol
checkbox; an accessible no-alternate-screen profile requires validation with
assistive-technology users.

Do not proactively enable modifyOtherKeys.

## 7. Quarterly review

At each review:

1. Recheck primary specifications and emulator release notes for ledger items.
2. Re-run portable terminal-core CI on every supported OS.
3. Refresh receipts whose terminal, multiplexer, or Fleury implementation
   changed materially.
4. Downgrade stale or contradicted claims to unverified immediately.
5. Add a protocol only with its owner, negotiation, fallback, cleanup, tests,
   and receipt plan already filled in.

The review updates this ledger and the public compatibility matrix together.
Neither may imply evidence the other does not contain.
